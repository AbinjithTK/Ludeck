// The orchard's meadow: one continuous night landscape under every tree.
//
// Before this, each page painted its own sky and its own hill, so a swipe
// slid a whole hill away and brought a new one in, with a seam where two
// pages met. Now the land is one function of WORLD x (page index x width +
// position on the page) and is painted in three layers:
//
//   [MeadowBackPainter]   behind the pages: sky, parallax stars, the rolling
//                         ridge, back grass. Repaints from the page scroll.
//   per page              the tree's halo, its props and the tree itself,
//                         moving with the page (they belong to one tree).
//   [MeadowFrontPainter]  above the pages: a row of short front grass, so
//                         the trunk's foot stands IN the grass, not on it.
//
// The ridge crests exactly under each trunk (the soil line) and dips between
// trees, so trees stand on knolls of one rolling meadow and the ground never
// ends. The sky and stars are static apart from a slight parallax: the home
// screen is on screen whenever the app is open, where ambient motion stops
// being delight and becomes noise.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../tokens.dart';
import 'rive_tree.dart' show kTreeArtW, treeFrame;
import 'tree_style.dart';

/// Where the blossom's light is centred, in artboard units, and its reach.
const Offset kHaloCentre = Offset(190, 400);
const double kHaloRadius = 260;

/// The trunk's x in artboard units (TREE_X in rive/tree/build_tree.py).
const double kTreeBaseX = 180;

/// How far the meadow dips between two trees, as a fraction of page width.
const double kRidgeDip = 0.045;

/// Stars drift at this fraction of the page scroll: far away, barely moving.
const double kStarParallax = 0.08;

/// The ridge's height at world x [xw] for pages [pageW] wide whose trees'
/// soil line is [groundY]. Crest (== [groundY]) at every page centre, lowest
/// at the seams between pages, with the depth of each dip varied slowly so
/// the meadow does not read as a sine wave.
double ridgeY(double xw, double pageW, double groundY) {
  if (pageW <= 0) return groundY;
  final u = xw / pageW - 0.5;
  final depth = kRidgeDip * pageW *
      (1 + 0.35 * math.sin(2 * math.pi * xw / (2.3 * pageW)));
  return groundY + depth * (1 - math.cos(2 * math.pi * u)) / 2;
}

/// A stable pseudo-random value in [0, 1) for integer [k] and [salt]: the
/// same blade is the same shape every frame and every launch.
double _hash(int k, int salt) {
  var h = (k * 374761393 + salt * 668265263) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return (h ^ (h >> 16)) / 0x7fffffff;
}

