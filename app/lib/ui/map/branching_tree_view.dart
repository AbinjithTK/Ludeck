// The collection as an actual tree: a spine, with branches going left and right.
//
// This REPLACES the vertical serpentine roadmap. The roadmap wasted the whole
// horizontal axis -- a 64px card on a 1080px screen left the map ~80% empty sky
// and fitted four games out of eight -- and it drew a road rather than a tree,
// which is the metaphor the whole app is built on. Branching left and right uses
// the axis that was empty and says "tree" without a caption explaining it.
//
// Four things it has to do at once, and the tension between them is the design:
//
//   1. BRANCH left and right off a spine, so the shape reads as a tree.
//   2. Let you NAVIGATE along a branch, because a branch can hold more games
//      than fit across a phone.
//   3. Let you MOVE a game between branches by press-and-hold, which is the
//      direct-manipulation answer to filing.
//   4. NOT paint branch names, for a seamless look -- while still telling a
//      screen-reader user which category a game is in.
//
// (4) is the one that could have been faked. It is not: the branch name is on
// every node's `Semantics` label ("Hades, on Finished someday, finished") and on
// the junction itself, and a junction can be tapped to reveal the name visually
// for anyone who wants it. Hidden is not the same as absent.
//
// The SOURCE OF TRUTH is unchanged: branches come from `LudeckStore.branches` in
// the user's order, membership from `placements`. A drop calls `onMove`, which
// the screen routes to the store -- this widget never writes.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../services/cover_art_cache.dart';
import '../tokens.dart';
import 'game_node.dart';

/// A game being dragged, and where it came from.
///
/// Carries the source branch so a drop can be a MOVE rather than a copy: without
/// it, dropping onto a branch would add a placement and leave the old one, and
/// the game would hang on two branches from one gesture.
class GameDrag {
  const GameDrag({required this.item, required this.fromBranchId});

  final TreeItem item;

  /// Null when the game was unplaced (dragged from the soil tray).
  final int? fromBranchId;
}

class BranchingTreeView extends StatefulWidget {
  const BranchingTreeView({
    super.key,
    required this.items,
    required this.onSelect,
    required this.onHold,
    required this.topInset,
    required this.bottomInset,
    this.branches = const [],
    this.placements = const {},
    this.onMove,
    this.coverCache,
    this.onCoverFound,
    this.animateArrivals = true,
  });

  final List<TreeItem> items;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;

  final List<Branch> branches;
  final Map<int, List<int>> placements;

  /// Called when a game is dropped onto a different branch.
  ///
  /// `toBranchId` null means it was dropped into the soil -- taken off every
  /// branch rather than deleted, which is an ordinary state in this model.
  final void Function(GameDrag drag, int? toBranchId)? onMove;

  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  /// False in layout tests, so a node is at final size on the first pump.
  final bool animateArrivals;

  final double topInset;
  final double bottomInset;

  @override
  State<BranchingTreeView> createState() => _BranchingTreeViewState();
}

class _BranchingTreeViewState extends State<BranchingTreeView> {
  /// Ids present at the last build. Null only before the first, which is what
  /// stops the whole existing collection animating on app open.
  Set<int>? _seen;
  Set<int> _arriving = const {};

