// Stage 2 verification: the community backend contract, and the privacy
// invariant, tested against the in-memory fake -- no network, nothing deployed.
//
// The contract tests are written against the `SocialBackend` interface, not the
// fake specifically, so the Supabase implementation (Stage 3) can be run through
// the identical suite. That shared suite is what stops the two implementations
// from drifting.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/publish_export.dart';
import 'package:ludeck/services/social/social_backend.dart';

const _me = SocialProfile(
  id: 'me',
  handle: 'ada',
  displayName: 'Ada',
  avatarSeed: 'ada',
);

PublishedGame _pg(int id, String title, Progress status,
        {int? rating, String branch = 'Cozy'}) =>
    PublishedGame(
      igdbId: id,
      title: title,
      status: status,
      rating: rating,
      branchName: branch,
    );

void main() {
  // Every test that uses the default shared store starts from a clean one.
  setUp(FakeSocialBackend.resetShared);

  group('publish / visit', () {
    test('a signed-in owner publishes a tree a stranger can then load',
        () async {
      final owner = FakeSocialBackend(signedInAs: _me);
      await owner.publish(
        games: [_pg(1020, 'Hollow Knight', Progress.finished, rating: 5)],
        level: 3,
        isPublic: true,
      );

      // A visitor with NO account loads it by handle.
      final visitor = FakeSocialBackend();
      final tree = await visitor.treeByHandle('ada');

      expect(tree.owner.handle, 'ada');
      expect(tree.level, 3);
      expect(tree.games.single.title, 'Hollow Knight');
      expect(tree.harvestedCount, 1);
    });

    test('publishing private (unpublish) makes the link 404', () async {
      final owner = FakeSocialBackend(signedInAs: _me);
      await owner.publish(games: [], level: 1, isPublic: true);
      await owner.publish(games: [], level: 1, isPublic: false);

      expect(
        () => owner.treeByHandle('ada'),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.notFound)),
      );
    });

    test('publishing signed-out is unauthorized', () async {
      final anon = FakeSocialBackend();
      expect(
        () => anon.publish(games: [], level: 1, isPublic: true),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.unauthorized)),
      );
    });

    test('loading a handle that never published is notFound', () async {
      final visitor = FakeSocialBackend();
      expect(
        () => visitor.treeByHandle('nobody'),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.notFound)),
      );
    });
  });

  group('reactions', () {
    test('a visitor reacts and the count is visible; re-reacting does not stack',
        () async {
      final owner = FakeSocialBackend(signedInAs: _me);
      await owner.publish(games: [], level: 1, isPublic: true);

      final visitor = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'v1', handle: 'bo', displayName: 'Bo'));
      await visitor.react('ada', ReactionKind.admire);
      await visitor.react('ada', ReactionKind.admire); // same again

      final reactions = await owner.reactionsFor('ada');
      expect(reactions.where((r) => r.kind == ReactionKind.admire).length, 1);
    });

    test('reacting signed-out is unauthorized', () async {
      final anon = FakeSocialBackend();
      expect(
        () => anon.react('ada', ReactionKind.admire),
        throwsA(isA<SocialException>().having(
            (e) => e.failure, 'failure', SocialFailure.unauthorized)),
      );
    });
  });

  group('follows', () {
    test('follow then unfollow', () async {
      final me = FakeSocialBackend(signedInAs: _me);
      await me.setFollowing('bo', true);
      expect(await me.following(), contains('bo'));
      await me.setFollowing('bo', false);
      expect(await me.following(), isNot(contains('bo')));
    });
  });

  group('PRIVACY invariant 10 -- the projection drops third-party names', () {
    // A collection item that DOES carry the forbidden fields. If any of them
    // reached the public payload, this test would see it.
    final withPrivateData = TreeItem(
      game: const Game(igdbId: 113112, title: 'Hades', coverUrl: 'c'),
      entry: const Entry(
        igdbId: 113112,
        ownership: Ownership.owned,
        progress: Progress.finished,
        rating: 5,
        note: 'loved the narration', // must NOT publish
        recommendedBy: 'Priya', // a real person -- must NOT publish
      ),
      copies: const [Copy(igdbId: 113112, platform: Platform.pc,
          form: Form.digital, acquired: Acquired.bought)],
    );

    test('published payload carries only title, cover, status, rating, branch',
        () {
      final published = toPublished([withPrivateData], 'Metroidvanias').single;

      expect(published.title, 'Hades');
      expect(published.coverUrl, 'c');
      expect(published.status, Progress.finished);
      expect(published.rating, 5);
      expect(published.branchName, 'Metroidvanias');

      // PublishedGame has no field for recommendedBy or note -- assert the type
      // itself cannot express them, so a stray name has nowhere to live.
      final fields = published.toString();
      expect(fields.contains('Priya'), isFalse,
          reason: 'recommendedBy leaked into the public payload');
      expect(fields.contains('loved the narration'), isFalse,
          reason: 'note leaked into the public payload');
    });

    test('seeds are never published (spotted, not owned, often recommended)',
        () {
      final seed = TreeItem(
        game: const Game(igdbId: 1, title: 'Pentiment'),
        entry: const Entry(
          igdbId: 1,
          ownership: Ownership.spotted,
          progress: Progress.untouched,
          recommendedBy: 'a friend',
        ),
        copies: const [],
      );
      expect(toPublished([seed], 'Cozy'), isEmpty);
    });
  });
}
