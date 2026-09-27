import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/branch_tree.dart';
import 'package:ludeck/ui/orchard/orchard_view.dart';
import 'package:ludeck/ui/orchard/rive_tree.dart';

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

  group('orchard camera', () {
    // A Pixel 8 portrait page: 411x914, soil line 204pt above the bottom.
    const box = Size(411, 914);
    const groundY = 914.0 - 204;

    test('the soil line lands exactly on groundY at every zoom', () {
      for (final z in [1.0, 1.15, 1.3]) {
        final r = treeFrame(box, groundY, z);
        final s = r.width / kTreeArtW;
        expect(r.top + kTreeBaseY * s, moreOrLessEquals(groundY, epsilon: 0.01));
        expect(r.center.dx, moreOrLessEquals(box.width / 2, epsilon: 0.01));
      }
    });

    test('a full tree never reaches into the title band', () {
      // Width-bound phone, and a short landscape box where height binds.
      for (final b in [box, const Size(914, 411)]) {
        final g = b.height - 120;
        final r = treeFrame(b, g, treeZoom(kTreeSlots));
        final canopyTop = r.top + kCanopyTop * (r.width / kTreeArtW);
        expect(canopyTop, greaterThanOrEqualTo(140 - 0.01));
      }
    });

    test('zoom only ever eases back as a tree fills, never closer', () {
      var last = double.infinity;
      for (var g = 0; g <= kTreeSlots; g++) {
        final z = treeZoom(g);
        expect(z, lessThanOrEqualTo(last));
        last = z;
      }
      expect(treeZoom(0), 1.3);
      expect(treeZoom(4), 1.0);
      expect(treeZoom(kTreeSlots), 1.0);
    });

    test('on screen the tree still only grows as the camera eases back', () {
      // Sapling to full canopy spans artboard 501 -> 185 (measured on device).
      double onScreen(int g) {
        final top = 501 - (501 - kCanopyTop) * (g / kTreeSlots);
        return (kTreeBaseY - top) * treeZoom(g);
      }
      for (var g = 1; g <= kTreeSlots; g++) {
        expect(onScreen(g), greaterThan(onScreen(g - 1)),
            reason: 'the tree must never look smaller after a game is added '
                '(DECISIONS.md)');
      }
    });
  });
}
