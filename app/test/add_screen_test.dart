// The add screen: search a catalogue, add a game. "Save" in the Gaming criterion.
//
// The states are the feature, and the one that matters most is the distinction
// between EMPTY and FAILED. "Nothing matched" says the game is not in the
// catalogue; "could not search" says nobody asked. A careless implementation
// renders both as an empty list, and the first is then a lie.
//
// Every database call goes through `tester.runAsync`. testWidgets runs its body
// in a FakeAsync zone and sqflite does real file I/O that never completes under
// fake time, so mounting outside runAsync holds the database lock and the run
// hangs instead of failing. See docs/CONSTRAINTS.md and check.ps1 rule 8.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/add/add_screen.dart';

/// Counts calls, so the debounce can be proved rather than assumed.
class CountingCatalog implements CatalogSource {
  CountingCatalog(this._inner);

  final CatalogSource _inner;
  final List<String> queries = [];

  @override
  Future<List<Game>> search(String query) {
    queries.add(query);
    return _inner.search(query);
  }

  @override
  Future<Game?> byId(int igdbId) => _inner.byId(igdbId);

  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) =>
      _inner.byExternalId(twitchGameId: twitchGameId, steamAppId: steamAppId);
}

/// Always fails, with a chosen reason.
class FailingCatalog implements CatalogSource {
  FailingCatalog(this.failure);

  final CatalogFailure failure;

  @override
  Future<List<Game>> search(String query) async =>
      throw CatalogException(failure);

  @override
  Future<Game?> byId(int igdbId) async => throw CatalogException(failure);

  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) async =>
      throw CatalogException(failure);
}

/// Throws something that is NOT a CatalogException.
class BrokenCatalog implements CatalogSource {
  @override
  Future<List<Game>> search(String query) async => throw StateError('boom');

  @override
  Future<Game?> byId(int igdbId) async => throw StateError('boom');

  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) async =>
      throw StateError('boom');
}

/// Resolves slowly, and in a controllable order.
class SlowCatalog implements CatalogSource {
  SlowCatalog(this._inner, this._delays);

  final CatalogSource _inner;
  final Map<String, Duration> _delays;

  @override
  Future<List<Game>> search(String query) async {
    await Future<void>.delayed(_delays[query] ?? Duration.zero);
    return _inner.search(query);
  }

  @override
  Future<Game?> byId(int igdbId) => _inner.byId(igdbId);

  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) =>
      _inner.byExternalId(twitchGameId: twitchGameId, steamAppId: steamAppId);
}

