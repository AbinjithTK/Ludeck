// The social graph from migration 0003, tested against the in-memory fake.
//
// These mirror the 41 live RLS checks run against Supabase on 2026-09-29
// (Stage 2): the same three people, the same rules. If a rule here passes
// but the server disagrees, the fake is lying to every UI test, so keep the
// two in step.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';

const _alice = SocialProfile(id: 'a', handle: 'alice', displayName: 'Alice');
const _bob =
    SocialProfile(id: 'b', handle: 'bob', displayName: 'Bob', isPrivate: true);
const _cara = SocialProfile(id: 'c', handle: 'cara', displayName: 'Cara');

Matcher _fails(SocialFailure f) =>
    throwsA(isA<SocialException>().having((e) => e.failure, 'failure', f));

void main() {
  late FakeSocialStore store;
  late FakeSocialBackend alice, bob, cara, anon;

  setUp(() {
    store = FakeSocialStore();
    alice = FakeSocialBackend(signedInAs: _alice, store: store);
    bob = FakeSocialBackend(signedInAs: _bob, store: store);
    cara = FakeSocialBackend(signedInAs: _cara, store: store);
    anon = FakeSocialBackend(store: store);
  });

  group('profile and ID', () {
    test('an ID check normalises case and @, and knows reserved and taken IDs',
        () async {
      expect(await anon.isHandleAvailable('@Fresh_Name9'), isTrue);
      expect(await anon.isHandleAvailable('alice'), isFalse);
      expect(await anon.isHandleAvailable('admin'), isFalse);
      expect(await anon.isHandleAvailable('no'), isFalse, reason: 'too short');
      expect(await anon.isHandleAvailable('bad id!'), isFalse);
      // Your own ID is not "taken" from where you stand.
      expect(await alice.isHandleAvailable('alice'), isTrue);
    });

    test('editing the profile saves and shows in currentProfile', () async {
      final saved = await alice.updateProfile(const ProfileEdit(
        handle: '@Alice_Plays',
        bio: 'cozy games',
        platforms: ['pc', 'switch'],
        isPrivate: true,
        onboarded: true,
      ));
      expect(saved.handle, 'alice_plays');
      expect(alice.currentProfile!.bio, 'cozy games');
      expect(alice.currentProfile!.platforms, ['pc', 'switch']);
      expect(alice.currentProfile!.isPrivate, isTrue);
      expect(alice.currentProfile!.onboarded, isTrue);
    });

    test('a taken ID is a conflict; a bad one is invalid', () async {
      expect(alice.updateProfile(const ProfileEdit(handle: 'bob')),
          _fails(SocialFailure.conflict));
      expect(alice.updateProfile(const ProfileEdit(handle: 'ludeck')),
          _fails(SocialFailure.invalid));
      expect(alice.updateProfile(ProfileEdit(bio: 'x' * 161)),
          _fails(SocialFailure.invalid));
      expect(alice.updateProfile(const ProfileEdit(platforms: ['atari'])),
          _fails(SocialFailure.invalid));
    });

    test('changing your ID moves your public tree link with it', () async {
      await alice.publish(games: const [], level: 2, isPublic: true);
      await alice.updateProfile(const ProfileEdit(handle: 'alice2'));
      expect((await anon.treeByHandle('alice2')).level, 2);
      expect(anon.treeByHandle('alice'), _fails(SocialFailure.notFound));
    });

    test('editing signed out is unauthorized', () {
      expect(anon.updateProfile(const ProfileEdit(bio: 'hi')),
          _fails(SocialFailure.unauthorized));
    });
  });

  group('search', () {
    test('finds by ID or name prefix, exact ID first, never yourself', () async {
      store.addProfile(
          const SocialProfile(id: 'd', handle: 'alicia', displayName: 'Dee'));
      final hits = await cara.searchPeople('@ali');
      expect(hits.map((p) => p.handle), ['alice', 'alicia']);
      expect((await cara.searchPeople('bo')).single.handle, 'bob');
      expect(await cara.searchPeople('ca'), isEmpty, reason: 'that is me');
      expect(await cara.searchPeople('a'), isEmpty, reason: 'too short');
    });

    test('each hit carries the relationship', () async {
      await cara.setFollowing('alice', true);
      await alice.setFollowing('cara', true);
      final hit = (await cara.searchPeople('alice')).single;
      expect(hit.iFollow, FollowState.accepted);
      expect(hit.followsMe, isTrue);
      expect(hit.isFriend, isTrue);
    });
  });

  group('follows and privacy', () {
    test('following a public profile is accepted at once', () async {
      expect(await cara.setFollowing('alice', true), FollowState.accepted);
      expect((await alice.followers()).single.handle, 'cara');
    });

    test('a private profile hides its tree until the request is accepted',
        () async {
      await bob.publish(
        games: const [
          PublishedGame(
              igdbId: 2,
              title: 'Celeste',
              status: Progress.playing,
              branchName: 'Platformers'),
        ],
        level: 1,
        isPublic: true,
      );
      expect(cara.treeByHandle('bob'), _fails(SocialFailure.notFound));
      expect(anon.treeByHandle('bob'), _fails(SocialFailure.notFound));

      expect(await cara.setFollowing('bob', true), FollowState.pending);
      // Asking again does not skip the queue.
      expect(await cara.setFollowing('bob', true), FollowState.pending);
      expect(cara.treeByHandle('bob'), _fails(SocialFailure.notFound));

      expect((await bob.followRequests()).single.handle, 'cara');
      await bob.respondToFollowRequest('cara', accept: true);

      expect((await cara.treeByHandle('bob')).games.single.title, 'Celeste');
      expect(await bob.followRequests(), isEmpty);
      expect((await bob.followers()).single.handle, 'cara');
    });

    test('declining a request removes it', () async {
      await cara.setFollowing('bob', true);
      await bob.respondToFollowRequest('cara', accept: false);
      expect(await bob.followRequests(), isEmpty);
      expect((await cara.personByHandle('bob')).iFollow, FollowState.none);
    });

    test('removing a follower is not a block: they can follow again', () async {
      await cara.setFollowing('alice', true);
      await alice.removeFollower('cara');
      expect(await alice.followers(), isEmpty);
      expect(await cara.setFollowing('alice', true), FollowState.accepted);
    });

    test('followingPeople marks who follows you back', () async {
      await cara.setFollowing('alice', true);
      await cara.setFollowing('bob', true);
      await alice.setFollowing('cara', true);
      final list = {
        for (final p in await cara.followingPeople()) p.handle: p,
      };
      expect(list['alice']!.isFriend, isTrue);
      expect(list['bob']!.iFollow, FollowState.pending);
      expect(list['bob']!.isFriend, isFalse);
    });

    test('you cannot follow yourself or an unknown ID', () {
      expect(alice.setFollowing('alice', true), _fails(SocialFailure.invalid));
      expect(alice.setFollowing('ghost', true), _fails(SocialFailure.notFound));
    });
  });

  group('blocks', () {
    test('a block cuts follows, hides both ways and refuses a re-follow',
        () async {
      await alice.publish(games: const [], level: 1, isPublic: true);
      await cara.setFollowing('alice', true);
      await alice.setFollowing('cara', true);

      await alice.block('cara');

      expect(await alice.followers(), isEmpty);
      expect(await cara.followingPeople(), isEmpty);
      expect(await alice.searchPeople('cara'), isEmpty);
      expect(await cara.searchPeople('alice'), isEmpty);
      expect(cara.personByHandle('alice'), _fails(SocialFailure.notFound));
      expect(cara.treeByHandle('alice'), _fails(SocialFailure.notFound));
      expect(cara.setFollowing('alice', true), _fails(SocialFailure.forbidden));
      expect((await alice.blockedPeople()).single.handle, 'cara');
      expect(await cara.blockedPeople(), isEmpty,
          reason: 'nobody learns they were blocked');

      await alice.unblock('cara');
      expect(await alice.blockedPeople(), isEmpty);
      expect(await cara.setFollowing('alice', true), FollowState.accepted);
    });

    test('a report is accepted and stored', () async {
      await cara.report('bob', ReportReason.spam, details: 'ads');
      expect(store.reports.single, ('c', 'b', ReportReason.spam));
    });
  });

  group('quiet feed', () {
    test('shows accepted follows only, newest first', () async {
      await alice.postActivity(
          kind: ActivityKind.harvested, igdbId: 1, title: 'Hades');
      await bob.postActivity(
          kind: ActivityKind.planted, igdbId: 2, title: 'Celeste');
      await alice.postActivity(
          kind: ActivityKind.rated, igdbId: 1, title: 'Hades', rating: 5);

      await cara.setFollowing('alice', true);
      await cara.setFollowing('bob', true); // pending: not in the feed

      final feed = await cara.friendsActivity();
      expect(feed.map((a) => a.kind),
          [ActivityKind.rated, ActivityKind.harvested]);
      expect(feed.first.actor.handle, 'alice');
      expect(feed.first.rating, 5);
    });

    test('an empty window ends the list', () async {
      await alice.postActivity(
          kind: ActivityKind.planted, igdbId: 1, title: 'Hades');
      await cara.setFollowing('alice', true);
      // Windows' clock can tick in 15ms steps, so leave a clear gap.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(await cara.friendsActivity(window: const Duration(milliseconds: 20)),
          isEmpty);
      expect(await cara.friendsActivity(), hasLength(1));
    });

    test('needs sign-in', () {
      expect(anon.friendsActivity(), _fails(SocialFailure.unauthorized));
    });
  });

  group('hypes', () {
    test('the owner sees who hyped; hyping twice does not stack', () async {
      await cara.setHype('alice', 1, true);
      await cara.setHype('alice', 1, true);
      expect(await cara.myHypesOn('alice'), {1});
      final hypes = await alice.hypesOnMyTree();
      expect(hypes.single.from.handle, 'cara');
      expect(
          (await alice.notifications())
              .where((n) => n.kind == NotificationKind.hype),
          hasLength(1));
    });

    test('a third party cannot see other people\'s hypes', () async {
      await cara.setHype('alice', 1, true);
      expect(await bob.myHypesOn('alice'), isEmpty);
      expect(await bob.hypesOnMyTree(), isEmpty);
    });

    test('un-hype removes it', () async {
      await cara.setHype('alice', 1, true);
      await cara.setHype('alice', 1, false);
      expect(await alice.hypesOnMyTree(), isEmpty);
    });

    test('you cannot hype a private tree you cannot see', () {
      expect(cara.setHype('bob', 2, true), _fails(SocialFailure.forbidden));
    });
  });

  group('seeds', () {
    test('only someone who follows you can be sent a seed', () async {
      expect(
        cara.recommend(toHandle: 'alice', igdbId: 5, title: 'Balatro'),
        _fails(SocialFailure.forbidden),
      );
      await alice.setFollowing('cara', true);
      await cara.recommend(
          toHandle: 'alice',
          igdbId: 5,
          title: 'Balatro',
          message: 'you will love it');

      final inbox = await alice.recommendationsInbox();
      expect(inbox.single.from.handle, 'cara');
      expect(inbox.single.message, 'you will love it');
      expect(inbox.single.status, RecommendationStatus.sent);
      expect((await cara.recommendationsSent()).single.to.handle, 'alice');
    });

    test('only the recipient can plant or dismiss', () async {
      await alice.setFollowing('cara', true);
      await cara.recommend(toHandle: 'alice', igdbId: 5, title: 'Balatro');
      final id = (await alice.recommendationsInbox()).single.id;

      expect(cara.setRecommendationStatus(id, RecommendationStatus.planted),
          _fails(SocialFailure.notFound));
      await alice.setRecommendationStatus(id, RecommendationStatus.planted);
      expect((await alice.recommendationsInbox()).single.status,
          RecommendationStatus.planted);
    });

    test('a message over 140 characters is invalid', () async {
      await alice.setFollowing('cara', true);
      expect(
        cara.recommend(
            toHandle: 'alice', igdbId: 5, title: 'Balatro', message: 'x' * 141),
        _fails(SocialFailure.invalid),
      );
    });
  });

  group('notifications', () {
    test('follows, requests, acceptance and seeds all arrive', () async {
      await cara.setFollowing('alice', true);
      await cara.setFollowing('bob', true);
      expect((await alice.notifications()).single.kind, NotificationKind.follow);
      expect((await bob.notifications()).single.kind,
          NotificationKind.followRequest);

      await bob.respondToFollowRequest('cara', accept: true);
      expect(await bob.notifications(), isEmpty,
          reason: 'the answered request card is removed');
      expect((await cara.notifications()).single.kind,
          NotificationKind.followAccepted);

      await alice.setFollowing('cara', true);
      await alice.recommend(toHandle: 'cara', igdbId: 7, title: 'Tunic');
      final seed = (await cara.notifications()).first;
      expect(seed.kind, NotificationKind.recommendation);
      expect(seed.igdbId, 7);
      expect(seed.refId, isNotNull);
    });

    test('unread count drops to zero when marked read', () async {
      await cara.setFollowing('alice', true);
      await bob.setFollowing('alice', true);
      expect(await alice.unreadNotificationCount(), 2);
      await alice.markNotificationsRead();
      expect(await alice.unreadNotificationCount(), 0);
      expect((await alice.notifications()).every((n) => !n.isUnread), isTrue);
    });

    test('you only ever see your own', () async {
      await cara.setFollowing('alice', true);
      expect(await cara.notifications(), isEmpty);
      expect(await bob.notifications(), isEmpty);
    });
  });

  test('deleting an account removes the person from everyone', () async {
    await cara.setFollowing('alice', true);
    await alice.setFollowing('cara', true);
    await cara.recommend(toHandle: 'alice', igdbId: 5, title: 'Balatro');
    await cara.setHype('alice', 1, true);

    await cara.deleteAccount();

    expect(await alice.followers(), isEmpty);
    expect(await alice.followingPeople(), isEmpty);
    expect(await alice.recommendationsInbox(), isEmpty);
    expect(await alice.hypesOnMyTree(), isEmpty);
    expect(await alice.notifications(), isEmpty);
    expect(await alice.searchPeople('cara'), isEmpty);
  });
}
