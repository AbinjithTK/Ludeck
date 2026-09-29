import 'enums.dart';

/// Seconds to hours. The ONE place this division happens.
const int secondsPerHour = 3600;

/// Catalogue data. One record per IGDB id, never duplicated.
///
/// igdbId is THE identity. Never match a game on its title: IGDB search returns
/// DLC and remasters above base games, and titles get edited.
/// A branch of the tree: the user's own grouping of games.
///
/// A record rather than a class because it carries no behaviour and no
/// invariants, and the repository already returns exactly this shape. Named here
/// so the repository, the store and the views do not each repeat it, which is how
/// one of them ends up with a field the others do not have.
///
/// Branches are NOT derived from platforms. Arbitrary, unlimited categorisation
/// is what gives each tree its own shape.
///
/// Schema v4 made branches nest: [parentId] is null for a branch growing
/// straight from the trunk, otherwise the branch it grows from. [sortOrder] is
/// the position among SIBLINGS (same parent), not across the whole tree.
/// [collapsed] is the user's own fold state, persisted so a tree they tidied
/// stays tidy across launches.
typedef Branch = ({
  int id,
  String name,
  int sortOrder,
  int? parentId,
  bool collapsed,
});

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

/// Where a game came from. A SET of these per game, never one field.
///
/// A second video about a game already in the library is information, not a
/// duplicate: it records that the game keeps coming up, which is the thing the
/// user is trying to keep track of.
class Source {
  const Source({
    required this.igdbId,
    required this.kind,
    required this.matchMethod,
    required this.addedAt,
    this.id,
    this.url,
    this.title,
    this.channel,
    this.thumbUrl,
  });

  /// Null before the row is written. SQLite assigns it.
  final int? id;

  final int igdbId;

  /// Null when the share carried no link, which is a normal share.
  final String? url;

  final SourceKind kind;

  /// How the game was identified. Recorded so a row can be trusted in
  /// proportion to how it was matched, rather than all sources looking equal.
  final MatchMethod matchMethod;

  /// The video or page title, as that platform reported it.
  final String? title;

  /// PRIVACY: a real third party's name, exactly like `Entry.recommendedBy`.
  /// docs/DECISIONS.md invariant 10 keeps this off the share layer.
  final String? channel;

  final String? thumbUrl;

