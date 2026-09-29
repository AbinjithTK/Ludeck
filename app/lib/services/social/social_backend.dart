// The community layer's boundary.
//
// One interface with two implementations behind it, mirroring the catalogue's
// own split (catalog_service.dart / http_catalog.dart): an in-memory FAKE used
// by every test and offline path, and the Supabase-backed real one. The app
// depends only on this file, never on Supabase, so the whole publish/visit/react
// flow is exercisable without a network and without a project existing yet.
//
// PRIVACY -- docs/DECISIONS.md invariant 10 / scripts/check.ps1 rule 10.
// A published tree is world readable. Its payload is TITLE, COVER, STATUS and
// RATING only. The two columns that hold a real third party's name --
// entries.recommended_by (who suggested the game) and sources.channel (whose
// video it came from) -- must never reach this layer. `PublishedGame` below has
// no field for either, on purpose: the type system is the first line of that
// rule and the checker is the second. This file is named `social_*` and lives
// outside any `intake` path, so the checker scans it and would fail the build
// the instant a forbidden field appeared here.

import '../../data/enums.dart';
import 'social_types.dart';

export 'social_types.dart';

/// A person's public profile. Created on first sign-in; editable by its owner.
///
/// Deliberately thin. The tree is the identity in this app, so a profile is a
/// handle, a name and one short line, not a bio wall.
class SocialProfile {
  const SocialProfile({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarSeed,
    this.bio = '',
    this.platforms = const [],
    this.isPrivate = false,
    this.onboarded = false,
  });

  /// At most 160 characters (migration 0003).
  final String bio;

  /// Codes from [profilePlatforms].
  final List<String> platforms;

  /// Friends-only. Strangers can find the profile and ask to follow, but see
  /// no tree and no activity until accepted.
  final bool isPrivate;

  /// Whether the person finished onboarding (picked their own ID).
  final bool onboarded;

  SocialProfile copyWith({
    String? handle,
    String? displayName,
    String? avatarSeed,
    String? bio,
    List<String>? platforms,
    bool? isPrivate,
    bool? onboarded,
  }) =>
      SocialProfile(
        id: id,
        handle: handle ?? this.handle,
        displayName: displayName ?? this.displayName,
        avatarSeed: avatarSeed ?? this.avatarSeed,
        bio: bio ?? this.bio,
        platforms: platforms ?? this.platforms,
        isPrivate: isPrivate ?? this.isPrivate,
        onboarded: onboarded ?? this.onboarded,
      );

  /// Stable id from the auth layer. Never the handle -- handles can change.
  final String id;

  /// Unique, user-chosen, URL-safe. What a public tree link is keyed on.
  final String handle;

  final String displayName;

  /// Drives the generated avatar orb. Not a photo: no upload surface exists and
  /// none is planned, so identity stays a colour, never a face.
  final String? avatarSeed;
}

/// One game as it appears on a PUBLISHED tree. The entire public payload for a
/// game, and intentionally the whole of it.
///
/// Compare with `TreeItem` (data/models.dart), which additionally carries
/// `entry.recommendedBy`, `entry.note` and each source's `channel`. Those do NOT
/// exist here. That absence is the privacy invariant expressed as a type: you
/// cannot publish a field the DTO has no room for.
class PublishedGame {
  const PublishedGame({
    required this.igdbId,
    required this.title,
    required this.status,
    required this.branchName,
    this.coverUrl,
    this.rating,
  });

  final int igdbId;

  /// Title, cover and rating are catalogue/collection facts, not third-party
  /// names, so they are safe to publish. This is the exact list invariant 10
  /// permits.
  final String title;
  final String? coverUrl;

  /// The owner's own status for the game. Their fact about their play, not
  /// anyone else's name.
  final Progress status;

  /// The owner's own 1-5 rating, or null if unrated.
  final int? rating;

  /// The branch this game hangs on, by NAME only. A branch name is the owner's
  /// own category label ("Cozy", "Metroidvanias") -- never a person. It ships so
  /// a visitor sees the tree's shape; the checker permits it because it is not
  /// one of the two forbidden columns.
  final String branchName;
}

/// A whole tree as published. What a visitor loads from a public link.
class PublishedTree {
  const PublishedTree({
    required this.owner,
    required this.games,
    required this.publishedAt,
    required this.level,
  });

  final SocialProfile owner;
  final List<PublishedGame> games;
  final DateTime publishedAt;

