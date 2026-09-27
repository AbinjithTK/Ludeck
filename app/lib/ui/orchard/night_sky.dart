// The orchard's backdrop: night sky, the blossom's halo, a few stars and the
// hill a tree stands on. The tree file draws only the tree (see
// rive/tree/build_tree.py), so this owns everything behind it at the screen's
// own size and nothing ends at the artboard's edge.
//
// Static on purpose. It is on screen whenever the app is open, which is the
// frequency where ambient motion stops being delight and becomes noise; the
// tree's own sway is the only thing that moves.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tokens.dart';
import 'rive_tree.dart' show kTreeArtW;

/// Where, in artboard units, the blossom's light is centred and how far it
/// reaches (the full canopy spans roughly x 52..366, y 202..632).
const Offset kHaloCentre = Offset(190, 400);
const double kHaloRadius = 260;

/// The ridge: a shallow arc much wider than the screen, so it reads as the
/// top of a hill and not a bump. Width is a multiple of the screen width.
const double kHillWidthFactor = 2.4;
const double kHillRise = 0.075; // arc height as a fraction of its width

class NightSkyPainter extends CustomPainter {
  NightSkyPainter({required this.tree, required this.groundY});

  /// Where the tree's artboard sits on screen (from `treeFrame`).
  final Rect tree;

  /// The soil line: the hill's ridge passes through it under the trunk.
  final double groundY;

  static final List<(Offset, double, double)> _stars = () {
    final rnd = math.Random(7); // fixed: the same sky every launch
    return List.generate(46, (_) {
      final p = Offset(rnd.nextDouble(), math.pow(rnd.nextDouble(), 1.4) * 0.7);
      return (p, 0.4 + rnd.nextDouble() * 0.8, 0.10 + rnd.nextDouble() * 0.40);
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final c = Tokens.cosmos;

    canvas.drawRect(
        full,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: c.night,
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromLTRB(0, 0, size.width, groundY)));

    final star = Paint();
    for (final (p, r, a) in _stars) {
      star.color = c.star.withValues(alpha: a);
      canvas.drawCircle(Offset(p.dx * size.width, p.dy * groundY), r, star);
    }

    final s = tree.width / kTreeArtW;
    final halo = tree.topLeft + kHaloCentre * s;
    canvas.drawCircle(
        halo,
        kHaloRadius * s,
        Paint()
          ..shader = RadialGradient(colors: [c.halo, c.haloClear])
              .createShader(Rect.fromCircle(center: halo, radius: kHaloRadius * s)));

    final hw = size.width * kHillWidthFactor;
    final hill = Rect.fromCenter(
        center: Offset(size.width / 2, groundY + hw * kHillRise),
        width: hw,
        height: hw * kHillRise * 2);
    final ground = Path()
      ..addOval(hill)
      ..addRect(Rect.fromLTRB(-1, groundY + hw * kHillRise, size.width + 1,
          size.height + 1));
    canvas.drawPath(
        ground,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.hillTop, c.hillDeep],
          ).createShader(Rect.fromLTRB(0, groundY, size.width, size.height)));
    canvas.drawArc(
        hill,
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = c.hillRim);
  }

  @override
  bool shouldRepaint(NightSkyPainter old) =>
      old.tree != tree || old.groundY != groundY;
}
