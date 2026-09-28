// The orchard: the home screen. Each top-level branch is a tree; its games hang
// on it as cover fruit. Swipe between trees; the last page is an empty patch
// where a new tree is planted.
//
// Gestures, and why each is built the way it is:
//  - Paging is a PageView with bouncing physics: 1:1 tracking under the finger,
//    release velocity carried into the settle, and a rubber-band at the first
//    and last tree instead of a hard stop.
//  - Tapping a fruit is detected INSIDE the Rive file (its own hit areas), which
//    reports the slot back; this widget maps the slot to the game.
//  - Press-and-hold picks a fruit up. The file records which fruit the pointer
//    went down on (`pressed`), so the long-press knows what it is holding
//    without this widget re-deriving card positions. Dropped on another tree's
//    dot, the game moves there.
//
// The Rive tree is excluded from semantics; the count under the tree name is
// a real button that opens the tree's full, accessible list.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
// Prefixed: rive_native exports its own Animation / Image / Fit names.
import 'package:rive/rive.dart' as rv;

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../domain/branch_tree.dart';
import '../../domain/pick.dart';
import '../common/glass.dart';
import '../common/name_dialog.dart';
import '../tokens.dart';
import 'fruit_flight.dart';
import 'fruit_look.dart';
import 'fruit_slots.g.dart';
import 'ground_tray.dart';
import 'meadow.dart';
import 'rive_tree.dart';
import 'tree_customise_sheet.dart';
import 'tree_style.dart';

/// Top-level branches, in the user's order. These are the trees.
List<Branch> treesOf(List<Branch> branches) {
  final roots = branches.where((b) => b.parentId == null).toList()
    ..sort((a, b) => a.sortOrder != b.sortOrder
        ? a.sortOrder.compareTo(b.sortOrder)
        : a.id.compareTo(b.id));
  return roots;
}

/// The games on [tree], including any nested sub-branches, each once, in
/// placement order. The first [kTreeSlots] hang as fruit; the rest are on the
/// shelf. Stable: adding a game appends, so nothing already hanging moves.
List<TreeItem> gamesOnTree(
    Branch tree, BranchTree shape, Map<int, TreeItem> byId) {
  final seen = <int>{};
  final out = <TreeItem>[];
  for (final id in shape.gamesUnder(tree.id)) {
    final item = byId[id];
    if (item != null && seen.add(id)) out.add(item);
  }
  return out;
}

class OrchardView extends StatefulWidget {
  const OrchardView({
    super.key,
    required this.items,
    required this.branches,
    required this.placements,
    required this.onOpenGame,
    required this.onPlantTree,
    required this.onMoveGame,
    this.onFileGame,
    this.onUnfileGame,
    this.onPlay,
    this.onRenameTree,
    this.styles = const {},
    this.onStyleTree,
    this.unfiled = const [],
    this.addButton,
    this.actions = const [],
    this.bottomInset = 0,
  });

  final List<TreeItem> items;
  final List<Branch> branches;
  final Map<int, List<int>> placements;
  final void Function(TreeItem item) onOpenGame;

  /// Create a tree with [name]. Resolves once it exists.
  final Future<void> Function(String name) onPlantTree;

  /// Move [item] from tree [fromId] to tree [toId].
  final Future<void> Function(TreeItem item, int fromId, int toId) onMoveGame;

  /// Hang [item], from the ground, on tree [treeId].
  final Future<void> Function(TreeItem item, int treeId)? onFileGame;

  /// Take [item] off tree [fromTree] and put it back on the ground.
  final Future<void> Function(TreeItem item, int fromTree)? onUnfileGame;

  /// Start playing [item] (the shaken-loose pick's "Play it").
  final Future<void> Function(TreeItem item)? onPlay;
  final void Function(Branch tree)? onRenameTree;

  /// Each tree's look (`resolveTreeStyles`). A tree missing here gets its
  /// default for its position.
  final Map<int, TreeStyle> styles;

  /// Save [style] as [tree]'s look.
  final Future<void> Function(Branch tree, TreeStyle style)? onStyleTree;

  /// Games on no tree yet. They sit "on the ground" in the tray: a quiet
  /// pile, never a nag or a count of what is outstanding (DECISIONS.md).
  final List<TreeItem> unfiled;

  /// The add control, fixed at the bottom right beside the ground tray.
  final Widget? addButton;

  /// Icon buttons shown top right over every tree (Library, Friends, You).
  final List<OrchardAction> actions;

  /// Space the app's own bottom chrome takes (nav pill).
  final double bottomInset;

  @override
  State<OrchardView> createState() => _OrchardViewState();
}

/// How far above the finger a held card's centre sits, so the finger never
/// hides the cover being placed. And the held card's width.
const double kHoldAbove = 70, kHeldW = 58;

/// The hover target meaning "the ground tray", not a tree.
const int kGroundTarget = -1;

/// Whether a long-press at [at] is on the fruit card [card]: the card plus a
/// finger's slack (the file's tap area is 16pt larger than the card).
bool liftHits(Rect card, Offset at) => card.inflate(10).contains(at);

/// How long after a shake the pick card rises: the tree shakes, the fruit
/// falls and lands (the file's drop, ~1s), then the card.
const Duration kPickDelay = Duration(milliseconds: 1000);

