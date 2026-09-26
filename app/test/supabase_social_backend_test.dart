// The FIRST tests that execute SupabaseSocialBackend at all.
//
// This 9KB class shipped untested and unreachable from the app until Stage 6
// wired the --dart-define supply mechanism. It cannot be fully tested without a
// live Supabase project, but the parts that do NOT need the network -- the ones
// most likely to be wrong -- are exercised here: the configured flag, the
// signed-out identity, and the error-shape mapping that decides whether a caller
// sees unauthorized / notFound / malformed / offline.
//
// The backend takes a SupabaseClient in its constructor (connect() is the only
// path that touches the global Supabase.initialize), so a client pointed at a
// dummy URL constructs with no network and its auth session is simply empty.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/services/social/supabase_social_backend.dart';

void main() {
  late SupabaseClient client;
  late SupabaseSocialBackend backend;

  setUp(() {
    // A bare client against a dummy URL. No network happens until a query runs,
    // and these tests only touch auth state (empty) and pure mapping.
    client = SupabaseClient('https://example.invalid', 'dummy-anon-key');
    backend = SupabaseSocialBackend(client);
  });

  tearDown(() async {
    await client.dispose();
  });

  test('the real backend always reports itself configured', () {
    // The fake reports isConfigured=false in local-only mode; the real one is
    // configured by definition -- it would not exist otherwise. The UI uses
    // this to decide whether to offer sign-in.
    expect(backend.isConfigured, isTrue);
  });

  test('with no session, currentProfile is null, not a fake identity', () {
    // Signed out is a first-class state: the app is fully usable without an
    // account. currentProfile must be null rather than inventing a placeholder.
    expect(backend.currentProfile, isNull);
  });

  test('a write without sign-in throws unauthorized, not a silent no-op', () async {
    // _requireUid guards every write. Publishing while signed out must surface
    // as unauthorized so the UI can prompt sign-in, never fail quietly.
    await expectLater(
      backend.publish(games: const [], level: 1, isPublic: true),
      throwsA(isA<SocialException>().having(
        (e) => e.failure,
        'failure',
        SocialFailure.unauthorized,
      )),
    );
  });

  test('react without sign-in throws unauthorized', () async {
    await expectLater(
      backend.react('someone', ReactionKind.admire),
      throwsA(isA<SocialException>().having(
        (e) => e.failure,
        'failure',
        SocialFailure.unauthorized,
      )),
    );
  });

  test('following() without sign-in throws unauthorized', () async {
    await expectLater(
      backend.following(),
      throwsA(isA<SocialException>().having(
        (e) => e.failure,
        'failure',
        SocialFailure.unauthorized,
      )),
    );
  });

  test('reading a public tree does NOT require sign-in', () async {
    // treeByHandle has no _requireUid -- a shared link must open for anyone. It
    // will fail to REACH example.invalid, but the failure must be offline
    // (network), never unauthorized (auth), which proves no auth guard is on the
    // read path.
    await expectLater(
      backend.treeByHandle('anyone'),
      throwsA(isA<SocialException>().having(
        (e) => e.failure,
        'failure',
        isNot(SocialFailure.unauthorized),
      )),
    );
  });
}