/// Grass blades over the visible world range, batched into a few paths by
/// shade so a frame costs a handful of draw calls, not one per blade.
void _paintGrass(Canvas canvas, Size size,
    {required double scroll,
    required double groundY,
    required double spacing,
    required double minH,
    required double maxH,
    required double sink,
    required int salt,
    required List<Color> shades,
    Color? rim}) {
  final paths = List.generate(shades.length, (_) => Path());
  final rimPath = Path();
  final first = ((scroll - maxH) / spacing).floor();
  final last = ((scroll + size.width + maxH) / spacing).ceil();
  for (var k = first; k <= last; k++) {
    final r1 = _hash(k, salt), r2 = _hash(k, salt + 1), r3 = _hash(k, salt + 2);
    final xw = k * spacing + (r2 - 0.5) * spacing * 0.8;
    final x = xw - scroll;
    final base = ridgeY(xw, size.width, groundY) + sink;
    var h = minH + (maxH - minH) * r1 * r1;
    if (r3 > 0.93) h *= 1.5; // the odd tall stem
    final lean = (r2 - 0.5) * 0.9;
    final w = 1.6 + r3 * 1.4;
    final tip = Offset(x + math.sin(lean) * h, base - math.cos(lean) * h);
    final bend = Offset(x + math.sin(lean) * h * 0.35, base - h * 0.55);
    final p = paths[(r3 * shades.length).floor().clamp(0, shades.length - 1)];
    p
      ..moveTo(x - w / 2, base)
      ..quadraticBezierTo(bend.dx - w * 0.2, bend.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(bend.dx + w * 0.4, bend.dy, x + w / 2, base)
      ..close();
    if (rim != null && h > maxH * 0.8) {
      rimPath
        ..moveTo(bend.dx, bend.dy)
        ..quadraticBezierTo(
            (bend.dx + tip.dx) / 2, (bend.dy + tip.dy) / 2 - 1, tip.dx, tip.dy);
    }
  }
  for (var i = 0; i < shades.length; i++) {
    canvas.drawPath(paths[i], Paint()..color = shades[i]);
  }
  if (rim != null) {
    canvas.drawPath(
        rimPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = rim);
  }
}

class MeadowBackPainter extends CustomPainter {
  MeadowBackPainter({
    required this.scroll,
    required this.groundFromBottom,
    this.halos = const [],
  }) : super(repaint: scroll);

  /// The pages' scroll offset in pixels (0 = first tree centred).
  final ValueListenable<double> scroll;

  /// Page i's tree glow: its blossom colour and camera zoom, or null (the
  /// patch). Painted here, world-locked, not on the page: a glow is wider than
  /// a page, and on the page it was cut into a hard vertical edge mid-swipe.
  final List<(Color, double)?> halos;

  /// The soil line's distance from the bottom edge (same for every page).
  final double groundFromBottom;

  static final List<(Offset, double, double)> _stars = () {
    final rnd = math.Random(7); // fixed: the same sky every launch
    return List.generate(70, (_) {
      final p = Offset(rnd.nextDouble(), math.pow(rnd.nextDouble(), 1.4) * 0.7);
      return (p, 0.4 + rnd.nextDouble() * 0.8, 0.10 + rnd.nextDouble() * 0.40);
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final s = scroll.value;
    final groundY = size.height - groundFromBottom;
    final c = Tokens.cosmos, o = Tokens.orchard;

    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: c.night,
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromLTRB(0, 0, size.width, groundY)));

    // Stars over a band 1.6 screens wide, wrapped, drifting slowly.
    final span = size.width * 1.6;
    final star = Paint();
    for (final (p, r, a) in _stars) {
      final x = (p.dx * span - s * kStarParallax) % span;
      if (x > size.width + 2) continue;
      star.color = c.star.withValues(alpha: a);
      canvas.drawCircle(Offset(x, p.dy * groundY), r, star);
    }

    for (var i = 0; i < halos.length; i++) {
      final h = halos[i];
      final left = i * size.width - s;
      if (h == null || left > size.width * 1.5 || left < -size.width * 1.5) {
        continue;
      }
      final frame = treeFrame(size, groundY, h.$2).shift(Offset(left, 0));
      HaloPainter(tree: frame, colour: h.$1).paint(canvas, size);
    }

    // The ridge, sampled across the screen.
    final ridge = Path()..moveTo(-1, ridgeY(s - 1, size.width, groundY));
    for (var x = 0.0; x <= size.width + 6; x += 6) {
      ridge.lineTo(x, ridgeY(s + x, size.width, groundY));
    }
    final land = Path.from(ridge)
      ..lineTo(size.width + 6, size.height + 1)
      ..lineTo(-1, size.height + 1)
      ..close();
    canvas.drawPath(
        land,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.hillTop, c.hillDeep],
          ).createShader(
              Rect.fromLTRB(0, groundY - kRidgeDip * size.width, size.width, size.height)));

    // Back grass: dense, tall, standing just behind the ridge line.
    _paintGrass(canvas, size,
        scroll: s,
        groundY: groundY,
        spacing: 2.6,
        minH: 7,
        maxH: 24,
        sink: 1.5,
        salt: 11,
        shades: [o.grassBack, Color.lerp(o.grassBack, o.grassFront, 0.5)!, o.grassFront],
        rim: o.grassRim);

    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = c.hillRim.withValues(alpha: c.hillRim.a * 0.6));
  }

  @override
  bool shouldRepaint(MeadowBackPainter old) =>
      old.scroll != scroll ||
      old.groundFromBottom != groundFromBottom ||
      !listEquals(old.halos, halos);
}

/// Short grass in FRONT of the trees, so each trunk's foot stands in it.
class MeadowFrontPainter extends CustomPainter {
  MeadowFrontPainter({required this.scroll, required this.groundFromBottom})
      : super(repaint: scroll);

  final ValueListenable<double> scroll;

  /// The soil line's distance from the bottom edge (same for every page).
  final double groundFromBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Tokens.orchard;
    final groundY = size.height - groundFromBottom;
    _paintGrass(canvas, size,
        scroll: scroll.value,
        groundY: groundY,
        spacing: 3.6,
        minH: 4,
        maxH: 13,
        sink: 6,
        salt: 29,
        shades: [o.grassBack, Color.lerp(o.grassBack, Tokens.cosmos.hillTop, 0.5)!]);
  }

  @override
  bool shouldRepaint(MeadowFrontPainter old) =>
      old.scroll != scroll || old.groundFromBottom != groundFromBottom;
}