class _OrchardViewState extends State<OrchardView>
    with SingleTickerProviderStateMixin {
  final PageController _pages = PageController();

  /// Scroll offset in pixels and the fractional page. Notifiers, NOT
  /// setState: a swipe changes these every frame and only the meadow and the
  /// dots depend on them. Rebuilding the whole orchard (every page, every
  /// Rive tree) per frame was the main per-frame cost of a swipe.
  final ValueNotifier<double> _scroll = ValueNotifier(0);
  final ValueNotifier<double> _page = ValueNotifier(0);
  final Map<int, RiveTreeController> _controllers = {};

  /// The meadow's life: grass, flowers, fireflies (meadow.dart).
  final MeadowClock _clock = MeadowClock();
  late final Ticker _ambient = createTicker(_onAmbient);
  Duration _lastAmbient = Duration.zero;

  /// A tree planted this session: its page plays the seed -> sapling once.
  int? _sproutId;

  // ---- the card in your hand -------------------------------------------
  TreeItem? _held;

  /// The tree it came off, or null: it came from the ground tray.
  int? _heldFrom;
  Offset _heldAt = Offset.zero;

  /// Where it was picked up (global): a miss flies back here.
  Rect? _heldOrigin;
  int? _hoverTarget;

  /// The hover is the current tree's canopy, not a dot.
  bool _hoverCanopy = false;
  final Map<int, GlobalKey> _dotKeys = {};

  /// Cards flying to where they land, keyed so each keeps its own state.
  final List<(Key, Widget)> _flights = [];

  /// A tray game that is in flight back to the tray: its gap stays open.
  TreeItem? _returning;

  /// The soil line's distance from the bottom, from the last layout.
  double _treeBottom = 0;

  /// The tray's whole row: a fruit held over it goes back on the ground.
  final GlobalKey _trayKey = GlobalKey();

  // ---- the shake (roulette) ----------------------------------------------
  final math.Random _rnd = math.Random();
  final ShakeBag _bag = ShakeBag();
  Pick? _pick;
  Branch? _pickTree;
  Timer? _pickTimer;
  int _pickPage = 0;

  /// A fruit is down (or falling) on [_pickTree]: the file's drop is >= 0.
  bool _dropped = false;

  /// Shake [tree]: a game on it falls (the file's drop), and a card rises
  /// with what fell and why. Only fruit that is HANGING can fall, so the pool
  /// is the first [kTreeSlots] games. Every hanging game gets its turn before
  /// any falls twice (ShakeBag).
  void _shake(Branch tree, List<TreeItem> games) {
    final c = _controllers[tree.id];
    final hanging = games.take(kTreeSlots).toList();
    final pick = _bag.shake(tree.id, hanging, _rnd);
    _pickTimer?.cancel();
    if (pick == null) {
      // Nothing can fall: the tree still answers, and says why in words.
      HapticFeedback.lightImpact();
      c?.rustle();
      setState(() {
        _pick = null;
        _pickTree = tree;
        _nothingToShake = true;
      });
      _pickTimer = Timer(const Duration(milliseconds: 2400), () {
        if (mounted) setState(() => _nothingToShake = false);
      });
      return;
    }
    HapticFeedback.mediumImpact();
    final slot = hanging.indexWhere((i) => i.game.igdbId == pick.item.game.igdbId);
    final reduce = MediaQuery.disableAnimationsOf(context);
    void fall() {
      c?.drop(slot);
      _dropped = true;
      _pickTimer = Timer(reduce ? Duration.zero : kPickDelay,
          () => _showPick(tree, pick));
    }

    setState(() {
      _nothingToShake = false;
      _pick = null;
      _pickTree = tree;
      _pickPage = _page.value.round();
    });
    if (_dropped) {
      // A fruit is already down: it hangs back first, THEN the tree shakes.
      // Going straight from one drop to the next skipped the file's shake
      // (its tree layer only re-arms after drop < 0).
      for (final other in _controllers.values) {
        other.drop(-1);
      }
      _dropped = false;
      _pickTimer = Timer(const Duration(milliseconds: 380), () {
        if (mounted) fall();
      });
      return;
    }
    fall();
  }

  bool _nothingToShake = false;

  void _showPick(Branch tree, Pick pick) {
    if (!mounted) return;
    HapticFeedback.lightImpact(); // it has landed
    setState(() {
      _pick = pick;
      _pickTree = tree;
    });
  }

  /// Put the fruit back and take the card away.
  void _dismissPick() {
    _pickTimer?.cancel();
    final t = _pickTree;
    if (t != null) _controllers[t.id]?.drop(-1);
    _dropped = false;
    if (_pick != null || _nothingToShake) {
      setState(() {
        _pick = null;
        _nothingToShake = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      if (!_pages.hasClients) return;
      _scroll.value = _pages.offset;
      _page.value = _pages.page ?? 0;
      // Swiping to another tree puts a shaken-loose pick back.
      if ((_pick != null || _pickTimer?.isActive == true) &&
          (_page.value - _pickPage).abs() > 0.5) {
        _dismissPick();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final live = MeadowClock.enabled && !MediaQuery.disableAnimationsOf(context);
    if (live && !_ambient.isActive) {
      _lastAmbient = Duration.zero;
      _ambient.start();
    } else if (!live && _ambient.isActive) {
      _ambient.stop();
      _clock
        ..t = 0
        ..wind = 0;
    }
  }

  void _onAmbient(Duration elapsed) {
    final dt = (elapsed - _lastAmbient).inMicroseconds / 1e6;
    _lastAmbient = elapsed;
    _clock.advance(dt.clamp(0.0, 0.1), _scroll.value);
  }

  @override
  void dispose() {
    _pickTimer?.cancel();
    _ambient.dispose();
    _clock.dispose();
    _pages.dispose();
    _scroll.dispose();
    _page.dispose();
    super.dispose();
  }

  Future<void> _plant() async {
    HapticFeedback.selectionClick();
    final name = await showNameDialog(context,
        title: 'Plant a tree',
        confirmLabel: 'Plant',
        hint: 'Couch co-op, short games, with Sam');
    if (name == null || !mounted) return;
    final before = treesOf(widget.branches).map((b) => b.id).toSet();
    await widget.onPlantTree(name);
    if (!mounted) return;
    // The store has re-read, but this widget's `branches` only update on the
    // next build. Read them after that frame, or the new tree is not in them.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final now = treesOf(widget.branches);
    final fresh = now.where((b) => !before.contains(b.id)).toList();
    if (fresh.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() => _sproutId = fresh.first.id);
      // Saved at once, in the blossom the orchard has least of, so a new tree
      // never looks like its neighbour and keeps its colour if trees are
      // later reordered.
      await widget.onStyleTree?.call(
          fresh.first,
          TreeStyle.defaultFor(now.length - 1).copyWith(
              blossom: leastUsedBlossom([
            for (final t in now)
              if (t.id != fresh.first.id) _styleOf(t, now).blossom
          ])));
    }
  }

  TreeStyle _styleOf(Branch tree, List<Branch> trees) =>
      widget.styles[tree.id] ?? TreeStyle.defaultFor(trees.indexOf(tree));

  Future<void> _customise(Branch tree, List<Branch> trees) async {
    HapticFeedback.selectionClick();
    await showTreeCustomiseSheet(
      context,
      tree: tree,
      initial: _styleOf(tree, trees),
      onChanged: (style) => widget.onStyleTree?.call(tree, style),
    );
  }

  // ---- geometry ----------------------------------------------------------
  RenderBox? get _box => context.findRenderObject() as RenderBox?;

  List<TreeItem> _gamesOn(Branch tree) => gamesOnTree(
      tree,
      BranchTree(widget.branches, widget.placements),
      {for (final i in widget.items) i.game.igdbId: i});

  /// The tree on screen now, or null on the planting patch.
  Branch? get _currentTree {
    final trees = treesOf(widget.branches);
    final i = _page.value.round();
    return i >= 0 && i < trees.length ? trees[i] : null;
  }

  Rect _frameFor(int games) {
    final size = _box!.size;
    return treeFrame(size, size.height - _treeBottom, treeZoom(games));
  }

  /// The current tree's canopy, in global coordinates: where a card is
  /// "over the tree".
  Rect? _canopyGlobal(int games) {
    final box = _box;
    if (box == null || !box.hasSize) return null;
    final f = _frameFor(games);
    final s = f.width / kTreeArtW;
    final r = Rect.fromLTRB(f.left + 40 * s, f.top + (kCanopyTop - 20) * s,
        f.right - 40 * s, f.top + (kTreeBaseY - 70) * s);
    return box.localToGlobal(r.topLeft) & r.size;
  }

  /// Card [slot]'s centre (global) and width on a tree holding [games].
  (Offset, double)? _slotGlobal(int games, int slot) {
    final box = _box;
    if (box == null || !box.hasSize || games < 1 || games > kTreeSlots) {
      return null;
    }
    if (slot >= kFruitCentres[games - 1].length) return null;
    final (x, y, sc) = kFruitCentres[games - 1][slot];
    final f = _frameFor(games);
    final s = f.width / kTreeArtW;
    return (box.localToGlobal(f.topLeft + Offset(x, y) * s), 40 * sc * s);
  }

  Offset _toLocal(Offset global) => _box?.globalToLocal(global) ?? global;

  // ---- lift, carry, land -------------------------------------------------
  void _liftFromTree(Branch tree, List<TreeItem> games, LongPressStartDetails d) {
    final c = _controllers[tree.id];
    final slot = c?.pressed ?? -1;
    c?.clearPressed();
    if (slot < 0 || slot >= games.length || slot >= kTreeSlots) return;
    final at = _slotGlobal(games.length, slot);
    if (at == null) return;
    final card = Rect.fromCenter(center: at.$1, width: at.$2, height: at.$2 * 4 / 3);
    // The file's `pressed` is only reset by a press on the sky, so it can
    // name a fruit touched long ago. A long-press anywhere else (the tray,
    // the grass, a slow tap) lifted that fruit and a drop over the tray put
    // it on the ground: games left their trees on device (2026-09-28). Lift
    // only when the press is on the fruit itself.
    if (!liftHits(card, d.globalPosition)) return;
    _lift(games[slot], tree.id, card, d.globalPosition);
  }

  void _lift(TreeItem item, int? fromTree, Rect? origin, Offset at) {
    HapticFeedback.mediumImpact();
    // Build its image now, so the fruit that pops on the tree already has it.
    fruitPng(item.game, lookOf(item));
    setState(() {
      _held = item;
      _heldFrom = fromTree;
      _heldOrigin = origin;
      _heldAt = at;
      _hoverTarget = null;
      _hoverCanopy = false;
    });
  }

  void _carry(Offset at) {
    if (_held == null) return;
    final card = at - const Offset(0, kHoldAbove);
    int? over;
    var canopy = false;
    for (final e in _dotKeys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      // Generous: the dot's box inflated to a 56pt target.
      final r = (box.localToGlobal(Offset.zero) & box.size).inflate(14);
      if ((r.contains(card) || r.contains(at)) && e.key != _heldFrom) over = e.key;
    }
    final here = _currentTree;
    if (over == null && _heldFrom != null) {
      // Off a tree and over the tray: back on the ground.
      final box = _trayKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final r = (box.localToGlobal(Offset.zero) & box.size).inflate(12);
        if (r.contains(card) || r.contains(at)) over = kGroundTarget;
      }
    }
    if (over == null && here != null && here.id != _heldFrom) {
      final r = _canopyGlobal(_gamesOn(here).length);
      if (r != null && r.contains(card)) {
        over = here.id;
        canopy = true;
      }
    }
    if (over != _hoverTarget && over != null) HapticFeedback.selectionClick();
    setState(() {
      _heldAt = at;
      _hoverTarget = over;
      _hoverCanopy = canopy;
    });
  }

  Future<void> _land(Offset at, Velocity velocity) async {
    final item = _held;
    if (item == null) return;
    final from = _heldFrom, target = _hoverTarget, canopy = _hoverCanopy;
    final origin = _heldOrigin;
    final card = at - const Offset(0, kHoldAbove);
    final v = velocity.pixelsPerSecond;
    final trees = treesOf(widget.branches);
    final tree = target == null
        ? null
        : trees.where((t) => t.id == target).firstOrNull;

    setState(() {
      _held = null;
      _heldFrom = null;
      _hoverTarget = null;
      _hoverCanopy = false;
    });

    if (target == kGroundTarget && from != null) {
      // Back on the ground: into the pile, where the tray keeps it.
      final box = _trayKey.currentContext?.findRenderObject() as RenderBox?;
      final pile = box != null && box.hasSize
          ? box.localToGlobal(Offset(kTrayInset + kPileW / 2, box.size.height / 2))
          : card;
      _fly(item, from: card, velocity: v, to: pile, toWidth: 26);
      HapticFeedback.lightImpact();
      await widget.onUnfileGame?.call(item, from);
      return;
    }

    Future<void> commit() async {
      if (tree == null) return;
      if (from == null) {
        await widget.onFileGame?.call(item, tree.id);
      } else {
        await widget.onMoveGame(item, from, tree.id);
      }
    }

    if (tree != null && canopy) {
      // Onto the tree on screen: fly to the spot its fruit will pop in, and
      // hold there until the file's pop (which waits 180ms + 55ms per card
      // before it, discovery.py wait_frames) takes over.
      final n = _gamesOn(tree).length;
      final slot = n < kTreeSlots ? _slotGlobal(n + 1, n) : null;
      final r = _canopyGlobal(n);
      final to = slot?.$1 ?? r?.center ?? card;
      _fly(item,
          from: card,
          velocity: v,
          to: to,
          toWidth: slot?.$2 ?? 18,
          hold: Duration(milliseconds: slot == null ? 0 : 180 + 55 * n + 60),
          onArrive: () {
            HapticFeedback.lightImpact();
            _controllers[tree.id]?.rustle();
          });
      await commit();
      return;
    }
    if (tree != null) {
      // Onto another tree's dot: into the dot, then go to that tree to see it
      // hang there.
      final box = _dotKeys[tree.id]?.currentContext?.findRenderObject() as RenderBox?;
      final dot = box != null && box.hasSize
          ? box.localToGlobal(box.size.center(Offset.zero))
          : card;
      _fly(item, from: card, velocity: v, to: dot, toWidth: 12);
      HapticFeedback.lightImpact();
      await commit();
      if (!mounted) return;
      final i = treesOf(widget.branches).indexWhere((t) => t.id == tree.id);
      if (i >= 0 && _pages.hasClients) {
        _pages.animateToPage(i,
            duration: Tokens.motion.maybe(Tokens.motion.camera,
                reduceMotion: MediaQuery.disableAnimationsOf(context)),
            curve: Tokens.motion.easeInOut);
      }
      return;
    }
    // Nowhere: back where it came from.
    final home = origin?.center ?? card;
    if (from == null) setState(() => _returning = item);
    _fly(item,
        from: card,
        velocity: v,
        to: home,
        toWidth: origin?.width ?? 20,
        fade: from != null,
        onDone: () {
          if (mounted && _returning?.game.igdbId == item.game.igdbId) {
            setState(() => _returning = null);
          }
        });
  }

  void _fly(TreeItem item,
      {required Offset from,
      required Offset velocity,
      required Offset to,
      required double toWidth,
      Duration hold = Duration.zero,
      bool fade = true,
      VoidCallback? onArrive,
      VoidCallback? onDone}) {
    final key = UniqueKey();
    final w = FruitFlight(
      key: key,
      item: item,
      from: _toLocal(from),
      fromWidth: kHeldW,
      velocity: velocity,
      to: _toLocal(to),
      toWidth: toWidth,
      hold: hold,
      fade: fade,
      onArrive: onArrive,
      onDone: () {
        if (!mounted) return;
        setState(() => _flights.removeWhere((f) => f.$1 == key));
        onDone?.call();
      },
    );
    setState(() => _flights.add((key, w)));
  }

  @override
  Widget build(BuildContext context) {
    final trees = treesOf(widget.branches);
    final shape = BranchTree(widget.branches, widget.placements);
    final byId = {for (final i in widget.items) i.game.igdbId: i};
    final pageCount = trees.length + 1; // + the empty patch

    // The ground tray along the bottom (its add button as the end cap), the
    // tree dots just above it. Pages run the full screen so the sky continues
    // under the controls; each tree's soil line is placed just above the
    // dots, so its base, the patch and the fruit never sit behind chrome.
    final rowBottom = MediaQuery.paddingOf(context).bottom + widget.bottomInset;
    const rowH = kTrayH, dotsH = 48.0;
    final treeBottom = rowBottom + rowH + dotsH;
    _treeBottom = treeBottom;

    // The meadow answers touch: a finger parts the grass and scatters the
    // fireflies; a tap on the ground bounces the flowers and throws up a puff
    // of petals. A Listener, not a gesture detector: it only watches, so it
    // never takes a swipe or a tap away from the pages and the tree.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (!_ambient.isActive) return;
        _downAt = e.localPosition;
        _downTime = e.timeStamp;
        _clock.pointerDown(e.localPosition + Offset(_scroll.value, 0));
      },
      onPointerMove: (e) {
        if (_ambient.isActive) {
          _clock.pointerMove(e.localPosition + Offset(_scroll.value, 0));
        }
      },
      onPointerUp: (e) {
        _clock.pointerUp();
        final at = _downAt;
        _downAt = null;
        if (at == null || _held != null) return;
        final groundY = (_box?.size.height ?? 0) - _treeBottom;
        final quick = e.timeStamp - _downTime < const Duration(milliseconds: 350);
        final still = (e.localPosition - at).distance < 12;
        final onGround = at.dy > groundY - 70 && at.dy < groundY + 14;
        if (quick && still && onGround) {
          HapticFeedback.selectionClick();
          _clock.poke(at + Offset(_scroll.value, 0));
        }
      },
      onPointerCancel: (_) {
        _clock.pointerUp();
        _downAt = null;
      },
      child: Stack(
      fit: StackFit.expand,
      children: [
        // One continuous meadow behind every page (meadow.dart): it scrolls
        // with the pages, so the ground runs on from tree to tree.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
                painter: MeadowBackPainter(scroll: _scroll, groundFromBottom: treeBottom,
                    halos: [
                      for (final t in trees)
                        (
                          _styleOf(t, trees).blossom.swatch,
                          treeZoom(gamesOnTree(t, shape, byId).length)
                        ),
                      null, // the patch
                    ])),
          ),
        ),
        // The back grass, on its own layer: it sways every frame.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                  painter: MeadowGrassPainter(
                      scroll: _scroll, groundFromBottom: treeBottom, clock: _clock)),
            ),
          ),
        ),
        Positioned.fill(
          child: PageView.builder(
          controller: _pages,
          physics: const BouncingScrollPhysics(),
          // Build the neighbour on each side ahead of time, so a tree is
          // loaded and grown by the time a swipe reveals it instead of
          // popping in and regrowing mid-swipe.
          allowImplicitScrolling: true,
          itemCount: pageCount,
          itemBuilder: (context, index) {
            if (index == trees.length) {
              return _PatchPage(
                key: const ValueKey('orchard-patch'),
                onPlant: _plant,
                groundFromBottom: treeBottom,
              );
            }
            final tree = trees[index];
            final games = gamesOnTree(tree, shape, byId);
            final c = _controllers.putIfAbsent(tree.id, RiveTreeController.new);
            return _TreePage(
              key: ValueKey('orchard-tree-${tree.id}'),
              tree: tree,
              pageIndex: index,
              style: _styleOf(tree, trees),
              games: games,
              controller: c,
              clock: _clock,
              sprout: tree.id == _sproutId,
              groundFromBottom: treeBottom,
              onFruit: (slot) {
                if (slot < games.length) widget.onOpenGame(games[slot]);
              },
              onShelf: () => _openShelf(tree, games),
              onRename: widget.onRenameTree == null
                  ? null
                  : () => widget.onRenameTree!(tree),
              onCustomise: widget.onStyleTree == null
                  ? null
                  : () => _customise(tree, trees),
              onShake: () => _shake(tree, games),
              onLongPressStart: (d) {
                _dismissPick();
                _liftFromTree(tree, games, d);
              },
              onLongPressMove: (d) => _carry(d.globalPosition),
              onLongPressEnd: (d) => _land(d.globalPosition, d.velocity),
            );
          },
        ),
        ),

        // Short grass in front of every trunk. Visual only.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                  painter: MeadowFrontPainter(
                      scroll: _scroll, groundFromBottom: treeBottom, clock: _clock)),
            ),
          ),
        ),

        // Tree dots, in their own band just above the tray: where you are,
        // and where a held card can go.
        Positioned(
          left: 0,
          right: 0,
          bottom: rowBottom + rowH,
          height: dotsH,
          child: ValueListenableBuilder<double>(
            valueListenable: _page,
            builder: (context, page, _) => _TreeDots(
            trees: trees,
            page: page,
            holding: _held != null,
            heldFrom: _heldFrom,
            hover: _hoverTarget,
            keys: _dotKeys,
            onTap: (i) => _pages.animateToPage(i,
                duration: Tokens.motion.maybe(Tokens.motion.grow,
                    reduceMotion: MediaQuery.disableAnimationsOf(context)),
                curve: Tokens.motion.easeInOut),
          ),
          ),
        ),

        // The ground tray: games on no tree. It opens rightward up to the add
        // button, which never moves.
        Positioned(
          left: Tokens.space.md,
          right: Tokens.space.md + Tokens.size.control + Tokens.space.sm,
          bottom: rowBottom,
          height: rowH,
          child: SizedBox.expand(
            key: _trayKey,
            child: GroundTray(
            items: widget.unfiled,
            onOpen: widget.onOpenGame,
            lifted: _held ?? _returning,
            receiving: _hoverTarget == kGroundTarget,
            onLift: (item, from, at) => _lift(item, null, from, at),
            onLiftMove: _carry,
            onLiftEnd: _land,
          ),
          ),
        ),
        if (widget.addButton != null)
          Positioned(
            right: Tokens.space.md,
            bottom: rowBottom + (rowH - Tokens.size.control) / 2,
            child: widget.addButton!,
          ),

        // Shake: the orchard's roulette, over the add button in the thumb's
        // reach. Only on a tree page, and out of the way while a card is in
        // the hand or the pick card (which has its own "Shake again") is up.
        Positioned(
          right: Tokens.space.md + (Tokens.size.control - kShakeSize) / 2,
          bottom: rowBottom + rowH + Tokens.space.sm,
          child: ValueListenableBuilder<double>(
            valueListenable: _page,
            builder: (context, page, _) {
              final i = page.round();
              final tree = i < trees.length ? trees[i] : null;
              final show = tree != null && _held == null && _pick == null;
              return IgnorePointer(
                ignoring: !show,
                child: AnimatedOpacity(
                  opacity: show ? 1 : 0,
                  duration: Tokens.motion.maybe(Tokens.motion.swap,
                      reduceMotion: MediaQuery.disableAnimationsOf(context)),
                  curve: Tokens.motion.easeOut,
                  child: GlassButton(
                    key: const Key('orchard-shake'),
                    size: kShakeSize,
                    caption: 'Shake',
                    label: tree == null
                        ? 'Shake'
                        : 'Shake ${tree.name} for something to play',
                    onTap: tree == null ? null : () => _shake(tree, _gamesOn(tree)),
                    child: CustomPaint(
                        size: const Size.square(26), painter: ShakeGlyph()),
                  ),
                ),
              );
            },
          ),
        ),

        // Where else to go: icon buttons, top right, fixed over every page.
        if (widget.actions.isNotEmpty)
          Positioned(
            top: MediaQuery.paddingOf(context).top + Tokens.space.md,
            right: Tokens.space.md,
            child: _TopActions(actions: widget.actions),
          ),

        for (final f in _flights) f.$2,

        // What the shake knocked loose, rising from the ground.
        Positioned(
          left: Tokens.space.md,
          right: Tokens.space.md,
          // Over the tray and dots, below the soil: the fruit that fell stays
          // in view on the grass above the card.
          bottom: rowBottom,
          child: AnimatedSwitcher(
            duration: Tokens.motion.maybe(Tokens.motion.grow,
                reduceMotion: MediaQuery.disableAnimationsOf(context)),
            reverseDuration: Tokens.motion.maybe(Tokens.motion.swap,
                reduceMotion: MediaQuery.disableAnimationsOf(context)),
            switchInCurve: Tokens.motion.easeOut,
            switchOutCurve: Tokens.motion.easeOut,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                    .animate(a),
                child: child,
              ),
            ),
            child: _pick != null
                ? PickCard(
                    key: ValueKey('pick-${_pick!.item.game.igdbId}'),
                    pick: _pick!,
                    treeName: _pickTree?.name ?? '',
                    onPlay: () async {
                      final item = _pick!.item;
                      _dismissPick();
                      await widget.onPlay?.call(item);
                    },
                    onAgain: () {
                      final t = _pickTree;
                      if (t != null) _shake(t, _gamesOn(t));
                    },
                    onOpen: () {
                      final item = _pick!.item;
                      _dismissPick();
                      widget.onOpenGame(item);
                    },
                    onClose: _dismissPick,
                  )
                : _nothingToShake
                    ? _NothingToShake(
                        key: const ValueKey('pick-none'),
                        treeName: _pickTree?.name ?? '')
                    : const SizedBox.shrink(key: ValueKey('pick-off')),
          ),
        ),

        if (_held != null)
          _HeldFruit(
            item: _held!,
            at: _toLocal(_heldAt),
            origin: _heldOrigin == null
                ? null
                : _toLocal(_heldOrigin!.center),
            originWidth: _heldOrigin?.width,
            over: _hoverTarget != null,
          ),
      ],
    ),
    );
  }

  Offset? _downAt;
  Duration _downTime = Duration.zero;

  void _openShelf(Branch tree, List<TreeItem> games) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.palette.surface,
      isScrollControlled: true,
      builder: (context) => _Shelf(
        title: tree.name,
        games: games,
        onOpen: (item) {
          Navigator.of(context).pop();
          widget.onOpenGame(item);
        },
      ),
    );
  }
}

