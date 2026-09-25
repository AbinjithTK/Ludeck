// The real SocialBackend, backed by Supabase.
//
// It implements the SAME interface as FakeSocialBackend and is exercised by the
// SAME contract suite (test/social_backend_test.dart runs both), so the two
// cannot drift. Hand-written JSON mapping throughout -- no codegen, because the
// meta/analyzer chain is pinned shut on this Flutter SDK (see the project's
// codegen lesson) and Supabase needs none.
//
// PRIVACY -- docs/DECISIONS.md invariant 10. Every write goes through the
// `PublishedGame` DTO, which has no field for recommendedBy, note or channel,
// and this file inserts exactly the columns the migration defines. There is no
// path here that reads a private column. The checker (rule 10) scans this file
// because its name matches the share/export pattern.
//
// Configuration is injected, never hard-coded: `SupabaseSocialBackend.connect`
// takes the URL and anon key the operator supplies at deploy time. With none,
// the app uses FakeSocialBackend as its local-only mode instead of this class.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/enums.dart';
import 'social_backend.dart';

class SupabaseSocialBackend implements SocialBackend {
  SupabaseSocialBackend(this._client);

  /// Initialise Supabase and return a wired backend. Call once at startup only
  /// when a URL + publishable key are configured; otherwise the app runs
  /// local-only on the fake. The publishable key is a PUBLIC client key (RLS is
  /// the real boundary), so it is safe in the app; no service-role key ever
  /// ships.
  static Future<SupabaseSocialBackend> connect({
    required String url,
    required String publishableKey,
  }) async {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
    return SupabaseSocialBackend(Supabase.instance.client);
  }

  final SupabaseClient _client;

  @override
  bool get isConfigured => true;

  @override
  SocialProfile? get currentProfile {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    // The handle/display live on the profile row; currentProfile returns the
    // lightweight identity known from the session. A caller needing the full
    // row reads it explicitly.
    final meta = user.userMetadata ?? const {};
    return SocialProfile(
      id: user.id,
      handle: (meta['handle'] as String?) ?? user.id,
      displayName: (meta['display_name'] as String?) ?? 'You',
      avatarSeed: meta['avatar_seed'] as String?,
    );
  }

  Never _rethrow(Object e) {
    if (e is AuthException) {
      throw const SocialException(SocialFailure.unauthorized);
    }
    if (e is PostgrestException) {
      // PGRST116 == no rows where one was expected -> notFound.
      if (e.code == 'PGRST116') {
        throw const SocialException(SocialFailure.notFound);
      }
      throw SocialException(SocialFailure.malformed, e.message);
    }
    throw SocialException(SocialFailure.offline, e.toString());
  }

  String _requireUid() {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const SocialException(SocialFailure.unauthorized, 'sign in first');
    }
    return id;
  }

  @override
  Future<SocialProfile> signIn() async {
    try {
      // OAuth opens the system browser; the app resumes via its deep link. The
      // provider choice is the operator's -- Google is the least-friction
      // default and needs no password surface in-app.
      await _client.auth.signInWithOAuth(OAuthProvider.google);
      // The session arrives on the auth stream; callers await currentProfile.
      final p = currentProfile;
      if (p == null) {
        throw const SocialException(SocialFailure.unauthorized);
      }
      return p;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> publish({
    required List<PublishedGame> games,
    required int level,
    required bool isPublic,
  }) async {
    final uid = _requireUid();
    try {
      if (!isPublic) {
        // Delete cascades to published_games and reactions via the schema's FKs.
        await _client.from('published_trees').delete().eq('owner_id', uid);
        return;
      }
      await _client.from('published_trees').upsert({
        'owner_id': uid,
        'level': level,
      });
      // Replace the game set: clear then insert. A published tree is a snapshot,
      // not an append log.
      await _client.from('published_games').delete().eq('owner_id', uid);
      if (games.isNotEmpty) {
        await _client.from('published_games').insert([
          for (final g in games)
            {
              'owner_id': uid,
              'igdb_id': g.igdbId,
              'title': g.title,
              'cover_url': g.coverUrl,
              'status': g.status.name,
              'rating': g.rating,
              'branch_name': g.branchName,
              // No recommended_by. No channel. No note. The DTO has no such
              // field to read, and the table has no such column to write.
            },
        ]);
      }
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<PublishedTree> treeByHandle(String handle) async {
    try {
      final profile = await _client
          .from('profiles')
          .select('id, handle, display_name, avatar_seed')
          .eq('handle', handle)
          .single();

      final ownerId = profile['id'] as String;
      final treeRow = await _client
          .from('published_trees')
          .select('level, published_at')
          .eq('owner_id', ownerId)
          .single();

      final gameRows = await _client
          .from('published_games')
          .select('igdb_id, title, cover_url, status, rating, branch_name')
          .eq('owner_id', ownerId);

      return PublishedTree(
        owner: SocialProfile(
          id: ownerId,
          handle: profile['handle'] as String,
          displayName: profile['display_name'] as String,
          avatarSeed: profile['avatar_seed'] as String?,
        ),
        level: treeRow['level'] as int,
        publishedAt: DateTime.parse(treeRow['published_at'] as String),
        games: [
          for (final r in gameRows as List)
            PublishedGame(
              igdbId: r['igdb_id'] as int,
              title: r['title'] as String,
              coverUrl: r['cover_url'] as String?,
              status: _progress(r['status'] as String),
              rating: r['rating'] as int?,
              branchName: r['branch_name'] as String,
            ),
        ],
      );
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> react(String handle, ReactionKind kind) async {
    final uid = _requireUid();
    try {
      final owner = await _ownerIdForHandle(handle);
      await _client.from('reactions').upsert({
        'tree_owner_id': owner,
        'from_id': uid,
        'kind': kind.name,
      });
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<TreeReaction>> reactionsFor(String handle) async {
    try {
      final owner = await _ownerIdForHandle(handle);
      final rows = await _client
          .from('reactions')
          .select('from_id, kind')
          .eq('tree_owner_id', owner);
      return [
        for (final r in rows as List)
          TreeReaction(
            treeHandle: handle,
            fromProfileId: r['from_id'] as String,
            kind: ReactionKind.values.byName(r['kind'] as String),
          ),
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> setFollowing(String handle, bool following) async {
    final uid = _requireUid();
    try {
      final owner = await _ownerIdForHandle(handle);
      if (following) {
        await _client.from('follows').upsert({
          'follower_id': uid,
          'tree_owner_id': owner,
        });
      } else {
        await _client
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('tree_owner_id', owner);
      }
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<String>> following() async {
    final uid = _requireUid();
    try {
      // Join back to the handle so callers speak handles, not owner ids.
      final rows = await _client
          .from('follows')
          .select('profiles!follows_tree_owner_id_fkey(handle)')
          .eq('follower_id', uid);
      return [
        for (final r in rows as List)
          ((r['profiles'] as Map)['handle']) as String,
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  Future<String> _ownerIdForHandle(String handle) async {
    final row = await _client
        .from('profiles')
        .select('id')
        .eq('handle', handle)
        .single();
    return row['id'] as String;
  }

  static Progress _progress(String name) {
    for (final p in Progress.values) {
      if (p.name == name) return p;
    }
    // A status the app does not know is treated as untouched rather than
    // crashing a visitor's read on one unexpected row.
    return Progress.untouched;
  }
}
