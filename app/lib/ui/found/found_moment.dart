// The found-a-game moment: a full-screen beat when a game enters the
// collection, which ends with the user choosing the tree it hangs on.
//
// Motion, and why each piece is built the way it is (tokens in tokens.dart):
//  - Entrance spends the delight budget (`harvest`, 520ms, strong ease-out):
//    finding a game is occasional, the tier the budget exists for. The card
//    scales in from 0.92, never from nothing. The trees rise after it with a
//    50ms stagger so the eye lands on the game first, then on the choice.
//  - The cover loads on the spinning disc and fades in over it (DiscCover), so
//    "found" and "loading" read as one continuous event.
//  - The card can be grabbed at any moment, including mid-entrance. Dragging
//    tracks 1:1; upward, where there is nothing to drop on, it rubber-bands.
//  - On release the resting point is PROJECTED from the finger's velocity
//    (Apple's decay form, rate 0.998) and the tree nearest that point is the
//    target, so a flick toward a tree lands on it without dragging all the way.
//    X and Y run on separate springs seeded with the release velocity, so there
//    is no seam between the finger and the animation.
//  - Missing every tree springs the card home (damping 0.8: the flick carried
//    momentum, so a small overshoot is honest). Landing uses damping 1.0.
//  - Exit is not the entrance reversed: "Not now" drops the card toward the
//    ground in 200ms, filing shrinks it into the tree chip it chose.
//  - Reduced motion resolves every step instantly; dragging still tracks the
//    finger, because that motion is the user's own.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../state/ludeck_store.dart';
import '../common/loading_disc.dart';
import '../common/name_dialog.dart';
import '../orchard/orchard_view.dart' show treesOf;
import '../tokens.dart';

/// What the user did with a found game.
class FoundChoice {
  const FoundChoice.tree(int this.treeId) : newTreeName = null;
  const FoundChoice.newTree(String this.newTreeName) : treeId = null;
  const FoundChoice.notNow()
      : treeId = null,
        newTreeName = null;

  final int? treeId;
  final String? newTreeName;
  bool get isNotNow => treeId == null && newTreeName == null;
}

/// A tree offered as a destination.
typedef FoundTree = ({int id, String name, int count});

/// How far a flick at [velocity] px/s carries past the release point, using
/// Apple's exponential-decay projection (not v^2/2a).
double projectFlick(double velocity, {double? rate}) {
  final r = rate ?? Tokens.motion.deceleration;
  return velocity / 1000 * r / (1 - r);
}

/// Soft resistance past a boundary: the further past, the less it follows.
double rubberBand(double overshoot, double dimension, {double? constant}) {
  final c = constant ?? Tokens.motion.rubberBand;
  return (overshoot * dimension * c) / (dimension + c * overshoot.abs());
}