class _TreePage extends StatefulWidget {
  const _TreePage({
    super.key,
    required this.tree,
    required this.pageIndex,
    required this.style,
    required this.games,
    required this.controller,
    required this.clock,
    required this.sprout,
    required this.groundFromBottom,
    required this.onFruit,
    required this.onShelf,
    required this.onRename,
    required this.onCustomise,
    required this.onShake,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
  });

  final Branch tree;
  final int pageIndex;
  final TreeStyle style;
  final List<TreeItem> games;
  final RiveTreeController controller;
  final MeadowClock clock;
  final bool sprout;
  final double groundFromBottom;
  final void Function(int slot) onFruit;
  final VoidCallback onShelf;
  final VoidCallback? onRename;
  final VoidCallback? onCustomise;
  final VoidCallback onShake;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMove;
  final GestureLongPressEndCallback onLongPressEnd;

  @override
  State<_TreePage> createState() => _TreePageState();
}

/// Kept alive once visited: a tree that was unmounted by a swipe away had to
/// reload its file and regrow from nothing when swiped back to.
class _TreePageState extends State<_TreePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final w = widget;
    final tree = w.tree, games = w.games;
    final extra = games.length - kTreeSlots;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Double-tap the tree to shake it, like the button.
          onDoubleTap: w.onShake,
          onLongPressStart: w.onLongPressStart,
          onLongPressMoveUpdate: w.onLongPressMove,
          onLongPressEnd: w.onLongPressEnd,
          child: ExcludeSemantics(
            child: _Stage(
              groundFromBottom: w.groundFromBottom,
              zoom: treeZoom(games.length),
              pageIndex: w.pageIndex,
              style: w.style,
              clock: w.clock,
              child: _Sprouting(
                sprout: w.sprout,
                builder: (planted) => RiveTree(
                  games: games.map((i) => i.game).toList(),
                  looks: games.map(lookOf).toList(),
                  grownTarget: games.length,
                  onlyGrow: false,
                  planted: planted,
                  controller: w.controller,
                  onFruitTap: w.onFruit,
                  fit: rv.Fit.contain,
                  alignment: Alignment.center,
                  asset: w.style.asset,
                ),
              ),
            ),
          ),
        ),
        // Name and count top-left, clear of the canopy; the customise button
        // top-right, where a screen's own actions go.
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                Tokens.space.lg, Tokens.space.md, Tokens.space.sm, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onLongPress: w.onRename,
                  child: Text(
                    tree.name,
                    key: const Key('orchard-tree-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Tokens.type.displayFamily,
                      fontSize: Tokens.type.display,
                      fontWeight: FontWeight.w700,
                      color: Tokens.palette.text,
                      letterSpacing: Tokens.type.trackingDisplay,
                      height: Tokens.type.leadingDisplay,
                    ),
                  ),
                ),
                SizedBox(height: Tokens.space.xxs),
                Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Semantics(
                  container: true,
                  button: true,
                  label: '${_count(games.length)} on ${tree.name}. Show all',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Tokens.radius.card),
                    onTap: w.onShelf,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: Tokens.space.xs),
                      child: Text(
                        extra > 0
                            ? '${_count(games.length)}  ·  +$extra on the shelf'
                            : _count(games.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Tokens.type.body,
                            color: Tokens.palette.textDim),
                      ),
                    ),
                  ),
                )),
                // This tree's own look, beside its own count: it belongs to
                // the tree, not to the app's actions at the top right. The
                // shake is not here any more: it is the orchard's one playful
                // action, so it sits in the thumb's reach by the add button.
                if (w.onCustomise != null)
                  IconButton(
                    key: const Key('orchard-customise'),
                    onPressed: w.onCustomise,
                    // IconButton's tooltip does not reach semantics; the
                    // icon's label does.
                    icon: Icon(Icons.palette_outlined,
                        size: 20,
                        color: Tokens.palette.textDim,
                        semanticLabel: 'Customise ${tree.name}'),
                    style: IconButton.styleFrom(
                        minimumSize: const Size.square(44)),
                  ),
                ]),
              ],
            ),
                ),
                // Room for the orchard's own icon buttons, top right.
                const SizedBox(width: kTopActionsW),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _count(int n) => n == 1 ? '1 game' : '$n games';
}