void main() {
  late Repository repo;
  late LudeckStore store;

  setUp(() async {
    repo = await Repository.openInMemory();
  });

  tearDown(() async => repo.close());

  Future<void> pump(WidgetTester tester, CatalogSource catalog) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      store = LudeckStore(repo);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<LudeckStore>.value(
          value: store,
          child: AddScreen(catalog: catalog),
        ),
      ));
      await store.load();
    });
    await tester.pumpAndSettle();
  }

  /// Types, then lets the debounce fire and the search finish.
  ///
  /// `tester.pump(duration)` rather than a real-time delay, and that distinction
  /// is the whole trick: the debounce Timer is created inside testWidgets'
  /// FakeAsync zone, so it only fires when the FAKE clock advances. A
  /// `runAsync(Future.delayed(...))` advances real time and the timer never fires
  /// at all, which looks exactly like a search that does not work.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('search-field')), text);
    await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  /// Taps something that writes to the database, then waits for it.
  ///
  /// Here a REAL delay is required, because sqflite does real file I/O that the
  /// fake clock cannot advance.
  Future<void> tapAndWrite(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async => tester.tap(finder));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }

  group('the five states', () {
    testWidgets('idle before anything is typed, and it names the source',
        (tester) async {
      await pump(tester, FixtureCatalog());

      expect(find.byKey(const Key('state-idle')), findsOneWidget);
      // Until the proxy is deployed the catalogue is a handful of fixture
      // titles. Letting someone conclude their game does not exist would be
      // worse than saying where the results come from.
      expect(
        find.textContaining('not connected yet'),
        findsOneWidget,
        reason: 'catalogBaseUrl is empty, so the screen must say so',
      );
    });

    testWidgets('results appear for a match', (tester) async {
      await pump(tester, FixtureCatalog());
      await type(tester, 'hollow');

      expect(find.byKey(const Key('search-results')), findsOneWidget);
      expect(find.text('Hollow Knight'), findsOneWidget);
    });

    testWidgets('empty is its own state, and says nothing matched',
        (tester) async {
      await pump(tester, FixtureCatalog());
      await type(tester, 'zzzznotagame');

      expect(find.byKey(const Key('state-empty')), findsOneWidget);
      expect(find.text('Nothing matched.'), findsOneWidget);
      // This is the distinction the whole screen turns on.
      expect(find.byKey(const Key('state-failed')), findsNothing);
    });

    testWidgets('clearing the field returns to idle, not to empty',
        (tester) async {
      await pump(tester, FixtureCatalog());
      await type(tester, 'zzzznotagame');
      expect(find.byKey(const Key('state-empty')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('search-field')), '');
      await tester.pumpAndSettle();

      // Nothing was asked, so nothing can be claimed about what exists.
      expect(find.byKey(const Key('state-idle')), findsOneWidget);
      expect(find.byKey(const Key('state-empty')), findsNothing);
    });
  });

  group('failures are not empty results', () {
    testWidgets('offline says so and offers a retry', (tester) async {
      await pump(tester, FailingCatalog(CatalogFailure.offline));
      await type(tester, 'hollow');

      expect(find.byKey(const Key('state-failed')), findsOneWidget);
      expect(find.text('No connection.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // Critically NOT the empty state, which would say the game does not exist.
      expect(find.byKey(const Key('state-empty')), findsNothing);
    });

    testWidgets('a malformed reply offers no retry, because it would not help',
        (tester) async {
      await pump(tester, FailingCatalog(CatalogFailure.malformed));
      await type(tester, 'hollow');

      expect(find.text('That answer could not be read.'), findsOneWidget);
      // Retrying a broken response just breaks again. A button that cannot help
      // is worse than no button.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a rejection is reported as a rejection', (tester) async {
      await pump(tester, FailingCatalog(CatalogFailure.rejected));
      await type(tester, 'hollow');

      expect(find.text('The catalogue refused that.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('an unexpected error still surfaces, not a silent empty list',
        (tester) async {
      await pump(tester, BrokenCatalog());
      await type(tester, 'hollow');

      // A StateError is not a CatalogException, and swallowing it into "no
      // results" is exactly the lie this screen exists to avoid.
      expect(find.byKey(const Key('state-failed')), findsOneWidget);
      expect(find.byKey(const Key('state-empty')), findsNothing);
    });

    testWidgets('retry runs the search again', (tester) async {
      final catalog = CountingCatalog(FailingCatalog(CatalogFailure.offline));
      await pump(tester, catalog);
      await type(tester, 'hollow');
      expect(catalog.queries, ['hollow']);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(catalog.queries, ['hollow', 'hollow']);
    });
  });

  group('debounce', () {
    testWidgets('typing a word is one search, not one per keystroke',
        (tester) async {
      final catalog = CountingCatalog(FixtureCatalog());
      await pump(tester, catalog);

      // Six keystrokes inside the debounce window.
      for (final partial in ['h', 'ho', 'hol', 'holl', 'hollo', 'hollow']) {
        await tester.enterText(find.byKey(const Key('search-field')), partial);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // On the fixture six requests would merely be wasteful. Against the proxy
      // it is a rate limit and a bill.
      expect(catalog.queries, ['hollow']);
    });

    testWidgets('submitting searches immediately, without waiting it out',
        (tester) async {
      final catalog = CountingCatalog(FixtureCatalog());
      await pump(tester, catalog);

      await tester.enterText(find.byKey(const Key('search-field')), 'hollow');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Someone who pressed enter has finished typing and said so.
      expect(catalog.queries, contains('hollow'));
      expect(find.text('Hollow Knight'), findsOneWidget);
    });

    testWidgets('a blank query is never sent', (tester) async {
      final catalog = CountingCatalog(FixtureCatalog());
      await pump(tester, catalog);

      await tester.enterText(find.byKey(const Key('search-field')), '   ');
      await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(catalog.queries, isEmpty);
      expect(find.byKey(const Key('state-idle')), findsOneWidget);
    });

    testWidgets('a slow earlier response cannot overwrite a newer one',
        (tester) async {
      // "hollow" resolves long after "celeste". Without the in-flight guard the
      // stale result would land last and replace what the user is looking at.
      final catalog = SlowCatalog(FixtureCatalog(), {
        'hollow': const Duration(milliseconds: 400),
        'celeste': Duration.zero,
      });
      await pump(tester, catalog);

      await tester.enterText(find.byKey(const Key('search-field')), 'hollow');
      // Past the debounce, so the slow request is genuinely in flight.
      await tester.pump(kSearchDebounce + const Duration(milliseconds: 20));

      await tester.enterText(find.byKey(const Key('search-field')), 'celeste');
      // Past the debounce again, then past the first request's delay.
      await tester.pump(kSearchDebounce + const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Celeste'), findsOneWidget);
      expect(find.text('Hollow Knight'), findsNothing,
          reason: 'a stale response overwrote a newer one');
    });
  });

  group('adding', () {
    testWidgets('tapping a result adds it as a seed', (tester) async {
      await pump(tester, FixtureCatalog());
      await type(tester, 'hollow');

      await tapAndWrite(tester, find.text('Hollow Knight'));

      final added = store.items!
          .firstWhere((i) => i.game.title == 'Hollow Knight');
      // Searching for a game is not buying it. The two axes stay independent and
      // the user sets ownership from the status sheet when they actually have it.
      expect(added.entry.ownership, Ownership.spotted);
      expect(added.entry.progress, Progress.untouched);
      expect(added.isSeed, isTrue);
      // A new game gets its found moment before any confirmation; leaving it
      // on the ground is one tap, and then the snackbar says what happened.
      expect(find.text('New find'), findsOneWidget);
      await tester.tap(find.byKey(const Key('found-not-now')));
      await tester.pumpAndSettle();
      expect(find.text('New find'), findsNothing);
      // `_add` began inside runAsync, so what follows the moment resumes on a
      // real turn of the event loop.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
      expect(find.text('Added Hollow Knight.'), findsOneWidget);
    });

    testWidgets('the found moment files a new game onto the tree tapped',
        (tester) async {
      await tester.runAsync(() async => repo.createBranch('Cozy', sortOrder: 0));
      await pump(tester, FixtureCatalog());
      await type(tester, 'hollow');

      await tapAndWrite(tester, find.text('Hollow Knight'));
      // The shrink-into-the-chip exit runs on the fake clock; the write it
      // triggers is real I/O, so it gets a real wait of its own.
      await tester.tap(find.bySemanticsLabel('Hang it on Cozy'));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      final cozy = store.branches.firstWhere((b) => b.name == 'Cozy');
      final id = store.items!
          .firstWhere((i) => i.game.title == 'Hollow Knight')
          .game
          .igdbId;
      expect(store.placements[cozy.id], contains(id));
      expect(find.text('Added Hollow Knight to Cozy.'), findsOneWidget);
    });

    testWidgets('adding a game already held says so instead of claiming to add',
        (tester) async {
      await tester.runAsync(() async => repo.seedIfEmpty());
      await pump(tester, FixtureCatalog());
      await type(tester, 'hollow');

      await tapAndWrite(tester, find.text('Hollow Knight'));

      // "Added" on a game that was already there is a small lie, and the user
      // would wonder why nothing changed.
      expect(find.text('Hollow Knight is already in your collection.'),
          findsOneWidget);
    });

    testWidgets('re-adding does not reset what the user recorded',
        (tester) async {
      await tester.runAsync(() async => repo.seedIfEmpty());
      await pump(tester, FixtureCatalog());

      await tester.runAsync(() async {
        final id = store.items!
            .firstWhere((i) => i.game.title == 'Hollow Knight')
            .game
            .igdbId;
        await store.setProgress(id, Progress.finished);
      });
      await tester.pumpAndSettle();

      await type(tester, 'hollow');
      await tapAndWrite(tester, find.text('Hollow Knight'));

      final after = store.items!
          .firstWhere((i) => i.game.title == 'Hollow Knight');
      expect(after.entry.progress, Progress.finished);
    });
  });

  group('accessibility', () {
    testWidgets('a result announces its title and length as one sentence',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, FixtureCatalog());
      await type(tester, 'hollow');

      expect(
        find.bySemanticsLabel('Hollow Knight, 2017, about 26 hours'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('fileOnto — Add a game here', () {
    // The tree's branch menu opens AddScreen with fileOnto set, so a game added
    // there is placed on that branch, not just left on the trunk.
    testWidgets('a game added with fileOnto is placed on that branch',
        (tester) async {
      late int branchId;
      await tester.runAsync(() async {
        await repo.createBranch('Couch co-op');
        branchId = (await repo.branches())
            .firstWhere((b) => b.name == 'Couch co-op')
            .id;
        store = LudeckStore(repo);
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider<LudeckStore>.value(
            value: store,
            child: AddScreen(catalog: FixtureCatalog(), fileOnto: branchId),
          ),
        ));
        await store.load();
      });
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('search-field')), 'hollow');
      await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      await tester.runAsync(() async => tester.tap(find.text('Hollow Knight')));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();

      final added =
          store.items!.firstWhere((i) => i.game.title == 'Hollow Knight');
      // It is on the branch the add flow was scoped to.
      expect(store.placements[branchId], contains(added.game.igdbId));
    });
  });
}
