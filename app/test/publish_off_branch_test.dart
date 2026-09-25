// Regression: publishing a tree that has no branches must not publish nothing.
//
// The bug this pins down shipped and was caught on a real device. PublishScreen
// built its payload as `for (final b in store.branches) ...` only, so a user
// with zero branches -- every new user -- sent an EMPTY games list while the
// app showed "Your tree is live", the share card said "0 harvested", and a
// visitor saw "Nothing on this tree yet."
//
// Every database call goes through `tester.runAsync`, per check.ps1 rule 8:
// sqflite does real file I/O that never completes under testWidgets' fake
// clock, and mounting a DB-backed screen outside runAsync holds the database
// lock until the run hangs.

import 'package:flutter/material.dart' hide Form;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/publish/publish_screen.dart';

TreeItem _owned(int id, String title, {Progress progress = Progress.untouched}) =>
    TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: Ownership.owned,
        progress: progress,
      ),
      copies: const [],
    );

TreeItem _seed(int id, String title) => TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        // A seed is spotted, not owned -- toPublished drops it.
        ownership: Ownership.spotted,
        progress: Progress.untouched,
        recommendedBy: 'Priya',
      ),
      copies: const [],
    );

void main() {
  late Repository repo;
  late LudeckStore store;

  setUp(() async {
    repo = await Repository.openInMemory();
    FakeSocialBackend.resetShared();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() async => repo.close());

  group('off-branch publishing', () {
    testWidgets('a collection with no branches still publishes its games',
        (tester) async {
      await tester.runAsync(() async {
        store = LudeckStore(repo);
        await store.load();
        await store.upsert(_owned(1, 'Hades', progress: Progress.finished));
        await store.upsert(_owned(2, 'Celeste'));
      });

      expect(store.branches, isEmpty,
          reason: 'the whole point of this case is zero branches');

      final games = <PublishedGame>[
        for (final b in store.branches)
          ...toPublishedForBranch(store.items ?? const [], store, b),
        ...toPublishedOffBranch(store.items ?? const [], store),
      ];

      expect(games.map((g) => g.title), containsAll(['Hades', 'Celeste']),
          reason: 'owned games publish whether or not a branch holds them');
      expect(games.every((g) => g.branchName == trunkGroupName), isTrue);
    });

    testWidgets('placed and unplaced games publish once each, not twice',
        (tester) async {
      late int branchId;
      await tester.runAsync(() async {
        store = LudeckStore(repo);
        await store.load();
        await store.upsert(_owned(1, 'Hades'));
        await store.upsert(_owned(2, 'Celeste'));
        await store.createBranch('Cozy');
        branchId = store.branches.single.id;
        await store.place(1, branchId);
      });

      final games = <PublishedGame>[
        for (final b in store.branches)
          ...toPublishedForBranch(store.items ?? const [], store, b),
        ...toPublishedOffBranch(store.items ?? const [], store),
      ];

      // Hades is on Cozy, so it publishes under Cozy and must NOT also appear
      // on the trunk; Celeste is on no branch, so the trunk is where it lands.
      final byTitle = {for (final g in games) g.title: g.branchName};
      expect(byTitle, {'Hades': 'Cozy', 'Celeste': trunkGroupName});
      expect(games.where((g) => g.title == 'Hades'), hasLength(1),
          reason: 'a placed game must not be duplicated onto the trunk');
    });

    testWidgets('seeds are still never published', (tester) async {
      await tester.runAsync(() async {
        store = LudeckStore(repo);
        await store.load();
        await store.upsert(_owned(1, 'Hades'));
        await store.upsert(_seed(99, 'Someone elses pick'));
      });

      final games = toPublishedOffBranch(store.items ?? const [], store);

      expect(games.map((g) => g.title), ['Hades'],
          reason: 'a spotted game is not yours to publish, branch or no branch');
    });

    testWidgets('the whole screen publishes a non-empty tree with no branches',
        (tester) async {
      final backend = FakeSocialBackend(configured: true);

      await tester.runAsync(() async {
        store = LudeckStore(repo);
        await tester.pumpWidget(MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<SocialBackend>.value(value: backend),
              ChangeNotifierProvider<LudeckStore>.value(value: store),
            ],
            child: const PublishScreen(),
          ),
        ));
        await store.load();
        await store.upsert(_owned(1, 'Hades', progress: Progress.finished));
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('Public'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Save and share'));
      });
      await tester.pumpAndSettle();

      final handle = backend.currentProfile!.handle;
      late PublishedTree published;
      await tester.runAsync(() async {
        published = await backend.treeByHandle(handle);
      });

      expect(published.games, isNotEmpty,
          reason: 'this is the exact bug: a live tree that contains nothing');
      expect(published.games.single.title, 'Hades');
      expect(published.harvestedCount, 1,
          reason: 'the share card read "0 harvested" for a harvested game');
    });
  });
}