/// Holds a new tree unplanted for one frame, then plants it, so its page plays
/// the seed -> sapling once. Every other tree mounts planted.
class _Sprouting extends StatefulWidget {
  const _Sprouting({required this.sprout, required this.builder});
  final bool sprout;
  final Widget Function(bool planted) builder;

  @override
  State<_Sprouting> createState() => _SproutingState();
}

class _SproutingState extends State<_Sprouting> {
  late bool _planted = !widget.sprout;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.sprout) {
      // Long enough for the file to load and settle unplanted first.
      _t = Timer(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _planted = true);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_planted);
}

class _PatchPage extends StatelessWidget {
  const _PatchPage(
      {super.key, required this.onPlant, required this.groundFromBottom});
  final VoidCallback onPlant;
  final double groundFromBottom;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: _Stage(
            groundFromBottom: groundFromBottom,
            zoom: treeZoom(0),
            child: RiveTree(
                games: const [],
                grownTarget: 0,
                planted: false,
                fit: rv.Fit.contain,
                alignment: Alignment.center),
          ),
        ),
        Semantics(
          button: true,
          label: 'Plant a new tree',
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('orchard-plant'),
            behavior: HitTestBehavior.opaque,
            onTap: onPlant,
          ),
        ),
        // Said by the button above; visual only.
        ExcludeSemantics(
          child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                Tokens.space.lg, Tokens.space.md, Tokens.space.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('A new tree',
                    style: TextStyle(
                        fontFamily: Tokens.type.displayFamily,
                        fontSize: Tokens.type.display,
                        fontWeight: FontWeight.w700,
                        color: Tokens.palette.text,
                        letterSpacing: Tokens.type.trackingDisplay,

                        height: Tokens.type.leadingDisplay)),
                SizedBox(height: Tokens.space.xs),
                Text('Tap the patch to plant one.',
                    style: TextStyle(
                        fontSize: Tokens.type.body,
                        color: Tokens.palette.textDim)),
              ],
            ),
          ),
        ),
        ),
      ],
    );
  }
}

