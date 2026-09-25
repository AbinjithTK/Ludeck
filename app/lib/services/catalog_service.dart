// Where game facts come from.
//
// An interface with three implementations behind it: the ten-row fixture used by
// tests, the BUNDLED asset catalogue that ships in the app, and the HTTP source
// that talks to the deployed proxy. `resolveCatalog` in http_catalog.dart decides
// which combination actually runs.
//
// Why a bundled catalogue exists at all: for most of this app's life
// `resolveCatalog` returned the ten-row fixture, so searching for any real game
// found nothing. That is not a missing integration, it is a broken feature -- the
// app looked like it had search and did not. The bundled asset is the floor, and
// the proxy raises it rather than being the only thing that makes it work.

import '../data/models.dart';
import '../domain/title_match.dart';

// Re-exported so that every existing `normaliseTitle` caller keeps working while
// the definition lives with the rest of the matching logic. Two copies of that
// function would drift, and the drift would only show on one code path.
export '../domain/title_match.dart' show normaliseTitle, TitleKeys, MatchTier;

/// Why a catalogue lookup could not be answered.
///
/// Lives here, on the interface, rather than with the HTTP implementation: every
/// source can fail, and a caller catching this should not have to import the
/// networking layer to name the reason. `http_catalog.dart` re-exports it so the
/// existing imports are untouched.
enum CatalogFailure {
  /// The network could not be reached.
  offline,

  /// A reply arrived and could not be understood. Never offer a retry: the same
  /// request will produce the same unreadable answer.
  malformed,

  /// The far end refused the request.
  rejected,

  /// No catalogue is configured. Distinct from a failure -- nothing is wrong.
  notConfigured,
}

class CatalogException implements Exception {
  const CatalogException(this.failure, [this.detail]);

  final CatalogFailure failure;
  final String? detail;

  @override
  String toString() =>
      'CatalogException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// A lookup of games. Never writes; the repository owns writes.
abstract class CatalogSource {
  /// Games whose title matches [query], best first. Empty when nothing matches.
  ///
  /// Empty is a real answer meaning "no such game". A source that cannot answer
  /// at all throws [CatalogException] instead, because "nothing matched" and
  /// "could not search" mean opposite things to the person typing.
  Future<List<Game>> search(String query);

  /// One game by its IGDB id.
  Future<Game?> byId(int igdbId);

  /// One game by another platform's identifier.
  ///
  /// This is the exact path and the reason it exists. A Twitch clip carries the
  /// game id outright and Twitch's own Get Games both accepts and returns an
  /// `igdb_id`, so the mapping needs no title matching at all. A Steam appid
  /// maps through the catalogue's external ids the same way.
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId});
}

/// The catalogue backed by `fixtureTree()`.
///
/// Ten rows, and kept for tests rather than for shipping: it is enough to
/// exercise the whole share pipeline without an asset or a network. Routed
/// through [rankByKeys] so its ordering is the same code the real sources use --
/// it used to have its own, which meant a test proving the fixture's ordering
/// proved nothing about the app's.
class FixtureCatalog implements CatalogSource {
  FixtureCatalog() : _games = fixtureTree().map((t) => t.game).toList();

  FixtureCatalog.of(this._games);

  final List<Game> _games;

  @override
  Future<List<Game>> search(String query) async => rankByKeys(
        _games.map((g) => (value: g, keys: TitleKeys(g.title))),
        query,
      );

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
