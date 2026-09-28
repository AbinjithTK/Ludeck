// Glass: the one material every control over the orchard is made of.
//
// Before this each control drew its own frosted panel with a flat 1pt white
// hairline all the way round, which is what made the tray, the top actions,
// the shake chip and the pick card all read as outlined rounded rectangles
// (2026-09-28: "the overall style of buttons and ui which is in a rounded
// rectangle should be made something modern"). Glass here has no outline.
// Its edge is light: a rim that catches the sky at the top, fades out down
// the sides and picks up a little again along the bottom, over a sheen that
// is brighter at the top, on a blurred and tinted copy of the scene behind.
// That is how a material separates from a live background without a line
// drawn round it.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// A glass surface in [shape] (a capsule by default). [lit] brightens the
/// rim, for a drop target that is armed.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
    this.lit = false,
    this.blur = 18,
    this.rim = true,
  });

  final Widget child;
  final ShapeBorder shape;
  final bool lit;
  final double blur;

  /// Draw the lit rim. Off for a surface that should read as a soft pool of
  /// glass with no edge at all (the ground tray); a [lit] surface always
  /// shows its rim, because the rim is how a drop target says it is armed.
  final bool rim;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: CustomPaint(
          painter: GlassPainter(shape: shape, lit: lit, rim: rim || lit),
          child: child,
        ),
      ),
    );
  }
}

/// The glass itself, without the blur: tint, sheen and a lit rim. Public so
/// a surface that cannot blur (a share image) draws the same material.
class GlassPainter extends CustomPainter {
  GlassPainter({required this.shape, this.lit = false, this.rim = true});
  final ShapeBorder shape;
  final bool lit;
  final bool rim;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    canvas.drawPath(path, Paint()..color = Tokens.cosmos.glassTint);
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Tokens.cosmos.glassSheen, Tokens.cosmos.glassSheen.withValues(alpha: 0)],
            stops: const [0, 0.6],
          ).createShader(rect));
    if (!rim) return;
    final a = lit ? 1.0 : 0.62;
    canvas.drawPath(
        shape.getInnerPath(rect.deflate(0.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lit ? 1.4 : 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Tokens.cosmos.glassRim.withValues(alpha: 0.42 * a),
              Tokens.cosmos.glassRim.withValues(alpha: 0.05 * a),
              Tokens.cosmos.glassRim.withValues(alpha: 0.03 * a),
              Tokens.cosmos.glassRim.withValues(alpha: 0.16 * a),
            ],
            stops: const [0, 0.45, 0.7, 1],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(GlassPainter old) =>
      old.lit != lit || old.shape != shape || old.rim != rim;
}

/// A round glass button: [child] centred in a [size]pt circle, with the
/// press feedback every control shares (Tokens.motion.press, pressScale) and
/// a selection tick. [label] is what a screen reader says.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.label,
    this.size = 56,
    this.caption,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String label;
  final double size;

  /// A short word under the circle, for an action the glyph alone does not
  /// name (the shake is this app's own idea).
  final String? caption;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final circle = AnimatedScale(
      scale: _down ? Tokens.motion.pressScale : 1,
      duration: Tokens.motion.maybe(Tokens.motion.press, reduceMotion: reduce),
      curve: Tokens.motion.easeOut,
      child: SizedBox.square(
        dimension: widget.size,
        child: Glass(
          shape: const CircleBorder(),
          child: Center(child: widget.child),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: widget.caption == null
            ? circle
            : Column(mainAxisSize: MainAxisSize.min, children: [
                circle,
                SizedBox(height: Tokens.space.xxs),
                Text(widget.caption!,
                    style: TextStyle(
                      fontSize: Tokens.type.caption,
                      fontWeight: FontWeight.w600,
                      color: Tokens.palette.text.withValues(alpha: 0.85),
                      shadows: [Shadow(blurRadius: 6, color: Tokens.cosmos.captionShadow)],
                    )),
              ]),
      ),
    );
  }
}
