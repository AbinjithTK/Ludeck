// The home tree as a clean NODE OUTLINE. Replaces the painted canopy.
//
// A drop-in for `CanopyView`: identical constructor, so `main.dart` swaps one
// word. Where the canopy painted bark and foliage, this draws a standard,
// legible hierarchy -- rounded branch nodes, smaller game nodes, depth by
// indentation, soft elbow connectors -- because Abin's steer was "avoid tree,
// get back to the standard node like tree" and "polished look and usability of
// core functionality". Nothing here touches `Tokens.canopy`; every colour comes
// from `Tokens.palette` / `Tokens.cosmos`.
//
// Layout is `node_tree_layout.dart` (pure, unit-tested); this file is the
// interactive shell and the node/connector painting.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/enums.dart';
import '../../data/models.dart';
import '../../domain/branch_tree.dart';
import '../../services/cover_art_cache.dart';
import '../tokens.dart';

class NodeTreeView extends StatefulWidget {
  const NodeTreeView({
    super.key,
    required this.items,
    required this.branches,
    required this.placements,
    this.unfiledCount = 0,
    this.coverCache,
    this.onCoverFound,
    this.onSelect,
    this.onHold,
    this.onCreateBranch,
    this.onBranchHold,
    this.onToggleCollapse,
    this.onMoveGame,
    this.onPick,
    this.onUnfiledTap,
    this.onSwitchView,
    this.bottomInset = 0,
    this.rightInset = 0,
  });

  final List<TreeItem> items;
  final List<Branch> branches;
  final Map<int, List<int>> placements;
  final int unfiledCount;

  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  final ValueChanged<TreeItem>? onSelect;
  final ValueChanged<TreeItem>? onHold;

  /// Grow a new branch under [parentId] (`null` = from the trunk).
  final ValueChanged<int?>? onCreateBranch;

  /// Long-press / more on a branch: rename, move, delete.
  final ValueChanged<Branch>? onBranchHold;

  /// Fold or unfold a branch. Persisted via the store (schema v4 `collapsed`).
  final ValueChanged<Branch>? onToggleCollapse;

  /// Drop a dragged game onto a branch. The parent decides move-vs-also-add.
  final void Function(TreeItem game, Branch target)? onMoveGame;

  /// "What should I play?" with the games under [from] (null = whole tree).
  final void Function(List<TreeItem> pool, Branch? from)? onPick;

  final VoidCallback? onUnfiledTap;
  final VoidCallback? onSwitchView;
  final double bottomInset;
  final double rightInset;

  @override
  State<NodeTreeView> createState() => NodeTreeViewState();
}

class NodeTreeViewState extends State<NodeTreeView> {
  /// Fold state the store has not persisted yet is mirrored here so a tap feels
  /// instant; the store's `collapsed` field is the source of truth on rebuild.
  final Set<int> _optimisticCollapsed = {};

