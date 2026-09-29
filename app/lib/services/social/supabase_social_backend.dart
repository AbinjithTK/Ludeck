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

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/enums.dart';
import 'social_backend.dart';

/// A signed-in user's public handle. MUST match `public.handle_for` in
/// migration 0002, which creates the profile row with it: 'g' plus the first
/// ten hex digits of the user id. 11 chars of [a-z0-9], inside 0001's
/// `^[a-z0-9_]{3,30}$` check.
String handleFor(String userId) =>
    'g${userId.replaceAll('-', '').toLowerCase().substring(0, 10)}';

class SupabaseSocialBackend implements SocialBackend {
  SupabaseSocialBackend(this._client) {
    // One subscription for the backend's life. It is how a sign-in that lands
    // late (a Google redirect, a link opened from an email) still reaches the
    // screen waiting for it, and how a failed hand-off becomes a message
    // rather than a silent nothing.
    _client.auth.onAuthStateChange.listen(_onAuth, onError: _onAuthError);
    // A session saved from last time: read the row in the background so
    // currentProfile shows the chosen ID, not the derived 'g...' one (seen on
    // device 2026-09-29: Settings said @g08c8ee8795 for @aabi). Nothing waits
    // on it, so launch never waits on the network; offline, the derived
    // profile simply stands until the next read.
    if (_client.auth.currentUser != null) {
      refreshMyProfile().then((_) {}, onError: (Object _) {});
    }
  }

  /// Initialise Supabase and return a wired backend. Call once at startup only
  /// when a URL + publishable key are configured; otherwise the app runs
  /// local-only on the fake. The publishable key is a PUBLIC client key (RLS is
  /// the real boundary), so it is safe in the app; no service-role key ever
  /// ships.
  static Future<SupabaseSocialBackend> connect({
    required String url,
    required String publishableKey,
  }) async {
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      // PKCE, named rather than left to the default: the code verifier stays
      // on this phone and the redirect carries only a one-time code, which is
      // what makes the sign-in return to the app safely. The SDK's own
      // deep-link handler exchanges the code (detectSessionInUri).
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    return SupabaseSocialBackend(Supabase.instance.client);
  }

  final SupabaseClient _client;

  /// The caller's own profile row, once read. See [currentProfile].
  SocialProfile? _me;

  final StreamController<SocialAuthEvent> _auth =
      StreamController<SocialAuthEvent>.broadcast();

  @override
  Stream<SocialAuthEvent> get authChanges => _auth.stream;

  @override
  SignInMethod? get signInMethod {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return SignInMethod(
      provider: (user.appMetadata['provider'] as String?) ?? 'email',
      email: user.email,
    );
  }

  Future<void> _onAuth(AuthState s) async {
    switch (s.event) {
      case AuthChangeEvent.signedIn:
        // Read the row first, so a listener knows whether onboarding is done.
        SocialProfile? p;
        try {
          p = await refreshMyProfile();
        } catch (_) {
          p = currentProfile;
        }
        _auth.add(SocialAuthEvent(SocialAuthKind.signedIn, profile: p));
      case AuthChangeEvent.signedOut:
        _me = null;
        _auth.add(const SocialAuthEvent(SocialAuthKind.signedOut));
      case AuthChangeEvent.passwordRecovery:
        _auth.add(const SocialAuthEvent(SocialAuthKind.passwordRecovery));
      default:
        break;
    }
  }

  void _onAuthError(Object e) {
    _auth.add(SocialAuthEvent(SocialAuthKind.failed, message: _authFailureText(e)));
  }

  /// Plain words for a sign-in that came back broken.
  static String _authFailureText(Object e) {
    final code = e is AuthException ? e.code : null;
    final msg = e is AuthException ? e.message.toLowerCase() : '';
    if (code == 'bad_oauth_state' || msg.contains('state')) {
      return 'Google sign-in took too long. Try again.';
    }
    // Supabase could not trade Google's code for a session: the Google
    // client secret or redirect on the server side is wrong. Retrying from
    // the phone cannot fix that, so say so and point at email.
    if (msg.contains('exchange external code')) {
      return "Google sign-in isn't working on our side right now. Use email "
          'for now.';
    }
    if (code == 'otp_expired' || msg.contains('expired')) {
      return 'That link has expired. Ask for a new one.';
    }
    return "Sign-in didn't finish. Try again.";
  }

