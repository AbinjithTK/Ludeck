// A shared link becomes a game.
//
// The screenshot that prompted this work showed "Nothing recognised -- that link
// could not be matched to a game yet". Two separate reasons, both fixed and both
// covered here: there was no catalogue to match against, and the page-title tier
// was never built because it was believed to need the deployed proxy. It does not.
//
// Nothing in this file touches the network. The transport is injected, so every
// oEmbed shape and every failure mode is a recorded string.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/resolve.dart';
import 'package:ludeck/domain/video_title.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/link_metadata.dart';
import 'package:ludeck/services/share_resolver.dart';

/// Serves a canned response per URL, and records what was asked for.
class _FakeTransport implements PageTransport {
  _FakeTransport(this.responses);

  /// Keyed by a substring of the requested URL, so a test does not have to
  /// reproduce oEmbed's exact query encoding.
  final Map<String, PageResponse> responses;
  final List<Uri> requested = [];

  @override
  Future<PageResponse> get(Uri url) async {
    requested.add(url);
    for (final entry in responses.entries) {
      if (url.toString().contains(entry.key)) return entry.value;
    }
    throw const _NoRoute();
  }
}

class _NoRoute implements Exception {
  const _NoRoute();
}

PageResponse _json(String body) =>
    PageResponse(statusCode: 200, body: body, contentType: 'application/json');

PageResponse _html(String body) =>
    PageResponse(statusCode: 200, body: body, contentType: 'text/html');

/// A catalogue holding exactly the games these tests reason about.
CatalogSource _catalog() => FixtureCatalog.of([
      Game(igdbId: 1, title: 'Grand Theft Auto V', releaseYear: 2013),
      Game(igdbId: 2, title: 'Hades', releaseYear: 2020),
      Game(igdbId: 3, title: 'Hades II', releaseYear: 2024),
      Game(igdbId: 4, title: 'Elden Ring', releaseYear: 2022),
      Game(igdbId: 5, title: 'Control', releaseYear: 2019),
      Game(igdbId: 6, title: 'The Legend of Zelda: Breath of the Wild', releaseYear: 2017),
    ]);

