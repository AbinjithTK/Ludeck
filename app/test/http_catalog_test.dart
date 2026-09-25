// The HTTP catalogue, against recorded responses.
//
// The proxy is not deployed (docs/DEPLOY-PROXY.md steps 3 to 6 need account
// access), so this is what "written and inert" has to mean if it is to be worth
// anything: every branch exercised now, against real IGDB response shapes, so the
// day a project ref exists the only untested thing left is the network itself.
//
// Plain `test()`, not testWidgets: there is no widget and no database here.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/services/bundled_catalog.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/http_catalog.dart';

/// Returns a canned body, and records what was asked.
class FakeTransport implements CatalogTransport {
  FakeTransport(this._body) : _failure = null;

  FakeTransport.throwing(CatalogFailure failure)
      : _body = '',
        _failure = failure;

  final String _body;
  final CatalogFailure? _failure;

  final List<String> requests = [];
  final List<Map<String, String>> headers = [];

  @override
  Future<String> postJson(
      Uri url, String body, Map<String, String> requestHeaders) async {
    requests.add(body);
    headers.add(requestHeaders);
    final failure = _failure;
    if (failure != null) throw CatalogException(failure);
    return _body;
  }
}

/// A search response in IGDB's real shape, including the cover url with no
/// scheme and the `time_to_beat` object form.
const String _searchBody = '''
[
  {
    "id": 1030,
    "name": "Hollow Knight",
    "first_release_date": 1487116800,
    "cover": {"url": "//images.igdb.com/igdb/image/upload/t_thumb/co1rbi.jpg"},
    "time_to_beat": 93600
  },
  {
    "id": 7597,
    "name": "Celeste",
    "first_release_date": 1516752000,
    "time_to_beat": {"normally": 28800}
  }
]
''';