  /// The owner's level at publish time, derived from harvest count the same way
  /// the header derives it (domain/level.dart). A snapshot, not a live figure.
  final int level;

  int get harvestedCount =>
      games.where((g) => g.status == Progress.finished).length;
}

/// A reaction a visitor leaves on a published tree. Ratings and reactions are
/// the two "audience" verbs; both attach to a tree, not to the owner.
enum ReactionKind { admire, wishlist, played }

class TreeReaction {
  const TreeReaction({
    required this.treeHandle,
    required this.fromProfileId,
    required this.kind,
  });

  final String treeHandle;
  final String fromProfileId;
  final ReactionKind kind;
}

/// Why a community call could not be answered. Mirrors CatalogFailure so callers
/// handle a social outage the same shape as a catalogue outage.
enum SocialFailure {
  /// The network could not be reached.
  offline,

  /// A reply arrived and could not be understood.
  malformed,

  /// The far end refused -- most often: you must be signed in for this.
  unauthorized,

  /// The handle or tree asked for does not exist (or was unpublished).
  notFound,

  /// No backend is configured. Distinct from a failure -- nothing is wrong, the
  /// app simply runs in local-only mode.
  notConfigured,

  /// The value is already taken. In practice: someone else has that ID.
  conflict,

  /// The server rejected the value itself (an ID with bad characters, a bio
  /// that is too long).
  invalid,

  /// Signed in, but not allowed. Sending a seed to someone who does not follow
  /// you, or following someone across a block.
  forbidden,

  /// Too many attempts, or too many emails sent. Wait and try again.
  rateLimited,

  /// The account exists but its email link has not been opened yet.
  emailNotConfirmed,
}

class SocialException implements Exception {
  const SocialException(this.failure, [this.detail]);

  final SocialFailure failure;
  final String? detail;

  @override
  String toString() =>
      'SocialException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// The one seam the app talks to for anything community.
///
/// Every method is total about failure: a network or auth problem throws
/// [SocialException], never returns a misleading empty. Sign-in is OPTIONAL and
/// gates only the writes -- `publish`, `react`, `follow`. Reading a public tree
/// needs no account, because a shared link must open for anyone.
abstract class SocialBackend {
  /// The signed-in profile, or null when signed out. Null is not an error: the
  /// app is fully usable signed out, exactly as it is today.
  SocialProfile? get currentProfile;

  /// Whether a real backend is wired up at all. False in local-only mode, which
  /// is the honest state until the Supabase project exists.
  bool get isConfigured;

  /// Begin an optional sign-in. Returns the profile on success. Throws
  /// [SocialFailure.notConfigured] in local-only mode rather than pretending.
  Future<SocialProfile> signIn();

  /// Every change to the session, whatever caused it. Broadcast. Screens that
  /// wait on a sign-in listen here, because a Google redirect or an email link
  /// can land long after the button that started it.
  Stream<SocialAuthEvent> get authChanges;

  /// How the signed-in account signs in. Null when signed out.
  SignInMethod? get signInMethod;

  /// Sign in with an email and password. Throws [SocialFailure.unauthorized]
  /// for a wrong password or unknown email (deliberately not told apart), and
  /// [SocialFailure.emailNotConfirmed] before the email link is opened.
  Future<SocialProfile> signInWithEmail(String email, String password);

  /// Create an email account. Throws [SocialFailure.conflict] when the email
  /// already has an account and [SocialFailure.invalid] for a weak password or
  /// a malformed email.
  Future<SignUpOutcome> signUpWithEmail(String email, String password);

  /// Send the confirmation email again.
  Future<void> resendConfirmation(String email);

  /// Email a password reset link. Succeeds whether or not the email has an
  /// account, so the screen cannot be used to test who is signed up.
  Future<void> sendPasswordReset(String email);

  /// Set a new password for the signed-in account (after a reset link).
  Future<void> setNewPassword(String password);

  Future<void> signOut();

  /// Permanently delete the signed-in account and everything published under
  /// it (Google Play's account-deletion requirement). The on-device
  /// collection is untouched: it was never on the server. Requires sign-in.
  Future<void> deleteAccount();

  /// Publish (or re-publish) the caller's tree from the given public games.
  ///
  /// [isPublic] false means "unpublish" -- take it private again. The default is
  /// private, decided at the call site, never here. Requires a signed-in
  /// profile; throws [SocialFailure.unauthorized] otherwise.
  Future<void> publish({
    required List<PublishedGame> games,
    required int level,
    required bool isPublic,
  });

