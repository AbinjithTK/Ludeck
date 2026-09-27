// A game in flight: from your hand to where it lands.
//
// Released over a tree, the card flies to the exact spot its fruit will pop
// in (fruit_slots.g.dart), shrinking to the hanging size, and holds there
// until the Rive file's own pop takes over, then fades. Released over
// nothing, it flies back to where it was picked up.
//
// Per-axis springs seeded with the finger's release velocity (px/s), so a
// throw carries on in the direction it was thrown instead of restarting from
// rest. Damping 0.8: the slight overshoot DECISIONS.md allows after a drag
// release. The card leans into its own horizontal speed, like a held card
// does. Reduce motion: it arrives at once.

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import '../tokens.dart';
import 'fruit_look.dart';
import 'ground_tray.dart' show FruitImage;

class FruitFlight extends StatefulWidget {
  const FruitFlight({
    super.key,
    required this.item,
    required this.from,
    required this.fromWidth,
    required this.velocity,
    required this.to,
    required this.toWidth,
    this.hold = Duration.zero,
    this.fade = true,
    this.onArrive,
    required this.onDone,
  });

  final TreeItem item;

  /// Card centre and width at release, in this overlay's coordinates.
  final Offset from;
  final double fromWidth;

  /// Finger velocity at release, px/s.
  final Offset velocity;

  /// Where it lands and how wide it is there.
  final Offset to;
  final double toWidth;

  /// Stay visible at least this long after release (until the tree's pop).
  final Duration hold;

  /// Fade out on arrival (it became fruit). False: vanish on arrival (it is
  /// back in the tray, which shows it again).
  final bool fade;

  final VoidCallback? onArrive;
  final VoidCallback onDone;

  @override
  State<FruitFlight> createState() => _FruitFlightState();
}

class _FruitFlightState extends State<FruitFlight>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late SpringSimulation _x, _y, _w;
  double _t = 0;
  double? _arrivedAt;
  bool _finished = false;

  static const double _fadeSecs = 0.14;
  static final Tolerance _tol = Tolerance(distance: 0.5, velocity: 20);

  @override
  void initState() {
    super.initState();
    final m = Tokens.motion;
    final throwSpring = SpringDescription.withDampingRatio(
        mass: 1, stiffness: m.stiffnessDefault, ratio: m.dampingMomentum);
    final sizeSpring = SpringDescription.withDampingRatio(
        mass: 1, stiffness: m.stiffnessDefault, ratio: m.dampingDefault);
    final w = widget;
    _x = SpringSimulation(throwSpring, w.from.dx, w.to.dx, w.velocity.dx, tolerance: _tol);
    _y = SpringSimulation(throwSpring, w.from.dy, w.to.dy, w.velocity.dy, tolerance: _tol);
    _w = SpringSimulation(sizeSpring, w.fromWidth, w.toWidth, 0, tolerance: _tol);
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_finished) {
      _t = 10;
      _arrive();
      _finish();
    }
  }

  void _arrive() {
    if (_arrivedAt != null) return;
    _arrivedAt = _t;
    widget.onArrive?.call();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _ticker.stop();
    // After this frame: the parent removes this widget in onDone.
    SchedulerBinding.instance.addPostFrameCallback((_) => widget.onDone());
  }

  void _tick(Duration elapsed) {
    _t = elapsed.inMicroseconds / 1e6;
    final settled = (_x.isDone(_t) && _y.isDone(_t)) ||
        (Offset(_x.x(_t), _y.x(_t)) - widget.to).distance < 1.5;
    if (settled || _t > 2.5) _arrive();
    if (_arrivedAt != null) {
      if (!widget.fade) return _finish();
      final fadeFrom = _arrivedAt! > _holdSecs ? _arrivedAt! : _holdSecs;
      if (_t > fadeFrom + _fadeSecs) return _finish();
    }
    setState(() {});
  }

  double get _holdSecs => widget.hold.inMicroseconds / 1e6;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final w = _w.x(t).clamp(4.0, 400.0);
    final h = w * kFruitH / kFruitW;
    final cx = _finished ? widget.to.dx : _x.x(t);
    final cy = _finished ? widget.to.dy : _y.x(t);
    var opacity = 1.0;
    if (_arrivedAt != null && widget.fade) {
      final fadeFrom = _arrivedAt! > _holdSecs ? _arrivedAt! : _holdSecs;
      opacity = (1 - (t - fadeFrom) / _fadeSecs).clamp(0.0, 1.0);
    }
    final lean = (_x.dx(t) / 2600).clamp(-0.16, 0.16);
    return Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: _finished ? 0 : lean,
            child: FruitImage(
              game: widget.item.game,
              look: lookOf(widget.item),
              width: w,
              radius: w * 0.12,
              shadow: w > 30,
            ),
          ),
        ),
      ),
    );
  }
}