  /// True while a drag is in flight, so every branch can show a drop target.
  /// Without it the user has to guess where a game may legally go.
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _seen = {for (final i in widget.items) i.game.igdbId};
  }

  @override
  void didUpdateWidget(BranchingTreeView old) {
    super.didUpdateWidget(old);
    final current = {for (final i in widget.items) i.game.igdbId};
    _arriving = widget.animateArrivals
        ? current.difference(_seen ?? const <int>{})
        : const <int>{};
    _seen = current;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return _Empty(topInset: widget.topInset);

    final byId = {for (final i in widget.items) i.game.igdbId: i};
    final placed = <int>{};
    final rows = <Widget>[];

    for (var i = 0; i < widget.branches.length; i++) {
      final branch = widget.branches[i];
      final ids = widget.placements[branch.id] ?? const <int>[];
      final games = <TreeItem>[];
      for (final id in ids) {
        final item = byId[id];
        // A placement can name a shelved game. Skipping keeps the branch's
        // announced count equal to the cards actually on it.
        if (item == null) continue;
        games.add(item);
        placed.add(id);
      }

      rows.add(_BranchRow(
        branch: branch,
        games: games,
        // Alternating sides is what makes it a tree rather than a list with an
        // indent. Derived from the index, so reordering branches reshapes the
        // tree rather than leaving a gap on one side.
        side: i.isEven ? BranchSide.right : BranchSide.left,
        arriving: _arriving,
        dragging: _dragging,
        onSelect: widget.onSelect,
        onHold: widget.onHold,
        onAccept: (drag) => widget.onMove?.call(drag, branch.id),
        onDragStart: () => setState(() => _dragging = true),
        onDragEnd: () => setState(() => _dragging = false),
        coverCache: widget.coverCache,
        onCoverFound: widget.onCoverFound,
      ));
    }

    final unplaced =
        widget.items.where((i) => !placed.contains(i.game.igdbId)).toList();

    return SingleChildScrollView(
      key: const Key('tree-scroll'),
      padding: EdgeInsets.only(
          top: widget.topInset, bottom: widget.bottomInset),
      child: Column(
        children: [
          // Branches first, growing upward visually by being listed top-down --
          // this scroll is NOT reversed. The reversed roadmap made every
          // Y-ordering assertion invert and the drag gestures read backwards,
          // and a tree does not need it: the trunk is simply vertical.
          ...rows,

          // The soil: games on no branch. A real state, not an error -- it is
          // where a freshly shared game waits to be filed.
          if (unplaced.isNotEmpty)
            _SoilTray(
              games: unplaced,
              arriving: _arriving,
              dragging: _dragging,
              onSelect: widget.onSelect,
              onHold: widget.onHold,
              onAccept: (drag) => widget.onMove?.call(drag, null),
              onDragStart: () => setState(() => _dragging = true),
              onDragEnd: () => setState(() => _dragging = false),
              coverCache: widget.coverCache,
              onCoverFound: widget.onCoverFound,
            ),
        ],
      ),
    );
  }
}

enum BranchSide { left, right }

/// One branch: a junction on the spine, and its games running outward.
class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.games,
    required this.side,
    required this.arriving,
    required this.dragging,
    required this.onSelect,
    required this.onHold,
    required this.onAccept,
    required this.onDragStart,
    required this.onDragEnd,
    this.coverCache,
    this.onCoverFound,
  });

  final Branch branch;
  final List<TreeItem> games;
  final BranchSide side;
  final Set<int> arriving;
  final bool dragging;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;
  final ValueChanged<GameDrag> onAccept;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    // Cards are larger than the roadmap's 64px. That was a real defect: at 64px
    // on a phone the cover art was decorative rather than identifiable, and the
    // caption did all the work. The horizontal axis pays for this.
    const cardWidth = 96.0;

    final limb = DragTarget<GameDrag>(
      onWillAcceptWithDetails: (details) =>
          // Refuse a drop onto the branch the game already hangs on: it would be
          // a no-op write and a misleading "moved" flash.
          details.data.fromBranchId != branch.id,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return _Limb(
          side: side,
          // Visible only while a drag is in flight. A permanent dashed outline on
          // every branch would be chrome the user reads once and then ignores.
          highlighted: hovering,
          receptive: dragging,
          child: games.isEmpty
              ? _EmptyLimb(receptive: dragging, name: branch.name, side: side)
              : _LimbContent(
                  games: games,
                  side: side,
                  branchName: branch.name,
                  cardWidth: cardWidth,
                  arriving: arriving,
                  branchId: branch.id,
                  onSelect: onSelect,
                  onHold: onHold,
                  onDragStart: onDragStart,
                  onDragEnd: onDragEnd,
                  coverCache: coverCache,
                  onCoverFound: onCoverFound,
                ),
        );
      },
    );

    final junction = _Junction(
      branch: branch,
      count: games.length,
    );

    // The trunk runs down the MIDDLE, with limbs going outward on both sides.
    //
    // The first version put the spine as the row's first child, which pinned the
    // trunk to the left edge -- so every branch ran rightward from a left-hand
    // spine and "left and right" was not expressible at all. The centre column
    // is fixed-width and the two halves are Expanded, so the trunk stays on the
    // screen's centre line whatever a limb contains.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: side == BranchSide.left
                // A left limb is aligned to its RIGHT edge so it grows away from
                // the trunk rather than floating at the screen edge.
                ? Align(alignment: Alignment.centerRight, child: limb)
                : const SizedBox.shrink(),
          ),
          // Spine and junction share the centre column: the junction has to sit
          // ON the trunk, not beside it.
          SizedBox(
            width: Tokens.space.xl,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(child: Center(child: _spineLine(games))),
                junction,
              ],
            ),
          ),
          Expanded(
            child: side == BranchSide.right
                ? Align(alignment: Alignment.centerLeft, child: limb)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// The trunk segment behind this row, full height so consecutive rows join
  /// into one continuous line -- the roadmap's trail broke at every boundary
  /// because each stretch painted its own path.
  Widget _spineLine(List<TreeItem> games) => Container(
        width: 4,
        height: double.infinity,
        decoration: BoxDecoration(
          color: games.isNotEmpty
              ? Tokens.cosmos.trail
              : Tokens.cosmos.trailDim,
          borderRadius: BorderRadius.circular(Tokens.radius.pill),
        ),
      );
}

