// The procedural tree: one engine, derived from the collection, no widgets.
//
// This supersedes `tree_layout.dart`, which keyed branches on the PLATFORM a
// game was owned on. That model predates user-named branches and is the reason
// two different trees existed in the app at once: the profile portrait drew
// platform limbs while the home screen drew the user's own branches. Geometry
// here keys on `Branch` -- the user's own grouping -- and nothing else.
//
// Why it is procedural rather than an asset: a branch exists only when the user
// actually made one, so a player with two branches sees two limbs rather than a
// stock illustration of seven. The shape is GENERATED from the data, which also
// means the tree grows as the collection does.
//
// Three things it deliberately does NOT do:
//
//  - It does not rotate. An orbit/rotation parameter does not exist in this
//    file, because the user judged the rotating tree worse than a still one and
//    because a rotated limb puts every game title at an angle and makes
//    hit-testing a guess. Depth is expressed by overlap, scale and shading.
//  - It does not use `Random()` or the clock. Every draw comes from an explicit
//    seeded generator below, so the same collection always produces the SAME
//    tree -- a tree that reshuffled on every rebuild would not be the user's
//    tree, it would be a screensaver.
//  - It does not wither, shrink or evict anything. A full tree is a healthy
//    tree; that rule is inherited from DESIGN.md and is not renegotiated here.
//
// Pure Dart plus `Offset`/`Size` from `dart:ui`, so every rule below is
// unit-testable on the VM with no device and no canvas.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../../data/models.dart';

/// Deterministic pseudo-random source.
///
/// Written out rather than using `math.Random(seed)` because the SDK documents
/// no cross-version stability for its sequence, and "the same collection gives
/// the same tree" is a guarantee this engine makes and a test asserts. A plain
/// 32-bit LCG is more than enough for jitter.
class _Lcg {
  _Lcg(int seed) : _state = (seed & 0x7fffffff) | 1;

  int _state;

  double next() {
    _state = (_state * 1664525 + 1013904223) & 0xffffffff;
    return _state / 0x100000000;
  }

  /// Signed jitter in [-magnitude, magnitude].
  double jitter(double magnitude) => (next() - 0.5) * 2 * magnitude;
}

/// A tapered stem sampled along its length: the centreline, plus the half-width
/// at each sample.
///
/// A stem is a POLYLINE, not a start/tip pair. That is the single biggest
/// difference from the old engine: a straight segment cannot bend, and a tree
/// whose limbs do not bend reads as a diagram of a tree rather than a tree.
class TreeStem {
  const TreeStem({required this.spine, required this.halfWidth})
      : assert(spine.length == halfWidth.length,
            'every spine sample needs its own width');

  /// Base first, tip last.
  final List<Offset> spine;

  /// Half-width at the matching spine sample. Monotonically non-increasing:
  /// a stem never gets thicker as it grows away from its root.
  final List<double> halfWidth;

  Offset get base => spine.first;
  Offset get tip => spine.last;
  double get baseHalfWidth => halfWidth.first;

  /// Walked along the spine, not the straight-line distance -- for a curved
  /// stem those differ, and the walked length is the one that means anything.
  double get length {
    var total = 0.0;
    for (var i = 1; i < spine.length; i++) {
      total += (spine[i] - spine[i - 1]).distance;
    }
    return total;
  }

  /// The point at fraction [u] of the way along the spine, and the outward
  /// unit normal there. The renderer needs both to place a fruit; a test needs
  /// them to assert a fruit actually sits on its limb.
  ({Offset point, Offset normal}) sample(double u) {
    final clamped = u.clamp(0.0, 1.0);
    final span = (spine.length - 1) * clamped;
    final i = span.floor().clamp(0, spine.length - 2);
    final f = span - i;
    final a = spine[i];
    final b = spine[i + 1];
    final point = Offset(a.dx + (b.dx - a.dx) * f, a.dy + (b.dy - a.dy) * f);
    final dir = b - a;
    final mag = dir.distance == 0 ? 1.0 : dir.distance;
    return (point: point, normal: Offset(-dir.dy / mag, dir.dx / mag));
  }
}