/// Where a tree stands on its page, with its halo and props around it. The
/// sky and the ground are NOT here: they are one continuous meadow painted
/// behind all the pages (meadow.dart), so nothing ends at a page's edge.
///
/// [zoom] eases (interruptibly: the tween retargets from the value on screen)
/// whenever the tree's size changes, and the halo and props ride the same
/// frame as the tree.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.groundFromBottom,
    required this.zoom,
    required this.child,
    this.pageIndex = 0,
    this.style,
    this.clock,
  });
  final double groundFromBottom;
  final double zoom;
  final Widget child;
  final int pageIndex;
  final MeadowClock? clock;

  /// Null for the empty patch: no halo, no props.
  final TreeStyle? style;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final st = style;
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final groundY = size.height - groundFromBottom;
      return TweenAnimationBuilder<double>(
        tween: Tween(end: zoom),
        duration: Tokens.motion.maybe(Tokens.motion.camera, reduceMotion: reduce),
        curve: Tokens.motion.easeInOut,
        child: child,
        builder: (context, z, child) {
          final r = treeFrame(size, groundY, z);
          CustomPaint decor(bool front) => CustomPaint(
              painter: DecorPainter(
                  tree: r,
                  decor: st!.decor,
                  front: front,
                  groundY: groundY,
                  pageIndex: pageIndex,
                  clock: clock));
          // No clip: the halo and fireflies are soft light wider than a page.
          // Clipped, each tree's glow ended in a hard vertical edge mid-swipe.
          return Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
                child: IgnorePointer(
                    child: CustomPaint(
                        painter: GroundContactPainter(
                            tree: r,
                            groundY: groundY,
                            pageIndex: pageIndex,
                            patch: st == null)))),
            if (st != null)
              Positioned.fill(
                  child: IgnorePointer(child: RepaintBoundary(child: decor(false)))),
            Positioned.fromRect(rect: r, child: child!),
            if (st != null)
              Positioned.fill(
                  child: IgnorePointer(child: RepaintBoundary(child: decor(true)))),
          ]);
        },
      );
    });
  }
}

