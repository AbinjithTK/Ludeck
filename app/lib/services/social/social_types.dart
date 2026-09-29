// Value types for the social layer added in migration 0003: people and how you
// relate to them, the quiet activity list, hypes, seeds sent between friends,
// the notifications inbox, and reports.
//
// PRIVACY -- invariant 10 holds here too. Every game-shaped payload below is
// igdbId, title, cover and (for activity) the actor's own rating. None of
// these types has room for a note or a video source, so neither can be sent.
// The sender on a [Recommendation] is the signed-in person who chose to send
// it, which is the one name they agreed to share.

import 'social_backend.dart';

/// Where the caller stands with someone else's follow relationship.
enum FollowState {
  /// No follow row.
  none,

  /// Asked to follow a private profile; waiting for them to accept.
  pending,

  /// Following. For a private profile, this means they accepted.
  accepted;

  static FollowState parse(String? raw) => switch (raw) {
        'pending' => FollowState.pending,
        'accepted' => FollowState.accepted,
        _ => FollowState.none,
      };
}

/// Someone else, as seen from the signed-in caller.
class SocialPerson {
  const SocialPerson({
    required this.profile,
    this.iFollow = FollowState.none,
    this.followsMe = false,
  });

  final SocialProfile profile;

  /// Whether the caller follows them, and if so whether it is accepted.
  final FollowState iFollow;

  /// Whether they follow the caller (accepted only).
  final bool followsMe;

  /// Friends are mutual: you follow each other and both are accepted.
  bool get isFriend => iFollow == FollowState.accepted && followsMe;

  String get handle => profile.handle;

  SocialPerson copyWith({FollowState? iFollow, bool? followsMe}) => SocialPerson(
        profile: profile,
        iFollow: iFollow ?? this.iFollow,
        followsMe: followsMe ?? this.followsMe,
      );
}

/// The fields onboarding and Settings can change. Null means leave as is.
class ProfileEdit {
  const ProfileEdit({
    this.handle,
    this.displayName,
    this.avatarSeed,
    this.bio,
    this.platforms,
    this.isPrivate,
    this.onboarded,
  });

  final String? handle;
  final String? displayName;

  /// The name of the tree skin that stands for this person (see
  /// [avatarSeeds]). The tree is the avatar: there is no photo upload.
  final String? avatarSeed;
  final String? bio;
  final List<String>? platforms;
  final bool? isPrivate;
  final bool? onboarded;

  bool get isEmpty =>
      handle == null &&
      displayName == null &&
      avatarSeed == null &&
      bio == null &&
      platforms == null &&
      isPrivate == null &&
      onboarded == null;
}

/// Avatar choices. Each is a tree skin's name, so a person's orb is lit in the
/// colours of the tree they picked (Tokens.skins).
const avatarSeeds = <String>['biolume', 'twilight', 'neon', 'midnight'];

/// Something that happened to the session, from any cause: a button in the
/// app, a Google redirect arriving late, or a link opened from an email.
enum SocialAuthKind {
  signedIn,
  signedOut,

  /// A password reset link was opened. The app should ask for a new password.
  passwordRecovery,

  /// A sign-in attempt came back with an error (an expired Google hand-off,
  /// a used email link).
  failed,
}

class SocialAuthEvent {
  const SocialAuthEvent(this.kind, {this.profile, this.message});

  final SocialAuthKind kind;

  /// Set for [SocialAuthKind.signedIn].
  final SocialProfile? profile;

  /// Set for [SocialAuthKind.failed]. Plain words, safe to show.
  final String? message;
}

/// What creating an email account led to.
enum SignUpOutcome {
  /// Signed in straight away.
  signedIn,

  /// A confirmation link was emailed; the account is usable once it is opened.
  checkEmail,
}

/// The platform codes a profile may list. Must match the check in 0003.
const profilePlatforms = <String>[
  'pc', 'switch', 'ps5', 'ps4', 'xbox', 'mobile', 'steamdeck', 'other',
];

/// Lower-cases and strips a leading '@', the same way the server does, so
/// "@Abin" and "abin" are the same ID everywhere.
String normalizeHandle(String raw) {
  final t = raw.trim().toLowerCase();
  return t.startsWith('@') ? t.substring(1) : t;
}

/// The ID rule from 0001, checked locally so the field can say why before a
/// round trip. Reserved names are only known to the server.
bool handleLooksValid(String raw) =>
    RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(normalizeHandle(raw));

/// One real event in the quiet feed.
enum ActivityKind { planted, harvested, rated }

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.actor,
    required this.kind,
    required this.igdbId,
    required this.title,
    required this.at,
    this.coverUrl,
    this.rating,
  });

  final int id;
  final SocialProfile actor;
  final ActivityKind kind;
  final int igdbId;
  final String title;
  final String? coverUrl;

  /// The actor's own rating, set for [ActivityKind.rated].
  final int? rating;
  final DateTime at;
}

/// A hype someone gave one of the caller's games. Seen by the two of them only.
class Hype {
  const Hype({required this.from, required this.igdbId, required this.at});

  final SocialProfile from;
  final int igdbId;
  final DateTime at;
}

enum RecommendationStatus { sent, planted, dismissed }

/// A seed one friend sends another. Lands in the recipient's soil strip.
class Recommendation {
  const Recommendation({
    required this.id,
    required this.from,
    required this.to,
    required this.igdbId,
    required this.title,
    required this.status,
    required this.at,
    this.coverUrl,
    this.message = '',
  });

  final int id;

  /// The person who sent it.
  final SocialProfile from;

  /// The person it was sent to.
  final SocialProfile to;
  final int igdbId;
  final String title;
  final String? coverUrl;

  /// A short line from the sender, at most 140 characters.
  final String message;
  final RecommendationStatus status;
  final DateTime at;
}

enum NotificationKind {
  follow,
  followRequest,
  followAccepted,
  recommendation,
  hype;

  static NotificationKind? parse(String raw) => switch (raw) {
        'follow' => NotificationKind.follow,
        'follow_request' => NotificationKind.followRequest,
        'follow_accepted' => NotificationKind.followAccepted,
        'recommendation' => NotificationKind.recommendation,
        'hype' => NotificationKind.hype,
        _ => null,
      };
}

class SocialNotification {
  const SocialNotification({
    required this.id,
    required this.kind,
    required this.actor,
    required this.at,
    this.igdbId,
    this.refId,
    this.readAt,
  });

  final int id;
  final NotificationKind kind;
  final SocialProfile actor;

  /// The game involved, for a hype or a recommendation.
  final int? igdbId;

  /// The recommendation id, for a recommendation.
  final int? refId;
  final DateTime? readAt;
  final DateTime at;

  bool get isUnread => readAt == null;
}

enum ReportReason { spam, harassment, impersonation, inappropriate, other }


/// How the signed-in account signs in, shown in Settings.
class SignInMethod {
  const SignInMethod({required this.provider, this.email});

  /// 'google' or 'email'. Anything else is shown as-is.
  final String provider;

  /// The address on the account, when there is one.
  final String? email;

  String get label => switch (provider) {
        'google' => 'Google',
        'email' => 'Email and password',
        _ => provider,
      };
}