/// One game hanging on the tree.
class TreeFruit {
  const TreeFruit({
    required this.item,
    required this.centre,
    required this.anchor,
    required this.radius,
    required this.depth,
    required this.harvested,
    required this.branchId,
  });

  final TreeItem item;
  final Offset centre;

  /// Where on the wood this fruit is attached.
  ///
  /// Stored rather than recomputed because two things need it and neither can
  /// derive it: the renderer draws the stalk between wood and fruit, and an
  /// arrival animation has to GROW from the branch rather than fade in at its
  /// final position. Without it both would guess a point straight above the
  /// fruit, which is wrong on every limb that is not horizontal.
  final Offset anchor;

  final double radius;

  /// 0 nearest the viewer, 1 furthest. Drives scale and shading, never rotation.
  final double depth;

  final bool harvested;

  /// The branch this fruit hangs on, or [ProceduralTree.trunkBranchId] when the
  /// game is on no branch at all.
  final int branchId;
}

/// One named branch, as a limb.
class TreeLimb {
  const TreeLimb({
    required this.branchId,
    required this.name,
    required this.stem,
    required this.depth,
    required this.onLeft,
    required this.fruit,
  });

  final int branchId;
  final String name;
  final TreeStem stem;
  final double depth;
  final bool onLeft;
  final List<TreeFruit> fruit;

  /// Depth cues. Both are pure functions of [depth] so the renderer cannot
  /// invent its own perspective and drift from the geometry.
  double get scale => 1 - depth * 0.22;
  double get opacity => 1 - depth * 0.30;
}

/// A recommendation not yet owned, resting in the soil at the base.
class TreeSeed {
  const TreeSeed({
    required this.item,
    required this.centre,
    required this.radius,
  });

  final TreeItem item;
  final Offset centre;
  final double radius;
}

/// The whole generated tree.
class ProceduralTree {
  const ProceduralTree({
    required this.canvas,
    required this.trunk,
    required this.trunkStructuralHalfWidth,
    required this.limbs,
    required this.crown,
    required this.trunkFruit,
    required this.soil,
    required this.soilY,
    required this.seed,
  });

  /// The branch id reported for a game that sits on no branch.
  static const int trunkBranchId = -1;

  final Size canvas;
  final TreeStem trunk;

  /// One per named branch, in the user's own `sortOrder`.
  final List<TreeLimb> limbs;

  /// The crown: short twigs at the top of the trunk that exist regardless of
  /// how the user has organised anything.
  ///
  /// A real tree has twigs whether or not you have named a branch, and without
  /// them the commonest state in the app -- games owned, no branch made yet --
  /// generated a bare pole with fruit threaded up it like a kebab. That is the
  /// first silhouette every new user sees, so the crown is not decoration: it is
  /// what makes an unorganised tree still read as a tree. Naming a branch grows
  /// a big limb; the crown is the growth you get for free.
  final List<TreeStem> crown;

  /// Owned games on no branch. They hang in the [crown] rather than being
  /// hidden, which is the same rule publishing follows ("On the trunk") -- and
  /// it is why the home screen no longer renders an empty canvas for a user who
  /// has games but has never made a branch.
  final List<TreeFruit> trunkFruit;

  final List<TreeSeed> soil;
  final double soilY;

  /// The seed the shape was generated from. Exposed so a test can assert two
  /// builds of the same collection agree, and so a renderer can cache on it.
  final int seed;

  Iterable<TreeFruit> get allFruit =>
      [for (final l in limbs) ...l.fruit, ...trunkFruit];

  int get fruitCount => allFruit.length;

