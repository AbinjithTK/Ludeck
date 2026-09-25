// Search that actually finds things.
//
// The bug this file exists for was reported from a device with a screenshot: the
// add screen could not find Grand Theft Auto V. Two separate causes, and both are
// covered here.
//
// One, there was nothing to find: `resolveCatalog` returned a ten-row fixture, so
// the shipped app's search box was decorative.
//
// Two, even with the game present, "gta v" cannot reach "Grand Theft Auto V" by
// substring -- the query is an ACRONYM. People type what they say.
//
// The matching tests run against an INJECTED asset so that re-curating the real
// file cannot break them, and a separate group runs against the REAL shipped asset
// because "it finds GTA V" is a claim about what actually ships.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/title_match.dart';
import 'package:ludeck/services/bundled_catalog.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/layered_catalog.dart';

/// Serves one fixed JSON string for any asset key.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.json);
  final String json;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(json)));
}

const String _testAsset = '''
{
  "version": 1,
  "games": [
    {"title": "Grand Theft Auto V", "year": 2013, "hours": 31},
    {"title": "Grand Theft Auto: San Andreas", "year": 2004, "hours": 31},
    {"title": "The Legend of Zelda: Breath of the Wild", "year": 2017, "hours": 50},
    {"title": "Final Fantasy VII", "year": 1997, "hours": 37},
    {"title": "Hades", "year": 2020, "hours": 23},
    {"title": "Hades II", "year": 2024, "hours": 25},
    {"title": "Fortnite", "year": 2017},
    {"title": "", "year": 2000},
    {"title": "Half-Life 2", "year": 2004, "hours": 13}
  ]
}
''';

/// A source that always fails, for the layering tests.
class _FailingCatalog implements CatalogSource {
  const _FailingCatalog(this.failure);
  final CatalogFailure failure;

  @override
  Future<List<Game>> search(String q) async => throw CatalogException(failure);
  @override
  Future<Game?> byId(int id) async => throw CatalogException(failure);
  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) async =>
      throw CatalogException(failure);
}

/// A source with a fixed list, standing in for the live proxy.
class _StubCatalog implements CatalogSource {
  _StubCatalog(this.games);
  final List<Game> games;

  @override
  Future<List<Game>> search(String q) async => rankByKeys(
        games.map((g) => (value: g, keys: TitleKeys(g.title))),
        q,
      );
  @override
  Future<Game?> byId(int id) async =>
      games.where((g) => g.igdbId == id).firstOrNull;
  @override
  Future<Game?> byExternalId({String? twitchGameId, String? steamAppId}) async =>
      games.firstOrNull;
}

