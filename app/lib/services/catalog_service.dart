// Where game facts come from.
//
// An interface with a fixture implementation, the same shape as
// `EntitlementSource`: the app is built and tested against the fake, and the
// real one drops in without the callers changing. The IGDB proxy is not
// deployed yet (docs\DEPLOY-PROXY.md steps 3 to 6 need account access), so the
// fixture is what actually runs today.

import '../data/models.dart';

/// A lookup of games. Never writes; the repository owns writes.
abstract class CatalogSource {
  /// Games whose title matches [query], best first. Empty when nothing matches.
  Future<List<Game>> search(String query);

  /// One game by its IGDB id.
  Future<Game?> byId(int igdbId);

  /// One game by another platform's identifier.
  ///
  /// This is the exact path and the reason it exists. A Twitch clip carries the
  /// game id outright and Twitch's own Get Games both accepts and returns an
  /// `igdb_id`, so the mapping needs no title matching at all. A Steam appid
  /// maps through IGDB `external_games` the same way.
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId});
}

/// The catalogue backed by `fixtureTree()`.
///
/// Small on purpose. It is enough to exercise the whole share pipeline end to
/// end without a network, which is what makes the feature demonstrable before
/// the proxy exists. Every lookup is a linear scan; ten rows do not need an
/// index.
class FixtureCatalog implements CatalogSource {
  FixtureCatalog() : _games = fixtureTree().map((t) => t.game).toList();

  FixtureCatalog.of(this._games);

  final List<Game> _games;

  @override
  Future<List<Game>> search(String query) async {
    final q = normaliseTitle(query);
    if (q.isEmpty) return const [];

    final exact = <Game>[];
    final prefix = <Game>[];
    final contains = <Game>[];

    for (final g in _games) {
      final t = normaliseTitle(g.title);
      if (t == q) {
        exact.add(g);
      } else if (t.startsWith(q)) {
        prefix.add(g);
      } else if (t.contains(q)) {
        contains.add(g);
      }
    }
    // Ordered by how much of the title the query actually accounted for. A
    // one-character query must not rank ahead of a real match.
    return [...exact, ...prefix, ...contains];
  }

  @override
  Future<Game?> byId(int igdbId) async {
    for (final g in _games) {
      if (g.igdbId == igdbId) return g;
    }
    return null;
  }

  /// The fixture knows no external ids, so this is honestly empty rather than
  /// faking a mapping the real catalogue would have to contradict later.
  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) async =>
      null;
}

/// Lowercased, punctuation and article stripped, whitespace collapsed.
///
/// Titles arrive spelled every possible way: "Hollow Knight", "hollow knight",
/// "HOLLOW KNIGHT!", "Hollow  Knight". All four are the same game and none of
/// them is a reason to miss it.
String normaliseTitle(String raw) {
  var s = raw.toLowerCase().trim();
  // Curly apostrophes and hyphens are cosmetic here.
  s = s.replaceAll(RegExp(r"[\u2019'\u2018]"), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // A leading article is never the distinguishing part of a title.
  for (final article in const ['the ', 'a ', 'an ']) {
    if (s.startsWith(article)) {
      s = s.substring(article.length);
      break;
    }
  }
  return s;
}