class _TreeDots extends StatelessWidget {
  const _TreeDots({
    required this.trees,
    required this.page,
    required this.holding,
    required this.heldFrom,
    required this.hover,
    required this.keys,
    required this.onTap,
  });

  final List<Branch> trees;
  final double page;
  final bool holding;
  final int? heldFrom;
  final int? hover;
  final Map<int, GlobalKey> keys;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final dur = Tokens.motion.maybe(Tokens.motion.swap, reduceMotion: still);
    final children = <Widget>[];
    for (var i = 0; i <= trees.length; i++) {
      final isPatch = i == trees.length;
      final t = isPatch ? null : trees[i];
      final active = (page - i).abs() < 0.5;
      final isTarget = holding && t != null && t.id != heldFrom;
      final hovered = t != null && t.id == hover;
      final key = t == null ? null : keys.putIfAbsent(t.id, GlobalKey.new);
      children.add(Semantics(
        button: true,
        selected: active,
        label: isPatch ? 'Go to a new tree' : 'Go to ${t!.name}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => onTap(i),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: Tokens.space.xxs, vertical: Tokens.space.sm),
            child: AnimatedContainer(
              key: key,
              duration: dur,
              curve: Tokens.motion.easeOut,
              height: isTarget ? 32 : 8,
              padding: EdgeInsets.symmetric(
                  horizontal: isTarget ? Tokens.space.sm : 0),
              constraints: BoxConstraints(minWidth: active ? 22 : 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered
                    ? Tokens.palette.accent
                    : isTarget
                        ? Tokens.cosmos.panel
                        : active
                            ? Tokens.palette.text
                            : Tokens.palette.textDim.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: isTarget
                    ? Border.all(color: Tokens.cosmos.panelEdge)
                    : null,
              ),
              child: isTarget
                  ? Text(t.name,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: Tokens.type.caption,
                          fontWeight: FontWeight.w600,
                          color: hovered
                              ? Tokens.palette.bg
                              : Tokens.palette.text))
                  : null,
            ),
          ),
        ),
      ));
    }
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: Tokens.space.lg),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// The card in your hand. It lifts out of where it was picked up (a short
/// ease into place above the finger, where the finger does not hide it),
/// then tracks the finger 1:1. Over a tree it grows a little: that tree will
/// take it.
class _HeldFruit extends StatelessWidget {
  const _HeldFruit({
    required this.item,
    required this.at,
    this.origin,
    this.originWidth,
    required this.over,
  });
  final TreeItem item;
  final Offset at;
  final Offset? origin;
  final double? originWidth;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final m = Tokens.motion;
    final above = at - const Offset(0, kHoldAbove);
    final startScale = (originWidth ?? kHeldW) / kHeldW;
    return TweenAnimationBuilder<double>(
      key: ValueKey('held-${item.game.igdbId}'),
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: m.maybe(m.swap, reduceMotion: reduce),
      curve: m.easeOut,
      builder: (context, lift, child) {
        const h = kHeldW * kFruitH / kFruitW;
        // From where it was picked up to above the finger; converges on the
        // finger by the end of the lift, then it is 1:1.
        final c = origin == null ? above : Offset.lerp(origin, above, lift)!;
        final scale = startScale + (1 - startScale) * lift;
        return Positioned(
          left: c.dx - kHeldW / 2,
          top: c.dy - h / 2,
          child: IgnorePointer(
            child: Transform.scale(
              scale: scale,
              child: AnimatedScale(
                scale: over ? 1.1 : 1,
                duration: m.maybe(m.swap, reduceMotion: reduce),
                curve: m.easeOut,
                child: Transform.rotate(angle: -0.05 * lift, child: child),
              ),
            ),
          ),
        );
      },
      child: FruitImage(
        game: item.game,
        look: lookOf(item),
        width: kHeldW,
        radius: 7,
        shadow: true,
        border: Border.all(color: Tokens.palette.text.withValues(alpha: 0.85), width: 1.5),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.games, required this.onOpen});
  final String title;
  final List<TreeItem> games;
  final void Function(TreeItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                Tokens.space.lg, Tokens.space.lg, Tokens.space.lg, Tokens.space.sm),
            child: Text(title,
                style: TextStyle(
                    fontFamily: Tokens.type.displayFamily,
                    fontSize: Tokens.type.title,
                    fontWeight: FontWeight.w700,
                    color: Tokens.palette.text)),
          ),
          Expanded(
            child: GridView.builder(
              controller: scroll,
              padding: EdgeInsets.all(Tokens.space.md),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                childAspectRatio: 0.62,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: games.length,
              itemBuilder: (context, i) => _ShelfItem(
                item: games[i],
                onTap: () => onOpen(games[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfItem extends StatelessWidget {
  const _ShelfItem({required this.item, required this.onTap});
  final TreeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = item.game.coverUrl;
    return Semantics(
      button: true,
      label: item.game.title,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: url == null || url.isEmpty
                    ? ColoredBox(
                        color: Tokens.cosmos.panelDeep,
                        child: Icon(Icons.videogame_asset_outlined,
                            color: Tokens.palette.textDim))
                    : Image.network(url, fit: BoxFit.cover),
              ),
            ),
            SizedBox(height: Tokens.space.xxs),
            // Takes what is left of the cell rather than adding to it, so a
            // wrapped title (or large system text) ellipsises, never overflows.
            Expanded(
              child: Text(item.game.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Tokens.type.caption,
                      color: Tokens.palette.text)),
            ),
          ],
        ),
      ),
    );
  }
}


