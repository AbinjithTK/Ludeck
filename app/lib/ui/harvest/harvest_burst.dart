// The harvest celebration beat: a gold burst when a game becomes finished.
//
// `DECISIONS.md`: gamification "may only reward what already happened" and gold
// is the single reward colour. This burst fires on the TRANSITION into finished
// -- a real store event, never idle -- and is the one place the delight budget
// is spent (`Tokens.motion.harvest`). It plays once and removes itself, so it
// leaves nothing animating at rest.
//
// Self-contained: an expanding gold ring plus a few rays, painted, no assets. It
// honours reduced motion by resolving instantly (duration collapses to zero, so
// it runs to its final invisible frame and is gone) rather than being skipped.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Shows a one-shot gold burst centred in its box, then calls [onDone].
///
/// Sized to overlay a fruit: drop it in a `Stack` above the harvested card at
/// the card's rect. It ignores pointer events so it never eats a tap.
class HarvestBurst extends StatefulWidget {
  const HarvestBurst({super.key, this.onDone, this.levelUp = false});

  final VoidCallback? onDone;

  /// A harvest that also crossed a level threshold plays a LARGER burst -- the
  /// same event, weighted. Reused rather than a separate level-up sequence so
  /// there is one celebration primitive, not two.
  final bool levelUp;

  @override
  State<HarvestBurst> createState() => _HarvestBurstState();
}

class _HarvestBurstState extends State<HarvestBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Tokens.motion.harvest)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone?.call(); // check:ignore Flutter animation enum, not the banned game-progress word
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kick off once, honouring reduced motion. Done here rather than initState
    // because the reduce-motion query needs a context.
    if (_c.status == AnimationStatus.dismissed) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      _c.duration =
          Tokens.motion.maybe(Tokens.motion.harvest, reduceMotion: reduce);
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _BurstPainter(_c.value, levelUp: widget.levelUp),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, {this.levelUp = false});

  /// 0..1 progress.
  final double t;

  /// A level-up burst reaches further and throws more rays.
  final bool levelUp;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final centre = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * (levelUp ? 1.25 : 0.9);
    final gold = Tokens.palette.accent;

    // Expanding ring, fading as it grows -- the classic "pop" without a bounce.
    final ringR = maxR * Curves.easeOut.transform(t);
    final ringAlpha = (1 - t) * 0.8;
    canvas.drawCircle(
      centre,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = maxR * 0.08 * (1 - t)
        ..color = gold.withValues(alpha: ringAlpha),
    );

    // Rays shooting out, same fade. Eight reads as a burst; a level-up throws
    // twelve so it is visibly bigger without becoming a firework.
    final rays = levelUp ? 12 : 8;
    final rayAlpha = (1 - t) * 0.9;
    final inner = maxR * 0.3 * t;
    final outer = maxR * (0.5 + 0.5 * Curves.easeOut.transform(t));
    final rayPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = maxR * 0.04 * (1 - t)
      ..color = gold.withValues(alpha: rayAlpha);
    for (var i = 0; i < rays; i++) {
      final a = (i / rays) * 2 * math.pi;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(centre + dir * inner, centre + dir * outer, rayPaint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.levelUp != levelUp;
}