  @override
  Widget build(BuildContext context) {
    final tree = BranchTree(widget.branches, widget.placements);
    final byId = {for (final i in widget.items) i.game.igdbId: i};
    final live = [for (final i in widget.items) if (!i.entry.shelved) i.game.igdbId];

    // Effective collapsed = persisted `collapsed` XOR the optimistic override,
    // so a tap flips a branch instantly and the store write reconciles it.
    final collapsed = <int>{
      for (final b in widget.branches)
        if (b.collapsed ^ _optimisticCollapsed.contains(b.id)) b.id,
    };

    return LayoutBuilder(builder: (context, box) {
      // The floating control stack: CTA row (control height) + its bottom
      // margin, plus the unfiled pill and its gap when shown. The scroll must
      // reserve all of it or the last rows hide behind the buttons.
      final unfiledBand =
          (!tree.isEmpty && widget.unfiledCount > 0) ? 36.0 + Tokens.space.xs : 0.0;
      final bottomClear = widget.bottomInset +
          Tokens.size.control +
          Tokens.space.md * 2 +
          unfiledBand;

      // First run: no branches and no games.
      if (tree.isEmpty && live.isEmpty) {
        return _EmptyTree(
          onCreate: widget.onCreateBranch == null
              ? null
              : () => widget.onCreateBranch!(null),
          onSwitchView: widget.onSwitchView,
        );
      }

      final pool = widget.items.where((i) => !i.entry.shelved).toList();

      return Stack(children: [
        Positioned.fill(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: 40 + Tokens.space.md)),
              // Games with no branch hang on the trunk with a nudge to group.
              if (tree.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(Tokens.space.md, 0,
                        Tokens.space.md, Tokens.space.sm),
                    child: Text(
                      'These games are on the trunk. Group them into a branch by '
                      'mood, length or who you play with.',
                      style: TextStyle(
                          color: Tokens.palette.textDim,
                          fontSize: Tokens.type.caption),
                    ),
                  ),
                ),
              if (tree.isEmpty)
                SliverList.builder(
                  itemCount: live.length,
                  itemBuilder: (c, i) {
                    final item = byId[live[i]];
                    if (item == null) return const SizedBox.shrink();
                    return _GameNodeRow(
                      item: item,
                      depth: 0,
                      isLast: i == live.length - 1,
                      onTap: () => widget.onSelect?.call(item),
                      coverCache: widget.coverCache,
                      onCoverFound: widget.onCoverFound,
                    );
                  },
                )
              else
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final b in tree.roots)
                        _BranchSubtree(
                          branch: b,
                          tree: tree,
                          byId: byId,
                          depth: 0,
                          collapsedIds: collapsed,
                          onToggle: _toggle,
                          onSelectGame: widget.onSelect,
                          onBranchHold: widget.onBranchHold,
                          onCreateBranch: widget.onCreateBranch,
                          onMoveGame: widget.onMoveGame,
                          coverCache: widget.coverCache,
                          onCoverFound: widget.onCoverFound,
                        ),
                    ],
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: bottomClear + 48)),
            ],
          ),
        ),

        // Top bar: title + path-view escape.
        Positioned(
          left: Tokens.space.md,
          right: Tokens.space.md,
          top: Tokens.space.xs,
          child: _TopBar(onSwitchView: widget.onSwitchView),
        ),

        // Bottom controls.
        Positioned(
          left: Tokens.space.md,
          right: Tokens.space.md + widget.rightInset,
          bottom: widget.bottomInset + Tokens.space.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!tree.isEmpty && widget.unfiledCount > 0) ...[
                _Pill(
                  label: widget.unfiledCount == 1
                      ? '1 new game · tap to file'
                      : '${widget.unfiledCount} new games · tap to file',
                  dashed: true,
                  onTap: widget.onUnfiledTap,
                ),
                SizedBox(height: Tokens.space.xs),
              ],
              Row(children: [
                Expanded(
                  child: _PrimaryButton(
                    label: 'What should I play?',
                    onTap: pool.isEmpty || widget.onPick == null
                        ? null
                        : () => widget.onPick!(pool, null),
                  ),
                ),
                SizedBox(width: Tokens.space.xs),
                _SecondaryButton(
                  label: '+ Branch',
                  onTap: widget.onCreateBranch == null
                      ? null
                      : () => widget.onCreateBranch!(null),
                ),
              ]),
            ],
          ),
        ),
      ]);
    });
  }

  void _toggle(Branch b) {
    HapticFeedback.selectionClick();
    setState(() {
      // Effective state = persisted `collapsed` XOR an optimistic override.
      // One tap flips the override so the animation starts instantly; the
      // store write then makes it durable and the override is reconciled on
      // the next rebuild.
      if (_optimisticCollapsed.contains(b.id)) {
        _optimisticCollapsed.remove(b.id);
      } else {
        _optimisticCollapsed.add(b.id);
      }
    });
    widget.onToggleCollapse?.call(b);
  }
}

/// The dominant lifecycle colour for a branch, from the games under it: gold if
/// any are finished, accent-dim if any are playing, else plain. A single quiet
/// signal, never a lock or a nag.
Color _branchTint(BranchTree tree, int branchId, Map<int, TreeItem> byId) {
  var anyFinished = false, anyPlaying = false;
  for (final id in tree.gamesUnder(branchId)) {
    final it = byId[id];
    if (it == null) continue;
    if (it.entry.progress == Progress.finished) {
      anyFinished = true;
    }
    if (it.entry.progress == Progress.playing ||
        it.entry.progress == Progress.installed) {
      anyPlaying = true;
    }
  }
  if (anyFinished) return Tokens.palette.accent;
  if (anyPlaying) {
    return Tokens.palette.accent.withValues(alpha: 0.55);
  }
  return Tokens.palette.textDim.withValues(alpha: 0.5);
}

const double _indentStep = 20;
const double _railWidth = 3;

