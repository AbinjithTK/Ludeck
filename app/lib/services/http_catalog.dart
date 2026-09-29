// The real catalogue, over the IGDB proxy. Written now, inert until deployed.
//
// It is written rather than stubbed because the swap has to be one line, not a
// rewrite: the proxy needs account access nobody but the user has (see
// docs/DEPLOY-PROXY.md steps 3 to 6), and code that is only sketched until then
// tends to be wrong in the ways that matter. Every branch here is tested against
// recorded responses, so the day the project ref exists the only unknown left is
// the network.
//
// Two things it deliberately does NOT do:
//
// It does not hold a client secret. The Twitch credentials live in the proxy,
// because a key shipped in an APK is extractable with `strings`.
//
// It does not talk to IGDB's own host. The proxy is the only route, which is
// what `check.ps1` rule 3 enforces by refusing to let that hostname appear in
// `lib/` at all -- including in a comment, which is why this sentence names it
// only in words.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/models.dart';
import 'bundled_catalog.dart';
import 'catalog_service.dart';
import 'layered_catalog.dart';

/// Why a catalogue lookup failed.
///
/// [CatalogFailure] and [CatalogException] used to be declared here. They moved to
/// `catalog_service.dart`, beside the interface, because every source can fail and
/// a caller naming the reason should not have to import the networking layer to do
/// it. Re-exported so no existing import had to change.
///
/// The taxonomy still matters for the same reason it always did: the screen says
/// something different for each. Offline is worth a retry, a malformed response is
/// not the user's problem to fix, and "not configured" is a state the app is
/// deliberately in rather than a fault.
export 'catalog_service.dart' show CatalogFailure, CatalogException;

/// One POST, so the catalogue can be tested without a network.
///
/// Exists instead of taking a dependency on `package:http`: the app needs exactly
/// one request shape, and an injected seam is what lets every branch below be
/// tested against a recorded response.
abstract class CatalogTransport {
  /// POSTs [body] and returns the response body.
  ///
  /// Must throw [CatalogException] with [CatalogFailure.offline] when the host is
  /// unreachable, and with [CatalogFailure.rejected] on a non-2xx.
  Future<String> postJson(Uri url, String body, Map<String, String> headers);
}

/// The real transport. Capped, timed, and redirect-bounded.
class HttpCatalogTransport implements CatalogTransport {
  HttpCatalogTransport({
    this.timeout = const Duration(seconds: 10),
    this.maxBodyBytes = 1 << 20,
  });

  final Duration timeout;

  /// A cap, because a client that reads an unbounded body can be made to run out
  /// of memory by the thing it is talking to.
  final int maxBodyBytes;

  @override
  Future<String> postJson(
      Uri url, String body, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(url);
      // The proxy is a known endpoint, so a redirect is not something to follow.
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      request.write(body);

      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CatalogException(
            CatalogFailure.rejected, 'status ${response.statusCode}');
      }

      final buffer = <int>[];
      await for (final chunk in response) {
        buffer.addAll(chunk);
        if (buffer.length > maxBodyBytes) {
          throw const CatalogException(
              CatalogFailure.malformed, 'body exceeded cap');
        }
      }
      return utf8.decode(buffer);
    } on CatalogException {
      rethrow;
    } on SocketException catch (e) {
      throw CatalogException(CatalogFailure.offline, e.message);
    } on TimeoutException {
      throw const CatalogException(CatalogFailure.offline, 'timed out');
    } finally {
      client.close(force: true);
    }
  }
}

/// The catalogue over the proxy.
///
/// The proxy's contract, from `fallback-kotlin/supabase/functions/igdb/index.ts`:
/// POST a JSON body of `{endpoint, query}` where `endpoint` is one of its
/// allow-listed IGDB endpoints and `query` is an Apicalypse string. The response
/// is IGDB's own JSON array.
/// Where the proxy function runs. Supabase runs a function next to the CALLER
/// by default, but every call makes a second hop to IGDB, which lives in the
/// US; from India that put the proxy in ap-south-1 and the long leg across the
/// Pacific. Pinned next to IGDB, the long leg is paid once instead:
/// measured from India, warm median 1392ms (default, ap-south-1) vs 663ms
/// (us-west-1) vs 771ms (us-east-1). A header, not a secret.
const String kProxyRegion = 'us-west-1';

/// What a search asks for. Shared by single and batched searches so the two
/// can never drift apart.
const String _searchFields = 'id,name,first_release_date,cover.url,total_rating';

class _SearchCache {
  _SearchCache(this.max);
  final int max;
  final Map<String, List<Game>> _map = {};

  List<Game>? get(String key) {
    final hit = _map.remove(key);
    if (hit != null) _map[key] = hit; // most recent last
    return hit;
  }

  void put(String key, List<Game> value) {
    _map.remove(key);
    if (_map.length >= max) _map.remove(_map.keys.first);
    _map[key] = value;
  }
}

