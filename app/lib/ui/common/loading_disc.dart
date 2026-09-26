// A game disc that spins while something is on its way: a cover image loading,
// or a catalogue search that is taking long enough to be noticed.
//
// Motion rules, and why:
//  - The spin is LINEAR. Easing is for a change of state; a spinner is a
//    steady state, and an eased loop reads as a stutter once per turn.
//  - Only a transform animates. The disc is painted once into its own layer
//    (RepaintBoundary) and rotated, so a screen of loading covers costs no
//    repaint per frame.
//  - A cached cover never shows the disc at all (`wasSynchronouslyLoaded`):
//    animating something that is already here is noise.
//  - The cover lands with a `Tokens.motion.swap` fade on the strong ease-out,
//    and the disc stops its ticker the moment the first frame arrives.
//  - Reduced motion: the disc is drawn still and the cover appears without a
//    fade, via `Tokens.motion.maybe`.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// One full turn. Slow enough to read as a disc, fast enough to read as busy.
const Duration kDiscTurn = Duration(milliseconds: 1400);

/// A spinning game disc. Decorative: it carries no semantics of its own.
class LoadingDisc extends StatefulWidget {
  const LoadingDisc({super.key, required this.diameter, this.spinning = true});

  final double diameter;

  /// False parks the disc (and its ticker) without unmounting it, so a cover
  /// fading in over it does not also watch it stop mid-frame.
  final bool spinning;

  @override
  State<LoadingDisc> createState() => _LoadingDiscState();
}

class _LoadingDiscState extends State<LoadingDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn =
      AnimationController(vsync: this, duration: kDiscTurn);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LoadingDisc old) {
    super.didUpdateWidget(old);
    if (old.spinning != widget.spinning) _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.spinning && !still) {
      if (!_turn.isAnimating) _turn.repeat();
    } else {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.diameter,
        child: RotationTransition(
          turns: _turn,
          child: RepaintBoundary(
            child: CustomPaint(painter: const _DiscPainter()),
          ),
        ),
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Data side: near-black, with a faint cool-to-warm sheen. The sheen is a
    // sweep, so it is NOT rotationally symmetric -- that asymmetry is what
    // makes the rotation visible at all. A perfectly even disc looks parked.
    // Optical, not vinyl: a cool silver-violet base with two narrow iridescent
    // bands. First pass used a wide gold band and read as a record label.
    final base = Tokens.cosmos.discBase;
    final body = Paint()
      ..shader = SweepGradient(
        colors: [
          base,
          Tokens.cosmos.hero[2].withValues(alpha: 0.95),
          base,
          base,
          Tokens.palette.accent.withValues(alpha: 0.35),
          base,
        ],
        stops: const [0.0, 0.10, 0.22, 0.52, 0.60, 0.72],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, body);

    // One faint track boundary instead of grooves: optical discs have no
    // visible grooves, and rings are what made the first pass read as vinyl.
    canvas.drawCircle(
        c,
        r * 0.40,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.5, r * 0.01)
          ..color = Tokens.palette.text.withValues(alpha: 0.10));

    // One bright glint arc on the outer data band: the clearest turn cue.
    final glint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, r * 0.07)
      ..color = Tokens.palette.text.withValues(alpha: 0.28);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.78), -math.pi / 2,
        math.pi / 5, false, glint);

    // Rim, hub ring, and the hole the background shows through.
    canvas.drawCircle(
        c,
        r - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Tokens.palette.text.withValues(alpha: 0.12));
    // Clear plastic hub, a thin gold clamp ring, then the hole.
    canvas.drawCircle(c, r * 0.24,
        Paint()..color = Tokens.cosmos.discHub);
    canvas.drawCircle(
        c,
        r * 0.17,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, r * 0.035)
          ..color = Tokens.palette.accent.withValues(alpha: 0.75));
    canvas.drawCircle(c, r * 0.09, Paint()..color = Tokens.cosmos.panelDeep);
  }

  @override
  bool shouldRepaint(_DiscPainter old) => false;
}

/// A cover image that loads on a spinning disc and fades in over it.
///
/// [placeholder] is shown when there is no URL or the image fails, so a
/// missing cover never leaves a disc spinning forever.
class DiscCover extends StatelessWidget {
  const DiscCover({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.placeholder,
    this.radius = 6,
  });

  final String? url;
  final double width;
  final double height;
  final Widget placeholder;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return placeholder;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Image.network(
          u,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => placeholder,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            final landed = frame != null;
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Tokens.cosmos.panelDeep),
                Center(
                  child: AnimatedOpacity(
                    opacity: landed ? 0 : 1,
                    duration: Tokens.motion
                        .maybe(Tokens.motion.swap, reduceMotion: still),
                    curve: Tokens.motion.easeOut,
                    child: LoadingDisc(
                      diameter: width * 0.86,
                      spinning: !landed,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: landed ? 1 : 0,
                  duration: Tokens.motion
                      .maybe(Tokens.motion.swap, reduceMotion: still),
                  curve: Tokens.motion.easeOut,
                  child: child,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The search-in-flight state: nothing for the first [delay], then a disc.
///
/// A local search answers in a few milliseconds, and a disc that flashes for
/// one frame reads as a glitch (the reason this screen stayed blank before).
/// Past the delay the wait is real and deserves a signal.
class DelayedSearchDisc extends StatefulWidget {
  const DelayedSearchDisc({super.key, this.delay = kSearchDiscDelay});

  final Duration delay;

  @override
  State<DelayedSearchDisc> createState() => _DelayedSearchDiscState();
}

/// Below this a wait is not perceived as waiting.
const Duration kSearchDiscDelay = Duration(milliseconds: 350);

class _DelayedSearchDiscState extends State<DelayedSearchDisc> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink(key: Key('search-disc-hidden'));
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Center(
      key: const Key('search-disc'),
      child: Semantics(
        liveRegion: true,
        label: 'Searching',
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration:
              Tokens.motion.maybe(Tokens.motion.swap, reduceMotion: still),
          curve: Tokens.motion.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LoadingDisc(diameter: 72),
              SizedBox(height: Tokens.space.sm),
              ExcludeSemantics(
                child: Text('Searching',
                    style: TextStyle(
                        fontSize: Tokens.type.caption,
                        color: Tokens.palette.textDim)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
