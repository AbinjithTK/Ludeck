// resolveSocialBackend's decision, and the supply mechanism it now has.
//
// Stage 6 gave the resolver an actual feed (--dart-define in main.dart). The
// resolver itself is the one place that decides fake-vs-real, so its contract is
// locked here: no config -> the fake in local-only mode (isConfigured false);
// config present -> it attempts the real Supabase path.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_service.dart';

void main() {
  test('no config resolves to the fake, honestly unconfigured', () async {
    final backend = await resolveSocialBackend();
    expect(backend, isA<FakeSocialBackend>());
    expect(backend.isConfigured, isFalse,
        reason: 'local-only mode must say so, not offer a dead sign-in button');
  });

  test('empty strings are treated as absent, not as a real URL', () async {
    // main.dart passes null when a --dart-define is empty, but guard the empty
    // case here too so a blank define can never reach Supabase.initialize.
    final backend = await resolveSocialBackend(
      supabaseUrl: '',
      supabasePublishableKey: '',
    );
    expect(backend, isA<FakeSocialBackend>());
    expect(backend.isConfigured, isFalse);
  });

  test('a URL with no key still falls back rather than half-connecting', () async {
    final backend = await resolveSocialBackend(
      supabaseUrl: 'https://project.supabase.co',
      supabasePublishableKey: null,
    );
    expect(backend, isA<FakeSocialBackend>(),
        reason: 'both halves are required; one alone must not connect');
  });
}