/// Which chip a card released toward [projected] lands on, or null to spring
/// home. Only a point that reaches the chips' band ([rowTop] and below) lands;
/// the target is the chip whose centre is horizontally nearest, so a throw
/// slightly past the end of the row still picks the end chip.
int? landingChip({
  required Offset projected,
  required List<Rect> chips,
  required double rowTop,
}) {
  if (chips.isEmpty || projected.dy < rowTop) return null;
  int? best;
  var bestD = double.infinity;
  for (var i = 0; i < chips.length; i++) {
    // A chip the lazy row has not built yet has no rect. Without this skip it
    // reports (0,0) and wins every throw toward the left edge.
    if (chips[i].isEmpty) continue;
    final d = (chips[i].center.dx - projected.dx).abs();
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// Shows the moment for [game] over the current screen. Never null: backing
/// out is "Not now".
Future<FoundChoice> showFoundMoment(
  BuildContext context, {
  required Game game,
  required List<FoundTree> trees,
}) async {
  final choice = await Navigator.of(context).push<FoundChoice>(
    PageRouteBuilder(
      opaque: false,
      // The moment animates itself, in and out.
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => FoundMoment(game: game, trees: trees),
    ),
  );
  return choice ?? const FoundChoice.notNow();
}

/// Shows the moment for a game just added to [store] and files it where the
/// user chose. Returns the tree's name, or null when it was left on the ground.
Future<String?> offerTree(
    BuildContext context, LudeckStore store, Game game) async {
  final shape = store.tree;
  final roots = treesOf(store.branches);
  final trees = <FoundTree>[
    for (final b in roots)
      (id: b.id, name: b.name, count: shape.gamesUnder(b.id).toSet().length),
  ];
  final choice = await showFoundMoment(context, game: game, trees: trees);
  if (choice.treeId != null) {
    await store.place(game.igdbId, choice.treeId!);
    return roots.firstWhere((b) => b.id == choice.treeId).name;
  }
  final name = choice.newTreeName;
  if (name != null) {
    final before = store.branches.map((b) => b.id).toSet();
    await store.createBranch(name);
    final fresh = treesOf(store.branches).where((b) => !before.contains(b.id));
    if (fresh.isNotEmpty) {
      await store.place(game.igdbId, fresh.first.id);
      return fresh.first.name;
    }
  }
  return null;
}

class FoundMoment extends StatefulWidget {
  const FoundMoment({super.key, required this.game, required this.trees});
  final Game game;
  final List<FoundTree> trees;

  @override
  State<FoundMoment> createState() => _FoundMomentState();
}

enum _Leaving { no, filing, dropping }

class _FoundMomentState extends State<FoundMoment>
    with TickerProviderStateMixin {
  /// Entrance timeline, 0..1 over [_enterTotal].
  late final AnimationController _enter;

  /// Card offset from its home, one spring per axis.
  late final AnimationController _x = AnimationController.unbounded(vsync: this);
  late final AnimationController _y = AnimationController.unbounded(vsync: this);

  /// Exit: 0..1, shrink-into-chip or drop-to-ground.
  late final AnimationController _leave;

  /// The finger's accumulated vertical travel, before rubber-banding.
  double _rawY = 0;

  final _slotKey = GlobalKey();
  final _rowKey = GlobalKey();
  late final List<GlobalKey> _chipKeys =
      List.generate(widget.trees.length + 1, (_) => GlobalKey());

  int? _hover;
  _Leaving _leaving = _Leaving.no;

  /// The whole entrance: backdrop and card from 0, words from 120ms, the hint
  /// and up to seven chips from 200ms at a 50ms stagger, each chip `grow`
  /// (260ms) long: 200 + 6 * 50 + 260.
  static const _enterTotal = Duration(milliseconds: 760);

  bool get _reduce => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(vsync: this, duration: _enterTotal);
    _leave = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduce) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _x.dispose();
    _y.dispose();
    _leave.dispose();
    super.dispose();
  }

  // ---- geometry ------------------------------------------------------------

  Rect? _globalRect(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Offset get _home => _globalRect(_slotKey)?.center ?? Offset.zero;
  Offset get _cardCentre => _home + Offset(_x.value, _y.value);

  List<Rect> get _chipRects => [
        for (final k in _chipKeys) _globalRect(k) ?? Rect.zero,
      ];

  double get _rowTop => (_globalRect(_rowKey)?.top ?? double.infinity) - 24;

  // ---- springs ---------------------------------------------------------------

  void _springTo(AnimationController c, double target, double velocity,
      {required double ratio, double? stiffness}) {
    if (_reduce) {
      c.value = target;
      return;
    }
    c.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: stiffness ?? Tokens.motion.stiffnessDefault,
          ratio: ratio),
      c.value,
      target,
      velocity,
    ));
  }

  // ---- drag ------------------------------------------------------------------

  void _onPanStart(DragStartDetails d) {
    if (_leaving != _Leaving.no) return;
    // Grab the card where it is on screen, mid-spring or mid-entrance.
    _x.stop();
    _y.stop();
    _rawY = _y.value >= 0 ? _y.value : _rawY;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_leaving != _Leaving.no) return;
    _x.value += d.delta.dx;
    _rawY += d.delta.dy;
    final h = MediaQuery.sizeOf(context).height;
    _y.value = _rawY >= 0 ? _rawY : -rubberBand(-_rawY, h);
    final over = _cardCentre.dy >= _rowTop
        ? landingChip(
            projected: _cardCentre, chips: _chipRects, rowTop: _rowTop)
        : null;
    if (over != _hover) {
      if (over != null) HapticFeedback.selectionClick();
      setState(() => _hover = over);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_leaving != _Leaving.no) return;
    final v = d.velocity.pixelsPerSecond;
    final projected = _cardCentre + Offset(projectFlick(v.dx), projectFlick(v.dy));
    final land =
        landingChip(projected: projected, chips: _chipRects, rowTop: _rowTop);
    setState(() => _hover = null);
    if (land != null) {
      _choose(land, velocity: v);
      return;
    }
    _rawY = 0;
    _springTo(_x, 0, v.dx, ratio: Tokens.motion.dampingMomentum);
    _springTo(_y, 0, v.dy, ratio: Tokens.motion.dampingMomentum);
  }

  // ---- outcomes --------------------------------------------------------------

  /// Chip [i]: a tree, or (the last chip) a new tree.
  Future<void> _choose(int i, {Offset velocity = Offset.zero}) async {
    if (_leaving != _Leaving.no) return;
    if (i == widget.trees.length) {
      // Name first: the card waits where it is, so cancelling costs nothing.
      _springTo(_x, 0, velocity.dx, ratio: Tokens.motion.dampingMomentum);
      _springTo(_y, 0, velocity.dy, ratio: Tokens.motion.dampingMomentum);
      _rawY = 0;
      final name = await showNameDialog(context,
          title: 'Plant a tree',
          confirmLabel: 'Plant',
          hint: 'Couch co-op, short games, with Sam');
      if (name == null || !mounted) return;
      await _fileInto(i, FoundChoice.newTree(name), Offset.zero);
      return;
    }
    await _fileInto(i, FoundChoice.tree(widget.trees[i].id), velocity);
  }

  Future<void> _fileInto(int chip, FoundChoice result, Offset velocity) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _leaving = _Leaving.filing;
      _hover = chip;
    });
    final target = _chipRects[chip].center - _home;
    _springTo(_x, target.dx, velocity.dx,
        ratio: Tokens.motion.dampingDefault,
        stiffness: Tokens.motion.stiffnessSnappy);
    _springTo(_y, target.dy, velocity.dy,
        ratio: Tokens.motion.dampingDefault,
        stiffness: Tokens.motion.stiffnessSnappy);
    await _runLeave(Tokens.motion.grow);
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _notNow() async {
    if (_leaving != _Leaving.no) return;
    setState(() => _leaving = _Leaving.dropping);
    await _runLeave(Tokens.motion.swap);
    if (mounted) Navigator.of(context).pop(const FoundChoice.notNow());
  }

  Future<void> _runLeave(Duration d) async {
    if (_reduce) {
      _leave.value = 1;
      return;
    }
    _leave.duration = d;
    await _leave.forward(from: 0);
  }

  // ---- build -----------------------------------------------------------------

  /// [start]..[start + length] of the entrance, eased, as 0..1.
  double _phase(int startMs, int lengthMs) {
    final total = _enterTotal.inMilliseconds;
    final t = ((_enter.value * total - startMs) / lengthMs).clamp(0.0, 1.0);
    return Tokens.motion.easeOut.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardW = math.min(200.0, size.width * 0.5);
    final cardH = cardW * 4 / 3;
    final game = widget.game;
    final meta = [
      if (game.releaseYear != null) '${game.releaseYear}',
      if (game.timeToBeatSeconds != null)
        '${(game.timeToBeatSeconds! / 3600).round()} h',
    ].join('  ·  ');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _notNow();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _x, _y, _leave]),
        builder: (context, _) {
          final leave = Tokens.motion.easeOut.transform(_leave.value);
          final backdrop = _phase(0, 200) * (1 - leave);
          final card = _phase(0, 520);
          final words = _phase(120, 260) * (1 - leave);
          final filing = _leaving == _Leaving.filing;
          final dropping = _leaving == _Leaving.dropping;
          final cardScale = (0.92 + 0.08 * card) * (filing ? 1 - 0.8 * leave : 1);
          final cardOpacity = card *
              (filing ? (1 - ((leave - 0.5) * 2).clamp(0.0, 1.0)) : 1) *
              (dropping ? 1 - leave : 1);
          final cardOffset = Offset(_x.value,
              _y.value + 24 * (1 - card) + (dropping ? 40 * leave : 0));

          return Material(
            type: MaterialType.transparency,
            child: Stack(fit: StackFit.expand, children: [
              Opacity(
                opacity: backdrop,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: Tokens.cosmos.deep,
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(children: [
                  const Spacer(flex: 3),
                  Opacity(
                    opacity: words,
                    child: Text('New find',
                        style: TextStyle(
                            fontSize: Tokens.type.caption,
                            color: Tokens.palette.textDim,
                            letterSpacing: 1.2)),
                  ),
                  SizedBox(height: Tokens.space.md),
                  SizedBox(
                    key: _slotKey,
                    width: cardW,
                    height: cardH,
                    child: Transform.translate(
                      offset: cardOffset,
                      child: Transform.scale(
                        scale: cardScale,
                        child: Opacity(
                          opacity: cardOpacity.clamp(0.0, 1.0),
                          child: GestureDetector(
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: _onPanEnd,
                            child: Semantics(
                              label: '${game.title}, new find',
                              image: true,
                              excludeSemantics: true,
                              child: _Card(game: game, w: cardW, h: cardH),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: Tokens.space.lg),
                  Opacity(
                    opacity: words,
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - words)),
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: Tokens.space.lg),
                        child: Column(children: [
                          Text(game.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Tokens.type.title,
                                  fontWeight: FontWeight.w700,
                                  color: Tokens.palette.text)),
                          if (meta.isNotEmpty) ...[
                            SizedBox(height: Tokens.space.xxs),
                            Text(meta,
                                style: TextStyle(
                                    fontSize: Tokens.type.body,
                                    color: Tokens.palette.textDim)),
                          ],
                        ]),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  Opacity(
                    opacity: _phase(200, 260) * (1 - leave),
                    child: Text(
                        widget.trees.isEmpty
                            ? 'Plant a tree for it'
                            : 'Flick it onto a tree, or tap one',
                        style: TextStyle(
                            fontSize: Tokens.type.caption,
                            color: Tokens.palette.textDim)),
                  ),
                  SizedBox(height: Tokens.space.sm),
                  _ChipRow(
                    rowKey: _rowKey,
                    chipKeys: _chipKeys,
                    trees: widget.trees,
                    hover: _hover,
                    appear: (i) => _phase(200 + 50 * math.min(i, 6), 260),
                    fade: filing ? 1.0 : 1 - leave,
                    onTap: _choose,
                  ),
                  SizedBox(height: Tokens.space.xs),
                  Opacity(
                    opacity: words,
                    child: TextButton(
                      key: const Key('found-not-now'),
                      onPressed: _leaving == _Leaving.no ? _notNow : null,
                      child: Text('Not now',
                          style: TextStyle(
                              fontSize: Tokens.type.body,
                              color: Tokens.palette.textDim)),
                    ),
                  ),
                  SizedBox(height: Tokens.space.sm),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.game, required this.w, required this.h});
  final Game game;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        boxShadow: [
          BoxShadow(
              color: Tokens.palette.bg.withValues(alpha: 0.6),
              blurRadius: 32,
              offset: const Offset(0, 16)),
        ],
      ),
      child: DiscCover(
        url: game.coverUrl,
        width: w,
        height: h,
        radius: Tokens.radius.card,
        placeholder: Container(
          width: w,
          height: h,
          color: Tokens.palette.surface,
          alignment: Alignment.center,
          child: Text(game.title.characters.first.toUpperCase(),
              style: TextStyle(
                  fontSize: w * 0.3,
                  fontWeight: FontWeight.w700,
                  color: Tokens.palette.textDim)),
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.rowKey,
    required this.chipKeys,
    required this.trees,
    required this.hover,
    required this.appear,
    required this.fade,
    required this.onTap,
  });

  final GlobalKey rowKey;
  final List<GlobalKey> chipKeys;
  final List<FoundTree> trees;
  final int? hover;
  final double Function(int i) appear;
  final double fade;
  final void Function(int i) onTap;

  @override
  Widget build(BuildContext context) {
    final n = trees.length;
    return SizedBox(
      key: rowKey,
      height: Tokens.size.control + 12,
      // Centred while the chips fit, scrolling once they do not: a two-tree
      // orchard should not hug the left edge under a centred card.
      child: Center(
      child: ListView.separated(
        shrinkWrap: true,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
            horizontal: Tokens.space.lg, vertical: 6),
        itemCount: n + 1,
        separatorBuilder: (_, _) => SizedBox(width: Tokens.space.sm),
        itemBuilder: (context, i) {
          final a = appear(i);
          final isNew = i == n;
          final t = isNew ? null : trees[i];
          return Opacity(
            opacity: (a * fade).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - a)),
              child: AnimatedScale(
                scale: hover == i ? 1.06 : 1,
                duration: Tokens.motion.press,
                curve: Tokens.motion.easeOut,
                child: Semantics(
                  button: true,
                  label: isNew ? 'Plant a new tree for it' : 'Hang it on ${t!.name}',
                  excludeSemantics: true,
                  child: Material(
                    key: chipKeys[i],
                    color: hover == i
                        ? Tokens.cosmos.panelEdge
                        : Tokens.cosmos.panel,
                    shape: StadiumBorder(
                      side: BorderSide(
                          color: hover == i
                              ? Tokens.palette.text
                              : Tokens.cosmos.panelEdge),
                    ),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => onTap(i),
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: Tokens.space.md),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isNew ? Icons.add : Icons.park_outlined,
                              size: 18, color: Tokens.palette.text),
                          SizedBox(width: Tokens.space.xs),
                          Text(isNew ? 'New tree' : t!.name,
                              style: TextStyle(
                                  fontSize: Tokens.type.body,
                                  fontWeight: FontWeight.w600,
                                  color: Tokens.palette.text)),
                          if (!isNew) ...[
                            SizedBox(width: Tokens.space.xs),
                            Text('${t!.count}',
                                style: TextStyle(
                                    fontSize: Tokens.type.caption,
                                    color: Tokens.palette.textDim)),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}
