// Stage 4: editable roadmap order. These lock persistence (a reorder survives a
// reload), the pure ordering logic (ordered games first, unordered kept in
// their default order), and the cascade (deleting a game removes its order row).
// Plain test() -- no widget, no FakeAsync (see CONSTRAINTS.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/roadmap/roadmap_layout.dart';

void main() {
  group('orderGames (pure)', () {
    test('orders games with a position first, by position', () {
      final result = orderGames([1, 2, 3], {1: 2, 2: 0, 3: 1});
      expect(result, [2, 3, 1]);
    });

    test('appends unordered games in their default order', () {
      // 2 has a position; 1 and 3 do not, so they follow in input order.
      final result = orderGames([1, 2, 3], {2: 0});
      expect(result, [2, 1, 3]);
    });

    test('empty order leaves the default order untouched', () {
      expect(orderGames([5, 4, 6], const {}), [5, 4, 6]);
    });
  });

  group('roadmap order persistence', () {
    late Repository repo;
    late LudeckStore store;

    setUp(() async {
      repo = await Repository.openInMemory();
      store = LudeckStore(repo);
    });

    tearDown(() async {
      store.dispose();
      await repo.close();
    });

    TreeItem game(int id, String title) => TreeItem(
          game: Game(igdbId: id, title: title),
          entry: Entry(
              igdbId: id, ownership: Ownership.owned, progress: Progress.untouched),
          copies: const [],
        );

    test('a reorder is persisted and survives a reload', () async {
      await store.upsert(game(1, 'A'));
      await store.upsert(game(2, 'B'));
      await store.upsert(game(3, 'C'));

      await store.reorderRoadmap([3, 1, 2]);
      expect(store.roadmapOrder, {3: 0, 1: 1, 2: 2});

      // A fresh store on the same repo must read the same order back.
      final store2 = LudeckStore(repo);
      addTearDown(store2.dispose);
      await store2.load();
      expect(store2.roadmapOrder, {3: 0, 1: 1, 2: 2},
          reason: 'the order was not persisted');
    });

    test('deleting a game removes its order row (cascade)', () async {
      await store.upsert(game(1, 'A'));
      await store.upsert(game(2, 'B'));
      await store.reorderRoadmap([1, 2]);

      await repo.purgeGame(1);
      final order = await repo.roadmapOrder();
      expect(order.containsKey(1), isFalse,
          reason: 'the cascade should drop the order row with the game');
      expect(order.containsKey(2), isTrue);
    });
  });
}
