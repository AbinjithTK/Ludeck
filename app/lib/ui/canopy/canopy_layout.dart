// Where everything sits on one level of the canopy. Pure: no widgets, no paint.
//
// The canopy shows ONE branch at a time -- the trunk at the root, or whichever
// branch the user has zoomed into -- and fans that branch's sub-branches up
// from a single fork, the way the Liven reference and mockup B draw it. A deep
// tree is never drawn all at once; each level is its own canopy. That is what
// keeps a radial layout legible: no screen ever carries more than
// [kMaxFanned] labels.
//
// Kept separate from the painter and the widget so the geometry is testable
// (no two labels overlap, nothing leaves the box) without pumping a frame.

import 'dart:math' as math;
import 'dart:ui';

import '../../data/models.dart';
import '../../domain/branch_tree.dart';

/// Most branches fanned on one level. The rest fold into a "+N" twig.
const int kMaxFanned = 6;


/// Cover chips shown at a branch tip on the fan (a preview, not the list).
const int kTipPreview = 3;

/// A cubic Bézier, start to end.
class Curve4 {
  const Curve4(this.p0, this.p1, this.p2, this.p3);
  final Offset p0, p1, p2, p3;

  Offset at(double t) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  Offset tangent(double t) {
    final u = 1 - t;
    return (p1 - p0) * (3 * u * u) +
        (p2 - p1) * (6 * u * t) +
        (p3 - p2) * (3 * t * t);
  }
}

/// One limb of the drawing: bark from [curve.p0] to [curve.p3], thick to thin.
class Limb {
  const Limb({
    required this.curve,
    required this.startWidth,
    required this.endWidth,
    required this.seed,
    this.leaves = 0,
    this.lit = false,
  });
  final Curve4 curve;
  final double startWidth, endWidth;

  /// Deterministic per branch, so the same tree always grows the same leaves.
  final int seed;
  final int leaves;

  /// Drawn in the lit bark tone (a drop target, the picked branch).
  final bool lit;
}

/// A labelled sub-branch on the fan.
class FanSlot {
  const FanSlot({
    required this.branch,
    required this.limb,
    required this.label,
    required this.gameCount,
    required this.subCount,
    required this.preview,
    required this.previewAt,
  });
  final Branch branch;
  final Limb limb;

  /// Centre of the name label.
  final Offset label;
  final int gameCount;
  final int subCount;

  /// Up to [kTipPreview] igdb ids to show as cover chips, and where.
  final List<int> preview;
  final List<Offset> previewAt;
}

/// A game hanging on its own short twig (a canopy with no sub-branches).
class GameTwig {
  const GameTwig({required this.igdbId, required this.limb, required this.at});
  final int igdbId;
  final Limb limb;

  /// Centre of the cover chip.
  final Offset at;
}

class CanopyLayout {
  const CanopyLayout({
    required this.size,
    required this.trunk,
    required this.fans,
    required this.twigs,
    required this.decor,
    required this.gameTwigs,
    required this.more,
    required this.moreAt,
    required this.chip,
  });

  final Size size;
  final Limb trunk;
  final List<FanSlot> fans;

  /// Stub twigs hinting at a fan slot's own sub-branches. Decoration.
  final List<Limb> twigs;

  /// Extra leafy sprigs on the trunk. Decoration.
  final List<Limb> decor;

  final List<GameTwig> gameTwigs;

  /// Branches (or games) that did not fit, and where the "+N" sits.
  final int more;
  final Offset? moreAt;

  /// Cover chip size used on this level.
  final Size chip;