class HttpCatalog implements CatalogSource, BatchSearch {
  HttpCatalog({
    required this.baseUrl,
    required this.transport,
    this.anonKey,
  });

  /// Search results by exact phrase, for the life of this catalogue (the app
  /// builds one). The same phrases recur constantly -- a second share of the
  /// same video, the user retyping a search -- and a hit here is a network
  /// round trip not made. Bounded so a long session cannot grow it forever.
  final _SearchCache _searchCache = _SearchCache(256);

  final Uri baseUrl;
  final CatalogTransport transport;

  /// Supabase's anon key. Not a secret in the sense that matters: it authorises
  /// calling the function, not reading the database, and the Twitch credentials
  /// it fronts never leave the server.
  final String? anonKey;

  @override
  Future<List<Game>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final cached = _searchCache.get(trimmed);
    if (cached != null) return cached;

    // Apicalypse. `search` with a where clause rather than a name match, so
    // IGDB's own relevance does the ranking.
    final body = jsonEncode({
      'endpoint': 'games',
      'query': 'search "${_escape(trimmed)}"; '
          // No `time_to_beat`: IGDB removed it from `games` (it lives on the
          // separate game_time_to_beats endpoint now), and naming a field that
          // no longer exists makes IGDB reject the WHOLE query with a 400.
          'fields $_searchFields; '
          'limit 25;',
    });

    final games = _games(await _post(body));
    _searchCache.put(trimmed, games);
    return games;
  }

  /// Many searches in few requests.
  ///
  /// IGDB's multiquery would be the obvious tool, but it silently answers an
  /// empty array for any sub-query that uses `search` -- measured, not assumed.
  /// So: the first [broad] phrases get a real relevance search each, all at
  /// once (these are the ones likely to BE a title, and the only way to reach
  /// acronyms like "botw" or "cod vanguard"), and EVERY phrase is also matched
  /// on exact name in ONE request (`where name ~ "a" | name ~ "b" ...`), which
  /// IGDB answers in the time of a single call. A resolved video title went
  /// from ~20 sequential ~1s calls to one parallel wave.
  ///
  /// A failed request yields empty results for its phrases rather than failing
  /// the batch: resolving a share must degrade, not break.
  @override
  Future<Map<String, List<Game>>> searchMany(List<String> queries,
      {int broad = 6}) async {
    final out = <String, List<Game>>{};
    final todo = <String>[];
    for (final q in queries) {
      final t = q.trim();
      final cached = t.isEmpty ? const <Game>[] : _searchCache.get(t);
      if (cached != null) {
        out[q] = cached;
      } else {
        todo.add(q);
      }
    }
    if (todo.isEmpty) return out;

    final wide = todo.take(broad).toList();
    final wideHits = <String, List<Game>>{};
    final exact = <String, List<Game>>{for (final q in todo) q: []};

    Future<void> broadOne(String q) async {
      try {
        wideHits[q] = await search(q);
      } on CatalogException {
        wideHits[q] = const [];
      }
    }

    Future<void> exactChunk(List<String> chunk) async {
      final where = chunk.map((q) => 'name ~ "${_escape(q.trim())}"').join(' | ');
      try {
        final games = _games(await _post(jsonEncode({
          'endpoint': 'games',
          'query': 'fields $_searchFields; where $where; limit 500;',
        })));
        for (final g in games) {
          final key = g.title.toLowerCase();
          for (final q in chunk) {
            if (q.trim().toLowerCase() == key) exact[q]!.add(g);
          }
        }
      } on CatalogException {
        // Leave these phrases empty.
      }
    }

    // Chunked by query length: the proxy caps a query at 2000 characters.
    final chunks = <List<String>>[];
    var current = <String>[];
    var length = 0;
    for (final q in todo) {
      final cost = q.length + 14;
      if (current.isNotEmpty && length + cost > 1700) {
        chunks.add(current);
        current = [];
        length = 0;
      }
      current.add(q);
      length += cost;
    }
    if (current.isNotEmpty) chunks.add(current);

    await Future.wait([
      ...wide.map(broadOne),
      ...chunks.map(exactChunk),
    ]);

    for (final q in todo) {
      final seen = <int>{};
      final games = [
        for (final g in [...?wideHits[q], ...exact[q]!])
          if (seen.add(g.igdbId)) g,
      ];
      out[q] = games;
      // Only a broad result is a complete answer for that phrase; an
      // exact-only answer must not stand in for a later full search.
      if (wideHits.containsKey(q)) _searchCache.put(q.trim(), games);
    }
    return out;
  }

  @override
  Future<Game?> byId(int igdbId) async {
    final body = jsonEncode({
      'endpoint': 'games',
      'query': 'where id = $igdbId; '
          'fields id,name,first_release_date,cover.url; '
          'limit 1;',
    });
    final games = _games(await _post(body));
    return games.isEmpty ? null : games.first;
  }

  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) async {
    // The exact path. A Twitch clip carries the game id outright, and Steam maps
    // through external_games, so neither needs title matching.
    if (twitchGameId == null && steamAppId == null) return null;

    final where = twitchGameId != null
        // IGDB category 14 is Twitch.
        ? 'where category = 14 & uid = "${_escape(twitchGameId)}"'
        // Category 1 is Steam.
        : 'where category = 1 & uid = "${_escape(steamAppId!)}"';

    final body = jsonEncode({
      'endpoint': 'external_games',
      'query': '$where; fields game; limit 1;',
    });

    final rows = _decodeArray(await _post(body));
    if (rows.isEmpty) return null;
    final gameId = rows.first['game'];
    if (gameId is! int) throw const CatalogException(CatalogFailure.malformed);
    return byId(gameId);
  }

  Future<String> _post(String body) => transport.postJson(
        baseUrl,
        body,
        {
          if (anonKey case final String key) 'Authorization': 'Bearer $key',
          if (anonKey case final String key) 'apikey': key,
          'x-region': kProxyRegion,
        },
      );

  List<Map<String, Object?>> _decodeArray(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw CatalogException(CatalogFailure.malformed, e.message);
    }
    if (decoded is! List) {
      throw const CatalogException(
          CatalogFailure.malformed, 'expected a JSON array');
    }
    return decoded.whereType<Map<String, Object?>>().toList();
  }

  /// Parses IGDB rows into games, SKIPPING any row it cannot read.
  ///
  /// Skipping rather than throwing, and this is the same call `loadDetailed`
  /// makes about a bad database row: one unreadable result must not lose the
  /// other twenty-four. A row with no id or no name is not a game.
  List<Game> _games(String raw) {
    final out = <Game>[];
    for (final row in _decodeArray(raw)) {
      final id = row['id'];
      final name = row['name'];
      if (id is! int || name is! String || name.trim().isEmpty) continue;

      out.add(Game(
        igdbId: id,
        title: name,
        coverUrl: _coverUrl(row['cover']),
        releaseYear: _year(row['first_release_date']),
        // IGDB reports seconds, and `timeToBeatSeconds` IS seconds. Only
        // Game.hours divides it, which is the rule in DECISIONS.md.
        timeToBeatSeconds: _seconds(row['time_to_beat']),
      ));
    }
    return out;
  }

  /// IGDB returns `//images.igdb.com/...` with a `t_thumb` size and no scheme.
  static String? _coverUrl(Object? cover) {
    if (cover is! Map) return null;
    final url = cover['url'];
    if (url is! String || url.isEmpty) return null;
    final sized = url.replaceFirst('t_thumb', 't_cover_big');
    return sized.startsWith('//') ? 'https:$sized' : sized;
  }

  static int? _year(Object? epochSeconds) {
    if (epochSeconds is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true)
        .year;
  }

  static int? _seconds(Object? value) {
    if (value is int) return value;
    // IGDB has served this as an object with a `normally` field.
    if (value is Map && value['normally'] is int) {
      return value['normally'] as int;
    }
    return null;
  }

  /// Apicalypse strings are quoted, so a quote in a title would end the string.
  static String _escape(String raw) =>
      raw.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