/// The node on the spine where a branch attaches.
///
/// Count only. The NAME lives on the limb, where there is room for it -- it used
/// to be revealed here on tap, inside the 32pt-wide centre column, which rendered
/// "Finished someday" as "Finis hed...". A narrow column is the wrong place for a
/// name, and tap-to-reveal was the wrong answer to "keep it seamless": it made
/// every branch anonymous until poked.
class _Junction extends StatelessWidget {
  const _Junction({
    required this.branch,
    required this.count,
  });

  final Branch branch;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Not a button any more -- nothing to tap, because the name is on screen.
      label: count == 1
          ? '${branch.name} branch, 1 game'
          : '${branch.name} branch, $count games',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: Tokens.space.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Tokens.cosmos.panelDeep,
                border: Border.all(
                  color: count > 0
                      ? Tokens.palette.accent
                      : Tokens.cosmos.panelEdge,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 9,
                  color: Tokens.palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The horizontal limb a branch's games sit on.
class _Limb extends StatelessWidget {
  const _Limb({
    required this.side,
    required this.highlighted,
    required this.receptive,
    required this.child,
  });

  final BranchSide side;
  final bool highlighted;

  /// A drag is in flight somewhere, so this limb may be a destination.
  final bool receptive;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radius.panel),
        color: highlighted ? Tokens.cosmos.panel : null,
        border: highlighted
            ? Border.all(color: Tokens.palette.accent)
            : receptive
                ? Border.all(color: Tokens.cosmos.panelEdge)
                : null,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: Tokens.space.xs),
        child: child,
      ),
    );
  }
}

/// A branch's NAME plus its games.
///
/// The name is pinned at the trunk end and sits OUTSIDE the horizontal scroller,
/// so it stays on screen while the games scroll past it. Putting it inside the
/// scroller would let a branch scroll until it was anonymous.
class _LimbContent extends StatelessWidget {
  const _LimbContent({
    required this.games,
    required this.side,
    required this.branchName,
    required this.branchId,
    required this.cardWidth,
    required this.arriving,
    required this.onSelect,
    required this.onHold,
    required this.onDragStart,
    required this.onDragEnd,
    this.coverCache,
    this.onCoverFound,
  });