/// One branch and everything under it, drawn recursively. The children
/// (sub-branches, then game rows) live inside an `AnimatedSize` + `ClipRect`
/// so folding the branch animates its height to zero instead of a hard cut.
class _BranchSubtree extends StatelessWidget {
  const _BranchSubtree({
    required this.branch,
    required this.tree,
    required this.byId,
    required this.depth,
    required this.collapsedIds,
    required this.onToggle,
    this.onSelectGame,
    this.onBranchHold,
    this.onCreateBranch,
    this.onMoveGame,
    this.coverCache,
    this.onCoverFound,
  });

  final Branch branch;
  final BranchTree tree;
  final Map<int, TreeItem> byId;
  final int depth;
  final Set<int> collapsedIds;
  final ValueChanged<Branch> onToggle;
  final ValueChanged<TreeItem>? onSelectGame;
  final ValueChanged<Branch>? onBranchHold;
  final ValueChanged<int?>? onCreateBranch;
  final void Function(TreeItem game, Branch target)? onMoveGame;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    final subBranches = tree.childrenOf(branch.id);
    final games = tree.gamesOn(branch.id);
    final hasChildren = subBranches.isNotEmpty || games.isNotEmpty;
    final collapsed = collapsedIds.contains(branch.id);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // The children column, built regardless of fold so AnimatedSize has a
    // stable child to grow to / shrink from.
    final children = <Widget>[
      for (final sb in subBranches)
        _BranchSubtree(
          branch: sb,
          tree: tree,
          byId: byId,
          depth: depth + 1,
          collapsedIds: collapsedIds,
          onToggle: onToggle,
          onSelectGame: onSelectGame,
          onBranchHold: onBranchHold,
          onCreateBranch: onCreateBranch,
          onMoveGame: onMoveGame,
          coverCache: coverCache,
          onCoverFound: onCoverFound,
        ),
      for (var i = 0; i < games.length; i++)
        if (byId[games[i]] != null)
          _DraggableGame(
            item: byId[games[i]]!,
            enabled: onMoveGame != null,
            child: _GameNodeRow(
              item: byId[games[i]]!,
              depth: depth,
              isLast: i == games.length - 1,
              onTap: () => onSelectGame?.call(byId[games[i]]!),
              coverCache: coverCache,
              onCoverFound: onCoverFound,
            ),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DragTarget<TreeItem>(
          onWillAcceptWithDetails: (d) => onMoveGame != null,
          onAcceptWithDetails: (d) => onMoveGame?.call(d.data, branch),
          builder: (context, candidate, rejected) => _BranchNodeRow(
            branch: branch,
            depth: depth,
            childCount: tree.gamesUnder(branch.id).length,
            hasChildren: hasChildren,
            collapsed: collapsed,
            tint: _branchTint(tree, branch.id, byId),
            highlighted: candidate.isNotEmpty,
            onToggle: () => onToggle(branch),
            onMore: onBranchHold == null ? null : () => onBranchHold!(branch),
            onAdd: onCreateBranch == null
                ? null
                : () => onCreateBranch!(branch.id),
          ),
        ),
        // Collapse to zero height when folded; ClipRect stops children
        // spilling during the shrink.
        ClipRect(
          child: AnimatedSize(
            duration: reduce ? Duration.zero : Tokens.motion.swap,
            curve: Tokens.motion.easeInOut,
            alignment: Alignment.topCenter,
            child: (collapsed || !hasChildren)
                ? const SizedBox(width: double.infinity, height: 0)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
          ),
        ),
      ],
    );
  }
}

/// A branch node: rounded panel with a lifecycle rail, name, count, chevron.
class _BranchNodeRow extends StatelessWidget {
  const _BranchNodeRow({
    required this.branch,
    required this.depth,
    required this.childCount,
    required this.hasChildren,
    required this.collapsed,
    required this.tint,
    this.highlighted = false,
    required this.onToggle,
    this.onMore,
    this.onAdd,
  });

