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
    required this.radius,
    required this.depth,
    required this.harvested,
    required this.branchId,
  });

  final TreeItem item;
  final Offset centre;
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
    final apexY = canvas.height * _lerp(0.44, 0.14, structure);

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
    final trunkHalfWidth = math.min(
      canvas.width * 0.075,
      trunkWidth * 0.5 + math.sqrt(totalFruit.toDouble()) * 1.5,
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
      final loadFactor =
          0.85 + 0.15 * math.min(1.0, fruitItems.length / 6.0);
      final length = canvas.width * (0.30 - 0.11 * t) * loadFactor;

      // Three depth planes, cycling. Two read as a mistake and four are not
      // distinguishable at phone size.
      final depth = (i % 3) * 0.35;

      final limbHalfWidth = math.max(
        2.4,
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
        ? math.max(5, math.min(8, 3 + (unplaced.length / 3).ceil()))
        : math.max(3, math.min(6, (unplaced.length / 3).ceil() + 2));
    final crownFrom = _lerp(0.52, 0.80, structure);
    final crownAngle = _lerp(0.88, 0.52, structure);
    final crownLength = canvas.width * _lerp(0.27, 0.13, structure);

    final crown = <TreeStem>[];
    for (var k = 0; k < crownCount; k++) {
      final span = 0.98 - crownFrom;
      final t = crownFrom +
          span * (crownCount == 1 ? 0.5 : k / (crownCount - 1));
      final attach = trunk.sample(t);
      // Twigs fan alternately. A crown reads as a spray rather than as another
      // set of limbs competing with the named ones.
      final side = k.isEven ? -1.0 : 1.0;
      final angle = crownAngle + rng.jitter(0.16);
      crown.add(_limbStem(
        start: attach.point,
        angleFromVertical: angle,
        side: side,
        length: crownLength * (1.0 - 0.28 * (k / crownCount)),
        halfWidthBase: math.max(1.6, trunkHalfWidth * 0.20),
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

    return ProceduralTree(
      canvas: canvas,
      trunk: trunk,
      limbs: limbs,
      crown: crown,
      trunkFruit: trunkFruit,
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
    widths.add(math.max(1.4, halfWidthBase * math.pow(1 - t, 0.62).toDouble()));
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
    widths.add(math.max(1.0, halfWidthBase * math.pow(1 - u, 0.70).toDouble()));
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
    out.add(TreeFruit(
      item: items[k],
      centre: at.point + at.normal * stagger + Offset(0, radius * 0.85),
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
  final r = fruitRadius * 0.42;
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