  @override
  bool get isConfigured => true;

  @override
  SocialProfile? get currentProfile {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    // The server's row wins once it has been read: onboarding replaces the
    // derived ID, and only the row knows that.
    final cached = _me;
    if (cached != null && cached.id == user.id) return cached;
    // Until then, the profile row is created by migration 0002's trigger with
    // exactly these values, so the session alone is enough to know them.
    final meta = user.userMetadata ?? const {};
    final name = (meta['full_name'] as String?) ?? (meta['name'] as String?);
    return SocialProfile(
      id: user.id,
      handle: handleFor(user.id),
      displayName: (name == null || name.isEmpty) ? 'Gardener' : name,
      avatarSeed: meta['avatar_seed'] as String?,
    );
  }

  /// Where Google and every auth email send the person back to. Must be listed
  /// under Authentication > URL Configuration > Redirect URLs in Supabase, and
  /// is caught by the VIEW intent filter in AndroidManifest.xml.
  static const redirectUrl = 'com.ludeck.android://login-callback';

  /// GoTrue's error codes, sorted into what the screen can say about them.
  static SocialFailure _authFailure(AuthException e) {
    if (e is AuthRetryableFetchException) return SocialFailure.offline;
    if (e.statusCode == '429') return SocialFailure.rateLimited;
    return switch (e.code) {
      'invalid_credentials' || 'user_not_found' => SocialFailure.unauthorized,
      'email_not_confirmed' => SocialFailure.emailNotConfirmed,
      'user_already_exists' || 'email_exists' => SocialFailure.conflict,
      'weak_password' ||
      'email_address_invalid' ||
      'validation_failed' ||
      'same_password' =>
        SocialFailure.invalid,
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' =>
        SocialFailure.rateLimited,
      // The project's built-in mailer only sends to its own team until a
      // custom SMTP server is set; sign-up is also refused when disabled.
      'email_address_not_authorized' || 'signup_disabled' =>
        SocialFailure.forbidden,
      _ => SocialFailure.unauthorized,
    };
  }

