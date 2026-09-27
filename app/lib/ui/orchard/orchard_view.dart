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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Prefixed: rive_native exports its own Animation / Image / Fit names.
import 'package:rive/rive.dart' as rv;

import '../../data/models.dart';
import '../../domain/branch_tree.dart';
import '../common/name_dialog.dart';
import '../tokens.dart';
import 'rive_tree.dart';

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
    this.onRenameTree,
    this.unfiled = const [],
    this.onUnfiledTap,
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
  final void Function(Branch tree)? onRenameTree;

  /// Games on no tree yet. They sit "on the ground": a quiet pile, never a
  /// nag or a count of what is outstanding (DECISIONS.md).
  final List<TreeItem> unfiled;
  final VoidCallback? onUnfiledTap;

  /// Space the app's own bottom chrome takes (nav pill, add button).
  final double bottomInset;

  @override
  State<OrchardView> createState() => _OrchardViewState();
}

class _OrchardViewState extends State<OrchardView> {
  final PageController _pages = PageController();
  double _page = 0;
  final Map<int, RiveTreeController> _controllers = {};

  /// A tree planted this session: its page plays the seed -> sapling once.
  int? _sproutId;

  // Drag-to-move state.
  TreeItem? _held;
  int? _heldFrom;
  Offset _heldAt = Offset.zero;
  int? _hoverTarget;
  final Map<int, GlobalKey> _dotKeys = {};

  @override
  void initState() {
    super.initState();
    _pages.addListener(() => setState(() => _page = _pages.page ?? 0));
  }

  @override
  void dispose() {
    _pages.dispose();
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
    final now = treesOf(widget.branches);
    final fresh = now.where((b) => !before.contains(b.id)).toList();
    if (fresh.isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() => _sproutId = fresh.first.id);
    }
  }

  // ---- drag to move -------------------------------------------------------
  void _pickUp(Branch tree, List<TreeItem> games, LongPressStartDetails d) {
    final slot = _controllers[tree.id]?.pressed ?? -1;
    if (slot < 0 || slot >= games.length || slot >= kTreeSlots) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _held = games[slot];
      _heldFrom = tree.id;
      _heldAt = d.globalPosition;
      _hoverTarget = null;
    });
  }

  void _dragTo(LongPressMoveUpdateDetails d) {
    if (_held == null) return;
    int? over;
    for (final e in _dotKeys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      // Generous: the dot's box inflated to a 56pt target.
      final r = (box.localToGlobal(Offset.zero) & box.size).inflate(14);
      if (r.contains(d.globalPosition) && e.key != _heldFrom) over = e.key;
    }
    if (over != _hoverTarget) HapticFeedback.selectionClick();
    setState(() {
      _heldAt = d.globalPosition;
      _hoverTarget = over;
    });
  }

  Future<void> _release() async {
    final item = _held, from = _heldFrom, to = _hoverTarget;
    setState(() {
      _held = null;
      _heldFrom = null;
      _hoverTarget = null;
    });
    if (item == null || from == null || to == null) return;
    HapticFeedback.mediumImpact();
    await widget.onMoveGame(item, from, to);
  }

  @override
  Widget build(BuildContext context) {
    final trees = treesOf(widget.branches);
    final shape = BranchTree(widget.branches, widget.placements);
    final byId = {for (final i in widget.items) i.game.igdbId: i};
    final pageCount = trees.length + 1; // + the empty patch

    // One control row at the add button's height: ground pile left, tree dots
    // centre (the add button, owned by the shell, sits right). Pages run the
    // full screen so the sky continues under the controls; each tree's soil
    // line is placed just above the dots, so its base, the patch and the fruit
    // never sit behind chrome.
    final rowBottom = MediaQuery.paddingOf(context).bottom + widget.bottomInset;
    const rowH = 52.0, dotsH = 48.0;
    final treeBottom = rowBottom + rowH + dotsH;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: PageView.builder(
          controller: _pages,
          physics: const BouncingScrollPhysics(),
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
              games: games,
              controller: c,
              sprout: tree.id == _sproutId,
              groundFromBottom: treeBottom,
              onFruit: (slot) {
                if (slot < games.length) widget.onOpenGame(games[slot]);
              },
              onShelf: () => _openShelf(tree, games),
              onRename: widget.onRenameTree == null
                  ? null
                  : () => widget.onRenameTree!(tree),
              onLongPressStart: (d) => _pickUp(tree, games, d),
              onLongPressMove: _dragTo,
              onLongPressEnd: (_) => _release(),
            );
          },
        ),
        ),

        // Tree dots, in their own band just above the control row: where you
        // are, and where a held fruit can go.
        Positioned(
          left: 0,
          right: 0,
          bottom: rowBottom + rowH,
          height: dotsH,
          child: _TreeDots(
            trees: trees,
            page: _page,
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

        // The ground pile shares the add button's row, on the left.
        if (widget.unfiled.isNotEmpty && _held == null)
          Positioned(
            left: Tokens.space.md,
            right: 88, // clear of the add button's column
            bottom: rowBottom,
            height: rowH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Ground(items: widget.unfiled, onTap: widget.onUnfiledTap),
            ),
          ),

        if (_held != null) _HeldFruit(item: _held!, at: _heldAt),
      ],
    );
  }

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

