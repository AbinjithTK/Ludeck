// A complete, in-memory SocialBackend. No network, no Supabase.
//
// This is not a stub that throws "not implemented" -- it genuinely publishes,
// stores, reads back, reacts and follows, all in RAM. That is what lets the
// whole community UI (publish consent, the visitor page, reactions, follows) be
// built and tested before the real project exists, and it is the reference the
// Supabase implementation's contract tests hold BOTH implementations to, so the
// two cannot drift.
//
// It mirrors migration 0003's rules, not just its tables: a follow of a private
// profile is pending until accepted, a block cuts follows both ways and hides
// each person from the other, a seed may only go to someone who follows you,
// and notifications are created by the "server" (this store), never passed in.
// When a rule changes in SQL, change it here too, or the UI is tested against
// a server that does not exist.
//
// It is also the app's real local-only mode: with no backend configured, the
// app still runs, and publishing simply stays on the device.

import 'dart:async';

import 'social_backend.dart';

class _FakeNotification {
  _FakeNotification(this.id, this.userId, this.actorId, this.kind,
      {this.igdbId, this.refId});
  final int id;
  final String userId;
  final String actorId;
  final NotificationKind kind;
  final int? igdbId;
  final int? refId;
  DateTime? readAt;
  final DateTime at = DateTime.now();
}

class _FakeRecommendation {
  _FakeRecommendation(this.id, this.fromId, this.toId, this.igdbId, this.title,
      this.coverUrl, this.message);
  final int id;
  final String fromId;
  final String toId;
  final int igdbId;
  final String title;
  final String? coverUrl;
  final String message;
  RecommendationStatus status = RecommendationStatus.sent;
  final DateTime at = DateTime.now();
}

class _FakeActivity {
  _FakeActivity(this.id, this.actorId, this.kind, this.igdbId, this.title,
      this.coverUrl, this.rating);
  final int id;
  final String actorId;
  final ActivityKind kind;
  final int igdbId;
  final String title;
  final String? coverUrl;
  final int? rating;
  final DateTime at = DateTime.now();
}

class _FakeHype {
  _FakeHype(this.fromId, this.ownerId, this.igdbId);
  final String fromId;
  final String ownerId;
  final int igdbId;
  final DateTime at = DateTime.now();
}

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
  // an unpublished link should meet. An ID change re-keys it.
  final Map<String, PublishedTree> trees = {};
  final Map<String, List<TreeReaction>> reactions = {};

  /// Every known account, by id. The profiles table.
  final Map<String, SocialProfile> profiles = {};

  /// follower id -> followee id -> state. Never holds [FollowState.none].
  final Map<String, Map<String, FollowState>> follows = {};

  /// blocker id -> blocked ids.
  final Map<String, Set<String>> blocks = {};

  final List<_FakeHype> _hypes = [];
  final List<_FakeRecommendation> _recommendations = [];
  final List<_FakeActivity> _activity = [];
  final List<_FakeNotification> _notifications = [];

  /// Reports as (reporter id, target id, reason). Write-only from the app.
  final List<(String, String, ReportReason)> reports = [];

  /// Email accounts: email -> (password, profile id, confirmed).
  final Map<String, ({String password, String id, bool confirmed})> accounts =
      {};

  /// Emails a reset link was requested for, oldest first.
  final List<String> resetRequests = [];

  /// Whether a new email account must open its link before it can sign in,
  /// as the live project is configured. Off by default so tests that only
  /// need an account get one in a single step.
  bool requireEmailConfirmation = false;

  int _nextId = 1;
  int nextId() => _nextId++;

  /// How many activity events were posted, by anyone. For tests.
  int get activityCount => _activity.length;

  /// Add a person other tests can find, follow and visit.
  SocialProfile addProfile(SocialProfile p) => profiles[p.id] = p;

  void clear() {
    trees.clear();
    reactions.clear();
    profiles.clear();
    follows.clear();
    blocks.clear();
    _hypes.clear();
    _recommendations.clear();
    _activity.clear();
    _notifications.clear();
    reports.clear();
    accounts.clear();
    resetRequests.clear();
    requireEmailConfirmation = false;
    _nextId = 1;
  }
}