  /// The trunk's half-width EXCLUDING the root flare.
  ///
  /// This, not `trunk.baseHalfWidth`, is the number every limb's thickness is
  /// derived from, and the distinction is structural rather than pedantic. The
  /// flare at ground level is a root buttress: it spreads load into the soil and
  /// carries no branches. Including it in the branching cross-section would make
  /// da Vinci's rule demand limbs thick enough to match a cross-section that
  /// never forks.
  ///
  /// Stored rather than sampled back off the spine, because the taper means no
  /// single sample equals it and a reader comparing limb widths to the painted
  /// base would otherwise conclude the rule was violated.
  final double trunkStructuralHalfWidth;

  /// Which fruit or seed is under [point], nearest first so overlapping fruit
  /// resolve to the one drawn on top. Null for a tap on empty canvas.
  TreeItem? hitTest(Offset point) {
    TreeItem? best;
    var bestDistance = double.infinity;

    void consider(TreeItem item, Offset centre, double radius) {
      final d = (centre - point).distance;
      // A generous target: a fruit is small and a finger is not.
      if (d <= radius * 1.35 && d < bestDistance) {
        bestDistance = d;
        best = item;
      }
    }

    for (final f in allFruit) {
      consider(f.item, f.centre, f.radius);
    }
    for (final s in soil) {
      consider(s.item, s.centre, s.radius);
    }
    return best;
  }

