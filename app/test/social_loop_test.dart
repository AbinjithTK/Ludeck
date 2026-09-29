// The social loop: your own events become friends' Lately lines, seeds travel
// to an inbox and graft onto a tree "from @them", and notifications arrive.
// Privacy runs through all of it: an event carries title, cover and rating
// only, and a friends-only person's events reach accepted followers alone.
//
// Database-backed screens mount inside tester.runAsync (check.ps1 rule 8).

import 'package:flutter/material.dart' hide Form;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/services/social/activity_recorder.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/social/inbox_screen.dart';
import 'package:ludeck/ui/social/lately_screen.dart';
import 'package:ludeck/ui/social/send_seed_sheet.dart';

const _abin = SocialProfile(
    id: 'me', handle: 'abin', displayName: 'Abin', onboarded: true);
const _alice = SocialProfile(
    id: 'a', handle: 'alice', displayName: 'Alice', onboarded: true);
const _bob = SocialProfile(
    id: 'b', handle: 'bob', displayName: 'Bob', isPrivate: true, onboarded: true);

/// A stand-in for the store: a list of items that notifies.
class _Items extends ChangeNotifier {
  List<TreeItem>? items;
  void set(List<TreeItem> next) {
    items = next;
    notifyListeners();
  }
}

TreeItem _item(int id, String title,
        {Progress progress = Progress.untouched,
        int? rating,
        String? note,
        String? by}) =>
    TreeItem(
      game: Game(igdbId: id, title: title, coverUrl: 'c$id'),
      entry: Entry(
        igdbId: id,
        ownership: Ownership.owned,
        progress: progress,
        rating: rating,
        note: note,
        recommendedBy: by,
      ),
      copies: const [],
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSocialStore social;
  late FakeSocialBackend me, alice, bob;

  setUp(() {
    social = FakeSocialStore();
    me = FakeSocialBackend(signedInAs: _abin, store: social);
    alice = FakeSocialBackend(signedInAs: _alice, store: social);
    bob = FakeSocialBackend(signedInAs: _bob, store: social);
  });

  group('activity recorder', () {
    late _Items source;
    late ValueNotifier<bool> on;

    setUp(() {
      source = _Items();
      on = ValueNotifier(true);
      ActivityRecorder(source, () => source.items, alice, enabled: on).attach();
      // Abin follows Alice, so he can read what she posts.
      me.setFollowing('alice', true);
    });

    Future<List<ActivityItem>> feed() => me.friendsActivity();

    test('the first read is the library, not news', () async {
      source.set([_item(1, 'Hades')]);
      await _settle();
      expect(await feed(), isEmpty);
    });

    test('a new game is planted, a finish is harvested, a rating is rated',
        () async {
      source.set([_item(1, 'Hades')]);
      source.set([_item(1, 'Hades'), _item(2, 'Celeste')]);
      source.set([
        _item(1, 'Hades', progress: Progress.finished),
        _item(2, 'Celeste')
      ]);
      source.set([
        _item(1, 'Hades', progress: Progress.finished, rating: 5),
        _item(2, 'Celeste')
      ]);
      await _settle();
      final kinds = [for (final a in await feed()) (a.kind, a.title)];
      expect(kinds, [
        (ActivityKind.rated, 'Hades'),
        (ActivityKind.harvested, 'Hades'),
        (ActivityKind.planted, 'Celeste'),
      ]);
      expect((await feed()).first.rating, 5);
    });

    test('an event carries title, cover and rating, never a note or a name',
        () async {
      source.set([]);
      source.set([_item(3, 'Tunic', note: 'my secret note', by: 'Priya')]);
      await _settle();
      final a = (await feed()).single;
      expect(a.title, 'Tunic');
      expect(a.coverUrl, 'c3');
      // ActivityItem has no field that could hold either; prove the fake
      // store did not receive them some other way.
      final everything = [a.title, a.coverUrl, a.rating, a.actor.handle].join('|');
      expect(everything.contains('my secret note'), isFalse);
      expect(everything.contains('Priya'), isFalse);
    });

    test('a bulk change posts nothing', () async {
      source.set([]);
      source.set([for (var i = 0; i < 6; i++) _item(i, 'Game $i')]);
      await _settle();
      expect(await feed(), isEmpty);
    });

    test('the switch off posts nothing', () async {
      on.value = false;
      source.set([]);
      source.set([_item(1, 'Hades')]);
      await _settle();
      expect(await feed(), isEmpty);
    });

    test('signed out posts nothing', () async {
      final quiet = _Items();
      final anon = FakeSocialBackend(store: social);
      ActivityRecorder(quiet, () => quiet.items, anon, enabled: on).attach();
      quiet.set([]);
      quiet.set([_item(9, 'Pentiment')]);
      await _settle();
      expect(social.activityCount, 0);
    });
  });

  group('privacy', () {
    test("a friends-only person's events reach accepted followers only",
        () async {
      await bob.postActivity(
          kind: ActivityKind.harvested, igdbId: 1, title: 'Hades');
      await me.setFollowing('bob', true); // pending
      expect(await me.friendsActivity(), isEmpty);
      await bob.respondToFollowRequest('abin', accept: true);
      expect((await me.friendsActivity()).single.title, 'Hades');
    });

    test('a seed only goes to someone who follows you', () async {
      expect(
          me.recommend(toHandle: 'alice', igdbId: 5, title: 'Balatro'),
          throwsA(isA<SocialException>()
              .having((e) => e.failure, 'f', SocialFailure.forbidden)));
    });
  });

  group('screens', () {
    late Repository repo;
    late LudeckStore store;

    setUp(() async {
      repo = await Repository.openInMemory();
    });

    tearDown(() async => repo.close());

    Future<void> pump(WidgetTester tester, SocialBackend b, Widget screen) async {
      tester.view.physicalSize = const Size(412, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        store = LudeckStore(repo);
        await tester.pumpWidget(MultiProvider(
          providers: [
            Provider<SocialBackend>.value(value: b),
            ChangeNotifierProvider<LudeckStore>.value(value: store),
          ],
          child: MaterialApp(home: Scaffold(body: Builder(builder: (context) {
            return TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('open'),
            );
          }))),
        ));
        await store.load();
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> waitForItems(WidgetTester tester, int n) async {
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while ((store.items?.length ?? 0) < n &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        // The write is in; give the screen's follow-up refresh a moment.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      // A future completed in the real zone delivers there, so pump once to
      // subscribe, then let the real zone run, then settle.
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    testWidgets('Lately lists friends, lets you hype and plant, and ends',
        (tester) async {
      await me.setFollowing('alice', true);
      await alice.postActivity(
          kind: ActivityKind.harvested, igdbId: 1, title: 'Hades');
      await alice.postActivity(
          kind: ActivityKind.rated, igdbId: 1, title: 'Hades', rating: 4);

      await pump(tester, me, const LatelyScreen());
      expect(find.text('@alice rated Hades 4 of 5', findRichText: true), findsOneWidget);
      expect(find.text('@alice finished Hades', findRichText: true), findsOneWidget);
      expect(find.byKey(const Key('lately-end')), findsOneWidget);

      final first = (await me.friendsActivity()).first.id;
      await tester.tap(find.byKey(Key('lately-hype-$first')));
      await tester.pumpAndSettle();
      expect(await me.myHypesOn('alice'), {1});
      expect((await alice.notifications()).first.kind, NotificationKind.hype);

      await tester.runAsync(
          () => tester.tap(find.byKey(Key('lately-graft-$first'))));
      await waitForItems(tester, 1);
      final planted = store.items!.single;
      expect(planted.entry.ownership, Ownership.spotted);
      expect(planted.entry.recommendedBy, 'alice');
      expect(find.text('In yours'), findsWidgets);
    });

    testWidgets('an empty Lately explains itself', (tester) async {
      await pump(tester, me, const LatelyScreen());
      expect(find.byKey(const Key('lately-empty')), findsOneWidget);
    });

    testWidgets('a seed in the inbox plants onto your tree from the sender',
        (tester) async {
      await me.setFollowing('alice', true);
      await alice.recommend(
          toHandle: 'abin',
          igdbId: 5,
          title: 'Balatro',
          message: 'you will love it');
      final id = (await me.recommendationsInbox()).single.id;

      await pump(tester, me, const InboxScreen());
      expect(find.text('Balatro'), findsOneWidget);
      expect(find.byKey(Key('seed-message-$id')), findsOneWidget);
      expect(find.text('@alice sent you a game', findRichText: true), findsOneWidget);
      expect(await me.unreadNotificationCount(), 0, reason: 'opening reads it');

      await tester.runAsync(
          () => tester.tap(find.byKey(Key('seed-plant-$id'))));
      await waitForItems(tester, 1);
      final planted = store.items!.single;
      expect(planted.game.title, 'Balatro');
      expect(planted.entry.recommendedBy, 'alice');
      expect((await me.recommendationsInbox()).single.status,
          RecommendationStatus.planted);
      expect(find.byKey(Key('seed-$id')), findsNothing);
    });

    testWidgets('Not for me dismisses a seed and plants nothing',
        (tester) async {
      await me.setFollowing('alice', true);
      await alice.recommend(toHandle: 'abin', igdbId: 5, title: 'Balatro');
      final id = (await me.recommendationsInbox()).single.id;
      await pump(tester, me, const InboxScreen());
      await tester.runAsync(
          () => tester.tap(find.byKey(Key('seed-dismiss-$id'))));
      await tester.pumpAndSettle();
      expect((await me.recommendationsInbox()).single.status,
          RecommendationStatus.dismissed);
      expect(store.items, isEmpty);
    });

    testWidgets('the inbox shows follows and requests', (tester) async {
      await me.updateProfile(const ProfileEdit(isPrivate: true));
      await alice.setFollowing('abin', true);
      await pump(tester, me, const InboxScreen());
      expect(find.text('@alice asked to follow you', findRichText: true), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'New'),
          findsOneWidget);
    });

    testWidgets('send a game to a follower, with a line', (tester) async {
      await alice.setFollowing('abin', true);
      await pump(
        tester,
        me,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSendSeedSheet(
                  context, const Game(igdbId: 7, title: 'Tunic', coverUrl: 'c')),
              child: const Text('send'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('send'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-to-alice')));
      await tester.enterText(find.byKey(const Key('send-message')), 'go');
      await tester.tap(find.byKey(const Key('send-go')));
      await tester.pumpAndSettle();

      final got = (await alice.recommendationsInbox()).single;
      expect(got.title, 'Tunic');
      expect(got.message, 'go');
      expect(got.from.handle, 'abin');
      expect(find.text('Sent Tunic to @alice.'), findsOneWidget);
    });

    testWidgets('with no followers, the send sheet says who can receive',
        (tester) async {
      await pump(
        tester,
        me,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSendSeedSheet(
                  context, const Game(igdbId: 7, title: 'Tunic')),
              child: const Text('send'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('send'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send-empty')), findsOneWidget);
    });
  });

  test('whenLabel reads like a person', () {
    final now = DateTime(2026, 9, 29, 12);
    expect(whenLabel(now, now), 'just now');
    expect(whenLabel(now.subtract(const Duration(minutes: 5)), now), '5m');
    expect(whenLabel(now.subtract(const Duration(hours: 3)), now), '3h');
    expect(whenLabel(now.subtract(const Duration(days: 1)), now), 'Yesterday');
    expect(whenLabel(now.subtract(const Duration(days: 4)), now), '4d');
  });
}