/// Handles the server refuses (migration 0003 `handle_is_reserved`).
const _reservedHandles = {
  'admin', 'ludeck', 'support', 'help', 'official', 'moderator', 'mod',
  'system', 'root', 'me', 'you', 'settings', 'friends', 'orchard', 'null',
};

class FakeSocialBackend implements SocialBackend {
  FakeSocialBackend({
    SocialProfile? signedInAs,
    bool configured = true,
    FakeSocialStore? store,
  })  : _myId = signedInAs?.id,
        _configured = configured,
        _store = store ?? _shared {
    if (signedInAs != null) _store.profiles.putIfAbsent(signedInAs.id, () => signedInAs);
  }

  /// The default store, shared across instances built without an explicit one,
  /// so `FakeSocialBackend(signedInAs: owner)` and a bare `FakeSocialBackend()`
  /// visitor see the same published trees -- one process, many clients.
  static final FakeSocialStore _shared = FakeSocialStore();

  /// The default store, for tests that need to seed other people into it.
  static FakeSocialStore get sharedStore => _shared;

  /// Reset the default shared store. Call in test setUp so state does not leak
  /// between tests that both use the default store.
  static void resetShared() => _shared.clear();

  String? _myId;
  final bool _configured;
  final FakeSocialStore _store;

  @override
  SocialProfile? get currentProfile =>
      _myId == null ? null : _store.profiles[_myId];

  @override
  bool get isConfigured => _configured;

  SocialProfile _requireSignedIn() {
    final p = currentProfile;
    if (p == null) {
      throw const SocialException(
          SocialFailure.unauthorized, 'sign in to do this');
    }
    return p;
  }

  SocialProfile _byHandle(String handle) {
    final h = normalizeHandle(handle);
    for (final p in _store.profiles.values) {
      if (p.handle == h) return p;
    }
    throw SocialException(SocialFailure.notFound, h);
  }

  bool _blockedBetween(String a, String b) =>
      (_store.blocks[a]?.contains(b) ?? false) ||
      (_store.blocks[b]?.contains(a) ?? false);

  FollowState _state(String follower, String followee) =>
      _store.follows[follower]?[followee] ?? FollowState.none;

  /// Migration 0003 `can_view`.
  bool _canView(String ownerId) {
    final me = _myId;
    if (ownerId == me) return true;
    if (me != null && _blockedBetween(ownerId, me)) return false;
    final owner = _store.profiles[ownerId];
    if (owner == null || !owner.isPrivate) return true;
    return me != null && _state(me, ownerId) == FollowState.accepted;
  }

  SocialPerson _person(SocialProfile p) {
    final me = _myId;
    if (me == null) return SocialPerson(profile: p);
    return SocialPerson(
      profile: p,
      iFollow: _state(me, p.id),
      followsMe: _state(p.id, me) == FollowState.accepted,
    );
  }

  void _notify(String userId, String actorId, NotificationKind kind,
      {int? igdbId, int? refId}) {
    _store._notifications.add(_FakeNotification(
        _store.nextId(), userId, actorId, kind,
        igdbId: igdbId, refId: refId));
  }

  @override
  Future<SocialProfile> signIn() async {
    if (!_configured) {
      throw const SocialException(SocialFailure.notConfigured);
    }
    final existing = currentProfile;
    if (existing != null) return existing;
    // Onboarded, so tests that only need "a signed-in person" are not routed
    // through profile setup. Email sign-up below starts un-onboarded.
    const me = SocialProfile(
      id: 'local-me',
      handle: 'you',
      displayName: 'You',
      avatarSeed: 'biolume',
      onboarded: true,
    );
    _store.profiles.putIfAbsent(me.id, () => me);
    return _signInAs(me.id);
  }