  final DateTime addedAt;
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
          igdbId: 14593,
          title: 'Hollow Knight',
          releaseYear: 2017,
          timeToBeatSeconds: 93600),
      entry: e(14593, Ownership.owned, Progress.playing),
      copies: [c(14593, Platform.pc), c(14593, Platform.switch_)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 11737,
          title: 'Outer Wilds',
          releaseYear: 2019,
          timeToBeatSeconds: 50400),
      entry: e(11737, Ownership.owned, Progress.untouched),
      copies: [c(11737, Platform.pc)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 26226,
          title: 'Celeste',
          releaseYear: 2018,
          timeToBeatSeconds: 28800),
      entry: e(26226, Ownership.owned, Progress.untouched),
      copies: [c(26226, Platform.switch_)],
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
          igdbId: 26472,
          title: 'Disco Elysium',
          releaseYear: 2019,
          timeToBeatSeconds: 118800),
      entry: e(26472, Ownership.owned, Progress.abandoned),
      copies: [c(26472, Platform.pc)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 23733,
          title: 'Tunic',
          releaseYear: 2022,
          timeToBeatSeconds: 41400),
      entry: e(23733, Ownership.owned, Progress.untouched),
      copies: [c(23733, Platform.xbox)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 303811,
          title: 'Astro Bot',
          releaseYear: 2024,
          timeToBeatSeconds: 43200),
      entry: e(303811, Ownership.owned, Progress.untouched),
      copies: [c(303811, Platform.playstation)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 126098,
          title: 'Half-Life: Alyx',
          releaseYear: 2020,
          timeToBeatSeconds: 39600),
      entry: e(126098, Ownership.owned, Progress.installed),
      copies: [c(126098, Platform.quest)],
    ),
    // Owned, spanning every console so the demo tree shows real platform
    // variety and the detail sheet's platform line has something to say. Real
    // IGDB ids/titles/years; a game owned on more than one platform carries
    // more than one copy, exactly as a real multi-platform owner would.
    TreeItem(
      game: const Game(
          igdbId: 119133,
          title: 'Elden Ring',
          releaseYear: 2022,
          timeToBeatSeconds: 209000),
      entry: e(119133, Ownership.owned, Progress.playing),
      copies: [c(119133, Platform.playstation)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 119171,
          title: "Baldur's Gate III",
          releaseYear: 2023,
          timeToBeatSeconds: 259200),
      entry: e(119171, Ownership.owned, Progress.playing),
      copies: [c(119171, Platform.pc), c(119171, Platform.steamDeck)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 17000,
          title: 'Stardew Valley',
          releaseYear: 2016,
          timeToBeatSeconds: 187200),
      entry: e(17000, Ownership.owned, Progress.playing),
      copies: [
        c(17000, Platform.switch_),
        c(17000, Platform.ios),
        c(17000, Platform.android),
      ],
    ),
    TreeItem(
      game: const Game(
          igdbId: 1877,
          title: 'Cyberpunk 2077',
          releaseYear: 2020,
          timeToBeatSeconds: 220000),
      entry: e(1877, Ownership.owned, Progress.finished),
      copies: [c(1877, Platform.xbox)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 251833,
          title: 'Balatro',
          releaseYear: 2024,
          timeToBeatSeconds: 90000),
      entry: e(251833, Ownership.owned, Progress.playing),
      copies: [c(251833, Platform.switch_), c(251833, Platform.steamDeck)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 127044,
          title: "Marvel's Spider-Man 2",
          releaseYear: 2023,
          timeToBeatSeconds: 90000),
      entry: e(127044, Ownership.owned, Progress.finished),
      copies: [c(127044, Platform.playstation)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 186725,
          title: 'Vampire Survivors',
          releaseYear: 2022,
          timeToBeatSeconds: 54000),
      entry: e(186725, Ownership.owned, Progress.installed),
      copies: [c(186725, Platform.steamDeck), c(186725, Platform.ios)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 7346,
          title: 'The Legend of Zelda: Breath of the Wild',
          releaseYear: 2017,
          timeToBeatSeconds: 180000),
      entry: e(7346, Ownership.owned, Progress.abandoned),
      copies: [c(7346, Platform.switch_)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 8900,
          title: 'Monument Valley',
          releaseYear: 2014,
          timeToBeatSeconds: 7200),
      entry: e(8900, Ownership.owned, Progress.finished),
      copies: [c(8900, Platform.ios), c(8900, Platform.android)],
    ),
    TreeItem(
      game: const Game(
          igdbId: 141503,
          title: 'Forza Horizon 5',
          releaseYear: 2021,
          timeToBeatSeconds: 90000),
      entry: e(141503, Ownership.owned, Progress.installed),
      copies: [c(141503, Platform.xbox), c(141503, Platform.pc)],
    ),
    // Seeds. Recommended, not owned. No platform, so no branch.
    TreeItem(
      game: const Game(
          igdbId: 204623,
          title: 'Pentiment',
          releaseYear: 2022,
          timeToBeatSeconds: 68400),
      entry: e(204623, Ownership.spotted, Progress.untouched, by: 'Priya'),
      copies: const [],
    ),
    TreeItem(
      game: const Game(
          igdbId: 149657,
          title: 'Blue Prince',
          releaseYear: 2025,
          timeToBeatSeconds: 90000),
      entry: e(149657, Ownership.spotted, Progress.untouched, by: 'a TikTok clip'),
      copies: const [],
    ),
  ];
}
