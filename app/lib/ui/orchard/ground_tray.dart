// The ground tray: games on no tree yet, and the way onto one.
//
// Collapsed it is a small fanned pile of covers with its count. Tapping (or
// pulling) it opens the tray to the right, and the pile DEALS itself out into
// a strip of every cover on the ground: each card travels from its place in
// the pile to its place in the strip, the nearest first, on a small arc like a
// card being dealt, growing and straightening as it goes; the cards that were
// hidden under the pile fade in on their way out. Closing gathers them back
// into the pile, the far ones first. The strip scrolls sideways; press and
// hold a cover to lift it and drag it onto a tree.
//
// The add button is NOT part of the tray: it stays put at the bottom right,
// and the tray opens up to it.
//
// Motion (DECISIONS.md "Motion"):
//  - one critically damped spring drives everything (capsule width, every
//    card, the label and the chevron), retargeted from the value and velocity
//    on screen, so a tap mid-flight reverses it smoothly; close is the
//    snappier spring (exits are quicker than entrances)
//  - pulling the pile tracks the finger 1:1, and on release the decision uses
//    a momentum projection (0.998 deceleration), not where the finger stopped
//  - the strip rubber-bands at both ends
//  - press feedback on pointer-down; lift after a 320ms hold
//  - reduce motion: it opens and closes instantly

import 'dart:math' as math;
import 'dart:ui' as ui;

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

/// Tray geometry, inside the capsule's inset (all in points).
const double kTrayH = 66, kTrayInset = 5, kTrayInner = kTrayH - 2 * kTrayInset;

/// The pile's box, the open state's chevron zone, and the strip's pitch.
const double kPileW = 58, kChevronW = 40, kCoverW = 42, kCoverPitch = 48;

/// Card i's own progress through the deal, from the tray's [t]: card i starts
/// [kDealStagger] x i later (capped), so the pile deals out nearest-first and
/// gathers back far-first. Monotonic in [t]; 0 at t=0 and 1 at t=1.
const double kDealStagger = 0.045;
double dealT(double t, int i) {
  final d = math.min(i, 6) * kDealStagger;
  return ((t - d) / (1 - d)).clamp(0.0, 1.0);
}

/// Card [i]'s pose at deal progress [u]: its rect and rotation in the
/// capsule's inner coordinates. [scroll] is the strip's offset (non-zero only
/// when closing a strip that had been scrolled).
({Rect rect, double angle, double opacity}) dealPose(int i, double u, double scroll) {
  final k = math.min(i, 2);
  const fw = 28.0, fh = fw * 4 / 3;
  final fan = Rect.fromLTWH(
      8 + 10.0 * k, (kTrayInner - fh) / 2 + (k.isEven ? 2 : -2), fw, fh);
  final strip = Rect.fromLTWH(kChevronW + 4 + i * kCoverPitch - scroll,
      (kTrayInner - kCoverW * 4 / 3) / 2, kCoverW, kCoverW * 4 / 3);
  final r = Rect.lerp(fan, strip, u)!;
  // A small arc up and back down, like a card being dealt.
  final lift = -7 * math.sin(math.pi * u);
  return (
    rect: r.shift(Offset(0, lift)),
    angle: (k - 1) * 0.12 * (1 - u),
    opacity: i < 3 ? 1 : Curves.easeOut.transform(u),
  );
}

class GroundTray extends StatefulWidget {
  const GroundTray({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onLift,
    required this.onLiftMove,
    required this.onLiftEnd,
    this.lifted,
    this.receiving = false,
  });

  /// A fruit taken off a tree is being held over the tray: it will go back
  /// on the ground if dropped here, so the tray says so.
  final bool receiving;

  final List<TreeItem> items;

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
  ScrollController _strip = ScrollController();