  final StreamController<SocialAuthEvent> _auth =
      StreamController<SocialAuthEvent>.broadcast();

  @override
  Stream<SocialAuthEvent> get authChanges => _auth.stream;

  @override
  SignInMethod? get signInMethod {
    final id = _myId;
    if (id == null) return null;
    for (final e in _store.accounts.entries) {
      if (e.value.id == id) return SignInMethod(provider: 'email', email: e.key);
    }
    return const SignInMethod(provider: 'google', email: 'you@gmail.com');
  }

  SocialProfile _signInAs(String id) {
    _myId = id;
    final p = currentProfile!;
    _auth.add(SocialAuthEvent(SocialAuthKind.signedIn, profile: p));
    return p;
  }

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String _checkEmail(String email) {
    final e = email.trim().toLowerCase();
    if (!_emailShape.hasMatch(e)) {
      throw const SocialException(SocialFailure.invalid, 'email');
    }
    return e;
  }

  void _checkPassword(String password) {
    // The live project's minimum (config.toml minimum_password_length).
    if (password.length < 6) {
      throw const SocialException(SocialFailure.invalid, 'weak password');
    }
  }

  @override
  Future<SocialProfile> signInWithEmail(String email, String password) async {
    if (!_configured) throw const SocialException(SocialFailure.notConfigured);
    final e = email.trim().toLowerCase();
    final a = _store.accounts[e];
    if (a == null || a.password != password) {
      throw const SocialException(SocialFailure.unauthorized, 'credentials');
    }
    if (!a.confirmed) {
      throw const SocialException(SocialFailure.emailNotConfirmed);
    }
    return _signInAs(a.id);
  }

  @override
  Future<SignUpOutcome> signUpWithEmail(String email, String password) async {
    if (!_configured) throw const SocialException(SocialFailure.notConfigured);
    final e = _checkEmail(email);
    _checkPassword(password);
    if (_store.accounts.containsKey(e)) {
      throw const SocialException(SocialFailure.conflict, 'email');
    }
    final n = _store.nextId();
    final id = 'email-$n';
    // Same shape as the server's derived ID: a placeholder until onboarding.
    _store.profiles[id] = SocialProfile(
      id: id,
      handle: 'g${n.toString().padLeft(10, '0')}',
      displayName: e.split('@').first,
    );
    final confirmed = !_store.requireEmailConfirmation;
    _store.accounts[e] = (password: password, id: id, confirmed: confirmed);
    if (!confirmed) return SignUpOutcome.checkEmail;
    _signInAs(id);
    return SignUpOutcome.signedIn;
  }

  /// Test hook: the person opened the confirmation link on this phone.
  void openConfirmationLink(String email) {
    final e = email.trim().toLowerCase();
    final a = _store.accounts[e]!;
    _store.accounts[e] = (password: a.password, id: a.id, confirmed: true);
    _signInAs(a.id);
  }

  /// Test hook: the person opened a password reset link on this phone.
  void openResetLink(String email) {
    final a = _store.accounts[email.trim().toLowerCase()]!;
    _myId = a.id;
    _auth.add(const SocialAuthEvent(SocialAuthKind.passwordRecovery));
  }

  /// Test hook: a sign-in came back with an error.
  void failSignIn(String message) =>
      _auth.add(SocialAuthEvent(SocialAuthKind.failed, message: message));

  @override
  Future<void> resendConfirmation(String email) async {
    if (!_configured) throw const SocialException(SocialFailure.notConfigured);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    if (!_configured) throw const SocialException(SocialFailure.notConfigured);
    _store.resetRequests.add(_checkEmail(email));
  }

  @override
  Future<void> setNewPassword(String password) async {
    final me = _requireSignedIn();
    _checkPassword(password);
    for (final entry in _store.accounts.entries) {
      if (entry.value.id == me.id) {
        _store.accounts[entry.key] =
            (password: password, id: me.id, confirmed: true);
      }
    }
  }