  final List<TreeItem> games;
  final BranchSide side;
  final String branchName;
  final int branchId;
  final double cardWidth;
  final Set<int> arriving;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    final scroller = SingleChildScrollView(
      key: Key('branch-games-$branchId'),
      scrollDirection: Axis.horizontal,
      // A left branch fills from the trunk outward, so its content starts at the
      // right edge; without this a short left branch floats away from its own
      // junction with a gap in between.
      reverse: side == BranchSide.left,
      child: Row(
        children: [
          for (final game in games)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Tokens.space.xxs),
              child: _DraggableGame(
                item: game,
                fromBranchId: branchId,
                branchName: branchName,
                cardWidth: cardWidth,
                animateIn: arriving.contains(game.game.igdbId),
                onSelect: onSelect,
                onHold: onHold,
                onDragStart: onDragStart,
                onDragEnd: onDragEnd,
                coverCache: coverCache,
                onCoverFound: onCoverFound,
              ),
            ),
        ],
      ),
    );

    final label = _BranchName(name: branchName, side: side);

    return Row(
      // Name nearest the trunk on both sides, so it always reads as naming THIS
      // bough rather than the one across the trunk from it.
      children: side == BranchSide.right
          ? [label, Expanded(child: scroller)]
          : [Expanded(child: scroller), label],
    );
  }
}

/// A branch's name, on the limb.
class _BranchName extends StatelessWidget {
  const _BranchName({required this.name, required this.side});

  final String name;
  final BranchSide side;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: Tokens.space.xs),
        child: ConstrainedBox(
          // A real width budget, unlike the 72pt box in the trunk that broke
          // "Finished someday" into "Finis hed...". Long names ellipsize on ONE
          // line rather than wrapping mid-word.
          constraints: const BoxConstraints(maxWidth: 104),
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            textAlign:
                side == BranchSide.right ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: Tokens.type.caption,
              color: Tokens.palette.text,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );
}

/// A game that can be picked up by press-and-hold and dropped on a branch.
///
/// `LongPressDraggable`, not `Draggable`: the limbs scroll horizontally, and an
/// immediate drag would steal every pan gesture so a branch could not be
/// navigated at all. Press-and-hold is also what the user asked for, and it is
/// the conventional "pick this up" on touch.
class _DraggableGame extends StatelessWidget {
  const _DraggableGame({
    required this.item,
    required this.fromBranchId,
    required this.branchName,
    required this.cardWidth,
    required this.animateIn,
    required this.onSelect,
    required this.onHold,
    required this.onDragStart,
    required this.onDragEnd,
    this.coverCache,
    this.onCoverFound,
  });

  final TreeItem item;
  final int? fromBranchId;
  final String? branchName;
  final double cardWidth;
  final bool animateIn;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    final node = GameNode(
      item: item,
      cardWidth: cardWidth,
      branchName: branchName,
      animateIn: animateIn,
      // TAP opens the game's status sheet, and long-press is deliberately NOT
      // handled here: the drag recognizer owns it. An InkWell long-press inside a
      // LongPressDraggable sits deeper in the tree, wins the gesture arena, and
      // the drag then never starts at all -- so "press and hold to move" and
      // "press and hold for status" cannot both exist. Moving between branches is
      // the gesture the user asked for, so status moved to tap.
      onTap: () => onHold(item),
      coverCache: coverCache,
      onCoverFound: onCoverFound,
    );

    return LongPressDraggable<GameDrag>(
      data: GameDrag(item: item, fromBranchId: fromBranchId),
      onDragStarted: onDragStart,
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (velocity, offset) => onDragEnd(),
      // What follows the finger. Deliberately the card WITHOUT its title: the
      // thing being moved is the game, and a floating caption reads as a label
      // that has come loose.
      feedback: Opacity(
        opacity: 0.85,
        child: GameNode(
          item: item,
          cardWidth: cardWidth,
          showTitle: false,
          onTap: () {},
          onLongPress: () {},
        ),
      ),
      // What stays behind: a dimmed gap, so the branch does not reflow while the
      // user is still deciding where to put it.
      childWhenDragging: Opacity(opacity: 0.25, child: node),
      child: node,
    );
  }
}

/// A branch with nothing on it.
class _EmptyLimb extends StatelessWidget {
  const _EmptyLimb({
    required this.receptive,
    required this.name,
    required this.side,
  });