class _TreePage extends StatelessWidget {
  const _TreePage({
    super.key,
    required this.tree,
    required this.games,
    required this.controller,
    required this.sprout,
    required this.groundFromBottom,
    required this.onFruit,
    required this.onShelf,
    required this.onRename,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
  });

  final Branch tree;
  final List<TreeItem> games;
  final RiveTreeController controller;
  final bool sprout;
  final double groundFromBottom;
  final void Function(int slot) onFruit;
  final VoidCallback onShelf;
  final VoidCallback? onRename;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMove;
  final GestureLongPressEndCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final extra = games.length - kTreeSlots;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: onLongPressStart,
          onLongPressMoveUpdate: onLongPressMove,
          onLongPressEnd: onLongPressEnd,
          child: ExcludeSemantics(
            child: _Stage(
              groundFromBottom: groundFromBottom,
              zoom: treeZoom(games.length),
              child: _Sprouting(
                sprout: sprout,
                builder: (planted) => RiveTree(
                  games: games.map((i) => i.game).toList(),
                  grownTarget: games.length,
                  planted: planted,
                  controller: controller,
                  onFruitTap: onFruit,
                  fit: rv.Fit.contain,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
        ),
        // Name and count. Top-left, clear of the canopy.
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                Tokens.space.lg, Tokens.space.md, Tokens.space.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onLongPress: onRename,
                  child: Text(
                    tree.name,
                    key: const Key('orchard-tree-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Tokens.type.display,
                      fontWeight: FontWeight.w700,
                      color: Tokens.palette.text,
                      letterSpacing: Tokens.type.trackingDisplay,
                      height: Tokens.type.leadingDisplay,
                    ),
                  ),
                ),
                SizedBox(height: Tokens.space.xxs),
                Semantics(
                  container: true,
                  button: true,
                  label: '${_count(games.length)} on ${tree.name}. Show all',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Tokens.radius.card),
                    onTap: onShelf,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: Tokens.space.xs),
                      child: Text(
                        extra > 0
                            ? '${_count(games.length)}  ·  +$extra on the shelf'
                            : _count(games.length),
                        style: TextStyle(
                            fontSize: Tokens.type.body,
                            color: Tokens.palette.textDim),
                      ),
                    ),
                  ),
                ),
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