/// One tree's light on the sky behind it, in its blossom's colour.
class HaloPainter extends CustomPainter {
  HaloPainter({required this.tree, required this.colour});
  final Rect tree;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final s = tree.width / kTreeArtW;
    final centre = tree.topLeft + kHaloCentre * s;
    final r = kHaloRadius * s;
    final a = Tokens.orchard.haloAlpha;
    canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            colour.withValues(alpha: a),
            colour.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: centre, radius: r)));
  }

  @override
  bool shouldRepaint(HaloPainter old) =>
      old.tree != tree || old.colour != colour;
}

/// A tree's props on the meadow. [front] paints what stands before the trunk
/// (flowers, mushrooms, stones, fireflies); otherwise what stands behind it
/// (fence, lantern). Every prop sits on [ridgeY], so it follows the knoll.
class DecorPainter extends CustomPainter {
  DecorPainter({
    required this.tree,
    required this.decor,
    required this.front,
    required this.groundY,
    required this.pageIndex,
  });

  final Rect tree;
  final Set<TreeDecor> decor;
  final bool front;
  final double groundY;
  final int pageIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (decor.isEmpty) return;
    final s = tree.width / kTreeArtW;
    final trunk = tree.left + kTreeBaseX * s;
    final world0 = pageIndex * size.width;
    double ground(double x) => ridgeY(world0 + x, size.width, groundY);

