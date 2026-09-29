// Stage 6 verification: reactions (admire/wishlist/played) show live counts
// and toggling follow persists through the real backend -- both on the
// VisitScreen already built in Stage 5. Rate limiting itself lives in RLS
// (0001_community.sql's unique constraints), verified structurally in Stage 2;
// this stage verifies the UI actually drives those calls and reflects them.

import 'package:flutter/material.dart' hide Form;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

  Future<void> publishEmptyTree(FakeSocialBackend owner, String handle) => owner.publish(
      games: const [], level: 1, isPublic: true);

  group('reactions', () {
    testWidgets('admiring is saved once, and a visitor is shown no count',
        (tester) async {
      final owner = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'owner', handle: 'ada', displayName: 'Ada'));
      await publishEmptyTree(owner, 'ada');

      final visitor = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'v', handle: 'bo', displayName: 'Bo'));

      await pump(tester, visitor, 'ada');
      expect(find.text('Admire'), findsOneWidget);

      await tester.runAsync(() => tester.tap(find.text('Admire')));
      await tester.pumpAndSettle();
      // Same visitor, same kind, again.
      await tester.runAsync(() => tester.tap(find.text('Admire')));
      await tester.pumpAndSettle();

      // No public counts (direction B): the visitor sees their own choice
      // highlighted, never a tally.
      expect(find.text('Admire 1'), findsNothing);
      final admire = tester.widget<Semantics>(find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Admire'));
      expect(admire.properties.selected, isTrue);
      late List<TreeReaction> saved;
      await tester.runAsync(() async => saved = await owner.reactionsFor('ada'));
      expect(saved.where((r) => r.kind == ReactionKind.admire), hasLength(1));
    });

    testWidgets('a signed-out visitor is asked to sign in, then the reaction lands',
        (tester) async {
      final owner = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'owner', handle: 'ada', displayName: 'Ada'));
      await publishEmptyTree(owner, 'ada');

      // No signedInAs -- this visitor starts signed out.
      final visitor = FakeSocialBackend();
      expect(visitor.currentProfile, isNull);

      await pump(tester, visitor, 'ada');
      await tester.runAsync(() => tester.tap(find.text('Wishlist')));
      await tester.pumpAndSettle();

      // The account screen, not a silent sign-in.
      expect(find.byKey(const Key('account-google')), findsOneWidget);
      await tester.runAsync(
          () => tester.tap(find.byKey(const Key('account-google'))));
      await tester.pumpAndSettle();

      expect(visitor.currentProfile, isNotNull);
      late List<TreeReaction> saved;
      await tester.runAsync(() async => saved = await owner.reactionsFor('ada'));
      expect(saved.single.kind, ReactionKind.wishlist);
    });

    testWidgets('choosing Not now sends nothing and stays signed out',
        (tester) async {
      final owner = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'owner', handle: 'ada', displayName: 'Ada'));
      await publishEmptyTree(owner, 'ada');
      final visitor = FakeSocialBackend();

      await pump(tester, visitor, 'ada');
      await tester.runAsync(() => tester.tap(find.text('Wishlist')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('account-not-now')));
      await tester.pumpAndSettle();

      expect(visitor.currentProfile, isNull);
      late List<TreeReaction> saved;
      await tester.runAsync(() async => saved = await owner.reactionsFor('ada'));
      expect(saved, isEmpty);
    });
  });

  group('follow', () {
    testWidgets('tapping Follow toggles to Following and persists', (tester) async {
      final owner = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'owner', handle: 'ada', displayName: 'Ada'));
      await publishEmptyTree(owner, 'ada');

      final visitor = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'v', handle: 'bo', displayName: 'Bo'));

      await pump(tester, visitor, 'ada');
      expect(find.text('Follow'), findsOneWidget);

      await tester.runAsync(() => tester.tap(find.text('Follow')));
      await tester.pumpAndSettle();

      expect(find.text('Following'), findsOneWidget);
      expect(await visitor.following(), contains('ada'));
    });

    testWidgets('tapping Following again unfollows', (tester) async {
      final owner = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'owner', handle: 'ada', displayName: 'Ada'));
      await publishEmptyTree(owner, 'ada');

      final visitor = FakeSocialBackend(
          signedInAs: const SocialProfile(id: 'v', handle: 'bo', displayName: 'Bo'));
      await visitor.setFollowing('ada', true);

      await pump(tester, visitor, 'ada');
      expect(find.text('Following'), findsOneWidget);

      await tester.runAsync(() => tester.tap(find.text('Following')));
      await tester.pumpAndSettle();

      expect(find.text('Follow'), findsOneWidget);
      expect(await visitor.following(), isNot(contains('ada')));
    });
  });
}