  Never _rethrow(Object e) {
    if (e is SocialException) throw e;
    if (e is AuthException) {
      throw SocialException(_authFailure(e), e.code ?? e.message);
    }
    if (e is PostgrestException) {
      // PGRST116 == no rows where one was expected -> notFound.
      switch (e.code) {
        case 'PGRST116':
          throw const SocialException(SocialFailure.notFound);
        // unique_violation: the ID is taken.
        case '23505':
          throw SocialException(SocialFailure.conflict, e.message);
        // check_violation, string too long, not-null: the value itself.
        case '23514' || '22001' || '23502':
          throw SocialException(SocialFailure.invalid, e.message);
        // RLS refusal or a trigger's 'cannot follow' / 'only status may change'.
        case '42501':
          throw SocialException(SocialFailure.forbidden, e.message);
        // delete_my_account and friends raise this when signed out.
        case '28000':
          throw SocialException(SocialFailure.unauthorized, e.message);
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
    final existing = currentProfile;
    if (existing != null) return existing;
    try {
      // OAuth opens a browser tab and returns immediately. The session arrives
      // later, when Google redirects to [redirectUrl] and the SDK exchanges the
      // PKCE code, so wait for the outcome on [authChanges]: a sign-in, or a
      // failure such as Google's hand-off expiring (bad_oauth_state, seen on
      // 2026-09-28 after an eight-minute pause). The wait is generous because a
      // person may stop to pick an account or type a password; the screen
      // offers Cancel, and a late sign-in still lands through the stream.
      final outcome = authChanges
          .firstWhere((e) =>
              e.kind == SocialAuthKind.signedIn || e.kind == SocialAuthKind.failed)
          .timeout(const Duration(minutes: 10));
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      if (!launched) {
        throw const SocialException(SocialFailure.unauthorized, 'no browser');
      }
      final e = await outcome;
      if (e.kind == SocialAuthKind.failed) {
        throw SocialException(SocialFailure.unauthorized, e.message);
      }
      final p = e.profile ?? currentProfile;
      if (p == null) throw const SocialException(SocialFailure.unauthorized);
      return p;
    } on TimeoutException {
      throw const SocialException(
          SocialFailure.unauthorized, 'sign-in not finished');
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<SocialProfile> signInWithEmail(String email, String password) async {
    try {
      await _client.auth
          .signInWithPassword(email: email.trim(), password: password);
      return (await refreshMyProfile())!;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<SignUpOutcome> signUpWithEmail(String email, String password) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: redirectUrl,
      );
      // With confirmations on, an email that already has an account comes
      // back as a user with no identities and no session, by design, so the
      // endpoint cannot be used to test who has signed up. Say so plainly
      // here: the person asking owns the phone, not a list of emails.
      if (res.session == null && (res.user?.identities?.isEmpty ?? false)) {
        throw const SocialException(SocialFailure.conflict, 'email');
      }
      if (res.session == null) return SignUpOutcome.checkEmail;
      await refreshMyProfile();
      return SignUpOutcome.signedIn;
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> resendConfirmation(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: redirectUrl,
      );
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth
          .resetPasswordForEmail(email.trim(), redirectTo: redirectUrl);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> setNewPassword(String password) async {
    _requireUid();
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> deleteAccount() async {
    _requireUid();
    try {
      // migration 0002: deletes the caller's auth user; the schema cascades
      // profile, published tree and games, reactions and follows.
      await _client.rpc('delete_my_account');
      _me = null;
      await _client.auth.signOut();
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> signOut() async {
    _me = null;
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
  Future<FollowState> setFollowing(String handle, bool following) async {
    final uid = _requireUid();
    try {
      final owner = await _ownerIdForHandle(handle);
      if (!following) {
        await _client
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('tree_owner_id', owner);
        return FollowState.none;
      }
      // The status sent here is ignored: 0003's trigger sets it from the
      // target's privacy, so read back what the server decided.
      final row = await _client
          .from('follows')
          .upsert({'follower_id': uid, 'tree_owner_id': owner})
          .select('status')
          .single();
      return FollowState.parse(row['status'] as String?);
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

  // ---- Profile ------------------------------------------------------------

  static const _profileCols =
      'id, handle, display_name, avatar_seed, bio, platforms, is_private, onboarded';

  static SocialProfile _profileFrom(Map row) => SocialProfile(
        id: row['id'] as String,
        handle: row['handle'] as String,
        displayName: row['display_name'] as String,
        avatarSeed: row['avatar_seed'] as String?,
        bio: (row['bio'] as String?) ?? '',
        platforms: [
          for (final p in (row['platforms'] as List?) ?? const []) p as String,
        ],
        isPrivate: (row['is_private'] as bool?) ?? false,
        onboarded: (row['onboarded'] as bool?) ?? false,
      );

  @override
  Future<SocialProfile?> refreshMyProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return _me = null;
    try {
      final row =
          await _client.from('profiles').select(_profileCols).eq('id', uid).single();
      return _me = _profileFrom(row);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<SocialProfile> updateProfile(ProfileEdit edit) async {
    final uid = _requireUid();
    if (edit.isEmpty) return (await refreshMyProfile())!;
    try {
      final row = await _client
          .from('profiles')
          .update({
            if (edit.handle != null) 'handle': normalizeHandle(edit.handle!),
            if (edit.displayName != null)
              'display_name': edit.displayName!.trim(),
            if (edit.avatarSeed != null) 'avatar_seed': edit.avatarSeed,
            if (edit.bio != null) 'bio': edit.bio,
            if (edit.platforms != null) 'platforms': edit.platforms,
            if (edit.isPrivate != null) 'is_private': edit.isPrivate,
            if (edit.onboarded != null) 'onboarded': edit.onboarded,
          })
          .eq('id', uid)
          .select(_profileCols)
          .single();
      return _me = _profileFrom(row);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<bool> isHandleAvailable(String handle) async {
    // Skip the round trip for an ID that cannot be valid.
    if (!handleLooksValid(handle)) return false;
    try {
      final free = await _client.rpc('handle_available',
          params: {'candidate': normalizeHandle(handle)});
      return free == true;
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- People -------------------------------------------------------------

  static SocialPerson _personFromSearch(Map r) => SocialPerson(
        profile: SocialProfile(
          id: r['id'] as String,
          handle: r['handle'] as String,
          displayName: r['display_name'] as String,
          avatarSeed: r['avatar_seed'] as String?,
          isPrivate: (r['is_private'] as bool?) ?? false,
        ),
        iFollow: FollowState.parse(r['i_follow'] as String?),
        followsMe: (r['follows_me'] as bool?) ?? false,
      );

  Future<List<SocialPerson>> _search(String query) async {
    final rows =
        await _client.rpc('search_profiles', params: {'q': query}) as List;
    return [for (final r in rows) _personFromSearch(r as Map)];
  }

  @override
  Future<List<SocialPerson>> searchPeople(String query) async {
    if (normalizeHandle(query).length < 2) return const [];
    try {
      return await _search(query);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<SocialPerson> personByHandle(String handle) async {
    final h = normalizeHandle(handle);
    final me = currentProfile;
    try {
      // The profile row carries bio and platforms; the search RPC carries the
      // relationship and is the only read that knows about blocks. Both run
      // at once.
      final rowF = _client
          .from('profiles')
          .select(_profileCols)
          .eq('handle', h)
          .maybeSingle();
      final isMe = me != null && me.handle == h;
      final searchF = isMe ? Future.value(<SocialPerson>[]) : _search(h);
      final row = await rowF;
      final hits = await searchF;
      if (row == null) throw SocialException(SocialFailure.notFound, h);
      final profile = _profileFrom(row);
      if (me != null && profile.id == me.id) return SocialPerson(profile: profile);
      final hit = hits.where((p) => p.profile.id == profile.id);
      // Missing from search means a block stands between you.
      if (hit.isEmpty) throw SocialException(SocialFailure.notFound, h);
      return SocialPerson(
          profile: profile,
          iFollow: hit.first.iFollow,
          followsMe: hit.first.followsMe);
    } catch (e) {
      _rethrow(e);
    }
  }

  /// Both directions of the caller's follow graph, fetched together.
  Future<({List<(SocialProfile, FollowState)> out, List<(SocialProfile, FollowState)> inc})>
      _graph(String uid) async {
    final rows = await Future.wait([
      _client
          .from('follows')
          .select('status, profile:profiles!follows_tree_owner_id_fkey($_profileCols)')
          .eq('follower_id', uid)
          .order('created_at', ascending: false),
      _client
          .from('follows')
          .select('status, profile:profiles!follows_follower_id_fkey($_profileCols)')
          .eq('tree_owner_id', uid)
          .order('created_at', ascending: false),
    ]);
    List<(SocialProfile, FollowState)> parse(List list) => [
          for (final r in list)
            if (r['profile'] != null)
              (
                _profileFrom(r['profile'] as Map),
                FollowState.parse(r['status'] as String?)
              ),
        ];
    return (out: parse(rows[0]), inc: parse(rows[1]));
  }

  @override
  Future<List<SocialPerson>> followingPeople() async {
    final uid = _requireUid();
    try {
      final g = await _graph(uid);
      final fans = {
        for (final (p, s) in g.inc)
          if (s == FollowState.accepted) p.id,
      };
      return [
        for (final (p, s) in g.out)
          SocialPerson(profile: p, iFollow: s, followsMe: fans.contains(p.id)),
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  Future<List<SocialPerson>> _incoming(FollowState want) async {
    final uid = _requireUid();
    try {
      final g = await _graph(uid);
      final mine = {for (final (p, s) in g.out) p.id: s};
      return [
        for (final (p, s) in g.inc)
          if (s == want)
            SocialPerson(
              profile: p,
              iFollow: mine[p.id] ?? FollowState.none,
              followsMe: s == FollowState.accepted,
            ),
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<SocialPerson>> followers() => _incoming(FollowState.accepted);

  @override
  Future<List<SocialPerson>> followRequests() => _incoming(FollowState.pending);

  @override
  Future<void> respondToFollowRequest(String handle,
      {required bool accept}) async {
    _requireUid();
    try {
      final follower = await _ownerIdForHandle(handle);
      await _client.rpc('respond_follow_request',
          params: {'follower': follower, 'accept': accept});
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> removeFollower(String handle) async {
    final uid = _requireUid();
    try {
      final them = await _ownerIdForHandle(handle);
      await _client
          .from('follows')
          .delete()
          .eq('follower_id', them)
          .eq('tree_owner_id', uid);
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Quiet feed ---------------------------------------------------------

  @override
  Future<void> postActivity({
    required ActivityKind kind,
    required int igdbId,
    required String title,
    String? coverUrl,
    int? rating,
  }) async {
    final uid = _requireUid();
    try {
      await _client.from('activity').insert({
        'actor_id': uid,
        'kind': kind.name,
        'igdb_id': igdbId,
        'title': title,
        'cover_url': coverUrl,
        'rating': rating,
      });
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<ActivityItem>> friendsActivity({
    Duration window = const Duration(days: 14),
  }) async {
    _requireUid();
    try {
      final since = DateTime.now().toUtc().subtract(window).toIso8601String();
      final rows = await _client
          .rpc('friends_activity', params: {'since': since}) as List;
      if (rows.isEmpty) return const [];
      // Actors in one extra read rather than an embed on the RPC, which keeps
      // the function's return type plain.
      final ids = {for (final r in rows) r['actor_id'] as String}.toList();
      final profiles = await _client
          .from('profiles')
          .select(_profileCols)
          .inFilter('id', ids);
      final byId = {
        for (final p in profiles as List) p['id'] as String: _profileFrom(p as Map),
      };
      return [
        for (final r in rows)
          if (byId[r['actor_id']] != null &&
              ActivityKind.values.any((k) => k.name == r['kind']))
            ActivityItem(
              id: r['id'] as int,
              actor: byId[r['actor_id']]!,
              kind: ActivityKind.values.byName(r['kind'] as String),
              igdbId: r['igdb_id'] as int,
              title: r['title'] as String,
              coverUrl: r['cover_url'] as String?,
              rating: r['rating'] as int?,
              at: DateTime.parse(r['created_at'] as String),
            ),
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Hypes --------------------------------------------------------------

  @override
  Future<void> setHype(String handle, int igdbId, bool hyped) async {
    final uid = _requireUid();
    try {
      final owner = await _ownerIdForHandle(handle);
      if (hyped) {
        // DO NOTHING on a repeat, so a double tap does not notify twice.
        await _client.from('hypes').upsert(
          {'from_id': uid, 'owner_id': owner, 'igdb_id': igdbId},
          ignoreDuplicates: true,
        );
      } else {
        await _client
            .from('hypes')
            .delete()
            .eq('from_id', uid)
            .eq('owner_id', owner)
            .eq('igdb_id', igdbId);
      }
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<Set<int>> myHypesOn(String handle) async {
    final uid = _requireUid();
    try {
      final owner = await _ownerIdForHandle(handle);
      final rows = await _client
          .from('hypes')
          .select('igdb_id')
          .eq('from_id', uid)
          .eq('owner_id', owner);
      return {for (final r in rows as List) r['igdb_id'] as int};
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<Hype>> hypesOnMyTree() async {
    final uid = _requireUid();
    try {
      final rows = await _client
          .from('hypes')
          .select('igdb_id, created_at, giver:profiles!hypes_from_id_fkey($_profileCols)')
          .eq('owner_id', uid)
          .order('created_at', ascending: false);
      return [
        for (final r in rows as List)
          if (r['giver'] != null)
            Hype(
              from: _profileFrom(r['giver'] as Map),
              igdbId: r['igdb_id'] as int,
              at: DateTime.parse(r['created_at'] as String),
            ),
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Seeds --------------------------------------------------------------

  static const _recCols = 'id, igdb_id, title, cover_url, message, status, created_at, '
      'sender:profiles!recommendations_from_id_fkey($_profileCols), '
      'recipient:profiles!recommendations_to_id_fkey($_profileCols)';

  static Recommendation? _recFrom(Map r) {
    if (r['sender'] == null || r['recipient'] == null) return null;
    final status = RecommendationStatus.values
        .where((s) => s.name == r['status'])
        .firstOrNull;
    return Recommendation(
      id: r['id'] as int,
      from: _profileFrom(r['sender'] as Map),
      to: _profileFrom(r['recipient'] as Map),
      igdbId: r['igdb_id'] as int,
      title: r['title'] as String,
      coverUrl: r['cover_url'] as String?,
      message: (r['message'] as String?) ?? '',
      status: status ?? RecommendationStatus.sent,
      at: DateTime.parse(r['created_at'] as String),
    );
  }

  @override
  Future<void> recommend({
    required String toHandle,
    required int igdbId,
    required String title,
    String? coverUrl,
    String message = '',
  }) async {
    final uid = _requireUid();
    try {
      final to = await _ownerIdForHandle(toHandle);
      await _client.from('recommendations').insert({
        'from_id': uid,
        'to_id': to,
        'igdb_id': igdbId,
        'title': title,
        'cover_url': coverUrl,
        'message': message,
      });
    } catch (e) {
      _rethrow(e);
    }
  }

  Future<List<Recommendation>> _recs(String column) async {
    final uid = _requireUid();
    try {
      final rows = await _client
          .from('recommendations')
          .select(_recCols)
          .eq(column, uid)
          .order('created_at', ascending: false);
      return [for (final r in rows as List) ?_recFrom(r as Map)];
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<Recommendation>> recommendationsInbox() => _recs('to_id');

  @override
  Future<List<Recommendation>> recommendationsSent() => _recs('from_id');

  @override
  Future<void> setRecommendationStatus(
      int id, RecommendationStatus status) async {
    final uid = _requireUid();
    try {
      final rows = await _client
          .from('recommendations')
          .update({'status': status.name})
          .eq('id', id)
          .eq('to_id', uid)
          .select('id');
      // RLS hides a row you may not change, so zero rows is "not yours".
      if ((rows as List).isEmpty) {
        throw SocialException(SocialFailure.notFound, 'seed $id');
      }
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Notifications ------------------------------------------------------

  @override
  Future<List<SocialNotification>> notifications() async {
    final uid = _requireUid();
    try {
      final rows = await _client
          .from('notifications')
          .select('id, kind, igdb_id, ref_id, read_at, created_at, '
              'actor:profiles!notifications_actor_id_fkey($_profileCols)')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      return [
        for (final r in rows as List)
          if (r['actor'] != null && NotificationKind.parse(r['kind'] as String) != null)
            SocialNotification(
              id: r['id'] as int,
              kind: NotificationKind.parse(r['kind'] as String)!,
              actor: _profileFrom(r['actor'] as Map),
              igdbId: r['igdb_id'] as int?,
              refId: r['ref_id'] as int?,
              readAt: r['read_at'] == null
                  ? null
                  : DateTime.parse(r['read_at'] as String),
              at: DateTime.parse(r['created_at'] as String),
            ),
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<int> unreadNotificationCount() async {
    final uid = _requireUid();
    try {
      return await _client
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', uid)
          .isFilter('read_at', null);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> markNotificationsRead() async {
    final uid = _requireUid();
    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', uid)
          .isFilter('read_at', null);
    } catch (e) {
      _rethrow(e);
    }
  }

  // ---- Safety -------------------------------------------------------------

  @override
  Future<void> block(String handle) async {
    final uid = _requireUid();
    try {
      final them = await _ownerIdForHandle(handle);
      await _client.from('blocks').upsert(
        {'blocker_id': uid, 'blocked_id': them},
        ignoreDuplicates: true,
      );
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> unblock(String handle) async {
    final uid = _requireUid();
    try {
      final them = await _ownerIdForHandle(handle);
      await _client
          .from('blocks')
          .delete()
          .eq('blocker_id', uid)
          .eq('blocked_id', them);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<List<SocialProfile>> blockedPeople() async {
    final uid = _requireUid();
    try {
      final rows = await _client
          .from('blocks')
          .select('profile:profiles!blocks_blocked_id_fkey($_profileCols)')
          .eq('blocker_id', uid)
          .order('created_at', ascending: false);
      return [
        for (final r in rows as List)
          if (r['profile'] != null) _profileFrom(r['profile'] as Map),
      ];
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> report(String handle, ReportReason reason,
      {String details = ''}) async {
    final uid = _requireUid();
    try {
      final them = await _ownerIdForHandle(handle);
      await _client.from('reports').insert({
        'reporter_id': uid,
        'target_id': them,
        'reason': reason.name,
        'details': details,
      });
    } catch (e) {
      _rethrow(e);
    }
  }

  Future<String> _ownerIdForHandle(String handle) async {
    final row = await _client
        .from('profiles')
        .select('id')
        .eq('handle', normalizeHandle(handle))
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