  final Branch branch;
  final int depth;
  final int childCount;
  final bool hasChildren;
  final bool collapsed;
  final Color tint;
  final bool highlighted;
  final VoidCallback onToggle;
  final VoidCallback? onMore;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final b = branch;
    final indent = depth * _indentStep;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          Tokens.space.md + indent, Tokens.space.xxs, Tokens.space.md, Tokens.space.xxs),
      child: Semantics(
        label: '${b.name}, $childCount ${childCount == 1 ? 'game' : 'games'}'
            '${hasChildren ? (collapsed ? ', collapsed' : ', expanded') : ''}',
        button: true,
        excludeSemantics: true,
        child: Material(
          color: highlighted
              ? Tokens.palette.accent.withValues(alpha: 0.12)
              : Tokens.cosmos.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radius.card),
            side: BorderSide(
                color: highlighted
                    ? Tokens.palette.accent
                    : Tokens.cosmos.panelEdge,
                width: highlighted ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hasChildren ? onToggle : onAdd,
            onLongPress: onMore,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: Tokens.space.sm, vertical: Tokens.space.sm),
              child: Row(children: [
                Container(
                  width: _railWidth,
                  height: 24,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(_railWidth),
                  ),
                ),
                SizedBox(width: Tokens.space.sm),
                if (hasChildren)
                  AnimatedRotation(
                    turns: collapsed ? 0 : 0.25,
                    duration: (MediaQuery.maybeDisableAnimationsOf(context) ??
                            false)
                        ? Duration.zero
                        : Tokens.motion.swap,
                    curve: Tokens.motion.easeInOut,
                    child: Icon(Icons.chevron_right,
                        size: 20, color: Tokens.palette.textDim),
                  )
                else
                  Icon(Icons.add, size: 18, color: Tokens.palette.textDim),
                SizedBox(width: Tokens.space.xs),
                Expanded(
                  child: Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Tokens.palette.text,
                      fontSize: Tokens.type.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: Tokens.space.xs),
                Text(
                  '$childCount',
                  style: TextStyle(
                      color: Tokens.palette.textDim,
                      fontSize: Tokens.type.caption),
                ),
                if (onMore != null) ...[
                  SizedBox(width: Tokens.space.xxs),
                  InkResponse(
                    onTap: onMore,
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.more_horiz,
                          size: 18, color: Tokens.palette.textDim),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a game row so it can be dragged onto a branch. Long-press to pick up
/// (a tap still opens the status sheet); the payload is the game itself, which
/// a branch `DragTarget` receives. Disabled when no move handler is wired (e.g.
/// the read-only profile portrait).
class _DraggableGame extends StatelessWidget {
  const _DraggableGame({
    required this.item,
    required this.enabled,
    required this.child,
  });

  final TreeItem item;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final feedback = Material(
      color: Tokens.cosmos.panelDeep,
      elevation: 6,
      borderRadius: BorderRadius.circular(Tokens.radius.card),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: Tokens.space.md, vertical: Tokens.space.sm),
        child: Text(item.game.title,
            style: TextStyle(
                color: Tokens.palette.text, fontSize: Tokens.type.body)),
      ),
    );
    return LongPressDraggable<TreeItem>(
      data: item,
      onDragStarted: HapticFeedback.selectionClick,
      feedback: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: feedback,
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

/// A game node: an indented row with a small cover, title, and a status dot.
class _GameNodeRow extends StatelessWidget {
  const _GameNodeRow({
    required this.item,
    required this.depth,
    required this.isLast,
    required this.onTap,
    this.coverCache,
    this.onCoverFound,
  });

  final TreeItem item;
  final int depth;
  final bool isLast;
  final VoidCallback onTap;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    // Games sit one indent deeper than their branch.
    final indent = (depth + 1) * _indentStep;
    final finished = item.isHarvested;
    final statusColour = finished
        ? Tokens.palette.accent
        : (item.entry.progress == Progress.playing ||
                item.entry.progress == Progress.installed)
            ? Tokens.palette.accent.withValues(alpha: 0.55)
            : Tokens.palette.textDim.withValues(alpha: 0.6);

    return Padding(
      key: ValueKey('game-node-${item.game.igdbId}'),
      padding: EdgeInsets.fromLTRB(
          Tokens.space.md + indent, 1, Tokens.space.md, 1),
      child: Semantics(
        label: '${item.game.title}, ${item.entry.progress.label}',
        button: true,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Tokens.radius.card),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Tokens.space.xxs),
              child: Row(children: [
                // Connector stub into the row.
                SizedBox(
                  width: 14,
                  height: 40,
                  child: CustomPaint(
                    painter: _ConnectorPainter(isLast: isLast),
                  ),
                ),
                _Cover(item: item, cache: coverCache, onFound: onCoverFound),
                SizedBox(width: Tokens.space.sm),
                Expanded(
                  child: Text(
                    item.game.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Tokens.palette.text, fontSize: Tokens.type.body),
                  ),
                ),
                SizedBox(width: Tokens.space.xs),
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: statusColour, shape: BoxShape.circle),
                ),
                if (finished) ...[
                  SizedBox(width: Tokens.space.xxs),
                  Icon(Icons.check_circle,
                      size: 14, color: Tokens.palette.accent),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small cover thumbnail on a game node -- real art when cached, initials
/// otherwise. Portrait 3:4 kept via coverRatio so art never crops.
class _Cover extends StatelessWidget {
  const _Cover({required this.item, this.cache, this.onFound});
  final TreeItem item;
  final CoverArtCache? cache;
  final void Function(int igdbId, String coverUrl)? onFound;

  @override
  Widget build(BuildContext context) {
    const w = 30.0;
    final h = w * Tokens.size.coverRatio;
    final url = item.game.coverUrl;
    Widget placeholder() => Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Tokens.cosmos.panelDeep,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Tokens.cosmos.panelEdge),
          ),
          child: Text(
            _initials(item.game.title),
            style: TextStyle(
                color: Tokens.palette.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        );
    if (url == null || url.isEmpty) return placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => placeholder(),
      ),
    );
  }

  static String _initials(String title) {
    final words = title.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.substring(0, words.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}

/// Draws the elbow connector into a game/branch row: a vertical rail down the
/// left and a short horizontal stub into the node. On the last child the rail
/// stops at the elbow rather than continuing past it.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({required this.isLast});
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Tokens.palette.textDim.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final midY = size.height / 2;
    final railX = 2.0;
    // Vertical rail: from the top to the elbow (or through, if not last).
    canvas.drawLine(
      Offset(railX, 0),
      Offset(railX, isLast ? midY : size.height),
      paint,
    );
    // Horizontal stub to the node.
    canvas.drawLine(Offset(railX, midY), Offset(size.width, midY), paint);
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) => old.isLast != isLast;
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.onSwitchView});
  final VoidCallback? onSwitchView;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (onSwitchView != null)
          TextButton.icon(
            onPressed: onSwitchView,
            icon: Icon(Icons.route_outlined,
                size: 18, color: Tokens.palette.textDim),
            label: Text('Path view',
                style: TextStyle(color: Tokens.palette.textDim)),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.dashed = false, this.onTap});
  final String label;
  final bool dashed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tokens.cosmos.panelDeep,
      shape: StadiumBorder(
        side: BorderSide(
            color: Tokens.palette.accent.withValues(alpha: dashed ? 0.7 : 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Tokens.space.md, vertical: Tokens.space.xs),
          child: Text(label,
              style: TextStyle(
                  color: Tokens.palette.text, fontSize: Tokens.type.caption)),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SizedBox(
      height: Tokens.size.control,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Tokens.cosmos.panelDeep,
          foregroundColor: Tokens.palette.accent,
          disabledBackgroundColor: Tokens.cosmos.panelDeep,
          disabledForegroundColor: Tokens.palette.textDim,
          shape: StadiumBorder(
            side: BorderSide(
                color: enabled
                    ? Tokens.palette.accent.withValues(alpha: 0.6)
                    : Tokens.cosmos.panelEdge),
          ),
          textStyle: TextStyle(
              fontSize: Tokens.type.body, fontWeight: FontWeight.w700),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tokens.cosmos.panel,
      shape: StadiumBorder(side: BorderSide(color: Tokens.cosmos.panelEdge)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: Tokens.space.md, vertical: Tokens.space.md),
          child: Text(label,
              style: TextStyle(
                  color: Tokens.palette.text, fontSize: Tokens.type.body)),
        ),
      ),
    );
  }
}

class _EmptyTree extends StatelessWidget {
  const _EmptyTree({this.onCreate, this.onSwitchView});
  final VoidCallback? onCreate;
  final VoidCallback? onSwitchView;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          Tokens.space.lg, Tokens.space.xl, Tokens.space.lg, Tokens.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grow your first branch',
              style: TextStyle(
                  color: Tokens.palette.text,
                  fontSize: Tokens.type.title,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: Tokens.space.sm),
          Text(
            'A branch is a group of games you\u2019d play in the same mood, like '
            '\u201CCouch co-op\u201D or \u201CUnder 30 minutes\u201D. Branches can '
            'hold smaller branches, and a game can sit on more than one.',
            style: TextStyle(
                color: Tokens.palette.textDim, fontSize: Tokens.type.body),
          ),
          SizedBox(height: Tokens.space.lg),
          if (onCreate != null)
            _PrimaryButton(label: 'Grow a branch', onTap: onCreate),
          if (onSwitchView != null) ...[
            SizedBox(height: Tokens.space.sm),
            TextButton(
              onPressed: onSwitchView,
              child: Text('See my games as a path instead',
                  style: TextStyle(color: Tokens.palette.textDim)),
            ),
          ],
        ],
      ),
    );
  }
}