  /// The strip's offset when a close began, so the cards gather from where
  /// they actually were, not from a strip scrolled back to the start.
  double _closingFrom = 0;

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
    _strip.dispose();
    super.dispose();
  }

  bool get _settledOpen => _c.value == 1 && !_c.isAnimating;

  /// Before the value leaves 1: remember where the strip was, then hand over
  /// from the scrollable strip to the animated cards.
  void _leaveOpen() {
    if (_settledOpen || _c.value == 1) {
      _closingFrom = _strip.hasClients ? _strip.offset : 0;
    }
  }

  void _settle(bool open, [double velocity = 0]) {
    if (!open) _leaveOpen();
    if (open && _c.value == 0) {
      // A fresh strip starts at its first cover, where the deal lands.
      _strip.dispose();
      _strip = ScrollController();
      _closingFrom = 0;
    }
    if (_reduce) {
      setState(() => _c.value = open ? 1 : 0);
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
      // closed is exactly 0 and open exactly 1 (where the strip takes over).
      // Only on a natural finish; an interrupted spring never completes this.
      if (mounted) setState(() => _c.value = open ? 1 : 0);
    });
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    // Aim by where it is heading, so a tap mid-open closes it and vice versa.
    final heading = _c.isAnimating ? _c.velocity > 0 : _c.value > 0.5;
    _settle(!heading);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      if (!widget.receiving) return const SizedBox.shrink();
      // Nothing on the ground yet, but a fruit is on its way down.
      return Align(
        alignment: Alignment.centerLeft,
        child: _Glass(
          lit: true,
          child: SizedBox(
            height: kTrayH - 2,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Tokens.space.lg),
              child: Center(
                widthFactor: 1,
                child: Text('Put it on the ground',
                    style: TextStyle(
                        fontSize: Tokens.type.caption,
                        color: Tokens.palette.text)),
              ),
            ),
          ),
        ),
      );
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
          Tokens.space.md;
      final openW = box.maxWidth;
      // Never wider than the space: at large text the label gives way.
      final closedW = math.min(2 * kTrayInset + kPileW + labelW, openW);
      _travel = math.max(1, openW - closedW);

      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final w = closedW + (openW - closedW) * t;
          final inner = w - 2 * kTrayInset;
          return Align(
            alignment: Alignment.centerLeft,
            child: _Glass(
              lit: widget.receiving,
              child: Container(
              width: w,
              height: kTrayH,
              padding: const EdgeInsets.all(kTrayInset - 1),
              child: Stack(clipBehavior: Clip.hardEdge, children: [
                // The count, riding out to the right as the pile deals.
                Positioned(
                  left: kPileW,
                  top: 0,
                  bottom: 0,
                  width: labelW,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - t * 2.4).clamp(0.0, 1.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: style),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: kChevronW,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: ((t - 0.45) / 0.55).clamp(0.0, 1.0),
                      child: Icon(Icons.chevron_left_rounded,
                          size: 28, color: Tokens.palette.text),
                    ),
                  ),
                ),
                if (_settledOpen)
                  Positioned(
                    left: kChevronW,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: _stripView(items),
                  )
                else
                  ..._dealt(items, t, inner),
                // The handle: the whole pile while closed, the chevron once
                // open. On top, so a pull on the pile always reaches it.
                // KEYED: the number of cards before it changes every frame of
                // the deal, and an unkeyed handle was matched to a different
                // element mid-pull, which dropped the drag (no release, no
                // projection).
                Positioned(
                  key: const ValueKey('tray-handle'),
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: t < 0.5 ? math.min(kPileW + labelW, inner) : kChevronW,
                  child: _handle(n, t),
                ),
              ]),
            ),
            ),
          );
        },
      );
    });
  }

  /// The cards in flight between the pile and the strip.
  List<Widget> _dealt(List<TreeItem> items, double t, double inner) {
    final out = <Widget>[];
    final scroll = _closingFrom;
    // Painted far-to-near, so the pile's top card is card 0.
    for (var i = math.min(items.length, 40) - 1; i >= 0; i--) {
      final u = dealT(t, i);
      if (i >= 3 && u == 0) continue; // still hidden under the pile
      final p = dealPose(i, u, scroll);
      if (p.rect.left > inner + 8 || p.rect.right < -8) continue;
      out.add(Positioned.fromRect(
        key: ValueKey('dealt-${items[i].game.igdbId}'),
        rect: p.rect,
        child: IgnorePointer(
          child: Opacity(
            opacity: p.opacity,
            child: Transform.rotate(
              angle: p.angle,
              child: FruitImage(
                game: items[i].game,
                look: lookOf(items[i]),
                width: p.rect.width,
                radius: 4 + 2 * u,
                border: u < 1 ? Border.all(color: Tokens.cosmos.panelEdge) : null,
              ),
            ),
          ),
        ),
      ));
    }
    return out;
  }

  Widget _handle(int n, double t) => Semantics(
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
          onHorizontalDragStart: (_) {
            _leaveOpen();
            _c.stop();
            if (_c.value == 1) setState(() {}); // hand over from the strip
          },
          onHorizontalDragUpdate: (d) =>
              _c.value = (_c.value + d.delta.dx / _travel).clamp(0.0, 1.0),
          onHorizontalDragEnd: (d) {
            final v = d.velocity.pixelsPerSecond.dx / _travel;
            _settle(trayProjectsOpen(_c.value, v), v);
          },
        ),
      );

  Widget _stripView(List<TreeItem> items) {
    return ListView.builder(
      key: const Key('ground-strip'),
      controller: _strip,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(left: 4, right: 4),
      itemExtent: kCoverPitch,
      itemCount: items.length,
      itemBuilder: (context, i) => Align(
        alignment: Alignment.centerLeft,
        child: _TrayCover(
          key: ValueKey('ground-${items[i].game.igdbId}'),
          item: items[i],
          lifted: widget.lifted?.game.igdbId == items[i].game.igdbId,
          onTap: () => widget.onOpen(items[i]),
          onLift: widget.onLift,
          onLiftMove: widget.onLiftMove,
          onLiftEnd: widget.onLiftEnd,
        ),
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
            // No Center: the card must sit exactly where the deal landed it
            // (left of its 48pt cell), or the hand-over from the animated
            // cards to the list jumps 3pt.
            child: FruitImage(game: item.game, look: look, width: w, radius: 6),
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
        // Loading: a visible glass card, so a cover still downloading reads
        // as a card arriving rather than as a gap.
        color: png == null ? Tokens.cosmos.panel : Tokens.cosmos.panelDeep,
        borderRadius: BorderRadius.circular(widget.radius),
        border: widget.border ??
            (png == null ? Border.all(color: Tokens.cosmos.panelEdge) : null),
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


/// Frosted glass, the way a material sits over a live scene: the meadow
/// behind is blurred and tinted, not merely darkened, so the controls take
/// the scene's own colour and belong to it. [lit] brightens the edge when the
/// tray is a drop target.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.lit = false});
  final Widget child;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(kTrayH / 2);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: lit ? 1.03 : 1,
      duration: Tokens.motion.maybe(Tokens.motion.swap, reduceMotion: reduce),
      curve: Tokens.motion.easeOut,
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: AnimatedContainer(
            duration: Tokens.motion.maybe(Tokens.motion.swap, reduceMotion: reduce),
            decoration: BoxDecoration(
              color: Tokens.cosmos.panelDeep,
              borderRadius: r,
              border: Border.all(
                  color: lit
                      ? Tokens.palette.text.withValues(alpha: 0.7)
                      : Tokens.cosmos.panelEdge,
                  width: lit ? 1.5 : 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
