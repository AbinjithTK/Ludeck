// The ground tray: games on no tree yet, and the way onto one.
//
// Collapsed it is the small fanned pile with its count, and the add button as
// its end cap. Tapping (or pulling) the pile opens it to the right into a strip
// of every cover on the ground, which scrolls sideways; press and hold a cover
// to lift it, and drag it onto a tree to hang it there. The add button rides
// the tray's right end in both states, so "add a game" and "put it on a tree"
// read as one flow: things arrive here, and go up from here.
//
// Motion (DECISIONS.md "Motion"):
//  - open and close are a critically damped spring, retargeted from the value
//    and velocity on screen, so a second tap mid-flight reverses it smoothly;
//    close is the snappier spring (exits are quicker than entrances)
//  - pulling the pile tracks the finger 1:1, and on release the decision uses
//    a momentum projection (0.998 deceleration), not where the finger stopped
//  - the strip rubber-bands at both ends
//  - press feedback on pointer-down; lift after a 320ms hold
//  - reduce motion: it opens and closes instantly

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../tokens.dart';
import 'fruit_look.dart';

/// How long a cover must be held before it lifts. Long enough that a sideways
/// swipe through the strip always scrolls, short enough to feel direct.
const Duration kLiftDelay = Duration(milliseconds: 320);

/// Where a released open/close lands, from [value] (0 closed .. 1 open) moving
/// at [velocity] (units/s): Apple's projection with deceleration 0.998.
bool trayProjectsOpen(double value, double velocity) {
  final d = Tokens.motion.deceleration;
  return value + velocity * d / (1 - d) / 1000 > 0.5;
}

class GroundTray extends StatefulWidget {
  const GroundTray({
    super.key,
    required this.items,
    required this.addButton,
    required this.onOpen,
    required this.onLift,
    required this.onLiftMove,
    required this.onLiftEnd,
    this.lifted,
  });

  final List<TreeItem> items;

  /// The add control, shown as the tray's end cap.
  final Widget addButton;

  /// Tap on a cover.
  final void Function(TreeItem item) onOpen;

  /// A cover was held and lifted at [from] (its global rect), finger at [at].
  final void Function(TreeItem item, Rect from, Offset at) onLift;
  final void Function(Offset at) onLiftMove;
  final void Function(Offset at, Velocity velocity) onLiftEnd;

  /// The game currently in the user's hand: its place in the strip is left
  /// as a faint gap until it lands somewhere.
  final TreeItem? lifted;

  @override
  State<GroundTray> createState() => _GroundTrayState();
}

