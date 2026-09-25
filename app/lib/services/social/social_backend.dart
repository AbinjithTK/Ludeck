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

/// A person's public profile. Created on first sign-in; editable by its owner.
///
/// Deliberately thin. The tree is the identity in this app, so a profile is a
/// handle and a level, not a bio wall.
class SocialProfile {
  const SocialProfile({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarSeed,
  });

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

  Future<void> signOut();

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

  /// Follow / unfollow a tree so its updates surface later. Requires sign-in.
  Future<void> setFollowing(String handle, bool following);

  /// Handles the signed-in profile currently follows.
  Future<List<String>> following();
}