  /// Lays out [focus]'s level (`null` = the whole tree) in a [size] box.
  ///
  /// [topClear] and [bottomClear] are bands the drawing must stay out of: the
  /// breadcrumb row above, the pick button and navigation below.
  static CanopyLayout build(
    BranchTree tree,
    int? focus,
    Size size, {
    double topClear = 0,
    double bottomClear = 0,
    List<int> trunkGames = const [],
  }) {
    final w = size.width;
    final usableTop = topClear + 40; // label + chip headroom
    final base = Offset(w / 2, size.height);
    final forkY = math.max(usableTop + 160, size.height - bottomClear - 40);
    final fork = Offset(w / 2, forkY);
    final scale = (w / 360).clamp(0.8, 1.4);

    final trunk = Limb(
      curve: Curve4(base, Offset(w / 2 - 6, base.dy - (base.dy - forkY) * .4),
          Offset(w / 2 + 6, forkY + (base.dy - forkY) * .3), fork),
      startWidth: 38 * scale,
      endWidth: 20 * scale,
      seed: focus ?? 0,
    );

    final children = tree.childrenOf(focus);
    final chip = Size(34 * scale, 34 * scale * 4 / 3);

    final decor = <Limb>[
      for (final side in [-1.0, 1.0])
        Limb(
          curve: _twig(trunk.curve.at(.72), side * 0.9, 34 * scale, -1),
          startWidth: 5 * scale,
          endWidth: 1.5,
          seed: (focus ?? 0) * 7 + side.toInt() + 3,
          leaves: 3,
        ),
    ];

    // A leaf-level canopy: no sub-branches, so its GAMES fan instead.
    // Also the root of a tree with no branches yet: its games hang straight on
    // the trunk ([trunkGames]) rather than vanishing behind an empty state.
    if (children.isEmpty && (focus != null || trunkGames.isNotEmpty)) {
      final games = focus != null ? tree.gamesOn(focus) : trunkGames;
      final seed = focus ?? 0;
      // Largest cover that fits every game; shrink before hiding any, because
      // a game folded into "+N" is a game the user cannot see on their tree.
      final g = _gameGrid(games.length, w, forkY - 50 - usableTop, scale);
      final shown = games.take(g.capacity).toList();
      final bigChip = g.chip;
      final n = shown.length;
      final tips = _gameTips(n, w, usableTop, bigChip, g.perRow);
      // Out of room: the last slot becomes the "+N" instead of a cover.
      if (games.length > shown.length) shown.removeLast();
      final twigs = <GameTwig>[
        for (var i = 0; i < shown.length; i++)
          GameTwig(
            igdbId: shown[i],
            limb: _limb(fork, tips[i], 11 * scale, seed * 31 + i, leaves: 4),
            at: tips[i],
          ),
      ];
      return CanopyLayout(
        size: size,
        trunk: trunk,
        fans: const [],
        twigs: const [],
        decor: decor,
        gameTwigs: twigs,
        more: games.length - shown.length,
        moreAt: games.length > shown.length ? tips.last : null,
        chip: bigChip,
      );
    }

    final fanned = children.take(
        children.length > kMaxFanned ? kMaxFanned - 1 : kMaxFanned).toList();
    final overflow = children.length - fanned.length;
    final n = fanned.length + (overflow > 0 ? 1 : 0);
    final tips = _fanTips(n, fork, w, forkY - usableTop - chip.height - 24);

    final fans = <FanSlot>[];
    final twigs = <Limb>[];
    for (var i = 0; i < fanned.length; i++) {
      final b = fanned[i];
      final tip = tips[i];
      final limb = _limb(fork, tip, 14 * scale, b.id, leaves: 6);
      final under = tree.gamesUnder(b.id);
      // Two covers per tip once the fan is crowded, three when there is room.
      final preview = under.take(n > 3 ? kTipPreview - 1 : kTipPreview).toList();
      // Chips sit in a row just above the tip; the label sits above them.
      final rowW = preview.length * (chip.width + 4) - 4;
      final chipY = tip.dy - chip.height / 2 - 6;
      final previewAt = [
        for (var k = 0; k < preview.length; k++)
          Offset(tip.dx - rowW / 2 + chip.width / 2 + k * (chip.width + 4),
              chipY),
      ];
      final labelY = preview.isEmpty ? tip.dy - 16 : chipY - chip.height / 2 - 14;
      final subs = tree.childrenOf(b.id);
      for (var k = 0; k < math.min(subs.length, 3); k++) {
        final t = .5 + .14 * k;
        final dir = limb.curve.tangent(t);
        final side = k.isEven ? 1.0 : -1.0;
        twigs.add(Limb(
          curve: _twig(limb.curve.at(t), side, 26 * scale,
              math.atan2(dir.dy, dir.dx)),
          startWidth: 4.5 * scale,
          endWidth: 1.2,
          seed: subs[k].id,
          leaves: 3,
        ));
      }
      fans.add(FanSlot(
        branch: b,
        limb: limb,
        label: Offset(tip.dx, labelY),
        gameCount: under.length,
        subCount: subs.length,
        preview: preview,
        previewAt: previewAt,
      ));
    }

    return CanopyLayout(
      size: size,
      trunk: trunk,
      fans: fans,
      twigs: twigs,
      decor: decor,
      gameTwigs: const [],
      more: overflow,
      moreAt: overflow > 0 ? tips.last : null,
      chip: chip,
    );
  }

