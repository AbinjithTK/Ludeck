// Contract tests for SupabaseSocialBackend's REQUEST SHAPES.
//
// The fake proves the rules; these prove the real client asks the server the
// right thing: the right table or RPC, the right filters, and bodies with
// exactly the columns migration 0003 defines. A typo in a column name or an
// FK hint here is a runtime 400 on a phone, so it is pinned in a test.
//
// No network. The SupabaseClient is given a MockClient that records every
// request and answers with canned PostgREST replies, and a session is restored
// from JSON so `_requireUid` sees a signed-in user without a real sign-in.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/services/social/supabase_social_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = '11111111-2222-3333-4444-555555555555';
const _bobId = '99999999-8888-7777-6666-555555555555';

Map<String, Object?> _profileRow(String id, String handle,
        {bool private = false}) =>
    {
      'id': id,
      'handle': handle,
      'display_name': handle.toUpperCase(),
      'avatar_seed': null,
      'bio': '',
      'platforms': <String>[],
      'is_private': private,
      'onboarded': true,
    };

/// A canned reply: status, JSON body, extra headers.
typedef _Reply = (int, Object?, Map<String, String>);

void main() {
  late List<http.Request> sent;
  late _Reply Function(http.Request) respond;
  late SupabaseClient client;
  late SupabaseSocialBackend backend;

  _Reply ok(Object? body) => (200, body, const {});

  setUp(() async {
    sent = [];
    // Default: any handle lookup resolves to bob.
    respond = (r) {
      if (r.url.path == '/rest/v1/profiles' &&
          r.url.queryParameters['select'] == 'id') {
        return ok({'id': _bobId});
      }
      return ok([]);
    };
    client = SupabaseClient(
      'https://example.invalid',
      'dummy-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((req) async {
        sent.add(req);
        final (status, body, headers) = respond(req);
        return http.Response(body == null ? '' : jsonEncode(body), status,
            request: req,
            headers: {'content-type': 'application/json', ...headers});
      }),
    );
    // A non-JWT token has no expiry, so recoverSession accepts it offline.
    await client.auth.recoverSession(jsonEncode({
      'access_token': 'test-token',
      'token_type': 'bearer',
      'refresh_token': 'r',
      'user': {
        'id': _uid,
        'aud': 'authenticated',
        'role': 'authenticated',
        'app_metadata': {},
        'user_metadata': {'full_name': 'Ada'},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
    backend = SupabaseSocialBackend(client);
  });

  tearDown(() async => client.dispose());

  http.Request only(String method, String path) =>
      sent.singleWhere((r) => r.method == method && r.url.path == path);

  Map<String, dynamic> bodyOf(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  test('signed in from the restored session', () {
    expect(backend.currentProfile!.id, _uid);
  });

  test('a session restored at launch reads the real profile row', () async {
    // A fresh backend over a client that already holds a session: the
    // initial auth event should trigger one profile read.
    respond = (r) => r.url.path == '/rest/v1/profiles'
        ? ok(_profileRow(_uid, 'aabi'))
        : ok([]);
    final fresh = SupabaseSocialBackend(client);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fresh.currentProfile!.handle, 'aabi');
  });

  group('profile', () {
    test('updateProfile PATCHes only the changed columns, then caches the row',
        () async {
      respond = (r) => ok(_profileRow(_uid, 'ada_plays'));
      final saved = await backend.updateProfile(
          const ProfileEdit(handle: '@Ada_Plays', bio: 'hi'));

      final req = only('PATCH', '/rest/v1/profiles');
      expect(req.url.queryParameters['id'], 'eq.$_uid');
      expect(bodyOf(req), {'handle': 'ada_plays', 'bio': 'hi'});
      expect(saved.handle, 'ada_plays');
      // The derived 'g...' ID is replaced by the server's row.
      expect(backend.currentProfile!.handle, 'ada_plays');
    });

    test('a taken ID (23505) is a conflict', () async {
      respond = (r) => (409, {'code': '23505', 'message': 'duplicate key'}, {});
      await expectLater(backend.updateProfile(const ProfileEdit(handle: 'bob')),
          throwsA(isA<SocialException>()
              .having((e) => e.failure, 'f', SocialFailure.conflict)));
    });

    test('a check failure (23514) is invalid', () async {
      respond = (r) => (400, {'code': '23514', 'message': 'check'}, {});
      await expectLater(backend.updateProfile(const ProfileEdit(bio: 'x')),
          throwsA(isA<SocialException>()
              .having((e) => e.failure, 'f', SocialFailure.invalid)));
    });

    test('isHandleAvailable calls the RPC with the normalised ID', () async {
      respond = (r) => ok(true);
      expect(await backend.isHandleAvailable('@Ada'), isTrue);
      expect(bodyOf(only('POST', '/rest/v1/rpc/handle_available')),
          {'candidate': 'ada'});
    });

    test('an ID that cannot be valid is refused without a request', () async {
      expect(await backend.isHandleAvailable('no!'), isFalse);
      expect(sent, isEmpty);
    });
  });

  group('people', () {
    test('searchPeople calls search_profiles and reads the relationship',
        () async {
      respond = (r) => ok([
            {
              'id': _bobId,
              'handle': 'bob',
              'display_name': 'Bob',
              'avatar_seed': null,
              'is_private': true,
              'i_follow': 'pending',
              'follows_me': false,
            }
          ]);
      final hits = await backend.searchPeople('bo');
      expect(bodyOf(only('POST', '/rest/v1/rpc/search_profiles')), {'q': 'bo'});
      expect(hits.single.handle, 'bob');
      expect(hits.single.iFollow, FollowState.pending);
      expect(hits.single.profile.isPrivate, isTrue);
    });

    test('a one-letter search makes no request', () async {
      expect(await backend.searchPeople('b'), isEmpty);
      expect(sent, isEmpty);
    });

    test('setFollowing upserts without a status and returns the server\'s',
        () async {
      respond = (r) => r.url.path == '/rest/v1/follows'
          ? ok({'status': 'pending'})
          : ok({'id': _bobId});
      expect(await backend.setFollowing('bob', true), FollowState.pending);

      final req = only('POST', '/rest/v1/follows');
      expect(bodyOf(req), {'follower_id': _uid, 'tree_owner_id': _bobId});
      expect(req.headers['Prefer'], contains('resolution=merge-duplicates'));
      expect(req.url.queryParameters['select'], 'status');
    });

    test('following lists embed each end by its FK name', () async {
      await backend.followingPeople();
      final selects = [
        for (final r in sent.where((r) => r.url.path == '/rest/v1/follows'))
          r.url.queryParameters['select']!,
      ];
      expect(selects, hasLength(2));
      expect(selects.any((s) => s.contains('profiles!follows_tree_owner_id_fkey')),
          isTrue);
      expect(selects.any((s) => s.contains('profiles!follows_follower_id_fkey')),
          isTrue);
    });

    test('respondToFollowRequest calls the RPC with the follower id', () async {
      await backend.respondToFollowRequest('bob', accept: true);
      expect(bodyOf(only('POST', '/rest/v1/rpc/respond_follow_request')),
          {'follower': _bobId, 'accept': true});
    });

    test('block upserts and ignores a repeat', () async {
      await backend.block('bob');
      final req = only('POST', '/rest/v1/blocks');
      expect(bodyOf(req), {'blocker_id': _uid, 'blocked_id': _bobId});
      expect(req.headers['Prefer'], contains('resolution=ignore-duplicates'));
    });

    test('report sends the reason by name', () async {
      await backend.report('bob', ReportReason.harassment, details: 'dm');
      expect(bodyOf(only('POST', '/rest/v1/reports')), {
        'reporter_id': _uid,
        'target_id': _bobId,
        'reason': 'harassment',
        'details': 'dm',
      });
    });
  });

  group('seeds and hypes', () {
    test('recommend sends exactly the 0003 columns and nothing private',
        () async {
      await backend.recommend(
          toHandle: 'bob',
          igdbId: 5,
          title: 'Balatro',
          coverUrl: 'c',
          message: 'try it');
      expect(bodyOf(only('POST', '/rest/v1/recommendations')), {
        'from_id': _uid,
        'to_id': _bobId,
        'igdb_id': 5,
        'title': 'Balatro',
        'cover_url': 'c',
        'message': 'try it',
      });
    });

    test('a refused seed (42501) is forbidden, not a generic error', () async {
      respond = (r) => r.url.path == '/rest/v1/recommendations'
          ? (403, {'code': '42501', 'message': 'row-level security'}, {})
          : ok({'id': _bobId});
      await expectLater(
          backend.recommend(toHandle: 'bob', igdbId: 5, title: 'Balatro'),
          throwsA(isA<SocialException>()
              .having((e) => e.failure, 'f', SocialFailure.forbidden)));
    });

    test('planting a seed that is not yours is notFound', () async {
      await expectLater(
          backend.setRecommendationStatus(4, RecommendationStatus.planted),
          throwsA(isA<SocialException>()
              .having((e) => e.failure, 'f', SocialFailure.notFound)));
      final req = only('PATCH', '/rest/v1/recommendations');
      expect(bodyOf(req), {'status': 'planted'});
      expect(req.url.queryParameters['to_id'], 'eq.$_uid');
    });

    test('the inbox parses sender and recipient embeds', () async {
      respond = (r) => ok([
            {
              'id': 4,
              'igdb_id': 5,
              'title': 'Balatro',
              'cover_url': null,
              'message': 'try it',
              'status': 'sent',
              'created_at': '2026-09-29T04:00:00Z',
              'sender': _profileRow(_bobId, 'bob'),
              'recipient': _profileRow(_uid, 'ada'),
            }
          ]);
      final inbox = await backend.recommendationsInbox();
      final req = only('GET', '/rest/v1/recommendations');
      expect(req.url.queryParameters['to_id'], 'eq.$_uid');
      expect(req.url.queryParameters['select'],
          contains('sender:profiles!recommendations_from_id_fkey'));
      expect(inbox.single.from.handle, 'bob');
      expect(inbox.single.message, 'try it');
    });

    test('a hype upserts once; a repeat does nothing on the server', () async {
      await backend.setHype('bob', 1, true);
      final req = only('POST', '/rest/v1/hypes');
      expect(bodyOf(req), {'from_id': _uid, 'owner_id': _bobId, 'igdb_id': 1});
      expect(req.headers['Prefer'], contains('resolution=ignore-duplicates'));
    });
  });

  group('feed and notifications', () {
    test('postActivity inserts the actor\'s own event', () async {
      await backend.postActivity(
          kind: ActivityKind.rated, igdbId: 1, title: 'Hades', rating: 5);
      expect(bodyOf(only('POST', '/rest/v1/activity')), {
        'actor_id': _uid,
        'kind': 'rated',
        'igdb_id': 1,
        'title': 'Hades',
        'cover_url': null,
        'rating': 5,
      });
    });

    test('friendsActivity calls the RPC, then loads actors in one read',
        () async {
      respond = (r) {
        if (r.url.path == '/rest/v1/rpc/friends_activity') {
          return ok([
            {
              'id': 3,
              'actor_id': _bobId,
              'kind': 'harvested',
              'igdb_id': 1,
              'title': 'Hades',
              'cover_url': null,
              'rating': null,
              'created_at': '2026-09-29T04:00:00Z',
            },
            // A kind this build does not know is skipped, not a crash.
            {
              'id': 4,
              'actor_id': _bobId,
              'kind': 'someday',
              'igdb_id': 2,
              'title': 'x',
              'created_at': '2026-09-29T04:00:00Z',
            },
          ]);
        }
        return ok([_profileRow(_bobId, 'bob')]);
      };
      final feed = await backend.friendsActivity();
      expect(bodyOf(only('POST', '/rest/v1/rpc/friends_activity')),
          contains('since'));
      final actorRead = sent.singleWhere((r) =>
          r.method == 'GET' &&
          r.url.path == '/rest/v1/profiles' &&
          (r.url.queryParameters['id'] ?? '').startsWith('in.'));
      expect(actorRead.url.queryParameters['id'], 'in.("$_bobId")');
      expect(feed.single.actor.handle, 'bob');
      expect(feed.single.kind, ActivityKind.harvested);
    });

    test('notifications are newest first, capped at 50, own only', () async {
      respond = (r) => ok([
            {
              'id': 9,
              'kind': 'follow_request',
              'igdb_id': null,
              'ref_id': null,
              'read_at': null,
              'created_at': '2026-09-29T04:00:00Z',
              'actor': _profileRow(_bobId, 'bob'),
            },
            {
              'id': 8,
              'kind': 'unknown_kind',
              'created_at': '2026-09-29T03:00:00Z',
              'actor': _profileRow(_bobId, 'bob'),
            },
          ]);
      final list = await backend.notifications();
      final q = only('GET', '/rest/v1/notifications').url.queryParameters;
      expect(q['user_id'], 'eq.$_uid');
      expect(q['order'], startsWith('created_at.desc'));
      expect(q['limit'], '50');
      expect(q['select'], contains('actor:profiles!notifications_actor_id_fkey'));
      expect(list.single.kind, NotificationKind.followRequest);
      expect(list.single.isUnread, isTrue);
    });

    test('markNotificationsRead only touches unread rows', () async {
      await backend.markNotificationsRead();
      final req = only('PATCH', '/rest/v1/notifications');
      expect(req.url.queryParameters['read_at'], 'is.null');
      expect(bodyOf(req).keys, ['read_at']);
    });
  });

  test('signing out clears the cached profile', () async {
    respond = (r) => ok(_profileRow(_uid, 'ada_plays'));
    await backend.refreshMyProfile();
    expect(backend.currentProfile!.handle, 'ada_plays');
    await backend.signOut();
    expect(backend.currentProfile, isNull);
  });
}
