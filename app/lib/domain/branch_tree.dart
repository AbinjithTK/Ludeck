import '../data/models.dart';

/// The user's branches as a tree, built from the flat rows the repository
/// returns.
///
/// Pure and synchronous so every view (the canopy, the list fallback, the
/// picker, the share card) asks the same questions of the same structure
/// instead of each re-deriving parents from ids.
///
/// Defensive about bad data rather than trusting it: a row whose parent does
/// not exist, or a loop the repository should have refused, is treated as
/// growing from the trunk. Hiding a branch because its parent chain is broken
/// would look to the user exactly like losing it.
class BranchTree {
  BranchTree(List<Branch> branches, [Map<int, List<int>> placements = const {}])
      : _byId = {for (final b in branches) b.id: b},
        _placements = placements {
    for (final b in branches) {
      final parent = _safeParent(b);
      (_kids[parent] ??= <Branch>[]).add(b);
    }
    for (final list in _kids.values) {
      list.sort((a, b) => a.sortOrder != b.sortOrder
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.id.compareTo(b.id));
    }
  }

  final Map<int, Branch> _byId;
  final Map<int, List<int>> _placements;
  final Map<int?, List<Branch>> _kids = {};

  /// The parent to file [b] under, or null when its chain is missing or loops.
  int? _safeParent(Branch b) {
    final parent = b.parentId;
    if (parent == null || !_byId.containsKey(parent)) return null;
    final seen = <int>{b.id};
    int? cur = parent;
    while (cur != null) {
      if (!seen.add(cur)) return null; // loop
      final next = _byId[cur];
      if (next == null) return null;
      cur = next.parentId != null && _byId.containsKey(next.parentId)
          ? next.parentId
          : null;
    }
    return parent;
  }

  Branch? operator [](int id) => _byId[id];

  bool get isEmpty => _byId.isEmpty;

  /// Branches growing straight from the trunk, in order.
  List<Branch> get roots => childrenOf(null);

  /// [id]'s sub-branches in order; `null` asks for the roots.
  List<Branch> childrenOf(int? id) => List.unmodifiable(_kids[id] ?? const []);

  /// Root first, [id] last. The breadcrumb of a zoomed-in canopy.
  List<Branch> pathTo(int id) {
    final out = <Branch>[];
    Branch? cur = _byId[id];
    while (cur != null) {
      out.insert(0, cur);
      final parent = _safeParent(cur);
      cur = parent == null ? null : _byId[parent];
    }
    return out;
  }

  /// 0 for a root.
  int depthOf(int id) => pathTo(id).length - 1;

  /// Every branch below [id], depth first, not including [id].
  List<Branch> descendantsOf(int id) {
    final out = <Branch>[];
    void walk(int at) {
      for (final c in _kids[at] ?? const <Branch>[]) {
        out.add(c);
        walk(c.id);
      }
    }

    walk(id);
    return out;
  }

  /// Games hanging directly on [id], in their placement order.
  List<int> gamesOn(int id) => List.unmodifiable(_placements[id] ?? const []);

  /// Games on [id] or anywhere below it, each once, nearest first.
  ///
  /// This is what "pick from this branch" draws from and what a branch's count
  /// shows: a game on two sub-branches of "Couch co-op" is still one game in
  /// "Couch co-op".
  List<int> gamesUnder(int id) {
    final seen = <int>{};
    final out = <int>[];
    for (final b in [_byId[id], ...descendantsOf(id)]) {
      if (b == null) continue;
      for (final g in _placements[b.id] ?? const <int>[]) {
        if (seen.add(g)) out.add(g);
      }
    }
    return out;
  }

  /// Whether moving [id] under [newParentId] is allowed (no self or descendant).
  bool canMove(int id, int? newParentId) =>
      newParentId == null ||
      (newParentId != id && !descendantsOf(id).any((b) => b.id == newParentId));
}