void main() {
  group('the swap is one line', () {
    test('resolveCatalog returns the bundled catalogue while no base url is set',
        () {
      // This assertion CHANGED, deliberately. It used to expect FixtureCatalog,
      // and that was the bug: the shipped app resolved to ten hardcoded rows, so
      // its search box could not find Grand Theft Auto V. Returning the bundled
      // asset means search works with no proxy, no key and no network.
      expect(catalogBaseUrl, isEmpty,
          reason: 'when this is filled in, the assertion below changes meaning');
      expect(resolveCatalog(), isA<BundledCatalog>());
      // And specifically NOT the fixture, which is now for tests only.
      expect(resolveCatalog(), isNot(isA<FixtureCatalog>()));
    });
  });

  group('search', () {
    test('parses a real response shape', () async {
      final transport = FakeTransport(_searchBody);
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/functions/v1/igdb'),
        transport: transport,
      );

      final games = await catalog.search('hollow');

      expect(games, hasLength(2));
      expect(games.first.title, 'Hollow Knight');
      expect(games.first.releaseYear, 2017);
      // timeToBeatSeconds IS seconds. Only Game.hours divides it, per
      // DECISIONS.md, and 93600 seconds is 26 hours.
      expect(games.first.timeToBeatSeconds, 93600);
      expect(games.first.hours, 26);
    });

    test('handles the object form of time_to_beat', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport(_searchBody),
      );
      final games = await catalog.search('celeste');

      // IGDB has served this field both as an int and as an object. Reading only
      // one shape would silently lose every length.
      expect(games[1].timeToBeatSeconds, 28800);
      expect(games[1].hours, 8);
    });

    test('a cover url gets a scheme and a usable size', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport(_searchBody),
      );
      final games = await catalog.search('hollow');

      // IGDB returns "//images.igdb.com/..." with t_thumb, which is 90px wide.
      expect(games.first.coverUrl, startsWith('https://'));
      expect(games.first.coverUrl, contains('t_cover_big'));
      expect(games.first.coverUrl, isNot(contains('t_thumb')));
    });

    test('an empty query never reaches the network', () async {
      final transport = FakeTransport('[]');
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: transport,
      );

      expect(await catalog.search('   '), isEmpty);
      expect(transport.requests, isEmpty,
          reason: 'a blank query is not a request worth paying for');
    });

    test('a quote in the query cannot break out of the Apicalypse string',
        () async {
      final transport = FakeTransport('[]');
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: transport,
      );

      await catalog.search('Marvel\'s "Spider-Man"');

      final sent = jsonDecode(transport.requests.single) as Map;
      final query = sent['query'] as String;
      // Apicalypse strings are quoted, so an unescaped quote would terminate the
      // search term and the rest would be read as syntax.
      expect(query, contains(r'\"Spider-Man\"'));
      expect(sent['endpoint'], 'games');
    });

    test('a row with no id or no name is skipped, not fatal', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport('''
          [
            {"id": 1, "name": "Real Game"},
            {"name": "No id"},
            {"id": 3},
            {"id": 4, "name": "   "},
            {"id": 5, "name": "Another Real Game"}
          ]
        '''),
      );

      final games = await catalog.search('game');

      // The same call loadDetailed makes about a bad database row: one
      // unreadable result must not lose the others.
      expect(games.map((g) => g.title), ['Real Game', 'Another Real Game']);
    });

    test('an empty array is an empty result, not a failure', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport('[]'),
      );

      // "Nothing matched" and "could not search" mean opposite things.
      expect(await catalog.search('zzzz'), isEmpty);
    });
  });

  group('failures', () {
    test('malformed JSON surfaces as malformed', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport('not json at all'),
      );

      await expectLater(
        catalog.search('hollow'),
        throwsA(isA<CatalogException>().having(
            (e) => e.failure, 'failure', CatalogFailure.malformed)),
      );
    });

    test('a JSON object where an array belongs is malformed', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport('{"error": "endpoint not allowed"}'),
      );

      await expectLater(
        catalog.search('hollow'),
        throwsA(isA<CatalogException>().having(
            (e) => e.failure, 'failure', CatalogFailure.malformed)),
      );
    });

    test('offline propagates from the transport unchanged', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport.throwing(CatalogFailure.offline),
      );

      await expectLater(
        catalog.search('hollow'),
        throwsA(isA<CatalogException>()
            .having((e) => e.failure, 'failure', CatalogFailure.offline)),
      );
    });

    test('a rejection is not reported as an empty result', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport.throwing(CatalogFailure.rejected),
      );

      // Swallowing this into "no results" would tell the user their game does
      // not exist when the truth is that nobody asked.
      await expectLater(
        catalog.search('hollow'),
        throwsA(isA<CatalogException>()
            .having((e) => e.failure, 'failure', CatalogFailure.rejected)),
      );
    });
  });

  group('byId and byExternalId', () {
    test('byId returns one game, or null', () async {
      final found = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport('[{"id": 1030, "name": "Hollow Knight"}]'),
      );
      expect((await found.byId(1030))?.title, 'Hollow Knight');

      final missing = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport('[]'),
      );
      expect(await missing.byId(999999), isNull);
    });

    test('byExternalId with neither id asks nothing', () async {
      final transport = FakeTransport('[]');
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: transport,
      );

      expect(await catalog.byExternalId(), isNull);
      expect(transport.requests, isEmpty);
    });

    test('a Twitch game id queries external_games by its own category',
        () async {
      final transport = FakeTransport('[{"game": 1030}]');
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: transport,
      );

      // It resolves the external row, then the game, so two requests.
      await catalog.byExternalId(twitchGameId: '491578');

      final first = jsonDecode(transport.requests.first) as Map;
      expect(first['endpoint'], 'external_games');
      expect(first['query'], contains('category = 14'));
      expect(first['query'], contains('491578'));
    });

    test('a Steam appid uses the Steam category', () async {
      final transport = FakeTransport('[{"game": 1030}]');
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: transport,
      );

      await catalog.byExternalId(steamAppId: '367520');

      final first = jsonDecode(transport.requests.first) as Map;
      expect(first['query'], contains('category = 1'));
      expect(first['query'], contains('367520'));
    });

    test('an external row with a non-integer game id is malformed', () async {
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: FakeTransport('[{"game": "not an id"}]'),
      );

      await expectLater(
        catalog.byExternalId(twitchGameId: '1'),
        throwsA(isA<CatalogException>().having(
            (e) => e.failure, 'failure', CatalogFailure.malformed)),
      );
    });
  });

  group('credentials', () {
    test('no anon key means no auth headers', () async {
      final transport = FakeTransport('[]');
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: transport,
      );

      await catalog.byId(1);
      expect(transport.headers.single, isEmpty);
    });

    test('an anon key is sent as both headers Supabase wants', () async {
      final transport = FakeTransport('[]');
      final catalog = HttpCatalog(
        baseUrl: Uri.parse('https://example.test/igdb'),
        transport: transport,
        anonKey: 'anon-abc',
      );

      await catalog.byId(1);
      expect(transport.headers.single['Authorization'], 'Bearer anon-abc');
      expect(transport.headers.single['apikey'], 'anon-abc');
    });
  });
}