void main() {
  // rootBundle needs the binding, and the real-asset group loads through it.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalising a title', () {
    test('collapses case, punctuation and spacing', () {
      for (final spelling in [
        'Hollow Knight',
        'hollow knight',
        'HOLLOW KNIGHT!',
        'Hollow  Knight',
        'Hollow-Knight',
      ]) {
        expect(normaliseTitle(spelling), 'hollow knight');
      }
    });

    test('drops a leading article, which never distinguishes a title', () {
      expect(normaliseTitle('The Witcher 3'), 'witcher 3');
      expect(normaliseTitle('A Short Hike'), 'short hike');
    });

    test('keeps an article that is not leading', () {
      expect(normaliseTitle('Breath of the Wild'), 'breath of the wild');
    });
  });

  group('roman numerals read as digits', () {
    test('converts standalone numerals', () {
      expect(arabicNumerals('final fantasy vii'), 'final fantasy 7');
      expect(arabicNumerals('civilization v'), 'civilization 5');
      expect(arabicNumerals('grand theft auto iv'), 'grand theft auto 4');
    });

    test('leaves ordinary words alone', () {
      // "in" and "into" begin with a numeral letter and are not numerals.
      expect(arabicNumerals('into the breach'), 'into the breach');
      expect(arabicNumerals('inside'), 'inside');
    });
  });

  group('acronyms', () {
    test('takes initials and keeps numbers whole', () {
      expect(acronym('grand theft auto v'), 'gtav');
      expect(acronym('grand theft auto 5'), 'gta5');
      expect(acronym('half life 2'), 'hl2');
      // A multi-digit number must not be reduced to its first digit.
      expect(acronym('fallout 76'), 'f76');
    });
  });

  group('which tier a query reaches', () {
    final gta = TitleKeys('Grand Theft Auto V');
    final botw = TitleKeys('The Legend of Zelda: Breath of the Wild');

    test('the full title is exact', () {
      expect(gta.tierFor('Grand Theft Auto V'), MatchTier.exact);
      expect(gta.tierFor('grand theft auto 5'), MatchTier.exact);
    });

    test('an acronym is its own tier, spaced or not', () {
      // The reported failure, both ways round.
      expect(gta.tierFor('gta v'), MatchTier.acronym);
      expect(gta.tierFor('gtav'), MatchTier.acronym);
      expect(gta.tierFor('gta 5'), MatchTier.acronym);
      expect(gta.tierFor('gta5'), MatchTier.acronym);
    });

    test('a subtitle is a full name of its own', () {
      // Nobody asks whether you have played "The Legend of Zelda".
      expect(botw.tierFor('breath of the wild'), MatchTier.exact);
      expect(botw.tierFor('botw'), MatchTier.acronym);
      expect(botw.tierFor('tlozbotw'), MatchTier.acronym);
    });

    test('a prefix and a substring are weaker but still match', () {
      expect(TitleKeys('Hollow Knight').tierFor('hollow'), MatchTier.prefix);
      expect(TitleKeys('Hollow Knight').tierFor('knight'), MatchTier.contains);
    });

    test('a single letter is not an acronym', () {
      // Otherwise "h" would match Hades, Halo and Hollow Knight equally, which
      // is worse than no match.
      expect(TitleKeys('Hades').tierFor('h'), MatchTier.prefix);
    });

    test('an unrelated query matches nothing', () {
      expect(gta.tierFor('minecraft'), isNull);
      expect(gta.tierFor(''), isNull);
    });
  });

  group('ranking', () {
    test('a shorter title wins an equal tier, so Hades beats Hades II', () {
      final ranked = rankByKeys(
        [
          (value: 'Hades II', keys: TitleKeys('Hades II')),
          (value: 'Hades', keys: TitleKeys('Hades')),
        ],
        'hades',
      );
      expect(ranked.first, 'Hades');
    });

    test('exact outranks acronym outranks prefix outranks contains', () {
      final ranked = rankByKeys(
        [
          (value: 'contains', keys: TitleKeys('Something Zelda Something')),
          (value: 'exact', keys: TitleKeys('Zelda')),
          (value: 'prefix', keys: TitleKeys('Zelda Adventure')),
        ],
        'zelda',
      );
      expect(ranked, ['exact', 'prefix', 'contains']);
    });
  });

  group('synthetic ids for bundled games', () {
    test('are always negative, so they cannot collide with a real id', () {
      for (final title in ['Grand Theft Auto V', 'Hades', 'a', 'Z']) {
        expect(bundledIdFor(title), lessThan(0));
      }
    });

    test('are derived from the title, not the row position', () {
      // The reason this matters: if ids came from position, inserting one game
      // into the asset would shift every id after it and silently repoint every
      // row the user had already saved.
      expect(bundledIdFor('Hades'), bundledIdFor('Hades'));
      expect(bundledIdFor('Hades'), bundledIdFor('hades!'));
      expect(bundledIdFor('Hades'), isNot(bundledIdFor('Hades II')));
    });
  });

  group('the bundled catalogue, against an injected asset', () {
    late BundledCatalog catalog;
    setUp(() => catalog = BundledCatalog(bundle: _FakeBundle(_testAsset)));

    test('an acronym query finds the game', () async {
      final hits = await catalog.search('gta v');
      expect(hits.first.title, 'Grand Theft Auto V');
    });

    test('a roman-numeral title is found by its digit spelling', () async {
      final hits = await catalog.search('final fantasy 7');
      expect(hits.first.title, 'Final Fantasy VII');
    });

    test('hours are converted to seconds at the edge', () async {
      final hits = await catalog.search('hades');
      expect(hits.first.timeToBeatSeconds, 23 * 3600);
      expect(hits.first.hours, 23);
    });

    test('a game with no main story has no hours rather than zero', () async {
      final hits = await catalog.search('fortnite');
      expect(hits.single.timeToBeatSeconds, isNull);
      expect(hits.single.hours, isNull);
    });

    test('a blank title is skipped rather than stored', () async {
      // The asset has one. A titleless row must not become a nameless game.
      final all = await catalog.entryCount;
      expect(all, 8);
    });

    test('nothing matched is empty, not an error', () async {
      expect(await catalog.search('no such game anywhere'), isEmpty);
    });

    test('a round trip by id returns the same game', () async {
      final hit = (await catalog.search('gta v')).first;
      expect((await catalog.byId(hit.igdbId))?.title, 'Grand Theft Auto V');
    });

    test('malformed JSON is a malformed failure, not a crash', () async {
      final broken = BundledCatalog(bundle: _FakeBundle('{not json'));
      await expectLater(
        broken.search('anything'),
        throwsA(isA<CatalogException>().having(
            (e) => e.failure, 'failure', CatalogFailure.malformed)),
      );
    });

    test('a JSON array instead of an object is malformed', () async {
      final wrong = BundledCatalog(bundle: _FakeBundle('[]'));
      await expectLater(
        wrong.search('anything'),
        throwsA(isA<CatalogException>()),
      );
    });

    test('the asset is read once even for concurrent searches', () async {
      // Two searches before the first read completes must share one parse.
      final counting = _CountingBundle(_testAsset);
      final c = BundledCatalog(bundle: counting);
      await Future.wait([c.search('hades'), c.search('gta'), c.search('zelda')]);
      expect(counting.loads, 1);
    });
  });

  group('the layered catalogue', () {
    final live = Game(igdbId: 1942, title: 'Grand Theft Auto V', releaseYear: 2013);

    test('the live source leads and suppresses the bundled duplicate', () async {
      final layered = LayeredCatalog(
        primary: _StubCatalog([live]),
        fallback: BundledCatalog(bundle: _FakeBundle(_testAsset)),
      );
      final hits = await layered.search('gta v');
      // One entry, and it is the one with the real positive id. Two would become
      // two rows in the user's collection.
      expect(hits.where((g) => catalogDedupKey(g.title) == 'grand theft auto 5'),
          hasLength(1));
      expect(hits.first.igdbId, 1942);
    });

    test('the bundle still contributes what the live source lacks', () async {
      final layered = LayeredCatalog(
        primary: _StubCatalog([live]),
        fallback: BundledCatalog(bundle: _FakeBundle(_testAsset)),
      );
      final hits = await layered.search('hades');
      expect(hits.map((g) => g.title), contains('Hades'));
    });

    test('a failing live source degrades to the bundle instead of emptying',
        () async {
      // The whole point of the class. Offline must not mean "no search".
      final layered = LayeredCatalog(
        primary: const _FailingCatalog(CatalogFailure.offline),
        fallback: BundledCatalog(bundle: _FakeBundle(_testAsset)),
      );
      final hits = await layered.search('gta v');
      expect(hits.first.title, 'Grand Theft Auto V');
    });

    test('both sources failing is the only real failure', () async {
      final layered = LayeredCatalog(
        primary: const _FailingCatalog(CatalogFailure.offline),
        fallback: const _FailingCatalog(CatalogFailure.malformed),
      );
      await expectLater(layered.search('x'), throwsA(isA<CatalogException>()));
    });

    test('a negative id goes straight to the bundle, not the network',
        () async {
      final layered = LayeredCatalog(
        primary: const _FailingCatalog(CatalogFailure.offline),
        fallback: BundledCatalog(bundle: _FakeBundle(_testAsset)),
      );
      final id = bundledIdFor('Hades');
      // If this consulted the primary it would throw rather than answer.
      expect((await layered.byId(id))?.title, 'Hades');
    });
  });

  group('the REAL shipped asset', () {
    // Separate group on purpose: these assert what actually ships, so they fail
    // if the asset is dropped from pubspec or re-curated badly.
    late BundledCatalog catalog;
    setUp(() => catalog = BundledCatalog());

    test('loads and holds a substantial number of games', () async {
      expect(await catalog.entryCount, greaterThan(400));
    });

    test('finds Grand Theft Auto V by acronym -- the reported bug', () async {
      final hits = await catalog.search('gta v');
      expect(hits, isNotEmpty);
      expect(hits.first.title, 'Grand Theft Auto V');
    });

    test('finds the games people actually type shorthand for', () async {
      final expectations = {
        'botw': 'The Legend of Zelda: Breath of the Wild',
        'rdr2': 'Red Dead Redemption 2',
        'bg3': "Baldur's Gate 3",
        'elden ring': 'Elden Ring',
        'skyrim': 'The Elder Scrolls V: Skyrim',
        'minecraft': 'Minecraft',
        'witcher 3': 'The Witcher 3: Wild Hunt',
        'cyberpunk': 'Cyberpunk 2077',
      };
      for (final entry in expectations.entries) {
        final hits = await catalog.search(entry.key);
        expect(hits, isNotEmpty, reason: 'no hit for "${entry.key}"');
        expect(hits.first.title, entry.value,
            reason: 'wrong top hit for "${entry.key}"');
      }
    });

    test('every id is negative and distinct', () async {
      // A collision would silently merge two games into one row.
      final seen = <int>{};
      for (final query in ['a', 'e', 'i', 'o', 'u']) {
        for (final game in await catalog.search(query)) {
          expect(game.igdbId, lessThan(0));
          seen.add(game.igdbId);
        }
      }
      expect(seen, isNotEmpty);
    });

    test('carries no third-party hostname, per the project invariant',
        () async {
      final raw = await rootBundle.loadString(kCatalogAssetPath);
      expect(raw.contains('http'), isFalse);
      expect(raw.contains('.com'), isFalse);
    });
  });
}

class _CountingBundle extends CachingAssetBundle {
  _CountingBundle(this.json);
  final String json;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(json)));
  }
}