class _GroundTrayState extends State<GroundTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  // Height fits the 56pt add button inside the 4pt inset and 1pt edge.
  static const double _h = 66, _pad = 4, _edge = 1, _cap = 56, _gap = 4;

  /// How much the tray widens from closed to open (set each layout), so a
  /// pull can be tracked 1:1.
  double _travel = 1;

  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(GroundTray old) {
    super.didUpdateWidget(old);
    if (widget.items.isEmpty && _c.value != 0) _c.value = 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _settle(bool open, [double velocity = 0]) {
    if (_reduce) {
      _c.value = open ? 1 : 0;
      return;
    }
    final m = Tokens.motion;
    _c.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: open ? m.stiffnessDefault : m.stiffnessSnappy,
          ratio: m.dampingDefault),
      _c.value,
      open ? 1 : 0,
      velocity,
    )).then((_) {
      // A spring stops within tolerance of its target, not on it: snap, so
      // "closed" is exactly 0 and the strip is really gone. Only on a natural
      // finish; an interrupted spring never completes this future.
      if (mounted) _c.value = open ? 1 : 0;
    });
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    // Aim by where it is heading, so a tap mid-open closes it and vice versa.
    _settle(!(_c.status == AnimationStatus.forward ||
        (_c.isAnimating ? _c.velocity > 0 : _c.value > 0.5)));
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      // Nothing on the ground: the add button stands alone where the tray
      // starts, so it is in the same place the tray will grow from.
      return Align(alignment: Alignment.centerLeft, child: widget.addButton);
    }
    final n = items.length;
    final label = n == 1 ? '1 on the ground' : '$n on the ground';
    final style =
        TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.textDim);
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(builder: (context, box) {
      final labelW = (TextPainter(
            text: TextSpan(text: label, style: style),
            textScaler: scaler,
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout())
              .width +
          Tokens.space.sm;
      final fixed = (_pad + _edge) * 2 + _cap + _gap + _cap;
      final stripW = (box.maxWidth - fixed).clamp(0.0, double.infinity);
      // Never wider than the space: at large text the label gives way.
      final closedLabelW = labelW.clamp(0.0, stripW);
      _travel = (stripW - closedLabelW).clamp(1.0, double.infinity);

      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: _h,
              padding: const EdgeInsets.all(_pad),
              decoration: BoxDecoration(
                color: Tokens.cosmos.panelDeep,
                borderRadius: BorderRadius.circular(_h / 2),
                border: Border.all(color: Tokens.cosmos.panelEdge),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _handle(items, label, closedLabelW, t),
                SizedBox(
                  width: stripW * t,
                  child: t == 0
                      ? null
                      : ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: stripW,
                            maxWidth: stripW,
                            child: Opacity(
                              opacity: Curves.easeOut.transform(t),
                              child: _strip(items),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: _gap),
                widget.addButton,
              ]),
            ),
          );
        },
      );
    });
  }

  /// The pile and its count: tap or pull to open, and the close control
  /// once open.
  Widget _handle(List<TreeItem> items, String label, double labelW, double t) {
    final n = items.length;
    return Semantics(
      button: true,
      expanded: t > 0.5,
      label: t > 0.5
          ? 'Hide the games on the ground'
          : '${n == 1 ? '1 game' : '$n games'} on the ground. Show them',
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('orchard-ground'),
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        onHorizontalDragStart: (_) => _c.stop(),
        onHorizontalDragUpdate: (d) =>
            _c.value = (_c.value + d.delta.dx / _travel).clamp(0.0, 1.0),
        onHorizontalDragEnd: (d) {
          final v = d.velocity.pixelsPerSecond.dx / _travel;
          _settle(trayProjectsOpen(_c.value, v), v);
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: _cap,
            height: _cap,
            child: Stack(alignment: Alignment.center, children: [
              Opacity(opacity: 1 - t, child: _Fan(items: items)),
              if (t > 0)
                Opacity(
                  opacity: t,
                  child: Icon(Icons.chevron_left_rounded,
                      size: 28, color: Tokens.palette.text),
                ),
            ]),
          ),
          SizedBox(
            width: labelW * (1 - t),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: labelW,
                maxWidth: labelW,
                child: Opacity(
                  opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                          fontSize: Tokens.type.caption,
                          color: Tokens.palette.textDim)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _strip(List<TreeItem> items) {
    return ListView.separated(
      key: const Key('ground-strip'),
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: Tokens.space.xxs),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(width: Tokens.space.xs),
      itemBuilder: (context, i) => _TrayCover(
        key: ValueKey('ground-${items[i].game.igdbId}'),
        item: items[i],
        lifted: widget.lifted?.game.igdbId == items[i].game.igdbId,
        onTap: () => widget.onOpen(items[i]),
        onLift: widget.onLift,
        onLiftMove: widget.onLiftMove,
        onLiftEnd: widget.onLiftEnd,
      ),
    );
  }
}

class _TrayCover extends StatefulWidget {
  const _TrayCover({
    super.key,
    required this.item,
    required this.lifted,
    required this.onTap,
    required this.onLift,
    required this.onLiftMove,
    required this.onLiftEnd,
  });

  final TreeItem item;
  final bool lifted;
  final VoidCallback onTap;
  final void Function(TreeItem item, Rect from, Offset at) onLift;
  final void Function(Offset at) onLiftMove;
  final void Function(Offset at, Velocity velocity) onLiftEnd;

  @override
  State<_TrayCover> createState() => _TrayCoverState();
}

class _TrayCoverState extends State<_TrayCover> {
  bool _down = false;

  static const double w = 42;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final look = lookOf(item);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: '${item.game.title}, ${lookLabel(look)}. On the ground. '
          'Hold and drag onto a tree to hang it',
      excludeSemantics: true,
      child: RawGestureDetector(
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) => r
              ..onTapDown = ((_) { setState(() => _down = true); })
              ..onTapCancel = (() { setState(() => _down = false); })
              ..onTapUp = ((_) { setState(() => _down = false); })
              ..onTap = widget.onTap,
          ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: kLiftDelay),
            (r) => r
              ..onLongPressStart = (d) {
                setState(() => _down = false);
                final box = context.findRenderObject() as RenderBox?;
                if (box == null || !box.hasSize) return;
                final from = box.localToGlobal(Offset.zero) & box.size;
                widget.onLift(item, from, d.globalPosition);
              }
              ..onLongPressMoveUpdate = ((d) { widget.onLiftMove(d.globalPosition); })
              ..onLongPressEnd =
                  (d) => widget.onLiftEnd(d.globalPosition, d.velocity),
          ),
        },
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: Tokens.motion.maybe(Tokens.motion.press, reduceMotion: reduce),
          curve: Tokens.motion.easeOut,
          child: AnimatedOpacity(
            opacity: widget.lifted ? 0.18 : 1,
            duration: Tokens.motion.maybe(Tokens.motion.swap, reduceMotion: reduce),
            child: Center(
              child: FruitImage(
                  game: item.game, look: look, width: w, radius: 6),
            ),
          ),
        ),
      ),
    );
  }
}