  /// Build the tree from the collection.
  ///
  /// [branches] and [placements] come straight from `LudeckStore`: the user's
  /// own branches in their own order, and branch id -> the igdbIds hanging on
  /// it. A game placed on two branches hangs on both, because that is true of
  /// the collection and a single position would be a lie.
  static ProceduralTree build({
    required Size canvas,
    required List<Branch> branches,
    required Map<int, List<int>> placements,
    required List<TreeItem> items,
    required double fruitRadius,
    required double trunkWidth,
  }) {
    final soilY = canvas.height - canvas.height * 0.12;
    final centreX = canvas.width / 2;

    // Shelved games are out of sight by the user's own choice; seeds are not
    // owned yet and belong in the soil, not on a limb.
    final live = items.where((i) => !i.entry.shelved).toList();
    final owned = live.where((i) => !i.isSeed).toList();
    final seedItems = live.where((i) => i.isSeed).toList();

    final ordered = [...branches]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // How much STRUCTURE the collection has, 0..1. It drives the tree's whole
    // proportion, because a tree with no named branches is a young tree: short,
    // with a big bushy crown. Holding the trunk at full height regardless left
    // a bare pole with a tuft on top -- a lollipop, not a sapling. The tree
    // therefore grows TALLER as the user organises, which is the progression
    // made visible.
    final structure = math.min(1.0, ordered.length / 6.0);
    // 0.30 -> 0.10, NOT 0.44 -> 0.14.
    //
    // Measured off a render, not guessed. At 0.44 the unorganised tree -- the
    // state every new user is in -- was a small stick in the middle of a screen
    // whose top 44% was empty sky, which reads as a rendering failure rather than
    // as a young tree. A sapling being physically short is botanically right and
    // compositionally wrong: the tree is the subject of the frame and has to fill
    // it. Youth is expressed instead by PROPORTION -- a bigger crown relative to
    // a shorter, thicker trunk -- which is also how a real young tree differs
    // from an old one.
    final apexY = canvas.height * _lerp(0.30, 0.10, structure);

    final seed = _seedFor(ordered, owned);
    final rng = _Lcg(seed);

    final byId = <int, TreeItem>{for (final i in owned) i.game.igdbId: i};

    // Membership per branch, and the set of everything placed anywhere.
    final members = <int, List<TreeItem>>{};
    final placedIds = <int>{};
    for (final b in ordered) {
      final ids = placements[b.id] ?? const <int>[];
      final onBranch = <TreeItem>[];
      for (final id in ids) {
        final item = byId[id];
        if (item == null) continue; // placed but shelved, seeded or gone
        onBranch.add(item);
        placedIds.add(id);
      }
      members[b.id] = _tipwardOrder(onBranch);
    }
    final unplaced =
        _tipwardOrder(owned.where((i) => !placedIds.contains(i.game.igdbId)));

    // The trunk thickens with the whole load, so a big collection reads as a
    // big tree before a single title is legible.
    final totalFruit = owned.length;
    // Wider than it was. At the previous figure the trunk rendered about 30px
    // across on a 412pt canvas, which next to a 44px cover card reads as a pole
    // supporting objects heavier than itself. A trunk has to look load-bearing
    // before any of the botany matters.
    final trunkHalfWidth = math.min(
      canvas.width * 0.090,
      trunkWidth * 0.62 + math.sqrt(totalFruit.toDouble()) * 2.2,
    );

    final trunk = _trunkStem(
      centreX: centreX,
      soilY: soilY,
      apexY: apexY,
      halfWidthBase: trunkHalfWidth,
      amplitude: canvas.width * 0.030,
      rng: rng,
    );

    // Da Vinci's rule: a parent stem's cross-section equals the sum of its
    // children's, so limb thickness follows the load it actually carries and
    // the joins look structural rather than decorative. Deriving each limb from
    // sqrt(share) satisfies sum(limb^2) == trunk^2 by construction.
    var totalLoad = 0.0;
    final loads = <int, double>{};
    for (final b in ordered) {
      final load = 1.0 + (members[b.id]?.length ?? 0);
      loads[b.id] = load;
      totalLoad += load;
    }

    final limbs = <TreeLimb>[];
    final n = ordered.length;

    for (var i = 0; i < n; i++) {
      final b = ordered[i];
      final fruitItems = members[b.id] ?? const <TreeItem>[];

      // Limbs leave the trunk between 34% and 90% of its height, lowest first,
      // so the silhouette is bottom-heavy the way a real tree is. Nothing grows
      // out of the very base.
      final tBase = n == 1 ? 0.55 : 0.34 + (0.56 * i / (n - 1));
      final t = (tBase + rng.jitter(0.025)).clamp(0.30, 0.93);
      final attach = trunk.sample(t);

      final onLeft = i.isEven;
      final side = onLeft ? -1.0 : 1.0;

      // A low limb leaves the trunk close to horizontal; a high one leaves it
      // close to upright. That single gradient is most of what separates a tree
      // from a fan.
      final angle0 = _lerp(1.26, 0.60, t) + rng.jitter(0.06);

      // Longer low, shorter high, and a loaded limb reaches a little further.
      // Reaching further than it used to: at 0.30 the silhouette was narrower
      // than the crown sitting above it, so the tree read as a column with
      // whiskers rather than as something with a spread.
      final loadFactor =
          0.85 + 0.15 * math.min(1.0, fruitItems.length / 6.0);
      final length = canvas.width * (0.40 - 0.13 * t) * loadFactor;

      // Three depth planes, cycling. Two read as a mistake and four are not
      // distinguishable at phone size.
      final depth = (i % 3) * 0.35;

      // A visible minimum, because a limb thinner than the stalk hanging off it
      // stops reading as wood and starts reading as wire.
      final limbHalfWidth = math.max(
        4.0,
        trunkHalfWidth * math.sqrt(loads[b.id]! / totalLoad),
      );

      final stem = _limbStem(
        start: attach.point,
        angleFromVertical: angle0,
        side: side,
        length: length,
        halfWidthBase: limbHalfWidth,
        rng: rng,
      );

      limbs.add(TreeLimb(
        branchId: b.id,
        name: b.name,
        stem: stem,
        depth: depth,
        onLeft: onLeft,
        fruit: _hang(
          items: fruitItems,
          stem: stem,
          branchId: b.id,
          baseRadius: fruitRadius,
          depth: depth,
          from: 0.34,
          to: 0.94,
        ),
      ));
    }

    // The crown always exists, so an unorganised tree still has a shape. With
    // no named limbs it is the whole canopy -- wide, low and full; as limbs
    // arrive it recedes to a spray at the top and lets them carry the form.
    final crownCount = ordered.isEmpty
        ? math.max(7, math.min(11, 5 + (unplaced.length / 2).ceil()))
        : math.max(4, math.min(7, (unplaced.length / 3).ceil() + 3));
    // The crown starts LOW when there is no structure.
    //
    // At 0.40 the twigs all attached in the top third, so an unorganised
    // collection's covers bunched into two clumps with a long bare trunk below
    // them -- measured off a device capture, where several covers overlapped each
    // other. Starting at 0.22 spreads the same twigs over most of the trunk, so
    // the canopy fills the frame and the fruit have room not to collide. As
    // branches arrive the crown recedes upward and lets the limbs carry the form.
    final crownFrom = _lerp(0.22, 0.72, structure);
    final crownAngle = _lerp(1.02, 0.56, structure);
    final crownLength = canvas.width * _lerp(0.34, 0.16, structure);

    final crown = <TreeStem>[];
    for (var k = 0; k < crownCount; k++) {
      final span = 0.98 - crownFrom;
      final t = crownFrom +
          span * (crownCount == 1 ? 0.5 : k / (crownCount - 1));
      final attach = trunk.sample(t);

      // The LEADER: the last twig grows nearly straight up.
      //
      // Without it no twig pointed upward, so no foliage was ever generated above
      // the trunk's apex and the canopy rendered as two side lobes with the trunk
      // spiking through the gap between them. A real tree closes over its own
      // top; this one twig is what shuts that hole.
      final isLeader = k == crownCount - 1;

      // Irregular sides rather than strict left/right alternation. Alternating
      // every twig at even spacing produced a fishbone -- unmistakably generated,
      // because nothing in nature alternates perfectly. A fixed repeating pattern
      // breaks the rhythm while staying deterministic.
      const pattern = [-1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0];
      final side =
          isLeader ? (k.isEven ? -1.0 : 1.0) : pattern[k % pattern.length];

      final angle =
          isLeader ? 0.14 + rng.jitter(0.05) : crownAngle + rng.jitter(0.22);
      crown.add(_limbStem(
        start: attach.point,
        angleFromVertical: angle,
        side: side,
        length: crownLength *
            (isLeader ? 0.88 : (1.0 - 0.28 * (k / crownCount))) *
            (0.78 + rng.next() * 0.44),
        halfWidthBase: math.max(2.6, trunkHalfWidth * (isLeader ? 0.34 : 0.26)),
        rng: rng,
      ));
    }

    // Unplaced games spread ACROSS the crown twigs rather than threading up the
    // trunk, which is what turned this case into a kebab.
    final trunkFruit = <TreeFruit>[];
    if (unplaced.isNotEmpty) {
      final buckets = List.generate(crown.length, (_) => <TreeItem>[]);
      for (var i = 0; i < unplaced.length; i++) {
        buckets[i % crown.length].add(unplaced[i]);
      }
      for (var k = 0; k < crown.length; k++) {
        trunkFruit.addAll(_hang(
          items: buckets[k],
          stem: crown[k],
          branchId: trunkBranchId,
          baseRadius: fruitRadius * 0.88,
          depth: k.isEven ? 0.12 : 0.30,
          from: 0.40,
          to: 0.92,
        ));
      }
    }

    // Covers are portrait cards, so crowding is resolved before anything is
    // returned. Ratio is the card's height over its width -- the same
    // `Tokens.size.coverRatio` the renderer sizes the card with, passed in as a
    // plain number so this file stays free of the UI layer.
    final separated = _separateFruit(
      limbs: limbs,
      trunkFruit: trunkFruit,
      ratio: 4 / 3,
    );

    return ProceduralTree(
      canvas: canvas,
      trunk: trunk,
      trunkStructuralHalfWidth: trunkHalfWidth,
      limbs: separated.limbs,
      crown: crown,
      trunkFruit: separated.trunkFruit,
      soil: _soil(
        items: seedItems,
        canvas: canvas,
        soilY: soilY,
        fruitRadius: fruitRadius,
      ),
      soilY: soilY,
      seed: seed,
    );
  }
}