void main() {
  group('pulling candidate names out of a video title', () {
    test('finds the game in a title full of production noise', () {
      final phrases = videoTitlePhrases(
        'GTA 5 in 2026 is STILL Amazing | Full Playthrough Part 1 [4K 60FPS]',
      );
      expect(phrases, contains('GTA 5'));
    });

    test('finds a name buried mid-sentence', () {
      final phrases =
          videoTitlePhrases('I beat ELDEN RING without dodging once');
      expect(phrases, contains('ELDEN RING'));
    });

    test('finds a name that trails a label', () {
      // The "Review: Hades II" shape, where the name is last.
      final phrases = videoTitlePhrases('Early Access Review - Hades II');
      expect(phrases, contains('Hades II'));
    });

    test('keeps hyphens and colons, which real titles contain', () {
      // Splitting on these would destroy the very names being looked for.
      final phrases = videoTitlePhrases('Half-Life: Alyx is a masterpiece');
      expect(phrases.any((p) => p.contains('Half-Life: Alyx')), isTrue);
    });

    test('splits on a spaced hyphen, which titles do not contain', () {
      final phrases = videoTitlePhrases('Hades II - my honest thoughts');
      expect(phrases, contains('Hades II'));
    });

    test('drops a candidate that is nothing but noise', () {
      final phrases = videoTitlePhrases('Part 1 | 4K | No Commentary');
      expect(phrases, isEmpty);
    });

    test('an empty or decorative title yields nothing', () {
      expect(videoTitlePhrases(''), isEmpty);
      expect(videoTitlePhrases('   '), isEmpty);
      expect(videoTitlePhrases('🔥🔥🔥'), isEmpty);
    });

    test('orders longer candidates before their own prefixes', () {
      final phrases = videoTitlePhrases('Hades II Early Access');
      final full = phrases.indexOf('Hades II Early Access');
      final shorter = phrases.indexOf('Hades II');
      expect(full, lessThan(shorter));
    });
  });

  group('which links may be fetched', () {
    test('https on the default port is allowed', () {
      expect(refuseLink(Uri.parse('https://example.test/watch?v=1')), isNull);
    });

    test('plain http is refused, because it would leak the link', () {
      expect(refuseLink(Uri.parse('http://example.test/')), LinkRefusal.scheme);
    });

    test('the local machine and the home network are refused', () {
      // A phone cannot reach a cloud metadata service, but it CAN be walked into
      // probing the user's own router from inside their LAN.
      for (final host in [
        'https://127.0.0.1/',
        'https://localhost/',
        'https://10.0.0.1/',
        'https://192.168.1.1/',
        'https://172.16.5.4/',
        'https://169.254.169.254/',
        'https://router.local/',
        'https://thing.internal/',
      ]) {
        expect(refuseLink(Uri.parse(host)), LinkRefusal.privateAddress,
            reason: host);
      }
    });

    test('a public address that merely looks private is allowed', () {
      // 172.32 is outside the private range; 11.x is public.
      expect(refuseLink(Uri.parse('https://172.32.0.1/')), isNull);
      expect(refuseLink(Uri.parse('https://11.0.0.1/')), isNull);
    });

    test('embedded credentials and odd ports are refused', () {
      expect(refuseLink(Uri.parse('https://user:pw@example.test/')),
          LinkRefusal.credentials);
      expect(refuseLink(Uri.parse('https://example.test:8443/')),
          LinkRefusal.port);
    });
  });

  group('reading a title out of HTML', () {
    test('prefers Open Graph over the title element', () {
      // og:title is what the page wants to be called when shared; <title> carries
      // site furniture.
      const html = '''
        <html><head>
        <title>Hades II review | Some Site</title>
        <meta property="og:title" content="Hades II is the sequel we wanted">
        </head></html>''';
      expect(titleFromHtml(html), 'Hades II is the sequel we wanted');
    });

    test('falls back to JSON-LD, then to the title element', () {
      const ld = '<html><script type="application/ld+json">'
          '{"@type":"VideoObject","name":"Elden Ring in 2026"}</script></html>';
      expect(titleFromHtml(ld), 'Elden Ring in 2026');

      const plain = '<html><head><title>Just a title</title></head></html>';
      expect(titleFromHtml(plain), 'Just a title');
    });

    test('unescapes entities', () {
      const html =
          '<html><head><title>Ratchet &amp; Clank &#39;s return</title></head></html>';
      expect(titleFromHtml(html), "Ratchet & Clank 's return");
    });

    test('a page with no title at all is null, not an empty string', () {
      expect(titleFromHtml('<html><body>nothing</body></html>'), isNull);
    });
  });

  group('oEmbed endpoints', () {
    test('are chosen for the hosts that render their titles with script', () {
      // These pages often do not contain the title in their HTML at all.
      for (final url in [
        'https://www.youtube.com/watch?v=abc',
        'https://youtu.be/abc',
        'https://www.tiktok.com/@someone/video/123',
        'https://vimeo.com/123',
        'https://x.com/someone/status/123',
        'https://www.reddit.com/r/games/comments/abc/title/',
      ]) {
        expect(oEmbedEndpointFor(Uri.parse(url)), isNotNull, reason: url);
      }
    });

    test('an ordinary site has none and is read as a page', () {
      expect(oEmbedEndpointFor(Uri.parse('https://someblog.test/post')), isNull);
    });
  });

  group('the metadata reader', () {
    test('reads a title from an unauthenticated oEmbed reply', () async {
      // The key finding: this needs no API key. A YouTube Data API key is for
      // statistics and captions, not for a title.
      final transport = _FakeTransport({
        'youtube.com/oembed': _json('{"title":"Hades II Early Access review"}'),
      });
      final reader = LinkMetadataReader(transport: transport);
      final title =
          await reader.titleFor(Uri.parse('https://www.youtube.com/watch?v=x'));
      expect(title, 'Hades II Early Access review');
    });

    test('reads post text out of an oEmbed html payload', () async {
      final transport = _FakeTransport({
        'publish.x.com': _json(
            '{"html":"<blockquote><p>Just finished Elden Ring</p></blockquote>"}'),
      });
      final reader = LinkMetadataReader(transport: transport);
      final title = await reader
          .titleFor(Uri.parse('https://x.com/someone/status/123'));
      expect(title, contains('Elden Ring'));
    });

    test('falls back to the page when oEmbed misses', () async {
      final transport = _FakeTransport({
        'youtube.com/oembed': const PageResponse(statusCode: 404, body: ''),
        'youtube.com/watch': _html(
            '<meta property="og:title" content="Control walkthrough">'),
      });
      final reader = LinkMetadataReader(transport: transport);
      final title = await reader
          .titleFor(Uri.parse('https://www.youtube.com/watch?v=x'));
      expect(title, 'Control walkthrough');
    });

    test('a refused URL is never fetched at all', () async {
      final transport = _FakeTransport({});
      final reader = LinkMetadataReader(transport: transport);
      expect(await reader.titleFor(Uri.parse('http://192.168.0.1/')), isNull);
      expect(transport.requested, isEmpty);
    });

    test('a transport failure is null, not an exception', () async {
      // A link that cannot be read costs one extra tap, never the feature.
      final reader = LinkMetadataReader(transport: _FakeTransport({}));
      expect(await reader.titleFor(Uri.parse('https://nowhere.test/x')), isNull);
    });

    test('a non-text response is not parsed', () async {
      final reader = LinkMetadataReader(
        transport: _FakeTransport({
          'file.test': const PageResponse(
              statusCode: 200, body: 'binary', contentType: 'application/pdf'),
        }),
      );
      expect(await reader.titleFor(Uri.parse('https://file.test/a.pdf')), isNull);
    });
  });

  group('confidence for a page-title match', () {
    final bareLink = SharedLink(
      uri: Uri.parse('https://someblog.test/post'),
      kind: SourceKind.web,
    );

    test('sits below an id-carrying link and never reaches certainty', () {
      final score = metadataConfidence(
        tier: MatchTier.exact,
        phrase: 'grand theft auto five special',
        link: bareLink,
        hasGamingContext: false,
      );
      expect(score, lessThan(1.0));
      expect(score, lessThanOrEqualTo(0.92));
    });

    test('an exact hit beats an acronym hit', () {
      expect(
        metadataConfidence(
            tier: MatchTier.exact, phrase: 'hades two', link: bareLink, hasGamingContext: false),
        greaterThan(metadataConfidence(
            tier: MatchTier.acronym, phrase: 'hades two', link: bareLink, hasGamingContext: false)),
      );
    });

    test('a longer matched phrase scores higher than a single word', () {
      expect(
        metadataConfidence(
            tier: MatchTier.exact, phrase: 'a b c d e', link: bareLink, hasGamingContext: false),
        greaterThan(metadataConfidence(
            tier: MatchTier.exact, phrase: 'solo', link: bareLink, hasGamingContext: false)),
      );
    });
  });

  group('long and noisy video titles (real shares that used to fail)', () {
    // Recorded from real YouTube videos. These were a half-minute share that
    // then offered the wrong game, or nothing.
    CatalogSource catalog() => FixtureCatalog.of([
          Game(igdbId: 10, title: 'Call of Duty: Vanguard', releaseYear: 2021),
          Game(igdbId: 11, title: 'Behind Enemy Lines', releaseYear: 1997),
          Game(igdbId: 12, title: 'Enemy', releaseYear: 2018),
          Game(igdbId: 13, title: 'Hollow Knight', releaseYear: 2017),
          Game(igdbId: 14, title: 'Hollow', releaseYear: 2017),
          Game(igdbId: 15, title: 'Ghost of Tsushima', releaseYear: 2020),
          Game(igdbId: 16, title: 'Ghost', releaseYear: 2014),
        ]);

    Future<ShareResolution> resolveTitle(String title) => ShareResolver(
          catalog: catalog(),
          metadata: LinkMetadataReader(
            transport: _FakeTransport({
              'youtube.com/oembed': _json('{"title":${jsonEncode(title)}}'),
            }),
          ),
        ).resolve('https://youtu.be/abcdefghijk');

    test('the game named at the END of a long title is found', () async {
      // Twelve words before the game name: the old 40-window cap never
      // reached "COD Vanguard", and the series initials were not a key.
      final r = await resolveTitle(
          '(PS5) Merville 1944 Behind Enemy Lines | Ultra Realistic Gameplay '
          '[4K60FPS] COD Vanguard');
      expect(r.candidates.first.title, 'Call of Duty: Vanguard');
      expect(r.candidates.first.shouldAutoTick, isTrue);
      // "Behind Enemy Lines" is a real game inside a longer segment: shown,
      // never pre-ticked, so one share cannot add two games.
      final bel = r.candidates.where((c) => c.title == 'Behind Enemy Lines');
      expect(bel.every((c) => !c.shouldAutoTick), isTrue);
      // A lone word cut from the sentence is not offered at all.
      expect(r.candidates.map((c) => c.title), isNot(contains('Enemy')));
    });

    test('a segment padded with noise still counts as naming the game',
        () async {
      final hk = await resolveTitle(
          "Hollow Knight Walkthrough - King's Pass Beginner Guide");
      expect(hk.candidates.map((c) => c.title), ['Hollow Knight']);
      final got = await resolveTitle(
          'Ghost of Tsushima PS5 - Ruthless Samurai - 4K HDR 60FPS');
      expect(got.candidates.map((c) => c.title), ['Ghost of Tsushima']);
    });

    test('segments are trimmed of edge noise, never of inner words', () {
      expect(
          videoTitleSegments('Ghost of Tsushima PS5 - 4K HDR 60FPS | Call of Duty'),
          ['Ghost of Tsushima', 'Call of Duty']);
    });

    test('series initials plus subtitle is an acronym match', () {
      expect(TitleKeys('Call of Duty: Vanguard').tierFor('COD Vanguard'),
          MatchTier.acronym);
      expect(TitleKeys('Grand Theft Auto: San Andreas').tierFor('GTA San Andreas'),
          MatchTier.acronym);
    });
  });

  group('end to end: a shared link resolves to a game', () {
    test('a YouTube link about GTA V resolves, which is the reported bug',
        () async {
      final resolver = ShareResolver(
        catalog: _catalog(),
        metadata: LinkMetadataReader(
          transport: _FakeTransport({
            'youtube.com/oembed': _json(
                '{"title":"GTA 5 in 2026 is STILL Amazing | Part 1 [4K]"}'),
          }),
        ),
      );

      final result =
          await resolver.resolve('https://www.youtube.com/watch?v=abc');

      expect(result.hasMatches, isTrue);
      expect(result.candidates.first.title, 'Grand Theft Auto V');
      expect(result.candidates.first.method, MatchMethod.metadata);
    });

    test('a blog post resolves through Open Graph', () async {
      final resolver = ShareResolver(
        catalog: _catalog(),
        metadata: LinkMetadataReader(
          transport: _FakeTransport({
            'someblog.test': _html(
                '<meta property="og:title" content="Why Hades II works">'),
          }),
        ),
      );

      final result = await resolver.resolve('https://someblog.test/post');
      expect(result.candidates.first.title, 'Hades II');
    });

    test('a noisy title does not confidently offer the wrong game', () async {
      // "Control" appears inside the word "controller". A substring hit would
      // offer the game Control with confidence; an exact-or-acronym rule does not.
      final resolver = ShareResolver(
        catalog: _catalog(),
        metadata: LinkMetadataReader(
          transport: _FakeTransport({
            'someblog.test': _html(
                '<meta property="og:title" content="The best controller settings">'),
          }),
        ),
      );

      final result = await resolver.resolve('https://someblog.test/post');
      expect(result.candidates.map((c) => c.title), isNot(contains('Control')));
    });

    test('an unreadable link still keeps the link itself', () async {
      // The state in the screenshot, and it must stay graceful: no match, but the
      // link is still worth saving.
      final resolver = ShareResolver(
        catalog: _catalog(),
        metadata: LinkMetadataReader(transport: _FakeTransport({})),
      );

      final result = await resolver.resolve('https://nowhere.test/thing');
      expect(result.hasMatches, isFalse);
      expect(result.hasKeepableLink, isTrue);
    });

    test('with no reader supplied, nothing reaches the network', () async {
      // Every pre-existing test constructs the resolver this way, so this is the
      // assertion that they stayed offline.
      final resolver = ShareResolver(catalog: _catalog());
      final result =
          await resolver.resolve('https://www.youtube.com/watch?v=abc');
      expect(result.hasMatches, isFalse);
      expect(result.hasKeepableLink, isTrue);
    });
  });
}