  /// Tips for games hung on their own twigs: two staggered rows rather than an
  /// arc. Covers are large here, and an arc of five 56px covers collides near
  /// the top wherever neighbouring angles are close; rows cannot.
  static List<Offset> _gameTips(
      int n, double w, double top, Size chip, int perRow) {
    if (n == 0) return const [];
    final rows = (n / perRow).ceil();
    // Spread evenly over the rows (5 over 2 rows is 3+2, not 4+1).
    final base = n ~/ rows, extra = n % rows;
    final out = <Offset>[];
    for (var r = 0; r < rows; r++) {
      final m = base + (r < extra ? 1 : 0);
      final y = top + chip.height / 2 + r * (chip.height + 20);
      final shift = r.isOdd ? .5 : 0.0;
      for (var k = 0; k < m; k++) {
        out.add(Offset(w * (k + 1 + shift) / (m + 1 + shift * 2), y));
      }
    }
    return out;
  }

  /// The biggest cover size (of three) at which [n] games fit in [height].
  static ({Size chip, int perRow, int capacity}) _gameGrid(
      int n, double w, double height, double scale) {
    ({Size chip, int perRow, int capacity})? g;
    for (final cw in const [56.0, 44.0, 36.0]) {
      final chip = Size(cw * scale, cw * scale * 4 / 3);
      final perRow = ((w - 24) / (chip.width + 14)).floor().clamp(1, 6);
      final rows = ((height + 20) / (chip.height + 20)).floor().clamp(1, 6);
      g = (chip: chip, perRow: perRow, capacity: perRow * rows);
      if (g.capacity >= n) return g;
    }
    return g!;
  }

  /// [n] tips on an upward fan above [fork], alternating near and far so
  /// neighbouring labels sit at different heights instead of colliding.
  static List<Offset> _fanTips(int n, Offset fork, double w, double reach) {
    if (n == 0) return const [];
    if (n == 1) return [Offset(fork.dx, fork.dy - reach)];
    // 200deg..340deg in screen space (0 = right, 270 = straight up).
    final spread = n == 2 ? 70.0 : (n == 3 ? 120.0 : 150.0);
    final start = 270 - spread / 2;
    final rx = w / 2 - 58; // keep a half-label clear of each edge
    return [
      for (var i = 0; i < n; i++)
        () {
          final a = (start + spread * i / (n - 1)) * math.pi / 180;
          final k = (n > 3 && i.isOdd) ? 0.72 : 1.0;
          return Offset(fork.dx + math.cos(a) * rx * (0.55 + 0.45 * k),
              fork.dy + math.sin(a) * reach * k);
        }(),
    ];
  }

  /// A limb from [from] to [to] that leaves the fork rising, then bends out.
  static Limb _limb(Offset from, Offset to, double width, int seed,
      {int leaves = 0}) {
    final d = to - from;
    return Limb(
      curve: Curve4(
        from,
        Offset(from.dx + d.dx * .08, from.dy + d.dy * .45),
        Offset(from.dx + d.dx * .72, to.dy - d.dy * .22),
        to,
      ),
      startWidth: width,
      endWidth: 2.5,
      seed: seed,
      leaves: leaves,
    );
  }

  /// A short curled twig at [at], off to [side] of [heading] (radians).
  static Curve4 _twig(Offset at, double side, double len, double heading) {
    final h = heading == -1 ? -math.pi / 2 : heading;
    final a = h + side * math.pi / 3;
    final end = at + Offset(math.cos(a), math.sin(a)) * len;
    final mid = at + Offset(math.cos(h), math.sin(h)) * (len * .5);
    return Curve4(at, mid, Offset.lerp(mid, end, .6)!, end);
  }

  /// Every rectangle a label or chip occupies, for overlap checks.
  List<Rect> chipRects() => [
        for (final f in fans)
          for (final p in f.previewAt)
            Rect.fromCenter(center: p, width: chip.width, height: chip.height),
        for (final g in gameTwigs)
          Rect.fromCenter(center: g.at, width: chip.width, height: chip.height),
      ];
}