  @override
  Future<void> signOut() async {
    _myId = null;
    _auth.add(const SocialAuthEvent(SocialAuthKind.signedOut));
  }

  @override
  Future<void> deleteAccount() async {
    final me = _requireSignedIn();
    // Same effect as migration 0002's cascade: everything under the account
    // goes, then the session.
    _store.trees.remove(me.handle);
    _store.reactions.remove(me.handle);
    for (final list in _store.reactions.values) {
      list.removeWhere((r) => r.fromProfileId == me.id);
    }
    _store.follows.remove(me.id);
    for (final m in _store.follows.values) {
      m.remove(me.id);
    }
    _store.blocks.remove(me.id);
    for (final s in _store.blocks.values) {
      s.remove(me.id);
    }
    _store._hypes.removeWhere((h) => h.fromId == me.id || h.ownerId == me.id);
    _store._recommendations
        .removeWhere((r) => r.fromId == me.id || r.toId == me.id);
    _store._activity.removeWhere((a) => a.actorId == me.id);
    _store._notifications
        .removeWhere((n) => n.userId == me.id || n.actorId == me.id);
    _store.profiles.remove(me.id);
    _store.accounts.removeWhere((_, a) => a.id == me.id);
    _myId = null;
    _auth.add(const SocialAuthEvent(SocialAuthKind.signedOut));
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
    final t = _store.trees[normalizeHandle(handle)];
    // A private tree you may not see looks exactly like no tree, the same as
    // the row RLS hides on the server.
    if (t == null || !_canView(t.owner.id)) {
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
  Future<List<TreeReaction>> reactionsFor(String handle) async {
    final t = _store.trees[handle];
    if (t != null && !_canView(t.owner.id)) return const [];
    return List.unmodifiable(_store.reactions[handle] ?? const []);
  }

  // ---- Follows ------------------------------------------------------------

  @override
  Future<FollowState> setFollowing(String handle, bool following) async {
    final me = _requireSignedIn();
    final them = _byHandle(handle);
    final mine = _store.follows.putIfAbsent(me.id, () => {});
    if (!following) {
      mine.remove(them.id);
      return FollowState.none;
    }
    if (them.id == me.id) {
      throw const SocialException(SocialFailure.invalid, 'cannot follow yourself');
    }
    if (_blockedBetween(me.id, them.id)) {
      throw const SocialException(SocialFailure.forbidden, 'cannot follow');
    }
    final existing = mine[them.id];
    if (existing != null) return existing; // an upsert never flips the status
    final state = them.isPrivate ? FollowState.pending : FollowState.accepted;
    mine[them.id] = state;
    _notify(them.id, me.id,
        state == FollowState.pending
            ? NotificationKind.followRequest
            : NotificationKind.follow);
    return state;
  }

  @override
  Future<List<String>> following() async {
    final me = _requireSignedIn();
    return [
      for (final id in (_store.follows[me.id] ?? const {}).keys)
        if (_store.profiles[id] != null) _store.profiles[id]!.handle,
    ];
  }

  @override
  Future<List<SocialPerson>> followingPeople() async {
    final me = _requireSignedIn();
    return [
      for (final id in (_store.follows[me.id] ?? const {}).keys)
        if (_store.profiles[id] != null) _person(_store.profiles[id]!),
    ];
  }

  Iterable<SocialProfile> _incoming(String me, FollowState state) sync* {
    for (final e in _store.follows.entries) {
      if (e.value[me] == state && _store.profiles[e.key] != null) {
        yield _store.profiles[e.key]!;
      }
    }
  }

  @override
  Future<List<SocialPerson>> followers() async {
    final me = _requireSignedIn();
    return [for (final p in _incoming(me.id, FollowState.accepted)) _person(p)];
  }

  @override
  Future<List<SocialPerson>> followRequests() async {
    final me = _requireSignedIn();
    return [for (final p in _incoming(me.id, FollowState.pending)) _person(p)];
  }

  @override
  Future<void> respondToFollowRequest(String handle,
      {required bool accept}) async {
    final me = _requireSignedIn();
    final them = _byHandle(handle);
    final theirs = _store.follows[them.id];
    if (theirs?[me.id] != FollowState.pending) return;
    if (accept) {
      theirs![me.id] = FollowState.accepted;
      _notify(them.id, me.id, NotificationKind.followAccepted);
      _store._notifications.removeWhere((n) =>
          n.userId == me.id &&
          n.actorId == them.id &&
          n.kind == NotificationKind.followRequest);
    } else {
      theirs!.remove(me.id);
    }
  }

  @override
  Future<void> removeFollower(String handle) async {
    final me = _requireSignedIn();
    final them = _byHandle(handle);
    _store.follows[them.id]?.remove(me.id);
  }

  // ---- Profile ------------------------------------------------------------

  @override
  Future<SocialProfile?> refreshMyProfile() async => currentProfile;

  @override
  Future<SocialProfile> updateProfile(ProfileEdit edit) async {
    final me = _requireSignedIn();
    var next = me;
    if (edit.handle != null) {
      final h = normalizeHandle(edit.handle!);
      if (!handleLooksValid(h) || _reservedHandles.contains(h)) {
        throw SocialException(SocialFailure.invalid, 'bad ID $h');
      }
      final taken = _store.profiles.values
          .any((p) => p.handle == h && p.id != me.id);
      if (taken) throw SocialException(SocialFailure.conflict, h);
      next = next.copyWith(handle: h);
    }
    if (edit.displayName != null) {
      final n = edit.displayName!.trim();
      if (n.isEmpty || n.length > 40) {
        throw const SocialException(SocialFailure.invalid, 'name length');
      }
      next = next.copyWith(displayName: n);
    }
    if (edit.avatarSeed != null) {
      if (!avatarSeeds.contains(edit.avatarSeed)) {
        throw const SocialException(SocialFailure.invalid, 'avatar');
      }
      next = next.copyWith(avatarSeed: edit.avatarSeed);
    }
    if (edit.bio != null) {
      if (edit.bio!.length > 160) {
        throw const SocialException(SocialFailure.invalid, 'bio length');
      }
      next = next.copyWith(bio: edit.bio);
    }
    if (edit.platforms != null) {
      if (!edit.platforms!.every(profilePlatforms.contains)) {
        throw const SocialException(SocialFailure.invalid, 'platform');
      }
      next = next.copyWith(platforms: List.unmodifiable(edit.platforms!));
    }
    if (edit.isPrivate != null) next = next.copyWith(isPrivate: edit.isPrivate);
    if (edit.onboarded != null) next = next.copyWith(onboarded: edit.onboarded);

    _store.profiles[me.id] = next;
    if (next.handle != me.handle) {
      // The public link follows the ID, as it does on the server where the
      // tree is keyed by owner id and looked up by handle.
      final tree = _store.trees.remove(me.handle);
      if (tree != null) {
        _store.trees[next.handle] = PublishedTree(
            owner: next,
            games: tree.games,
            publishedAt: tree.publishedAt,
            level: tree.level);
      }
      final r = _store.reactions.remove(me.handle);
      if (r != null) _store.reactions[next.handle] = r;
    }
    return next;
  }

  @override
  Future<bool> isHandleAvailable(String handle) async {
    final h = normalizeHandle(handle);
    if (!handleLooksValid(h) || _reservedHandles.contains(h)) return false;
    return !_store.profiles.values.any((p) => p.handle == h && p.id != _myId);
  }

  // ---- People -------------------------------------------------------------

  @override
  Future<List<SocialPerson>> searchPeople(String query) async {
    final q = normalizeHandle(query);
    if (q.length < 2) return const [];
    final me = _myId;
    final hits = _store.profiles.values.where((p) =>
        p.id != me &&
        (me == null || !_blockedBetween(p.id, me)) &&
        (p.handle.startsWith(q) || p.displayName.toLowerCase().startsWith(q)));
    final sorted = hits.toList()
      ..sort((a, b) {
        int rank(SocialProfile p) =>
            p.handle == q ? 0 : (p.handle.startsWith(q) ? 1 : 2);
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.handle.compareTo(b.handle);
      });
    return [for (final p in sorted.take(20)) _person(p)];
  }

  @override
  Future<SocialPerson> personByHandle(String handle) async {
    final p = _byHandle(handle);
    final me = _myId;
    if (me != null && p.id != me && _blockedBetween(p.id, me)) {
      throw SocialException(SocialFailure.notFound, handle);
    }
    return _person(p);
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
    final me = _requireSignedIn();
    _store._activity.add(_FakeActivity(
        _store.nextId(), me.id, kind, igdbId, title, coverUrl, rating));
  }

  @override
  Future<List<ActivityItem>> friendsActivity({
    Duration window = const Duration(days: 14),
  }) async {
    final me = _requireSignedIn();
    final since = DateTime.now().subtract(window);
    final mine = _store.follows[me.id] ?? const {};
    final rows = _store._activity
        .where((a) =>
            mine[a.actorId] == FollowState.accepted && !a.at.isBefore(since))
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    return [
      for (final a in rows.take(100))
        if (_store.profiles[a.actorId] != null)
          ActivityItem(
            id: a.id,
            actor: _store.profiles[a.actorId]!,
            kind: a.kind,
            igdbId: a.igdbId,
            title: a.title,
            coverUrl: a.coverUrl,
            rating: a.rating,
            at: a.at,
          ),
    ];
  }

  // ---- Hypes --------------------------------------------------------------

  @override
  Future<void> setHype(String handle, int igdbId, bool hyped) async {
    final me = _requireSignedIn();
    final owner = _byHandle(handle);
    bool same(_FakeHype h) =>
        h.fromId == me.id && h.ownerId == owner.id && h.igdbId == igdbId;
    if (!hyped) {
      _store._hypes.removeWhere(same);
      return;
    }
    if (owner.id == me.id) {
      throw const SocialException(SocialFailure.invalid, 'own game');
    }
    if (!_canView(owner.id)) {
      throw const SocialException(SocialFailure.forbidden, 'cannot see tree');
    }
    if (_store._hypes.any(same)) return;
    _store._hypes.add(_FakeHype(me.id, owner.id, igdbId));
    _notify(owner.id, me.id, NotificationKind.hype, igdbId: igdbId);
  }

  @override
  Future<Set<int>> myHypesOn(String handle) async {
    final me = _requireSignedIn();
    final owner = _byHandle(handle);
    return {
      for (final h in _store._hypes)
        if (h.fromId == me.id && h.ownerId == owner.id) h.igdbId,
    };
  }

  @override
  Future<List<Hype>> hypesOnMyTree() async {
    final me = _requireSignedIn();
    return [
      for (final h in _store._hypes.reversed)
        if (h.ownerId == me.id && _store.profiles[h.fromId] != null)
          Hype(from: _store.profiles[h.fromId]!, igdbId: h.igdbId, at: h.at),
    ];
  }

  // ---- Seeds --------------------------------------------------------------

  @override
  Future<void> recommend({
    required String toHandle,
    required int igdbId,
    required String title,
    String? coverUrl,
    String message = '',
  }) async {
    final me = _requireSignedIn();
    final to = _byHandle(toHandle);
    if (to.id == me.id) {
      throw const SocialException(SocialFailure.invalid, 'to yourself');
    }
    if (message.length > 140 || title.isEmpty || title.length > 200) {
      throw const SocialException(SocialFailure.invalid, 'length');
    }
    // Migration 0003 `may_recommend_to`: they must follow you.
    if (_blockedBetween(me.id, to.id) ||
        _state(to.id, me.id) != FollowState.accepted) {
      throw const SocialException(SocialFailure.forbidden, 'not a follower');
    }
    final r = _FakeRecommendation(
        _store.nextId(), me.id, to.id, igdbId, title, coverUrl, message);
    _store._recommendations.add(r);
    _notify(to.id, me.id, NotificationKind.recommendation,
        igdbId: igdbId, refId: r.id);
  }

  Recommendation? _rec(_FakeRecommendation r) {
    final from = _store.profiles[r.fromId];
    final to = _store.profiles[r.toId];
    if (from == null || to == null) return null;
    return Recommendation(
      id: r.id,
      from: from,
      to: to,
      igdbId: r.igdbId,
      title: r.title,
      coverUrl: r.coverUrl,
      message: r.message,
      status: r.status,
      at: r.at,
    );
  }

  @override
  Future<List<Recommendation>> recommendationsInbox() async {
    final me = _requireSignedIn();
    return [
      for (final r in _store._recommendations.reversed)
        if (r.toId == me.id) ?_rec(r),
    ];
  }

  @override
  Future<List<Recommendation>> recommendationsSent() async {
    final me = _requireSignedIn();
    return [
      for (final r in _store._recommendations.reversed)
        if (r.fromId == me.id) ?_rec(r),
    ];
  }

  @override
  Future<void> setRecommendationStatus(
      int id, RecommendationStatus status) async {
    final me = _requireSignedIn();
    for (final r in _store._recommendations) {
      if (r.id == id && r.toId == me.id) {
        r.status = status;
        return;
      }
    }
    throw SocialException(SocialFailure.notFound, 'seed $id');
  }

  // ---- Notifications ------------------------------------------------------

  @override
  Future<List<SocialNotification>> notifications() async {
    final me = _requireSignedIn();
    return [
      for (final n in _store._notifications.reversed.take(1000))
        if (n.userId == me.id && _store.profiles[n.actorId] != null)
          SocialNotification(
            id: n.id,
            kind: n.kind,
            actor: _store.profiles[n.actorId]!,
            igdbId: n.igdbId,
            refId: n.refId,
            readAt: n.readAt,
            at: n.at,
          ),
    ].take(50).toList();
  }

  @override
  Future<int> unreadNotificationCount() async {
    final me = _requireSignedIn();
    return _store._notifications
        .where((n) => n.userId == me.id && n.readAt == null)
        .length;
  }

  @override
  Future<void> markNotificationsRead() async {
    final me = _requireSignedIn();
    final now = DateTime.now();
    for (final n in _store._notifications) {
      if (n.userId == me.id) n.readAt ??= now;
    }
  }

  // ---- Safety -------------------------------------------------------------

  @override
  Future<void> block(String handle) async {
    final me = _requireSignedIn();
    final them = _byHandle(handle);
    if (them.id == me.id) {
      throw const SocialException(SocialFailure.invalid, 'block yourself');
    }
    _store.blocks.putIfAbsent(me.id, () => {}).add(them.id);
    _store.follows[me.id]?.remove(them.id);
    _store.follows[them.id]?.remove(me.id);
  }

  @override
  Future<void> unblock(String handle) async {
    final me = _requireSignedIn();
    final them = _byHandle(handle);
    _store.blocks[me.id]?.remove(them.id);
  }

  @override
  Future<List<SocialProfile>> blockedPeople() async {
    final me = _requireSignedIn();
    return [
      for (final id in _store.blocks[me.id] ?? const <String>{})
        if (_store.profiles[id] != null) _store.profiles[id]!,
    ];
  }

  @override
  Future<void> report(String handle, ReportReason reason,
      {String details = ''}) async {
    final me = _requireSignedIn();
    final them = _byHandle(handle);
    if (details.length > 500) {
      throw const SocialException(SocialFailure.invalid, 'details length');
    }
    _store.reports.add((me.id, them.id, reason));
  }
}