/// A game's fruit image (its cover with its look), from the shared cache.
/// Fades in when it arrives; shown at once when already built.
class FruitImage extends StatefulWidget {
  const FruitImage({
    super.key,
    required this.game,
    required this.look,
    required this.width,
    this.radius = 6,
    this.border,
    this.shadow = false,
  });

  final Game game;
  final FruitLook look;
  final double width;
  final double radius;
  final BoxBorder? border;
  final bool shadow;

  @override
  State<FruitImage> createState() => _FruitImageState();
}

class _FruitImageState extends State<FruitImage> {
  Uint8List? _png;
  bool _instant = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(FruitImage old) {
    super.didUpdateWidget(old);
    if (old.game.igdbId != widget.game.igdbId ||
        old.game.coverUrl != widget.game.coverUrl ||
        old.look != widget.look) {
      _resolve();
    }
  }

  void _resolve() {
    final now = fruitPngNow(widget.game, widget.look);
    if (now != null) {
      _png = now;
      _instant = true;
      return;
    }
    _instant = false;
    final key = (widget.game.igdbId, widget.look);
    fruitPng(widget.game, widget.look).then((png) {
      if (!mounted || key != (widget.game.igdbId, widget.look)) return;
      setState(() => _png = png);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width, h = w * kFruitH / kFruitW;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final png = _png;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Tokens.cosmos.panelDeep,
        borderRadius: BorderRadius.circular(widget.radius),
        border: widget.border,
        boxShadow: widget.shadow
            ? [
                BoxShadow(
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                    color: Tokens.palette.bg.withValues(alpha: 0.55)),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: png == null
          ? null
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: _instant ? 1 : 0, end: 1),
              duration: Tokens.motion
                  .maybe(Tokens.motion.swap, reduceMotion: reduce || _instant),
              curve: Tokens.motion.easeOut,
              builder: (context, o, child) => Opacity(opacity: o, child: child),
              child: Image.memory(png,
                  fit: BoxFit.cover, gaplessPlayback: true, width: w, height: h),
            ),
    );
  }
}

/// The collapsed pile: the first three covers, fanned.
class _Fan extends StatelessWidget {
  const _Fan({required this.items});
  final List<TreeItem> items;

  @override
  Widget build(BuildContext context) {
    final fan = items.take(3).toList();
    const w = 26.0;
    return SizedBox(
      width: w + 10.0 * (fan.length - 1),
      height: w * 4 / 3 + 4,
      child: Stack(children: [
        for (var i = fan.length - 1; i >= 0; i--)
          Positioned(
            left: 10.0 * i,
            top: i.isEven ? 4 : 0,
            child: Transform.rotate(
              angle: (i - 1) * 0.12,
              child: FruitImage(
                  game: fan[i].game,
                  look: lookOf(fan[i]),
                  width: w,
                  radius: 4,
                  border: Border.all(color: Tokens.cosmos.panelEdge)),
            ),
          ),
      ]),
    );
  }
}
