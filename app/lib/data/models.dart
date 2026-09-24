import 'enums.dart';

/// Seconds to hours. The ONE place this division happens.
const int secondsPerHour = 3600;

/// Catalogue data. One record per IGDB id, never duplicated.
///
/// igdbId is THE identity. Never match a game on its title: IGDB search returns
/// DLC and remasters above base games, and titles get edited.
class Game {
  const Game({
    required this.igdbId,
    required this.title,
    this.coverUrl,
    this.releaseYear,
    this.timeToBeatSeconds,
  });

  final int igdbId;
  final String title;
  final String? coverUrl;
  final int? releaseYear;

  /// SECONDS, exactly as IGDB returns them.
  final int? timeToBeatSeconds;

  /// Hours, converted once. Null when IGDB has no length on file, which is
  /// left as null rather than guessed: the reason line is the whole value of a
  /// suggestion, and "unknown hours" is not a reason.
  int? get hours {
    final s = timeToBeatSeconds;
    if (s == null || s <= 0) return null;
    return s ~/ secondsPerHour;
  }
}

/// One owned copy. A SET of these, not a field on the game, because people own
/// the same game on more than one platform and selling one copy must not erase
/// the other.
class Copy {
  const Copy({
    required this.igdbId,
    required this.platform,
    required this.form,
    required this.acquired,
    this.pricePaidMinor,
  });

  final int igdbId;
  final Platform platform;
  final Form form;
  final Acquired acquired;
  final int? pricePaidMinor;
}

/// The user's relationship to a game. One per game.
class Entry {
  const Entry({
    required this.igdbId,
    required this.ownership,
    required this.progress,
    this.rating,
    this.note,
    this.lastPlayedAt,
    this.recommendedBy,
    this.shelved = false,
  });

  final int igdbId;
  final Ownership ownership;
  final Progress progress;
  final int? rating;
  final String? note;

  /// From Steam's rtime_last_played when available.
  final DateTime? lastPlayedAt;

  /// Who put this on your radar. The whole premise of the app is that this is
  /// worth keeping, so a seed carries its source.
  final String? recommendedBy;

  /// Replaces delete. Deleting a collection row is not a feature.
  final bool shelved;

  /// Sentinel meaning "this argument was not supplied". Needed because `rating`
  /// and `note` are themselves nullable: without it, `copyWith(rating: null)`
  /// could not distinguish "leave the rating alone" from "clear the rating",
  /// and clearing a rating is a real action a caller needs to be able to do.
  static const Object _unset = Object();

  Entry copyWith({
    Ownership? ownership,
    Progress? progress,
    Object? rating = _unset,
    Object? note = _unset,
    bool? shelved,
  }) =>
      Entry(
        igdbId: igdbId,
        ownership: ownership ?? this.ownership,
        progress: progress ?? this.progress,
        rating: rating == _unset ? this.rating : rating as int?,
        note: note == _unset ? this.note : note as String?,
        lastPlayedAt: lastPlayedAt,
        recommendedBy: recommendedBy,
        shelved: shelved ?? this.shelved,
      );
}

/// A game plus the user's relationship to it plus the copies owned, which is
/// what both the tree and the list render from.
class TreeItem {
  const TreeItem({
    required this.game,
    required this.entry,
    required this.copies,
  });

  final Game game;
  final Entry entry;
  final List<Copy> copies;

  /// A seed is something recommended but not owned. It sits in soil, not on a
  /// branch, and it may sit there forever without reproach.
  bool get isSeed => entry.ownership == Ownership.spotted;

  bool get isHarvested => entry.progress == Progress.finished;

  /// Which branches this fruit hangs on. A game owned on two platforms
  /// legitimately appears twice, which reads correctly on a tree in a way it
  /// cannot in a list.
  Set<Platform> get platforms => copies.map((c) => c.platform).toSet();
}

/// Seed data with real IGDB ids, titles and lengths, so the canvas can be
/// looked at and judged before the network layer exists. Replaced by the real
/// import; not shipped as a demo mode.
List<TreeItem> fixtureTree() {
  Copy c(int id, Platform p,
          [Form f = Form.digital, Acquired a = Acquired.bought]) =>
      Copy(igdbId: id, platform: p, form: f, acquired: a);

  Entry e(int id, Ownership o, Progress pr, {String? by}) =>
      Entry(igdbId: id, ownership: o, progress: pr, recommendedBy: by);

  return [
    TreeItem(
      game: const Game(
          igdbId: 1020,
          title: 'Hollow Knight',
          releaseYear: 2017,
          timeToBeatSeconds: 93600),
      entry: e(1020, Ownership.owned, Progress.playing),
      copies: [c(1020, Platform.pc), c(1020, Platform.switch_)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 11208,
          title: 'Outer Wilds',
          releaseYear: 2019,
          timeToBeatSeconds: 50400),
      entry: e(11208, Ownership.owned, Progress.untouched),
      copies: [c(11208, Platform.pc)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 7597,
          title: 'Celeste',
          releaseYear: 2018,
          timeToBeatSeconds: 28800),
      entry: e(7597, Ownership.owned, Progress.untouched),
      copies: [c(7597, Platform.switch_)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 113112,
          title: 'Hades',
          releaseYear: 2020,
          timeToBeatSeconds: 82800),
      entry: e(113112, Ownership.owned, Progress.finished),
      copies: [c(113112, Platform.pc)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 26192,
          title: 'Disco Elysium',
          releaseYear: 2019,
          timeToBeatSeconds: 118800),
      entry: e(26192, Ownership.owned, Progress.abandoned),
      copies: [c(26192, Platform.pc)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 134595,
          title: 'Tunic',
          releaseYear: 2022,
          timeToBeatSeconds: 41400),
      entry: e(134595, Ownership.owned, Progress.untouched),
      copies: [c(134595, Platform.xbox)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 19560,
          title: 'Astro Bot',
          releaseYear: 2024,
          timeToBeatSeconds: 43200),
      entry: e(19560, Ownership.owned, Progress.untouched),
      copies: [c(19560, Platform.playstation)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 96437,
          title: 'Half-Life: Alyx',
          releaseYear: 2020,
          timeToBeatSeconds: 39600),
      entry: e(96437, Ownership.owned, Progress.installed),
      copies: [c(96437, Platform.quest)],
    ),
    // Seeds. Recommended, not owned. No platform, so no branch.
    TreeItem(
      game: const Game(
          igdbId: 119171,
          title: 'Pentiment',
          releaseYear: 2022,
          timeToBeatSeconds: 68400),
      entry: e(119171, Ownership.spotted, Progress.untouched, by: 'Priya'),
      copies: const [],
    ),
    TreeItem(
      game: const Game(
          igdbId: 125174,
          title: 'Blue Prince',
          releaseYear: 2025,
          timeToBeatSeconds: 90000),
      entry: e(125174, Ownership.spotted, Progress.untouched, by: 'a TikTok clip'),
      copies: const [],
    ),
  ];
}
