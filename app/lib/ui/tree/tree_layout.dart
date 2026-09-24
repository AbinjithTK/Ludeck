import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../../data/enums.dart';
import '../../data/models.dart';

/// Pure geometry for the tree. No widgets, no canvas, no Flutter bindings, so
/// every rule below is unit-testable on the VM without a device.
///
/// The layout is DERIVED FROM DATA, which is the whole reason this is a canvas
/// and not a 3D asset: a branch exists only when a platform is actually owned,
/// so a PC-only player sees one branch rather than seven empty ones.

/// One platform's branch. `depth` is the 2.5D cue: 0 is nearest the viewer, 1
/// is furthest. It drives scale, opacity and how far the branch shifts when the
/// tree is orbited, which is what produces parallax without real 3D.
class BranchGeom {
  const BranchGeom({
    required this.platform,
    required this.start,
    required this.tip,
    required this.depth,
    required this.thickness,
    required this.fruit,
  });

  final Platform platform;
  final Offset start;
  final Offset tip;
  final double depth;

  /// Follows how many fruit sit on it. A loaded branch reads as loaded.
  final double thickness;

  final List<FruitGeom> fruit;

  double get scale => 1 - depth * 0.25;
  double get opacity => 1 - depth * 0.35;
}

/// One game hanging on one branch.
class FruitGeom {
  const FruitGeom({
    required this.item,
    required this.centre,
    required this.radius,
    required this.depth,
    required this.harvested,
  });

  final TreeItem item;
  final Offset centre;
  final double radius;
  final double depth;
  final bool harvested;
}

/// A recommendation not yet owned, resting in soil at the base.
class SeedGeom {
  const SeedGeom({
    required this.item,
    required this.centre,
    required this.radius,
  });

  final TreeItem item;
  final Offset centre;
  final double radius;
}

class TreeLayout {
  TreeLayout({
    required this.trunkBase,
    required this.trunkTop,
    required this.branches,
    required this.seeds,
    required this.soilY,
  });

  final Offset trunkBase;
  final Offset trunkTop;
  final List<BranchGeom> branches;
  final List<SeedGeom> seeds;
  final double soilY;

  int get fruitCount =>
      branches.fold<int>(0, (sum, b) => sum + b.fruit.length);

