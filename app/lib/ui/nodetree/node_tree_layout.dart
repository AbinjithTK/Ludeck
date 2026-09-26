// The home tree as a clean indented NODE OUTLINE, not an illustration.
//
// Replaces the painted canopy (trunk/leaves) with the standard, legible shape
// for a hierarchy: branch nodes as rounded panels, game nodes as child rows,
// depth shown by indentation, connected by soft elbow connectors. No bark, no
// foliage -- this file and its view never touch `Tokens.canopy`.
//
// This module is PURE and synchronous: it flattens a `BranchTree` into the
// ordered list of rows that are currently visible (a collapsed branch hides its
// descendants) plus the geometry a painter needs to draw the connectors. It has
// no Flutter-widget dependency beyond `Offset`/`Size`-free primitives, so it is
// unit-testable without a rendering stack -- the lesson from the canopy work is
// that layout must be checkable without pixels.

import '../../data/models.dart';
import '../../domain/branch_tree.dart';

/// What one flattened row represents.
enum NodeKind { branch, game }

/// One visible row in the outline, in top-to-bottom order.
///
/// A row is either a branch (expandable, may carry sub-branches and games) or a
/// game leaf. `depth` is how far it is indented (0 = a root branch). `parentId`
/// is the branch it hangs under, or null at the trunk.
class NodeRow {
  const NodeRow({
    required this.kind,
    required this.depth,
    this.branch,
    this.gameId,
    this.parentId,
    this.hasChildren = false,
    this.collapsed = false,
    this.childCount = 0,
    this.isLastChild = false,
  });

  final NodeKind kind;
  final int depth;

  /// Set when [kind] is [NodeKind.branch].
  final Branch? branch;

  /// Set when [kind] is [NodeKind.game].
  final int? gameId;

  /// The branch this row hangs under (null = trunk-level root branch).
  final int? parentId;

  /// A branch that has sub-branches or games under it (so it can expand).
  final bool hasChildren;

  /// A branch the user has folded. Its descendants are absent from the list.
  final bool collapsed;

  /// Count of games under this branch and everything below it (each once).
  final int childCount;

  /// The last row among its siblings -- the connector's vertical rail stops here.
  final bool isLastChild;

  bool get isBranch => kind == NodeKind.branch;
  bool get isGame => kind == NodeKind.game;
}

/// Flatten [tree] into the visible rows, depth-first, honouring collapsed
/// branches. Games hang directly under their branch, after that branch's
/// sub-branches (so structure reads before contents).
///
/// [collapsedIds] is the set of branch ids the user has folded; a folded branch
/// still appears, but its children do not. This is derived from each branch's
/// own `collapsed` field by the view, passed in so the function stays pure and
/// a test can drive any fold state.
List<NodeRow> flattenTree(
  BranchTree tree, {
  Set<int> collapsedIds = const {},
}) {
  final rows = <NodeRow>[];

  void walk(int? parentId, int depth) {
    final branches = tree.childrenOf(parentId);
    final games = parentId == null ? const <int>[] : tree.gamesOn(parentId);

    for (var i = 0; i < branches.length; i++) {
      final b = branches[i];
      final subBranches = tree.childrenOf(b.id);
      final ownGames = tree.gamesOn(b.id);
      final hasChildren = subBranches.isNotEmpty || ownGames.isNotEmpty;
      final collapsed = collapsedIds.contains(b.id);
      final lastSibling = i == branches.length - 1 && games.isEmpty;

      rows.add(NodeRow(
        kind: NodeKind.branch,
        depth: depth,
        branch: b,
        parentId: parentId,
        hasChildren: hasChildren,
        collapsed: collapsed,
        childCount: tree.gamesUnder(b.id).length,
        isLastChild: lastSibling,
      ));

      if (!collapsed) walk(b.id, depth + 1);
    }

    // Games hanging directly on this branch (never at the synthetic trunk).
    for (var i = 0; i < games.length; i++) {
      rows.add(NodeRow(
        kind: NodeKind.game,
        depth: depth,
        gameId: games[i],
        parentId: parentId,
        isLastChild: i == games.length - 1,
      ));
    }
  }

  walk(null, 0);
  return rows;
}

/// The games shown when a branch is focused for "what should I play?" -- every
/// game under [branchId], each once. Trunk-level (null) pools every game that
/// sits on any branch. Kept here so the view and the picker agree.
List<int> poolFor(BranchTree tree, int? branchId) {
  if (branchId != null) return tree.gamesUnder(branchId);
  final seen = <int>{};
  final out = <int>[];
  for (final b in tree.roots) {
    for (final g in tree.gamesUnder(b.id)) {
      if (seen.add(g)) out.add(g);
    }
  }
  return out;
}

/// Resolve a flattened row list to concrete [TreeItem]s by igdbId, dropping any
/// game the store no longer has. Convenience for the view.
List<TreeItem> gamesToItems(List<int> ids, Map<int, TreeItem> byId) =>
    [for (final id in ids) if (byId[id] != null) byId[id]!];
