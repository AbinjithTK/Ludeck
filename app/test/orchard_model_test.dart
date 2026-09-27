import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/branch_tree.dart';
import 'package:ludeck/ui/orchard/orchard_view.dart';

Branch _b(int id, String name, {int? parent, int order = 0}) =>
    (id: id, name: name, sortOrder: order, parentId: parent, collapsed: false);

TreeItem _i(int id) => TreeItem(
      game: Game(igdbId: id, title: 'G$id'),
      entry: Entry(
          igdbId: id,
          ownership: Ownership.owned,
          progress: Progress.values.first),
      copies: const [],
    );

void main() {
  test('trees are the top-level branches, in the user order', () {
    final trees = treesOf([
      _b(3, 'C', order: 2),
      _b(1, 'A', order: 0),
      _b(9, 'nested', parent: 1),
      _b(2, 'B', order: 1),
    ]);
    expect(trees.map((b) => b.name), ['A', 'B', 'C']);
  });

  test('a tree carries the games on its sub-branches, each once, stably', () {
    final branches = [_b(1, 'Tree'), _b(2, 'Sub', parent: 1)];
    final shape = BranchTree(branches, {
      1: [10, 11],
      2: [11, 12], // 11 is on both: counted once
    });
    final byId = {for (final id in [10, 11, 12]) id: _i(id)};
    final games = gamesOnTree(branches.first, shape, byId);
    expect(games.map((g) => g.game.igdbId).toSet(), {10, 11, 12});
    expect(games.length, 3);
    // Stable: the same inputs give the same order (fruit never reshuffles).
    expect(gamesOnTree(branches.first, shape, byId).map((g) => g.game.igdbId),
        games.map((g) => g.game.igdbId));
  });
}