/// The sky a tree stands in, full screen, with the artboard placed so its soil
/// line sits [groundFromBottom] above the bottom edge.
///
/// The artboard is 412x732 and a phone is taller, so the file's own sky cannot
/// reach the screen edges. Above the artboard the sky is continued in its top
/// colour and below it in its bottom colour -- the same stops the file uses
/// (`Tokens.cosmos.deep`) -- so there is no seam where the file ends and the
/// controls begin. [zoom] eases (interruptibly: the tween retargets from the
/// value on screen) whenever the tree's size changes.
class _Stage extends StatelessWidget {
  const _Stage(
      {required this.groundFromBottom, required this.zoom, required this.child});
  final double groundFromBottom;
  final double zoom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final sky = Tokens.cosmos.deep;
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
          return Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned.fill(child: ColoredBox(color: sky.last)),
            Positioned(
                left: 0,
                right: 0,
                top: 0,
                // One px of overlap so no hairline shows at the join.
                height: (r.top + 1).clamp(0.0, size.height),
                child: ColoredBox(color: sky.first)),
            Positioned.fromRect(rect: r, child: child!),
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

class _HeldFruit extends StatelessWidget {
  const _HeldFruit({required this.item, required this.at});
  final TreeItem item;
  final Offset at;

  @override
  Widget build(BuildContext context) {
    const w = 56.0, h = w * 4 / 3;
    final url = item.game.coverUrl;
    return Positioned(
      left: at.dx - w / 2,
      top: at.dy - h - 24, // above the finger, so it can be seen
      child: IgnorePointer(
        child: Transform.rotate(
          angle: -0.06,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: Tokens.palette.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Tokens.palette.accent, width: 1.5),
              boxShadow: [
                BoxShadow(blurRadius: 18, offset: const Offset(0, 8),
                    color: Tokens.palette.bg.withValues(alpha: 0.6)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: url == null || url.isEmpty
                ? Center(
                    child: Text(item.game.title.characters.first,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Tokens.palette.text)))
                : Image.network(url, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

/// Games on no tree yet, as a small fanned pile of covers with a plain label.
class _Ground extends StatelessWidget {
  const _Ground({required this.items, this.onTap});
  final List<TreeItem> items;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    final label = n == 1 ? '1 on the ground' : '$n on the ground';
    final fan = items.take(3).toList();
    const w = 26.0, h = w * 4 / 3;
    return Semantics(
      button: true,
      label: '${n == 1 ? '1 game' : '$n games'} on the ground. '
          'Open the library to put them on a tree',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('orchard-ground'),
        borderRadius: BorderRadius.circular(Tokens.radius.card),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(Tokens.space.xs),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: w + 10.0 * (fan.length - 1),
              height: h + 4,
              child: Stack(children: [
                for (var i = fan.length - 1; i >= 0; i--)
                  Positioned(
                    left: 10.0 * i,
                    top: i.isEven ? 4 : 0,
                    child: Transform.rotate(
                      angle: (i - 1) * 0.12,
                      child: _Thumb(item: fan[i], w: w, h: h),
                    ),
                  ),
              ]),
            ),
            SizedBox(width: Tokens.space.sm),
            // Flexible + one line: the parent caps this row at 36pt tall, so
            // wrapping cannot help at large text sizes. The semantics label
            // above carries the full sentence either way.
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Tokens.type.caption,
                      color: Tokens.palette.textDim)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.w, required this.h});
  final TreeItem item;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    final url = item.game.coverUrl;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Tokens.cosmos.panelDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Tokens.cosmos.panelEdge),
      ),
      clipBehavior: Clip.antiAlias,
      // No cover yet: the title's first letter, so the pile reads as games
      // rather than as images that failed to load.
      child: url == null || url.isEmpty
          ? Center(
              child: Text(item.game.title.characters.first.toUpperCase(),
                  style: TextStyle(
                      fontSize: Tokens.type.caption,
                      fontWeight: FontWeight.w700,
                      color: Tokens.palette.textDim)))
          : Image.network(url, fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => const SizedBox()),
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
