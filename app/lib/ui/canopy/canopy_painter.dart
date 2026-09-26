// Paints the canopy: tapered bark and teardrop leaves, in the active skin.
//
// The style is the Liven reference translated to Ludeck's own material: every
// limb is a filled outline whose width eases from thick to thin along a cubic
// Bézier (a stroke cannot taper), and the leaves are one teardrop shape
// repeated at seeded positions. Two tones of bark, three of leaf, no outlines.
//
// Static by design. DECISIONS.md: foliage never browns, thins or sheds, and
// nothing animates at rest (DESIGN.md rejects idle sway as a vestibular
// trigger). Motion on this screen belongs to the zoom between levels, which is
// the widget's, not the painter's.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../tokens.dart';
import 'canopy_layout.dart';

class CanopyPainter extends CustomPainter {
  CanopyPainter(this.layout, {this.litBranchId});

  final CanopyLayout layout;

  /// A fan slot drawn in the lit bark tone (hover target, picked branch).
  final int? litBranchId;

  @override
  void paint(Canvas canvas, Size size) {
    final skin = Tokens.canopy;
    final bark = Paint()..color = skin.barkMid;
    final lit = Paint()..color = skin.barkLit;
    final shade = Paint()..color = skin.barkShade;

    // Order: decoration and twigs first so the main limbs sit on top of their
    // own stubs, then the trunk last so every fork is covered by it.
    for (final t in [...layout.decor, ...layout.twigs]) {
      _limb(canvas, t, bark);
    }
    for (final f in layout.fans) {
      final isLit = f.branch.id == litBranchId;
      if (isLit) {
        _glow(canvas, f.limb, skin.glow);
      }
      _limb(canvas, f.limb, isLit ? lit : bark);
    }
    for (final g in layout.gameTwigs) {
      _limb(canvas, g.limb, bark);
    }
    // A faint shadow side on the trunk gives it volume without a gradient.
    _limb(canvas, layout.trunk, shade, dx: 3);
    _limb(canvas, layout.trunk, bark);

    for (final l in [
      ...layout.decor,
      ...layout.twigs,
      for (final f in layout.fans) f.limb,
      for (final g in layout.gameTwigs) g.limb,
    ]) {
      _leaves(canvas, l, skin);
    }
  }

  static Path taper(Limb limb, {double dx = 0}) {
    const steps = 32;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = limb.curve.at(t);
      final d = limb.curve.tangent(t);
      final len = d.distance == 0 ? 1.0 : d.distance;
      final n = Offset(-d.dy / len, d.dx / len);
      final w = (limb.startWidth +
              (limb.endWidth - limb.startWidth) * math.pow(t, .8)) /
          2;
      left.add(p + n * w + Offset(dx, 0));
      right.add(p - n * w + Offset(dx, 0));
    }
    final path = Path()..moveTo(left.first.dx, left.first.dy);
    for (final q in left.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    // A rounded tip rather than a blunt cut.
    final tip = limb.curve.p3;
    path.quadraticBezierTo(tip.dx, tip.dy, right.last.dx, right.last.dy);
    for (final q in right.reversed.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    return path..close();
  }

  void _limb(Canvas c, Limb l, Paint p, {double dx = 0}) =>
      c.drawPath(taper(l, dx: dx), p);

  void _glow(Canvas c, Limb l, Color colour) => c.drawPath(
        taper(l),
        Paint()
          ..color = colour
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

  /// Teardrop leaves along [l], alternating sides, clear of the last 12% so the
  /// tip stays free for a label or a cover.
  void _leaves(Canvas c, Limb l, TreeSkin skin) {
    if (l.leaves == 0) return;
    var r = (l.seed.abs() * 9301 + 49297) % 233280;
    double rnd() => (r = (r * 9301 + 49297) % 233280) / 233280;
    for (var i = 0; i < l.leaves; i++) {
      final t = .12 + .76 * (i + rnd() * .5) / l.leaves;
      final p = l.curve.at(t);
      final d = l.curve.tangent(t);
      final side = i.isOdd ? 1 : -1;
      final a = math.atan2(d.dy, d.dx) + side * (45 + rnd() * 25) * math.pi / 180;
      final s = .7 + rnd() * .5;
      final pick = rnd();
      final colour = pick < .3
          ? skin.foliageLit
          : (pick < .65 ? skin.foliageNear : skin.foliageFar);
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(a);
      c.scale(s);
      c.drawPath(_leaf, Paint()..color = colour);
      c.drawLine(const Offset(1, 0), const Offset(14, 0),
          Paint()
            ..color = skin.foliageFar
            ..strokeWidth = .8);
      c.restore();
    }
  }

  static final Path _leaf = Path()
    ..moveTo(0, 0)
    ..cubicTo(4, -5, 12, -6, 18, 0)
    ..cubicTo(12, 6, 4, 5, 0, 0)
    ..close();

  @override
  bool shouldRepaint(CanopyPainter old) =>
      old.layout != layout || old.litBranchId != litBranchId;
}