/// Push overlapping fruit apart.
///
/// WHY THIS EXISTS. Hanging fruit along each stem independently gives no stem any
/// knowledge of its neighbours, so two twigs whose tips are close hang their
/// covers on top of each other. On a device capture that produced a stack of three
/// overlapping covers with only the topmost readable -- and a cover you cannot
/// read is the same as no cover, which defeats the whole reason the tree hangs art
/// instead of painted circles. Raising the cover size made it worse, because the
/// cards grew and the spacing did not.
///
/// A few rounds of pairwise relaxation, not a full physics pass. Two properties
/// make it safe to run inside a pure build:
///
///  - It is DETERMINISTIC: fixed iteration count, fixed order, no randomness. The
///    same collection still produces the same tree.
///  - Every fruit is CLAMPED to a short leash from where the botany put it, so a
///    crowded canopy loosens rather than rearranging itself into something the
///    stalks no longer explain. Fruit may still touch; they may not stack.
///
/// Comparison happens in a y-COMPRESSED space, because a cover is a portrait card
/// rather than a circle: a vertical gap has to be `ratio` times larger than a
/// horizontal one to look equally clear, and treating the card as a circle would
/// separate them correctly sideways and leave them overlapping vertically.
({List<TreeLimb> limbs, List<TreeFruit> trunkFruit}) _separateFruit({
  required List<TreeLimb> limbs,
  required List<TreeFruit> trunkFruit,
  required double ratio,
}) {
  // Flatten, remembering where each fruit came from so it can be put back.
  final flat = <TreeFruit>[];
  final owner = <int>[]; // limb index, or -1 for the crown
  for (var i = 0; i < limbs.length; i++) {
    for (final f in limbs[i].fruit) {
      flat.add(f);
      owner.add(i);
    }
  }
  for (final f in trunkFruit) {
    flat.add(f);
    owner.add(-1);
  }
  if (flat.length < 2) {
    return (limbs: limbs, trunkFruit: trunkFruit);
  }

  final centres = [for (final f in flat) f.centre];
  final origin = [...centres];

  const rounds = 14;
  for (var round = 0; round < rounds; round++) {
    var moved = false;
    for (var a = 0; a < flat.length; a++) {
      for (var b = a + 1; b < flat.length; b++) {
        // 0.94 rather than 1.0: cards are allowed to touch and slightly kiss,
        // which is what fruit on a branch actually does. Demanding a full gap
        // spread a loaded canopy into a grid.
        final want = (flat[a].radius + flat[b].radius) * 0.94;
        final dx = centres[b].dx - centres[a].dx;
        final dyReal = centres[b].dy - centres[a].dy;
        final dy = dyReal / ratio;
        var dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= want) continue;

        // Exactly coincident: nudge along x so the normal below is defined.
        var nx = dx;
        var ny = dy;
        if (dist < 0.0001) {
          nx = (a.isEven ? 1.0 : -1.0);
          ny = 0.0;
          dist = 1.0;
        }
        final push = (want - dist) / 2;
        final ux = nx / dist;
        final uy = ny / dist;
        centres[a] = Offset(
          centres[a].dx - ux * push,
          centres[a].dy - uy * push * ratio,
        );
        centres[b] = Offset(
          centres[b].dx + ux * push,
          centres[b].dy + uy * push * ratio,
        );
        moved = true;
      }
    }

    // Leash: no fruit strays further than 1.5 radii from where the botany put
    // it, so the stalk still explains the position.
    for (var i = 0; i < flat.length; i++) {
      final maxShift = flat[i].radius * 1.5;
      final d = centres[i] - origin[i];
      if (d.distance > maxShift) {
        centres[i] = origin[i] + d * (maxShift / d.distance);
      }
    }
    if (!moved) break;
  }

  TreeFruit moveTo(TreeFruit f, Offset centre) => TreeFruit(
        item: f.item,
        centre: centre,
        anchor: f.anchor,
        radius: f.radius,
        depth: f.depth,
        harvested: f.harvested,
        branchId: f.branchId,
      );

  final perLimb = [for (var i = 0; i < limbs.length; i++) <TreeFruit>[]];
  final crownOut = <TreeFruit>[];
  for (var i = 0; i < flat.length; i++) {
    final placed = moveTo(flat[i], centres[i]);
    if (owner[i] < 0) {
      crownOut.add(placed);
    } else {
      perLimb[owner[i]].add(placed);
    }
  }

  return (
    limbs: [
      for (var i = 0; i < limbs.length; i++)
        TreeLimb(
          branchId: limbs[i].branchId,
          name: limbs[i].name,
          stem: limbs[i].stem,
          depth: limbs[i].depth,
          onLeft: limbs[i].onLeft,
          fruit: perLimb[i],
        ),
    ],
    trunkFruit: crownOut,
  );
}

