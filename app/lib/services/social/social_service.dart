// Which SocialBackend actually runs, decided in one place.
//
// Mirrors resolveCatalog in http_catalog.dart: configuration decides whether the
// real (Supabase) or the local-only (fake) implementation is used, and the rest
// of the app depends only on the SocialBackend interface, never on which one it
// got. With no URL/anon key configured the app is fully usable -- it just keeps
// publishing on the device.

import 'fake_social_backend.dart';
import 'social_backend.dart';
import 'supabase_social_backend.dart';

/// Resolve the community backend from configuration.
///
/// [supabaseUrl] and [supabasePublishableKey] come from the operator at deploy
/// time (the same way the IGDB proxy URL is supplied). When either is absent,
/// the app runs on [FakeSocialBackend] in local-only mode -- which is the
/// honest state until the Supabase project exists, not a degraded one.
Future<SocialBackend> resolveSocialBackend({
  String? supabaseUrl,
  String? supabasePublishableKey,
}) async {
  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      supabasePublishableKey == null ||
      supabasePublishableKey.isEmpty) {
    // Local-only: configured=false so the UI can honestly say "sign-in is not
    // available yet" rather than offering a button that cannot work.
    return FakeSocialBackend(configured: false);
  }
  return SupabaseSocialBackend.connect(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
}