    if (!front) {
      if (decor.contains(TreeDecor.fence)) _fence(canvas, trunk, s, ground);
      if (decor.contains(TreeDecor.lantern)) _lantern(canvas, trunk, s, ground);
      return;
    }
    if (decor.contains(TreeDecor.stones)) _stones(canvas, trunk, s, ground);
    if (decor.contains(TreeDecor.mushrooms)) _mushrooms(canvas, trunk, s, ground);
    if (decor.contains(TreeDecor.flowers)) _flowers(canvas, trunk, s, ground);
    if (decor.contains(TreeDecor.fireflies)) _fireflies(canvas, s);
  }

  void _fence(Canvas c, double trunk, double s, double Function(double) g) {
    final paint = Paint()..color = Tokens.orchard.fence;
    const n = 6;
    final x0 = trunk + 64 * s, step = 17 * s, h = 30 * s, w = 4.2 * s;
    final tops = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = x0 + i * step;
      final y = g(x) + 2;
      final ph = h * (1 - 0.06 * (i % 2));
      c.drawPath(
          Path()
            ..moveTo(x - w / 2, y)
            ..lineTo(x - w / 2, y - ph + w / 2)
            ..lineTo(x, y - ph)
            ..lineTo(x + w / 2, y - ph + w / 2)
            ..lineTo(x + w / 2, y)
            ..close(),
          paint);
      tops.add(Offset(x, y));
    }
    final rail = Paint()
      ..color = Tokens.orchard.fence
      ..strokeWidth = 2.6 * s
      ..strokeCap = StrokeCap.round;
    for (final f in const [0.38, 0.72]) {
      for (var i = 0; i < n - 1; i++) {
        c.drawLine(tops[i] - Offset(0, h * f), tops[i + 1] - Offset(0, h * f), rail);
      }
    }
  }

  void _lantern(Canvas c, double trunk, double s, double Function(double) g) {
    final x = trunk - 92 * s, y = g(x) + 2;
    final frame = Paint()..color = Tokens.orchard.lanternFrame;
    final light = Tokens.orchard.lanternLight;
    final postH = 66 * s;
    c.drawRect(Rect.fromLTRB(x - 1.6 * s, y - postH, x + 1.6 * s, y), frame);
    // Arm, hook and the lamp hanging from it.
    final armEnd = Offset(x + 16 * s, y - postH + 4 * s);
    c.drawLine(Offset(x, y - postH + 4 * s), armEnd,
        Paint()
          ..color = Tokens.orchard.lanternFrame
          ..strokeWidth = 2.2 * s);
    final lamp = Rect.fromCenter(
        center: armEnd + Offset(0, 13 * s), width: 11 * s, height: 14 * s);
    // Glow first, so the frame draws over its bright core.
    for (final (r, a) in [(46.0, 0.14), (20.0, 0.22)]) {
      c.drawCircle(
          lamp.center,
          r * s,
          Paint()
            ..shader = RadialGradient(colors: [
              light.withValues(alpha: a),
              light.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: lamp.center, radius: r * s)));
    }
    // Light pooled on the grass below it.
    final pool = Rect.fromCenter(
        center: Offset(lamp.center.dx, g(lamp.center.dx) + 3),
        width: 70 * s,
        height: 12 * s);
    c.drawOval(
        pool,
        Paint()
          ..shader = RadialGradient(colors: [
            light.withValues(alpha: 0.10),
            light.withValues(alpha: 0),
          ]).createShader(pool));
    c.drawLine(armEnd, lamp.topCenter, Paint()
      ..color = Tokens.orchard.lanternFrame
      ..strokeWidth = 1.2 * s);
    c.drawRRect(RRect.fromRectAndRadius(lamp, Radius.circular(2.5 * s)),
        Paint()..color = light.withValues(alpha: 0.92));
    c.drawRRect(
        RRect.fromRectAndRadius(lamp, Radius.circular(2.5 * s)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * s
          ..color = Tokens.orchard.lanternFrame);
    c.drawRect(
        Rect.fromCenter(
            center: lamp.topCenter, width: 14 * s, height: 3 * s),
        frame);
  }

  void _stones(Canvas c, double trunk, double s, double Function(double) g) {
    for (final (dx, w, h) in [(36.0, 16.0, 9.0), (50.0, 11.0, 7.0), (-58.0, 13.0, 7.5)]) {
      final x = trunk + dx * s, y = g(x) + 4;
      final r = Rect.fromCenter(
          center: Offset(x, y - h * s / 2), width: w * s, height: h * s);
      c.drawOval(r, Paint()..color = Tokens.orchard.stone);
      c.drawOval(
          Rect.fromLTWH(r.left + r.width * 0.2, r.top + 0.5, r.width * 0.5,
              r.height * 0.38),
          Paint()..color = Tokens.orchard.stoneLit);
    }
  }

  void _mushrooms(Canvas c, double trunk, double s, double Function(double) g) {
    final t = Tokens.orchard;
    for (final (dx, k) in [(-24.0, 1.0), (-34.0, 0.72), (22.0, 0.6)]) {
      final x = trunk + dx * s, y = g(x) + 3;
      final sc = s * k;
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(x - 2.2 * sc, y - 9 * sc, x + 2.2 * sc, y),
              Radius.circular(1.5 * sc)),
          Paint()..color = t.mushroomStem);
      final cap = Rect.fromCenter(
          center: Offset(x, y - 9 * sc), width: 15 * sc, height: 11 * sc);
      c.drawArc(cap, math.pi, math.pi, true, Paint()..color = t.mushroomCap);
      final spot = Paint()..color = t.mushroomSpot;
      c.drawCircle(Offset(x - 3 * sc, y - 12 * sc), 1.3 * sc, spot);
      c.drawCircle(Offset(x + 2.5 * sc, y - 11 * sc), 1.0 * sc, spot);
    }
  }

  void _flowers(Canvas c, double trunk, double s, double Function(double) g) {
    final t = Tokens.orchard;
    final stem = Paint()
      ..color = t.stem
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round;
    const spots = [-148.0, -121.0, -104.0, -70.0, -47.0, 30.0, 58.0, 84.0, 118.0, 139.0];
    for (var i = 0; i < spots.length; i++) {
      final x = trunk + spots[i] * s, y = g(x) + 4;
      final h = (9 + 6 * _hash(i, 3)) * s;
      final head = Offset(x + (_hash(i, 4) - 0.5) * 4 * s, y - h);
      c.drawLine(Offset(x, y), head, stem);
      final petal = Paint()..color = t.petals[i % t.petals.length];
      final r = (2.0 + _hash(i, 5)) * s;
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * math.pi / 5 + i;
        c.drawCircle(head + Offset(math.cos(a), math.sin(a)) * r, r * 0.75, petal);
      }
      c.drawCircle(head, r * 0.55, Paint()..color = t.mushroomSpot);
    }
  }

  void _fireflies(Canvas c, double s) {
    final f = Tokens.orchard.firefly;
    // Artboard units: around and under the canopy, never over the fruit.
    const at = [
      Offset(44, 470), Offset(372, 440), Offset(30, 590), Offset(388, 575),
      Offset(120, 640), Offset(262, 628), Offset(70, 380), Offset(350, 330),
      Offset(210, 648),
    ];
    for (var i = 0; i < at.length; i++) {
      final p = tree.topLeft + at[i] * s;
      final r = (7 + 4 * _hash(i, 9)) * s;
      c.drawCircle(
          p,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              f.withValues(alpha: 0.30),
              f.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: p, radius: r)));
      c.drawCircle(p, 1.3 * s, Paint()..color = f.withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(DecorPainter old) =>
      old.tree != tree ||
      old.front != front ||
      old.groundY != groundY ||
      old.pageIndex != pageIndex ||
      !setEquals(old.decor, decor);
}
