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
class HttpCatalog implements CatalogSource {
  const HttpCatalog({
    required this.baseUrl,
    required this.transport,
    this.anonKey,
  });

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

    // Apicalypse. `search` with a where clause rather than a name match, so
    // IGDB's own relevance does the ranking.
    final body = jsonEncode({
      'endpoint': 'games',
      'query': 'search "${_escape(trimmed)}"; '
          'fields id,name,first_release_date,cover.url,'
          'time_to_beat,total_rating; '
          'limit 25;',
    });

    return _games(await _post(body));
  }

  @override
  Future<Game?> byId(int igdbId) async {
    final body = jsonEncode({
      'endpoint': 'games',
      'query': 'where id = $igdbId; '
          'fields id,name,first_release_date,cover.url,time_to_beat; '
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

/// Where the proxy lives, once it exists.
///
/// Empty today, and that is the whole reason `resolveCatalog` returns the
/// fixture. Filling this in is the one-line swap: no caller changes.
const String catalogBaseUrl = '';

/// Supabase anon key for the function. Empty until the project exists.
const String catalogAnonKey = '';

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