  final bool receptive;
  final String name;
  final BranchSide side;

  @override
  Widget build(BuildContext context) {
    final label = _BranchName(name: name, side: side);
    final hint = Padding(
      padding: EdgeInsets.symmetric(
          horizontal: Tokens.space.sm, vertical: Tokens.space.md),
      child: Text(
        // Says what it IS, and during a drag what it can DO. Never what the user
        // has failed to do -- DECISIONS.md rules out empty-state guilt.
        receptive ? 'Drop here' : 'Nothing on it yet',
        style: TextStyle(
          fontSize: Tokens.type.caption,
          color: Tokens.palette.textDim,
        ),
      ),
    );

    return Row(
      // Name nearest the trunk, matching a populated limb, so an empty branch is
      // identifiable rather than an anonymous "Empty branch" floating in space.
      children: side == BranchSide.right ? [label, hint] : [hint, label],
    );
  }
}

/// Games on no branch, at the base of the trunk.
class _SoilTray extends StatelessWidget {
  const _SoilTray({
    required this.games,
    required this.arriving,
    required this.dragging,
    required this.onSelect,
    required this.onHold,
    required this.onAccept,
    required this.onDragStart,
    required this.onDragEnd,
    this.coverCache,
    this.onCoverFound,
  });

  final List<TreeItem> games;
  final Set<int> arriving;
  final bool dragging;
  final ValueChanged<TreeItem> onSelect;
  final ValueChanged<TreeItem> onHold;
  final ValueChanged<GameDrag> onAccept;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final CoverArtCache? coverCache;
  final void Function(int igdbId, String coverUrl)? onCoverFound;

  @override
  Widget build(BuildContext context) {
    const cardWidth = 96.0;

    return DragTarget<GameDrag>(
      // Only meaningful for a game that is currently ON a branch: dropping an
      // already-unplaced game into the soil is a no-op.
      onWillAcceptWithDetails: (details) => details.data.fromBranchId != null,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          margin: EdgeInsets.only(top: Tokens.space.lg),
          padding: EdgeInsets.symmetric(vertical: Tokens.space.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.radius.panel),
            color: hovering ? Tokens.cosmos.panel : null,
            border: hovering
                ? Border.all(color: Tokens.palette.accent)
                : dragging
                    ? Border.all(color: Tokens.cosmos.panelEdge)
                    : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(
                    left: Tokens.space.md, bottom: Tokens.space.xs),
                child: Semantics(
                  header: true,
                  label: games.length == 1
                      ? 'In the soil, not on a branch, 1 game'
                      : 'In the soil, not on a branch, ${games.length} games',
                  excludeSemantics: true,
                  child: Text(
                    hovering || dragging
                        ? 'DROP TO TAKE OFF ITS BRANCH'
                        : 'IN THE SOIL  ${games.length}',
                    style: TextStyle(
                      fontSize: Tokens.type.caption,
                      color: Tokens.palette.textDim,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                key: const Key('soil-games'),
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: Tokens.space.sm),
                child: Row(
                  children: [
                    for (final game in games)
                      Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: Tokens.space.xxs),
                        child: _DraggableGame(
                          item: game,
                          fromBranchId: null,
                          branchName: null,
                          cardWidth: cardWidth,
                          animateIn: arriving.contains(game.game.igdbId),
                          onSelect: onSelect,
                          onHold: onHold,
                          onDragStart: onDragStart,
                          onDragEnd: onDragEnd,
                          coverCache: coverCache,
                          onCoverFound: onCoverFound,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Nothing on the tree at all.
class _Empty extends StatelessWidget {
  const _Empty({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            Tokens.space.md, topInset + Tokens.space.xl, Tokens.space.md, 0),
        child: Column(
          children: [
            Text(
              'The tree starts with one game.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Tokens.type.title,
                color: Tokens.palette.text,
              ),
            ),
            SizedBox(height: Tokens.space.xs),
            Text(
              'Share a link to Ludeck, or add one by name.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Tokens.type.body,
                color: Tokens.palette.textDim,
              ),
            ),
          ],
        ),
      );
}