/// Where the proxy lives: the `igdb` Edge Function on the project given at
/// build time (`--dart-define=SUPABASE_URL=https://<ref>.supabase.co`, the
/// same define the social backend reads). Empty on a plain build, which keeps
/// search on the bundled catalogue.
const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String catalogBaseUrl =
    _supabaseUrl == '' ? '' : '$_supabaseUrl/functions/v1/igdb';

/// Supabase publishable key, sent as the function's apikey header.
const String catalogAnonKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// The catalogue the app actually runs on.
///
/// The bundled asset is ALWAYS present, and that is the important change. This
/// function used to return the ten-row fixture whenever `catalogBaseUrl` was
/// empty, which meant the shipped app had a search box that could not find Grand
/// Theft Auto V -- a broken feature wearing the costume of a pending integration.
///
/// With the proxy configured the live source goes in front and the bundle becomes
/// the offline fallback. Filling in `catalogBaseUrl` is still the entire swap, and
/// now it upgrades search instead of switching it on.
CatalogSource resolveCatalog({CatalogTransport? transport}) {
  final bundled = BundledCatalog();
  if (catalogBaseUrl.isEmpty) return bundled;
  return LayeredCatalog(
    primary: HttpCatalog(
      baseUrl: Uri.parse(catalogBaseUrl),
      anonKey: catalogAnonKey.isEmpty ? null : catalogAnonKey,
      transport: transport ?? HttpCatalogTransport(),
    ),
    fallback: bundled,
  );
}
