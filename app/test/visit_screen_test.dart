// Stage 5 verification: visiting is read-only (only Plant is interactive),
// grouped by branch, and Plant genuinely writes a seed crediting the owner's
// handle through the real store path -- not a stub.
//
// Every database call goes through `tester.runAsync`, per this project's own
// rule (check.ps1 rule 8 / docs/CONSTRAINTS.md): sqflite does real file I/O
// that never completes under testWidgets' fake clock, and mounting a
// DB-backed screen outside runAsync holds the database lock and the run hangs.

import 'package:flutter/material.dart' hide Form;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/visit/visit_screen.dart';

void main() {
  late Repository repo;
  late LudeckStore store;

  setUp(() async {
    repo = await Repository.openInMemory();
    FakeSocialBackend.resetShared();
  });

  tearDown(() async => repo.close());

  Future<void> pump(WidgetTester tester, SocialBackend backend, String handle) async {
    await tester.runAsync(() async {
      store = LudeckStore(repo);
      await tester.pumpWidget(MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<SocialBackend>.value(value: backend),
            ChangeNotifierProvider<LudeckStore>.value(value: store),
          ],
          child: VisitScreen(handle: handle),
        ),
      ));
      await store.load();
    });
    await tester.pumpAndSettle();
  }

  group('visiting a public tree', () {
    testWidgets('shows the owner, is read-only, and groups games by branch',
        (tester) async {
      final owner = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'owner', handle: 'ada', displayName: 'Ada'));
      await owner.publish(
        games: [
          const PublishedGame(
              igdbId: 1, title: 'Hades', status: Progress.finished,
              rating: 5, branchName: 'Roguelikes'),
          const PublishedGame(
              igdbId: 2, title: 'Celeste', status: Progress.untouched,
              branchName: 'Roguelikes'),
        ],
        level: 4,
        isPublic: true,
      );

      final visitor = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'v', handle: 'bo', displayName: 'Bo'));

      await pump(tester, visitor, 'ada');

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Roguelikes'), findsOneWidget);
      expect(find.text('Hades'), findsOneWidget);
      expect(find.text('Celeste'), findsOneWidget);

      // Read-only: the only tappable label on a row is "Plant" -- there is no
      // rating control, no status editor, no delete.
      expect(find.text('Plant'), findsNWidgets(2));
      expect(find.byType(Slider), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets('an unpublished/nonexistent handle shows the notFound message',
        (tester) async {
      final visitor = FakeSocialBackend();

      await pump(tester, visitor, 'nobody');

      expect(find.textContaining("isn't public"), findsOneWidget);
    });

    testWidgets("tapping Plant adds a real seed crediting the owner's handle",
        (tester) async {
      final owner = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'owner', handle: 'ada', displayName: 'Ada'));
      await owner.publish(
        games: [
          const PublishedGame(
              igdbId: 113112, title: 'Hades', status: Progress.finished,
              branchName: 'Roguelikes'),
        ],
        level: 1,
        isPublic: true,
      );

      final visitor = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'v', handle: 'bo', displayName: 'Bo'));

      await pump(tester, visitor, 'ada');
      expect(store.items, isEmpty);

      await tester.runAsync(() async {
        await tester.tap(find.text('Plant'));
        // Bounded wait for the store's own async write (_write -> addShared ->
        // repo insert + reload) to actually land, rather than a fixed delay.
        // A fixed 50ms guess passed in isolation and failed inside the full
        // suite, because under concurrency the machine is loaded and the real
        // sqflite round trip outlives the guess -- the test was measuring the
        // host's spare capacity, not the code. Polling to a generous deadline
        // is both faster in the common case and deterministic.
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while ((store.items?.isEmpty ?? true) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      final items = store.items!;
      expect(items, hasLength(1));
      final grafted = items.single;
      expect(grafted.game.title, 'Hades');
      expect(grafted.entry.ownership, Ownership.spotted);
      expect(grafted.entry.recommendedBy, 'ada');
      // "Planted in your soil" was wrong: a seed grows its own tree. Taking a
      // cutting from someone else's tree and growing it on yours is a GRAFT,
      // which is also what carries `recommendedBy` above its literal meaning.
      expect(find.textContaining('Grafted Hades'), findsOneWidget);
    });
  });
}