/// One of the orchard's top-right icon buttons.
typedef OrchardAction = ({IconData icon, String label, VoidCallback onTap});

/// The shake button's diameter: a step below the add button (56), which
/// stays the primary action.
const double kShakeSize = 48;

/// The shake glyph: a small tree with the sway lines of being shaken and a
/// fruit falling from it. A die said "random" but not "shake the tree".
class ShakeGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 26;
    final ink = Paint()
      ..color = Tokens.palette.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    // Canopy, trunk.
    canvas.drawCircle(Offset(13 * s, 9.5 * s), 6.2 * s, ink);
    canvas.drawLine(Offset(13 * s, 15.7 * s), Offset(13 * s, 23 * s), ink);
    // Sway lines either side.
    final thin = Paint()
      ..color = Tokens.palette.text.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: Offset(13 * s, 9.5 * s), radius: 9.8 * s),
        2.69, 0.9, false, thin);
    canvas.drawArc(Rect.fromCircle(center: Offset(13 * s, 9.5 * s), radius: 9.8 * s),
        -0.45, 0.9, false, thin);
    // The fruit, falling.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(20.5 * s, 21 * s), width: 3.6 * s, height: 4.6 * s),
            Radius.circular(1 * s)),
        Paint()..color = Tokens.palette.text);
  }

  @override
  bool shouldRepaint(ShakeGlyph old) => false;
}