/// Harvested last, so a finished game lands nearest the tip where the light is
/// and the eye finds it without a legend. Title order otherwise, which keeps
/// the arrangement stable as the collection changes.
List<TreeItem> _tipwardOrder(Iterable<TreeItem> items) {
  final out = [...items];
  out.sort((a, b) {
    if (a.isHarvested != b.isHarvested) return a.isHarvested ? 1 : -1;
    return a.game.title.compareTo(b.game.title);
  });
  return out;
}

/// A stable seed for the shape.
///
/// FNV-1a over the branch identities and the sorted game ids. Sorted, because a
/// collection is a SET: the same games loaded in a different order must give the
/// same tree, and iterating a map's values would not guarantee that.
int _seedFor(List<Branch> branches, List<TreeItem> owned) {
  var h = 2166136261;
  void mix(int v) {
    h ^= v & 0xffffffff;
    h = (h * 16777619) & 0xffffffff;
  }

  for (final b in branches) {
    mix(b.id);
    for (final c in b.name.codeUnits) {
      mix(c);
    }
  }
  final ids = owned.map((i) => i.game.igdbId).toList()..sort();
  for (final id in ids) {
    mix(id);
  }
  return h;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// The trunk: a gently swaying, power-law taper.
///
/// The taper exponent is the detail that matters. A LINEAR taper is a cone, and
/// a cone is what made the old trunk read as a chess pawn; an exponent below 1
/// holds the trunk thick through its lower half and narrows late, which is what
/// real secondary growth produces. The sway is multiplied by `t` so the base
/// stays planted in the soil instead of sliding sideways.
TreeStem _trunkStem({
  required double centreX,
  required double soilY,
  required double apexY,
  required double halfWidthBase,
  required double amplitude,
  required _Lcg rng,
}) {
  const samples = 26;
  final phase = rng.next() * math.pi * 2;
  final lean = rng.jitter(1.0);

  final spine = <Offset>[];
  final widths = <double>[];
  for (var k = 0; k <= samples; k++) {
    final t = k / samples;
    final y = soilY + (apexY - soilY) * t;
    final sway = math.sin(t * 2.1 + phase) * amplitude * t * lean;
    spine.add(Offset(centreX + sway, y));

    // Exponent 0.80, not 0.62: at 0.62 the trunk stayed so close to full width
    // for most of its height that it rendered as a parallel pole rather than a
    // tapering stem.
    final taper = math.pow(1 - t, 0.80).toDouble();

    // Root flare over the lowest eighth. A real trunk widens where it meets the
    // ground, and without it the trunk looks inserted into the soil like a post
    // rather than grown out of it. This is the single cheapest cue that the tree
    // belongs to the ground it stands on.
    final flareT = math.max(0.0, 1 - t / 0.125);
    final flare = 1 + 0.42 * flareT * flareT;

    widths.add(math.max(1.4, halfWidthBase * taper * flare));
  }
  return TreeStem(spine: spine, halfWidth: widths);
}

/// One limb, bending upward as it grows out.
///
/// The bend is gravitropism: a limb leaves the trunk at [angleFromVertical] and
/// straightens toward upright along its length. Without it a limb is a straight
/// grey stroke, which is exactly how the previous tree looked.
TreeStem _limbStem({
  required Offset start,
  required double angleFromVertical,
  required double side,
  required double length,
  required double halfWidthBase,
  required _Lcg rng,
}) {
  const samples = 16;
  final step = length / samples;

  final spine = <Offset>[start];
  final widths = <double>[halfWidthBase];

  var point = start;
  for (var k = 1; k <= samples; k++) {
    final u = k / samples;
    // 0.40 rather than a steeper figure: a limb that curls upward too fast
    // barely reaches outward, and the silhouette closes into the trunk instead
    // of spreading. This was measured off a plot of the geometry, not guessed.
    final angle = angleFromVertical * (1 - 0.40 * u) + rng.jitter(0.03);
    point = Offset(
      point.dx + side * math.sin(angle) * step,
      point.dy - math.cos(angle) * step,
    );
    spine.add(point);
    // 0.70 held the taper too tight and left the outer half of every limb
    // thinner than the stalk hanging off it. 0.45 keeps real wood most of the
    // way out and narrows at the very tip, which is what a branch does.
    widths.add(math.max(1.6, halfWidthBase * math.pow(1 - u, 0.45).toDouble()));
  }
  return TreeStem(spine: spine, halfWidth: widths);
}

/// Place fruit along a stem, alternating to either side of it.
///
/// The alternating perpendicular offset is what stops adjacent fruit from
/// overlapping, and the small downward nudge is gravity: fruit hangs below the
/// wood it grows on rather than balancing on top of it.
List<TreeFruit> _hang({
  required List<TreeItem> items,
  required TreeStem stem,
  required int branchId,
  required double baseRadius,
  required double depth,
  required double from,
  required double to,
}) {
  final out = <TreeFruit>[];
  final count = items.length;
  if (count == 0) return out;

  final radius = baseRadius * (1 - depth * 0.25);

  for (var k = 0; k < count; k++) {
    final u = count == 1 ? (from + to) / 2 : from + (to - from) * (k / (count - 1));
    final at = stem.sample(u);
    final stagger = (k.isEven ? 1.0 : -1.0) * radius * 0.78;
    final anchor = at.point + at.normal * (stagger * 0.5);
    // 1.55 rather than a smaller nudge because a fruit is rendered as a PORTRAIT
    // cover card, not a circle: its height is 2.67 radii, so a smaller offset put
    // the card's top edge above the wood it hangs from and the cover then covered
    // its own branch. This number is what makes the stalk visible and the fruit
    // read as hanging rather than as pinned on top.
    out.add(TreeFruit(
      item: items[k],
      centre: at.point + at.normal * stagger + Offset(0, radius * 1.55),
      anchor: anchor,
      radius: radius,
      depth: depth,
      harvested: items[k].isHarvested,
      branchId: branchId,
    ));
  }
  return out;
}

/// Seeds in rows in the soil.
///
/// They WRAP rather than shrink: a seed getting smaller the more you have would
/// imply each one matters less, which is the opposite of what a recommendation
/// is.
List<TreeSeed> _soil({
  required List<TreeItem> items,
  required Size canvas,
  required double soilY,
  required double fruitRadius,
}) {
  final out = <TreeSeed>[];
  // 0.62 of a fruit rather than 0.42. A seed is rendered as a real cover chip,
  // and at 0.42 the chip was 18px wide -- too small to tell one game from
  // another, which defeats the point of showing the art at all. Seeds stay
  // SMALLER than fruit, because a recommendation is not yet a game you own.
  final r = fruitRadius * 0.62;
  final gap = r * 2.6;
  final perRow = math.max(1, (canvas.width * 0.8 / gap).floor());

  for (var i = 0; i < items.length; i++) {
    final row = i ~/ perRow;
    final col = i % perRow;
    final rowCount = math.min(perRow, items.length - row * perRow);
    final rowWidth = (rowCount - 1) * gap;
    out.add(TreeSeed(
      item: items[i],
      centre: Offset(
        canvas.width / 2 - rowWidth / 2 + col * gap,
        soilY + r * 2.0 + row * gap * 0.8,
      ),
      radius: r,
    ));
  }
  return out;
}
