// End to end for the share-to-library feature: text arrives, the sheet opens,
// the user confirms, and the game plus its source are on disk.
//
// This is the test that proves stages 2, 6 and 7 join up. The unit tests either
// side of it can both pass while the wiring between them is wrong.
//
// Every database call goes through `tester.runAsync`. testWidgets runs its body
// inside a FakeAsync zone, and sqflite does real file I/O that never completes
// under fake time. The repository unit tests do not need this because they use
// plain `test()`, which has no fake clock. Getting this wrong looks exactly like
// a feature that does not work.
//
// NOTE (2026-09-24): the home screen now renders `CollectionView`, a plain
// Flutter list, not the Rive tree. The tree loaded a native asset absent from a
// Windows test run, and the drain apparatus that used to work around it could
// spin waiting for an async failure that arrived through FlutterError rather
// than takeException. With no Rive in this screen that whole workaround is gone
// and the suite no longer wedges here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/main.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/share_intake.dart';
import 'package:ludeck/state/ludeck_store.dart';

void main() {
  late Repository repo;

  setUp(() async {
    repo = await Repository.openInMemory();
  });

  tearDown(() async => repo.close());

  /// Lets real async work finish, then settles the widget tree.
  ///
  /// 40ms rather than 20. A store write now re-reads the collection, the
  /// branches and the placements, so a fixed delay tuned to a single query is
  /// too short and the failure looks exactly like a feature that does not write.
  /// Any fixed delay here is a compromise; this one has headroom.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
  }

  /// Mounts the screen INSIDE `runAsync`, which is not optional.
  ///
  /// `TreeScreen.initState` calls `_load()`, so mounting starts a real sqflite
  /// query. Under fake time that query never completes and it keeps the
  /// database lock, so the next real-async call waits on a lock nothing will
  /// ever release. sqflite says so after ten seconds:
  ///
  ///   Warning database has been locked for 0:00:10.000000
  ///
  /// and then the run hangs rather than failing, because the framework's own
  /// timeout runs on the fake clock while the wait happens in real time. That
  /// is what wedged `flutter test` three times, and the canned message blames
  /// transaction misuse, which was never the cause here.
  Future<void> pumpWithShare(WidgetTester tester, String? shared) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<LudeckStore>(
          create: (_) => LudeckStore(repo)..load(),
          child: TreeScreen(
            intake: FakeShareIntake(shared),
            catalog: FixtureCatalog(),
          ),
        ),
      ));
    });
    await settle(tester);
  }

  /// Taps something that triggers a database write, then waits for it.
  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
    });
    await settle(tester);
  }

  Future<T> read<T>(WidgetTester tester, Future<T> Function() body) async {
    final out = await tester.runAsync(body);
    return out as T;
  }

  testWidgets('shared text becomes a game with its source recorded',
      (tester) async {
    await pumpWithShare(tester, 'you should play Hollow Knight');

    // The sheet opened on its own. That is the whole feature: the user shared
    // from another app and Ludeck already understood it.
    expect(find.text('Add to your collection'), findsOneWidget);
    expect(find.text('Hollow Knight'), findsOneWidget);

    await tapAndSettle(tester, 'Add 1 game');

    final items = await read(tester, () => repo.load());
    expect(items.map((i) => i.game.title), contains('Hollow Knight'));

    final added = items.firstWhere((i) => i.game.title == 'Hollow Knight');

    // A recommendation is not a purchase. The two axes stay independent.
    expect(added.entry.ownership, Ownership.spotted);
    expect(added.entry.progress, Progress.untouched);
    expect(added.isSeed, isTrue);

    final sources =
        await read(tester, () => repo.sourcesFor(added.game.igdbId));
    expect(sources, hasLength(1));
    expect(sources.single.kind, SourceKind.text);
    expect(sources.single.matchMethod, MatchMethod.text);
    expect(sources.single.url, isNull, reason: 'no link was shared');
  });

  testWidgets('a link is recorded on the source row', (tester) async {
    await pumpWithShare(
      tester,
      'https://www.youtube.com/watch?v=abc123 Hollow Knight is incredible',
    );

    await tapAndSettle(tester, 'Add 1 game');

    final items = await read(tester, () => repo.load());
    final added = items.firstWhere((i) => i.game.title == 'Hollow Knight');
    final sources =
        await read(tester, () => repo.sourcesFor(added.game.igdbId));

    expect(sources.single.kind, SourceKind.youtube);
    expect(sources.single.url, contains('abc123'));
  });

  testWidgets('the recommender is stored on the entry', (tester) async {
    await pumpWithShare(tester, 'play Hollow Knight');

    await tester.enterText(find.byType(TextField), 'Priya');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, 'Add 1 game');

    final items = await read(tester, () => repo.load());
    final added = items.firstWhere((i) => i.game.title == 'Hollow Knight');
    expect(added.entry.recommendedBy, 'Priya');
  });

  testWidgets('several games from one message all land', (tester) async {
    await pumpWithShare(tester, 'play Hollow Knight, Hades and Celeste');

    expect(find.text('Add 3 games'), findsOneWidget);
    await tapAndSettle(tester, 'Add 3 games');

    final titles =
        (await read(tester, () => repo.load())).map((i) => i.game.title);
    expect(titles, containsAll(['Hollow Knight', 'Hades', 'Celeste']));
  });

  testWidgets('unticking a game keeps it out of the library', (tester) async {
    await pumpWithShare(tester, 'play Hollow Knight and Hades');

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, 'Add 1 game');

    expect(await read(tester, () => repo.gameCount()), 1);
  });

  testWidgets('no share means no sheet', (tester) async {
    await pumpWithShare(tester, null);

    expect(find.text('Add to your collection'), findsNothing);
    expect(find.text('Nothing recognised'), findsNothing);
    expect(await read(tester, () => repo.gameCount()), 0);
  });

  testWidgets('a share naming nothing writes nothing', (tester) async {
    await pumpWithShare(tester, 'see you at six');

    expect(find.text('Nothing recognised'), findsOneWidget);
    await tapAndSettle(tester, 'Search instead');

    expect(await read(tester, () => repo.gameCount()), 0);
  });

  testWidgets('re-sharing a game already in the library keeps its progress',
      (tester) async {
    // A second share must not reset what the user recorded.
    //
    // The second share goes through a LIFECYCLE RESUME, not a rebuild. That is
    // the production path: MainActivity is singleTop, so a share into a running
    // app lands in onNewIntent and the activity resumes. Re-pumping the widget
    // would reuse the same State and never call initState again, so it would
    // test nothing.
    final intake = FakeShareIntake('play Hades');
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<LudeckStore>(
          create: (_) => LudeckStore(repo)..load(),
          child: TreeScreen(
            intake: intake,
            catalog: FixtureCatalog(),
          ),
        ),
      ));
    });
    await settle(tester);

    await tapAndSettle(tester, 'Add 1 game');

    final id = (await read(tester, () => repo.load()))
        .firstWhere((i) => i.game.title == 'Hades')
        .game
        .igdbId;

    await read(tester, () async {
      await repo.setProgress(id, Progress.playing);
      await repo.setOwnership(id, Ownership.owned);
      // 1 to 5. The repository rejects anything else outright.
      await repo.setRating(id, 5);
    });

    // Share the same game again, the way Android actually delivers it.
    intake.queued = 'play Hades';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(find.text('Add 1 game'), findsOneWidget,
        reason: 'a warm share must reopen the sheet');
    await tapAndSettle(tester, 'Add 1 game');

    final again = (await read(tester, () => repo.load()))
        .firstWhere((i) => i.game.igdbId == id);
    expect(again.entry.progress, Progress.playing);
    expect(again.entry.ownership, Ownership.owned);
    expect(again.entry.rating, 5);

    // But the second share IS recorded: that it came up again is worth keeping.
    expect(await read(tester, () => repo.sourcesFor(id)), hasLength(2));
  });
}