/// Width the header leaves free for [_TopActions] (three 44pt buttons in a
/// glass pill). Measured, not guessed: 3 x 44 + 2 x 2 gaps + 2 x 4 inset.
const double kTopActionsW = 3 * 44 + 2 * 2 + 2 * 4;

/// Library, Friends and You as quiet icon buttons in one glass pill: the
/// places the app goes besides the orchard, out of the scene's way.
class _TopActions extends StatelessWidget {
  const _TopActions({required this.actions});
  final List<OrchardAction> actions;

  @override
  Widget build(BuildContext context) {
    return Glass(
      child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          IconButton(
            key: Key('orchard-action-${actions[i].label.toLowerCase()}'),
            onPressed: () {
              HapticFeedback.selectionClick();
              actions[i].onTap();
            },
            icon: Icon(actions[i].icon,
                size: 22,
                color: Tokens.palette.text,
                semanticLabel: actions[i].label),
            style: IconButton.styleFrom(minimumSize: const Size.square(44)),
          ),
        ],
      ]),
    ),
    );
  }
}

/// What a shake knocked loose: the game, the true reason it is a good pick
/// tonight (pick.dart), and what to do with it. Frosted glass over the
/// meadow, so the fallen fruit stays in view above it.
class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.pick,
    required this.treeName,
    required this.onPlay,
    required this.onAgain,
    required this.onOpen,
    required this.onClose,
  });

  final Pick pick;
  final String treeName;
  final VoidCallback onPlay, onAgain, onOpen, onClose;

  @override
  Widget build(BuildContext context) {
    final item = pick.item;
    final bud = item.entry.ownership != Ownership.owned;
    final primary = bud
        ? 'Take a look'
        : switch (item.entry.progress) {
            Progress.playing => 'Back to it',
            Progress.finished => 'Play again',
            Progress.abandoned => 'Give it a go',
            _ => 'Play it',
          };
    return Glass(
      shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(Tokens.radius.sheet)),
      child: Padding(
          padding: EdgeInsets.all(Tokens.space.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              button: true,
              label: 'Open ${item.game.title}',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onOpen,
                child: FruitImage(
                    game: item.game, look: lookOf(item), width: 66, radius: 8),
              ),
            ),
            SizedBox(width: Tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('Fell from $treeName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Tokens.type.caption,
                              color: Tokens.palette.textDim)),
                    ),
                    IconButton(
                      key: const Key('pick-close'),
                      onPressed: onClose,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 18,
                          color: Tokens.palette.textDim,
                          semanticLabel: 'Put it back'),
                    ),
                  ]),
                  Text(item.game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: Tokens.type.displayFamily,
                          fontSize: Tokens.type.title,
                          fontWeight: FontWeight.w700,
                          color: Tokens.palette.text)),
                  SizedBox(height: Tokens.space.xxs),
                  Text(pick.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Tokens.type.caption,
                          color: Tokens.palette.textDim)),
                  SizedBox(height: Tokens.space.sm),
                  Wrap(spacing: Tokens.space.xs, runSpacing: Tokens.space.xs, children: [
                    FilledButton(
                      key: const Key('pick-play'),
                      onPressed: bud ? onOpen : onPlay,
                      style: FilledButton.styleFrom(
                          backgroundColor: Tokens.palette.text,
                          foregroundColor: Tokens.palette.bg,
                          visualDensity: VisualDensity.compact),
                      child: Text(primary),
                    ),
                    TextButton.icon(
                      key: const Key('pick-again'),
                      onPressed: onAgain,
                      style: TextButton.styleFrom(
                          foregroundColor: Tokens.palette.text,
                          backgroundColor: Tokens.cosmos.panel,
                          shape: const StadiumBorder(),
                          visualDensity: VisualDensity.compact),
                      icon: CustomPaint(
                          size: const Size.square(18), painter: ShakeGlyph()),
                      label: const Text('Shake again'),
                    ),
                  ]),
                ],
              ),
            ),
          ]),
      ),
    );
  }
}

/// A shake with nothing to drop still gets an answer, in words, and never a
/// guilty one (DECISIONS.md: no nagging).
class _NothingToShake extends StatelessWidget {
  const _NothingToShake({super.key, required this.treeName});
  final String treeName;

  @override
  Widget build(BuildContext context) => Center(
        child: Glass(
          child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Tokens.space.md, vertical: Tokens.space.sm),
          child: Text(
            'Nothing on $treeName to shake loose right now',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Tokens.type.caption, color: Tokens.palette.text),
          ),
          ),
        ),
      );
}
