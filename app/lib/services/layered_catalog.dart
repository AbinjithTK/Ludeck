// Two catalogues, one answer.
//
// The live source knows far more games; the bundled asset always answers. Neither
// alone is right: a proxy-only app is useless offline and on the day the proxy has
// an outage, and a bundle-only app cannot find anything released after the asset
// was written.
//
// The rule is that the primary source LEADS and the fallback FILLS. A game the
// live catalogue knows is always preferred, because it carries a real id, real
// cover art and real dates; the bundled row for the same game is a shadow of it
// and must never displace it or appear beside it.

import '../data/models.dart';
import '../domain/title_match.dart';
import 'catalog_service.dart';

class LayeredCatalog implements CatalogSource, BatchSearch {
  LayeredCatalog({required this.primary, required this.fallback});

  /// Asked first. Its answers rank above the fallback's.
  final CatalogSource primary;

  /// Asked always, and merged in beneath. Expected to be local and cheap.
  final CatalogSource fallback;

  /// The batch form of [search], with the same lead-and-fill merge per phrase.
  /// Only the primary is batched: it is the network one. A primary failure
  /// already maps to empty lists inside [searchAll], so the bundle still fills.
  @override
  Future<Map<String, List<Game>>> searchMany(List<String> queries,
      {int broad = 6}) async {
    final live = await searchAll(primary, queries, broad: broad);
    final local = await searchAll(fallback, queries);
    return {
      for (final q in queries)
        q: () {
          final seen = <String>{};
          return [
            for (final g in [...?live[q], ...?local[q]])
              if (seen.add(catalogDedupKey(g.title))) g,
          ];
        }(),
    };
  }

  @override
  Future<List<Game>> search(String query) async {
    final results = <Game>[];
    final seen = <String>{};

    // The primary's failure is NOT the search's failure. Being offline should
    // degrade search to the bundled set, not empty the screen -- which is the
    // whole reason this class exists rather than a try/catch at the call site.
    var primaryFailed = false;
    try {
      for (final game in await primary.search(query)) {
        if (seen.add(catalogDedupKey(game.title))) results.add(game);
      }
    } on CatalogException {
      primaryFailed = true;
    }

    try {
      for (final game in await fallback.search(query)) {
        // Deduplicated on the NORMALISED title, so "Grand Theft Auto V" from the
        // live source suppresses the bundled row for the same game rather than
        // showing the user two identical-looking entries with different ids --
        // which would then become two rows in their collection.
        if (seen.add(catalogDedupKey(game.title))) results.add(game);
      }
    } on CatalogException {
      // Both sources failed. Only now is the search genuinely unanswerable, and
      // the primary's reason is the more informative one to report.
      if (primaryFailed) {
        throw const CatalogException(
          CatalogFailure.offline,
          'no catalogue could answer',
        );
      }
      rethrow;
    }

    return results;
  }

  @override
  Future<Game?> byId(int igdbId) async {
    // A negative id can only have come from the bundled asset, so asking the live
    // source for one would be a guaranteed miss and a wasted round trip.
    if (igdbId < 0) return fallback.byId(igdbId);
    try {
      final hit = await primary.byId(igdbId);
      if (hit != null) return hit;
    } on CatalogException {
      // Fall through to the bundle.
    }
    return fallback.byId(igdbId);
  }

  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) async {
    try {
      final hit =
          await primary.byExternalId(twitchGameId: twitchGameId, steamAppId: steamAppId);
      if (hit != null) return hit;
    } on CatalogException {
      // The bundle carries no external ids, so there is nothing to fall back to
      // and a failure here is simply "not resolved". The caller still keeps the
      // link as a source row.
    }
    return null;
  }
}