  /// Load a public tree by its owner's handle. No account required.
  Future<PublishedTree> treeByHandle(String handle);

  /// React to a published tree. Requires sign-in.
  Future<void> react(String handle, ReactionKind kind);

  /// The reactions currently on a tree, for its visitor view.
  Future<List<TreeReaction>> reactionsFor(String handle);

  /// Follow or unfollow a person. Requires sign-in. Returns where the follow
  /// landed: [FollowState.pending] for a private profile, decided by the
  /// server, never by the caller.
  Future<FollowState> setFollowing(String handle, bool following);

  /// Handles the signed-in profile follows, including pending requests.
  Future<List<String>> following();

  // ---- Profile ------------------------------------------------------------

  /// Re-read the caller's own profile from the server and cache it, so
  /// [currentProfile] reflects an ID or name changed elsewhere. Null when
  /// signed out.
  Future<SocialProfile?> refreshMyProfile();

  /// Change the caller's own profile. Returns the saved profile. Throws
  /// [SocialFailure.conflict] when the ID is taken and
  /// [SocialFailure.invalid] when the server rejects a value.
  Future<SocialProfile> updateProfile(ProfileEdit edit);

  /// Whether [handle] is free for the caller. The caller's own current ID
  /// counts as free. Works signed out.
  Future<bool> isHandleAvailable(String handle);

  // ---- People -------------------------------------------------------------

  /// Find people by the start of their ID or name. Two characters minimum;
  /// shorter queries return nothing. Never includes the caller or anyone on
  /// either side of a block.
  Future<List<SocialPerson>> searchPeople(String query);

  /// One person by exact ID, with the caller's relationship to them. Throws
  /// [SocialFailure.notFound] for an unknown or blocked ID.
  Future<SocialPerson> personByHandle(String handle);

  /// Everyone the caller follows or has asked to follow.
  Future<List<SocialPerson>> followingPeople();

  /// Everyone who follows the caller (accepted).
  Future<List<SocialPerson>> followers();

  /// People asking to follow the caller's private profile.
  Future<List<SocialPerson>> followRequests();

  Future<void> respondToFollowRequest(String handle, {required bool accept});

  /// Stop [handle] following the caller. Not a block: they can ask again.
  Future<void> removeFollower(String handle);

  // ---- Quiet feed ---------------------------------------------------------

  /// Record one real event on the caller's own tree.
  Future<void> postActivity({
    required ActivityKind kind,
    required int igdbId,
    required String title,
    String? coverUrl,
    int? rating,
  });

  /// Recent events from people the caller follows (accepted), newest first.
  /// Finite by design: a fixed window and a cap, so the list ends.
  Future<List<ActivityItem>> friendsActivity({
    Duration window = const Duration(days: 14),
  });

  // ---- Hypes --------------------------------------------------------------

  /// Hype or un-hype one game on [handle]'s tree.
  Future<void> setHype(String handle, int igdbId, bool hyped);

  /// The games on [handle]'s tree the caller has hyped.
  Future<Set<int>> myHypesOn(String handle);

  /// Hypes other people gave the caller's games, newest first. Never a count
  /// shown to anyone else.
  Future<List<Hype>> hypesOnMyTree();

  // ---- Seeds --------------------------------------------------------------

  /// Send a game to [toHandle]. Allowed only when they follow the caller;
  /// otherwise [SocialFailure.forbidden].
  Future<void> recommend({
    required String toHandle,
    required int igdbId,
    required String title,
    String? coverUrl,
    String message = '',
  });

  /// Seeds sent to the caller, newest first.
  Future<List<Recommendation>> recommendationsInbox();

  /// Seeds the caller has sent, newest first.
  Future<List<Recommendation>> recommendationsSent();

  /// Plant or dismiss a seed sent to the caller.
  Future<void> setRecommendationStatus(int id, RecommendationStatus status);

  // ---- Notifications ------------------------------------------------------

  /// The caller's inbox, newest first, most recent 50.
  Future<List<SocialNotification>> notifications();

  Future<int> unreadNotificationCount();

  Future<void> markNotificationsRead();

  // ---- Safety -------------------------------------------------------------

  /// Block [handle]. Ends follows both ways and hides each from the other.
  Future<void> block(String handle);

  Future<void> unblock(String handle);

  /// People the caller has blocked.
  Future<List<SocialProfile>> blockedPeople();

  /// Report [handle]. Write-only: nobody reads it back from the app.
  Future<void> report(String handle, ReportReason reason, {String details = ''});
}
