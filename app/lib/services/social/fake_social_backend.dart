// A complete, in-memory SocialBackend. No network, no Supabase.
//
// This is not a stub that throws "not implemented" -- it genuinely publishes,
// stores, reads back, reacts and follows, all in RAM. That is what lets the
// whole community UI (publish consent, the visitor page, reactions, follows) be
// built and tested before the real project exists, and it is the reference the
// Supabase implementation's contract tests hold BOTH implementations to, so the
// two cannot drift.
//
// It is also the app's real local-only mode: with no backend configured, the
// app still runs, and publishing simply stays on the device.

import 'social_backend.dart';

/// The shared in-memory "server" every FakeSocialBackend instance talks to.
///
/// Separating this from the client is what makes the fake honest: a real
/// backend is one store that many clients reach, so an owner who publishes on
/// their phone and a stranger who reads on theirs are two clients over one
/// store. Keeping the store on the client instead would let "owner publishes"
/// and "visitor reads" silently miss each other -- exactly the bug the first
/// version had. Tests share one store; construct a fresh store per test for
/// isolation.
class FakeSocialStore {
  // Keyed by handle. A published tree that has been taken private is REMOVED,
  // not flagged -- treeByHandle then throws notFound, which is what a visitor to
  // an unpublished link should meet.
  final Map<String, PublishedTree> trees = {};
  final Map<String, List<TreeReaction>> reactions = {};
  // Follows are per-follower: profileId -> set of handles.
  final Map<String, Set<String>> follows = {};
}

class FakeSocialBackend implements SocialBackend {
  FakeSocialBackend({
    SocialProfile? signedInAs,
    bool configured = true,
    FakeSocialStore? store,
  })  : _profile = signedInAs,
        _configured = configured,
        _store = store ?? _shared;

  /// The default store, shared across instances built without an explicit one,
  /// so `FakeSocialBackend(signedInAs: owner)` and a bare `FakeSocialBackend()`
  /// visitor see the same published trees -- one process, many clients.
  static final FakeSocialStore _shared = FakeSocialStore();

  /// Reset the default shared store. Call in test setUp so state does not leak
  /// between tests that both use the default store.
  static void resetShared() {
    _shared.trees.clear();
    _shared.reactions.clear();
    _shared.follows.clear();
  }

  SocialProfile? _profile;
  final bool _configured;
  final FakeSocialStore _store;

  @override
  SocialProfile? get currentProfile => _profile;

  @override
  bool get isConfigured => _configured;

  SocialProfile _requireSignedIn() {
    final p = _profile;
    if (p == null) {
      throw const SocialException(
          SocialFailure.unauthorized, 'sign in to do this');
    }
    return p;
  }

  @override
  Future<SocialProfile> signIn() async {
    if (!_configured) {
      throw const SocialException(SocialFailure.notConfigured);
    }
    _profile ??= const SocialProfile(
      id: 'local-me',
      handle: 'you',
      displayName: 'You',
      avatarSeed: 'you',
    );
    return _profile!;
  }

  @override
  Future<void> signOut() async {
    _profile = null;
  }

  @override
  Future<void> publish({
    required List<PublishedGame> games,
    required int level,
    required bool isPublic,
  }) async {
    final me = _requireSignedIn();
    if (!isPublic) {
      // Unpublish: the link goes dead. Reactions on it are dropped with it.
      _store.trees.remove(me.handle);
      _store.reactions.remove(me.handle);
      return;
    }
    _store.trees[me.handle] = PublishedTree(
      owner: me,
      games: List.unmodifiable(games),
      publishedAt: DateTime.now(),
      level: level,
    );
  }

  @override
  Future<PublishedTree> treeByHandle(String handle) async {
    final t = _store.trees[handle];
    if (t == null) {
      throw SocialException(SocialFailure.notFound, 'no public tree for $handle');
    }
    return t;
  }

  @override
  Future<void> react(String handle, ReactionKind kind) async {
    final me = _requireSignedIn();
    if (!_store.trees.containsKey(handle)) {
      throw SocialException(SocialFailure.notFound, handle);
    }
    final list = _store.reactions.putIfAbsent(handle, () => []);
    // One reaction of each kind per visitor: react again to CHANGE it, not to
    // stack duplicates. A second admire from the same person is not two admires.
    list.removeWhere((r) => r.fromProfileId == me.id && r.kind == kind);
    list.add(TreeReaction(
        treeHandle: handle, fromProfileId: me.id, kind: kind));
  }

  @override
  Future<List<TreeReaction>> reactionsFor(String handle) async =>
      List.unmodifiable(_store.reactions[handle] ?? const []);

  @override
  Future<void> setFollowing(String handle, bool following) async {
    final me = _requireSignedIn();
    final mine = _store.follows.putIfAbsent(me.id, () => {});
    if (following) {
      mine.add(handle);
    } else {
      mine.remove(handle);
    }
  }

  @override
  Future<List<String>> following() async {
    final me = _requireSignedIn();
    return List.unmodifiable(_store.follows[me.id] ?? const {});
  }
}
