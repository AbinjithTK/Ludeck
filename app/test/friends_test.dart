// Friends, end to end against the fake: finding people, the three follow
// states, requests, the lists, inviting, the preview, and a friend's orchard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/services/social/tree_links.dart';
import 'package:ludeck/ui/friends/friends_screen.dart';
import 'package:ludeck/ui/visit/visit_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _abin = SocialProfile(
    id: 'me', handle: 'abin', displayName: 'Abin', onboarded: true);
const _alice = SocialProfile(
    id: 'a',
    handle: 'alice',
    displayName: 'Alice',
    bio: 'roguelikes forever',
    platforms: ['switch'],
    onboarded: true);
const _bob = SocialProfile(
    id: 'b', handle: 'bob', displayName: 'Bob', isPrivate: true, onboarded: true);
const _dee = SocialProfile(
    id: 'd', handle: 'dee', displayName: 'Alison Dee', onboarded: true);

const _hades = PublishedGame(
    igdbId: 1, title: 'Hades', status: Progress.finished, branchName: 'Rogues');
const _celeste = PublishedGame(
    igdbId: 2, title: 'Celeste', status: Progress.playing, branchName: 'Rogues');

void main() {
  late FakeSocialStore store;
  late FakeSocialBackend me, alice, bob;

  setUp(() async {
    store = FakeSocialStore();
    store.addProfile(_dee);
    me = FakeSocialBackend(signedInAs: _abin, store: store);
    alice = FakeSocialBackend(signedInAs: _alice, store: store);
    bob = FakeSocialBackend(signedInAs: _bob, store: store);
    await alice.publish(games: const [_hades, _celeste], level: 2, isPublic: true);
    await bob.publish(games: const [_hades], level: 1, isPublic: true);
  });

  Future<void> pump(WidgetTester tester, SocialBackend b, Widget home) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Provider<SocialBackend>.value(
      value: b,
      child: MaterialApp(home: home),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Finder tab(String label) => find.descendant(
      of: find.byKey(const Key('friends-tabs')), matching: find.text(label));

  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const Key('friends-search')), q);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  group('find', () {
    testWidgets('by ID, with @, or by name', (tester) async {
      await pump(tester, me, const FriendsScreen());
      await search(tester, '@ali');
      expect(find.byKey(const Key('result-alice')), findsOneWidget);
      expect(find.byKey(const Key('result-dee')), findsOneWidget,
          reason: 'Alison Dee matches by name');
      await search(tester, 'zz');
      expect(find.byKey(const Key('friends-no-results')), findsOneWidget);
    });

    testWidgets('search works signed out; following asks for an account',
        (tester) async {
      await pump(tester, FakeSocialBackend(store: store), const FriendsScreen());
      expect(find.byKey(const Key('friends-sign-in')), findsOneWidget);
      await search(tester, 'alice');
      await tap(tester, 'follow-alice');
      expect(find.byKey(const Key('account-google')), findsOneWidget);
    });
  });

  group('follow', () {
    testWidgets('public is Following at once; a follow back makes Friends',
        (tester) async {
      await pump(tester, me, const FriendsScreen());
      await search(tester, 'alice');
      await tap(tester, 'follow-alice');
      expect(find.text('Following'), findsOneWidget);
      expect(find.byKey(const Key('badge-alice')), findsNothing);

      await alice.setFollowing('abin', true);
      await search(tester, 'alic');
      expect(find.text('Friends'), findsWidgets);
      expect(find.byKey(const Key('badge-alice')), findsOneWidget);
    });

    testWidgets('someone who follows you shows Follow back', (tester) async {
      await alice.setFollowing('abin', true);
      await pump(tester, me, const FriendsScreen());
      await search(tester, 'alice');
      expect(find.text('Follows you'), findsOneWidget);
      expect(find.text('Follow back'), findsOneWidget);
    });

    testWidgets('private is Requested, and their orchard is a gate until yes',
        (tester) async {
      await pump(tester, me, const FriendsScreen());
      await search(tester, 'bob');
      await tap(tester, 'follow-bob');
      expect(find.text('Requested'), findsOneWidget);

      await pump(tester, me, const VisitScreen(handle: 'bob'));
      expect(find.byKey(const Key('visit-gate')), findsOneWidget);
      expect(find.textContaining('You asked to follow'), findsOneWidget);
      expect(find.text('Hades'), findsNothing);

      await bob.respondToFollowRequest('abin', accept: true);
      // A new visit, as reopening the screen would be.
      await pump(tester, me, VisitScreen(key: UniqueKey(), handle: 'bob'));
      expect(find.byKey(const Key('visit-gate')), findsNothing);
      expect(find.text('Hades'), findsOneWidget);
    });

    testWidgets('unfollowing a private friend asks first', (tester) async {
      await me.setFollowing('bob', true);
      await bob.respondToFollowRequest('abin', accept: true);
      await pump(tester, me, const FriendsScreen());
      await tester.tap(tab('Following'));
      await tester.pumpAndSettle();
      await tap(tester, 'follow-bob');
      expect(find.text('Unfollow @bob?'), findsOneWidget);
      await tap(tester, 'confirm-unfollow');
      expect(await me.following(), isEmpty);
    });
  });

  group('lists and requests', () {
    testWidgets('requests accept into Followers; tabs split the lists',
        (tester) async {
      await me.updateProfile(const ProfileEdit(isPrivate: true));
      await alice.setFollowing('abin', true); // a request, I am private
      await me.setFollowing('alice', true);
      await me.setFollowing('bob', true); // pending, bob is private

      await pump(tester, me, const FriendsScreen());
      expect(find.text('Asking to follow you'), findsOneWidget);
      await tap(tester, 'accept-alice');
      expect(find.text('Asking to follow you'), findsNothing);

      // Friends: alice only (mutual now).
      expect(find.byKey(const Key('person-alice')), findsOneWidget);
      expect(find.byKey(const Key('person-bob')), findsNothing);

      await tester.tap(tab('Following'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person-alice')), findsOneWidget);
      expect(find.byKey(const Key('person-bob')), findsOneWidget);

      await tester.tap(tab('Followers'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person-alice')), findsOneWidget);
      expect(find.byKey(const Key('person-bob')), findsNothing);
    });

    testWidgets('declining removes the request', (tester) async {
      await me.updateProfile(const ProfileEdit(isPrivate: true));
      await alice.setFollowing('abin', true);
      await pump(tester, me, const FriendsScreen());
      await tap(tester, 'decline-alice');
      expect(await me.followRequests(), isEmpty);
      expect(find.text('Asking to follow you'), findsNothing);
    });

    testWidgets('empty lists say what to do', (tester) async {
      await pump(tester, me, const FriendsScreen());
      expect(find.byKey(const Key('friends-empty')), findsOneWidget);
      expect(find.textContaining('follow you back'), findsOneWidget);
    });
  });

  testWidgets('invite shows a QR of your link and copies it', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(tester, me, const FriendsScreen());
    await tap(tester, 'friends-invite');
    expect(find.byKey(const Key('invite-sheet')), findsOneWidget);
    final qr = tester.widget<QrImageView>(find.byKey(const Key('invite-qr')));
    expect(qr, isNotNull);
    expect(find.text(treeLinkFor('abin')), findsOneWidget);

    await tap(tester, 'invite-copy-link');
    expect(copied.single, contains(treeLinkFor('abin')));
    await tap(tester, 'invite-copy-id');
    expect(copied.last, 'Find me on Ludeck: @abin');
  });

  testWidgets('a row opens a preview; the preview opens their orchard',
      (tester) async {
    await pump(tester, me, const FriendsScreen());
    await search(tester, 'alice');
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-preview')), findsOneWidget);
    expect(find.text('roguelikes forever'), findsOneWidget);
    expect(find.text('Switch'), findsOneWidget);
    await tap(tester, 'preview-open');
    expect(find.byType(VisitScreen), findsOneWidget);
    expect(find.text('Celeste'), findsOneWidget);
  });

  group('friend profile', () {
    testWidgets('shows who they are, their numbers, and hypes in one tap',
        (tester) async {
      await me.setFollowing('alice', true);
      await alice.setFollowing('abin', true);
      await pump(tester, me, const VisitScreen(handle: 'alice'));

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byKey(const Key('badge-alice')), findsOneWidget);
      expect(find.bySemanticsLabel('1 Finished'), findsOneWidget);
      expect(find.bySemanticsLabel('1 Playing'), findsOneWidget);
      expect(find.bySemanticsLabel('2 Games'), findsOneWidget);
      expect(find.byKey(const Key('visit-hyped')), findsNothing);

      await tap(tester, 'hype-1');
      expect(await me.myHypesOn('alice'), {1});
      expect(find.byKey(const Key('visit-hyped')), findsOneWidget);
      expect((await alice.hypesOnMyTree()).single.from.handle, 'abin');

      await tap(tester, 'hype-1');
      expect(await me.myHypesOn('alice'), isEmpty);
    });

    testWidgets('block from the menu blocks and leaves', (tester) async {
      await pump(tester, me, const VisitScreen(handle: 'alice'));
      await tap(tester, 'visit-menu');
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tap(tester, 'confirm-block');
      expect((await me.blockedPeople()).single.handle, 'alice');
    });

    testWidgets('report sends a reason', (tester) async {
      await pump(tester, me, const VisitScreen(handle: 'alice'));
      await tap(tester, 'visit-menu');
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tap(tester, 'report-spam');
      expect(store.reports.single, ('me', 'a', ReportReason.spam));
    });
  });
}