  /// Builds the whole layout from the collection.
  ///
  /// Deliberate rules, each of which is a design decision from DESIGN.md:
  ///  - one branch per platform ACTUALLY owned, in Platform enum order
  ///  - harvested fruit sits toward the branch tips, where the light is, so the eye
  ///    finds what is playable without needing a legend
  ///  - a game owned on two platforms hangs on both branches, because that is
  ///    true and a list cannot show it
  ///  - nothing ever withers, shrinks or is pushed off: a full tree is healthy
  static TreeLayout build({
    required Size canvas,
    required List<TreeItem> items,
    required double fruitRadius,
    required double trunkWidth,
  }) {
    final soilY = canvas.height - canvas.height * 0.12;
    final base = Offset(canvas.width / 2, soilY);
    final top = Offset(canvas.width / 2, canvas.height * 0.16);

    final owned = items.where((i) => !i.isSeed && !i.entry.shelved).toList();
    final seedItems = items.where((i) => i.isSeed && !i.entry.shelved).toList();

    // Which platforms are actually present, in the enum's own order.
    final present = <Platform>[];
    for (final p in Platform.values) {
      if (owned.any((i) => i.platforms.contains(p))) present.add(p);
    }

    final branches = <BranchGeom>[];
    final n = present.length;

    for (var i = 0; i < n; i++) {
      final platform = present[i];

      // Branches leave the trunk between 25% and 90% of its height, lowest
      // first, so the tree reads bottom-heavy the way a real one does.
      final t = n == 1 ? 0.55 : 0.25 + (0.65 * i / (n - 1));
      final start = Offset.lerp(base, top, t)!;

      final side = i.isEven ? -1.0 : 1.0;
      // Higher branches are shorter, which is what stops the silhouette
      // reading as a fan.
      final len = canvas.width * (0.34 - 0.10 * t);
      final tip = Offset(start.dx + side * len, start.dy - len * 0.45);

      // Three depth planes, cycling. Two would read as a mistake; four is not
      // distinguishable at this scale.
      final depth = (i % 3) * 0.35;

      final onBranch =
          owned.where((it) => it.platforms.contains(platform)).toList();

      // Harvested last, so a finished game lands nearest the tip.
      onBranch.sort((a, b) {
        if (a.isHarvested == b.isHarvested) return a.game.title.compareTo(b.game.title);
        return a.isHarvested ? 1 : -1;
      });

      final fruit = <FruitGeom>[];
      final count = onBranch.length;
      for (var k = 0; k < count; k++) {
        final u = count == 1 ? 0.62 : 0.30 + 0.62 * (k / (count - 1));
        final along = Offset.lerp(start, tip, u)!;

        // Perpendicular offset, alternating, so adjacent fruit never overlap.
        final dir = (tip - start);
        final mag = dir.distance == 0 ? 1 : dir.distance;
        final perp = Offset(-dir.dy / mag, dir.dx / mag);
        final stagger = (k.isEven ? 1.0 : -1.0) * fruitRadius * 0.75;

        fruit.add(FruitGeom(
          item: onBranch[k],
          centre: along + perp * stagger + Offset(0, fruitRadius * 0.9),
          radius: fruitRadius * (1 - depth * 0.25),
          depth: depth,
          harvested: onBranch[k].isHarvested,
        ));
      }

      branches.add(BranchGeom(
        platform: platform,
        start: start,
        tip: tip,
        depth: depth,
        thickness: math.max(3.0, trunkWidth * 0.30 + count * 0.9),
        fruit: fruit,
      ));
    }

    // Seeds in a row in the soil. They wrap rather than shrink, because a seed
    // shrinking would imply it matters less the more you have.
    final seeds = <SeedGeom>[];
    final r = fruitRadius * 0.42;
    final gap = r * 2.6;
    final perRow = math.max(1, (canvas.width * 0.8 / gap).floor());
    for (var i = 0; i < seedItems.length; i++) {
      final row = i ~/ perRow;
      final col = i % perRow;
      final rowCount =
          math.min(perRow, seedItems.length - row * perRow);
      final rowWidth = (rowCount - 1) * gap;
      seeds.add(SeedGeom(
        item: seedItems[i],
        centre: Offset(
          canvas.width / 2 - rowWidth / 2 + col * gap,
          soilY + r * 2.0 + row * gap * 0.8,
        ),
        radius: r,
      ));
    }

    return TreeLayout(
      trunkBase: base,
      trunkTop: top,
      branches: branches,
      seeds: seeds,
      soilY: soilY,
    );
  }

  /// Which fruit or seed is under a point, nearest-first so overlapping fruit
  /// resolve to the one on top. Returns null for a tap on empty canvas, which
  /// must NOT be treated as a miss to correct: tapping bark is a legitimate way
  /// to dismiss a selection.
  TreeItem? hitTest(Offset p) {
    TreeItem? best;
    var bestDist = double.infinity;

    for (final b in branches) {
      for (final f in b.fruit) {
        final d = (f.centre - p).distance;
        // A 10px hysteresis pad, because a finger is not a pixel.
        if (d <= f.radius + 10 && d < bestDist) {
          bestDist = d;
          best = f.item;
        }
      }
    }
    for (final s in seeds) {
      final d = (s.centre - p).distance;
      if (d <= s.radius + 10 && d < bestDist) {
        bestDist = d;
        best = s.item;
      }
    }
    return best;
  }

  /// The branch whose label was tapped, for filter-by-tapping-the-branch.
  Platform? hitTestBranch(Offset p, {double tolerance = 18}) {
    for (final b in branches) {
      final d = _distanceToSegment(p, b.start, b.tip);
      if (d <= math.max(tolerance, b.thickness)) return b.platform;
    }
    return null;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }
}

/// Apple's momentum projection, from the Designing Fluid Interfaces sample.
/// Answers "where would this come to rest if released now", so a flick lands
/// where the gesture was going rather than where the finger stopped.
///
/// This is the exponential-decay form, NOT the textbook v squared over twice
/// the deceleration. The textbook version does not feel right.
double projectMomentum(double velocityPxPerSecond, double deceleration) =>
    (velocityPxPerSecond / 1000) * deceleration / (1 - deceleration);

/// Progressive resistance past a boundary. A hard stop reads as frozen; this
/// reads as responsive with nothing more to find.
double rubberBand(double overshoot, double dimension, double constant) =>
    (overshoot * dimension * constant) /
    (dimension + constant * overshoot.abs());
