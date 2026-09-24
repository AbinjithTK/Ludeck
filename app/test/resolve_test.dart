// Stage 2 of the share-to-library feature: the resolver core.
//
// The group that matters most here is 'corroboration'. Everything else is
// parsing, which either works or obviously does not. The corroboration rule is
// what stops a message about nothing in particular putting games in someone's
// library, and a library the user stops trusting is worse than no feature.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/resolve.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/share_resolver.dart';

Game g(int id, String title) => Game(igdbId: id, title: title);

void main() {
  group('link extraction', () {
    test('finds a bare link', () {
      final p = parseShare('https://youtu.be/dQw4w9WgXcQ');
      expect(p.links, hasLength(1));
      expect(p.links.single.kind, SourceKind.youtube);
      expect(p.links.single.id, 'dQw4w9WgXcQ');
      expect(p.prose, isEmpty);
    });

    test('finds a link wrapped in prose and keeps the prose', () {
      final p = parseShare(
          'you have to play this https://youtu.be/abc123 it is incredible');
      expect(p.links, hasLength(1));
      expect(p.prose, 'you have to play this it is incredible');
    });

    test('strips trailing sentence punctuation from a link', () {
      // A real share ends in a full stop far more often than a URL legitimately
      // does, so the trailing character comes off.
      for (final suffix in const ['.', ',', ')', '!', '?', ';', '"']) {
        final p = parseShare('look at https://example.com/page$suffix');
        expect(p.links.single.uri.toString(), 'https://example.com/page',
            reason: 'suffix $suffix was not trimmed');
      }
    });

    test('finds several links', () {
      final p = parseShare(
          'https://youtu.be/one and https://www.twitch.tv/x/clip/two');
      expect(p.links.map((l) => l.kind),
          [SourceKind.youtube, SourceKind.twitch]);
    });

    test('text with no link is not a failure', () {
      final p = parseShare('you should play Hollow Knight');
      expect(p.links, isEmpty);
      expect(p.prose, 'you should play Hollow Knight');
      expect(p.isEmpty, isFalse);
    });

    test('ignores something that is not a usable url', () {
      final p = parseShare('email me at not-a-url and see http://');
      expect(p.links, isEmpty);
    });
  });

  group('platform detection', () {
    void expectKind(String url, SourceKind kind, {String? id}) {
      final link = parseShare(url).links.single;
      expect(link.kind, kind, reason: url);
      if (id != null) expect(link.id, id, reason: url);
    }

    test('recognises each platform', () {
      expectKind('https://www.youtube.com/watch?v=abc123', SourceKind.youtube,
          id: 'abc123');
      expectKind('https://youtu.be/abc123', SourceKind.youtube, id: 'abc123');
      expectKind('https://www.youtube.com/shorts/xyz789', SourceKind.youtube,
          id: 'xyz789');
      expectKind('https://www.tiktok.com/@user/video/12345', SourceKind.tiktok,
          id: '12345');
      expectKind('https://www.instagram.com/reel/CodeHere/',
          SourceKind.instagram, id: 'CodeHere');
      expectKind('https://x.com/user/status/999', SourceKind.x, id: '999');
      expectKind('https://twitter.com/user/status/999', SourceKind.x, id: '999');
      expectKind('https://www.reddit.com/r/games/comments/abc/title/',
          SourceKind.reddit);
      expectKind('https://store.steampowered.com/app/367520/Hollow_Knight/',
          SourceKind.steam, id: '367520');
      expectKind('https://someblog.example/2026/best-games', SourceKind.web);
    });

    test('a twitch clip carries a game id but a VOD does not', () {
      // Verified against the Helix reference: Get Clips returns game_id, Get
      // Videos returns no game field at all. So a clip is an exact match and a
      // VOD is metadata at best.
      final clip =
          parseShare('https://www.twitch.tv/somechannel/clip/SlugHere')
              .links
              .single;
      expect(clip.carriesGameId, isTrue);
      expect(clip.id, 'SlugHere');

      final shortClip =
          parseShare('https://clips.twitch.tv/SlugHere').links.single;
      expect(shortClip.carriesGameId, isTrue);

      final vod =
          parseShare('https://www.twitch.tv/videos/1234567890').links.single;
      expect(vod.carriesGameId, isFalse);
    });

    test('a malformed steam appid is not treated as exact', () {
      final link =
          parseShare('https://store.steampowered.com/app/notanumber/X')
              .links
              .single;
      expect(link.id, isNull);
      expect(link.carriesGameId, isFalse);
    });
  });

  group('prose phrases', () {
    test('pulls a title case run out of a sentence', () {
      final p = parseShare('you should really play Hollow Knight tonight');
      expect(p.phrases, contains('Hollow Knight'));
    });

    test('accepts a short lowercase fragment as its own title', () {
      // People type "hollow knight" without capitals constantly.
      final p = parseShare('hollow knight');
      expect(p.phrases, contains('hollow knight'));
    });

    test('splits a list into separate phrases', () {
      final p = parseShare('Elden Ring, Hades and Celeste');
      expect(p.phrases, contains('Elden Ring'));
      expect(p.phrases, contains('Hades'));
      expect(p.phrases, contains('Celeste'));
    });

    test('strips leading filler', () {
      final p = parseShare('the new Hades');
      expect(p.phrases.any((s) => s == 'Hades'), isTrue,
          reason: 'phrases were ${p.phrases}');
    });

    test('takes quoted text whole', () {
      final p = parseShare('he kept talking about "Blue Prince" all evening');
      expect(p.phrases, contains('Blue Prince'));
    });
  });

  group('gaming context', () {
    test('is true when a playing word is present', () {
      expect(parseShare('I finally beat it').hasGamingContext, isTrue);
      expect(parseShare('playing this all weekend').hasGamingContext, isTrue);
      expect(parseShare('on sale on steam').hasGamingContext, isTrue);
    });

    test('is true for a games platform link even with no words', () {
      expect(parseShare('https://clips.twitch.tv/Slug').hasGamingContext,
          isTrue);
      expect(
          parseShare('https://store.steampowered.com/app/1/X').hasGamingContext,
          isTrue);
    });

    test('is false for an arbitrary page with no gaming words', () {
      // Tier 4 reaches any page on the web, so a bare blog link proves nothing
      // about the subject.
      expect(parseShare('https://someblog.example/post').hasGamingContext,
          isFalse);
      expect(parseShare('dinner at eight?').hasGamingContext, isFalse);
    });
  });

  group('corroboration', () {
    // A catalogue of titles that are also ordinary English words. This is the
    // whole risk of accepting arbitrary shared text.
    late ShareResolver resolver;

    setUp(() {
      resolver = ShareResolver(
        catalog: FixtureCatalog.of([
          g(1, 'Control'),
          g(2, 'Journey'),
          g(3, 'Inside'),
          g(4, 'Hollow Knight'),
          g(5, 'Hades'),
          g(6, 'Celeste'),
        ]),
      );
    });

    test('an ambiguous title with no gaming context is dropped entirely',
        () async {
      for (final message in const [
        'I need control of my schedule',
        'the journey was long and tiring',
        'it is inside the top drawer',
      ]) {
        final r = await resolver.resolve(message);
        expect(r.candidates, isEmpty, reason: 'message: $message');
      }
    });

    test('the same ambiguous title WITH gaming context is offered', () async {
      final r = await resolver.resolve('you should play Control, it is great');
      expect(r.candidates.map((c) => c.title), contains('Control'));
      expect(r.candidates.first.shouldAutoTick, isTrue);
    });

    test('an unambiguous title needs no gaming context', () async {
      // "Hollow Knight" is not a phrase anyone types by accident.
      final r = await resolver.resolve('Hollow Knight');
      expect(r.candidates.map((c) => c.title), contains('Hollow Knight'));
    });

    test('quoting raises confidence', () async {
      final bare = await resolver.resolve('play Celeste');
      final quoted = await resolver.resolve('play "Celeste"');
      expect(quoted.candidates.first.confidence,
          greaterThan(bare.candidates.first.confidence));
    });

    test('one message can name several games', () async {
      final r = await resolver
          .resolve('you have to play Hollow Knight, Hades and Celeste');
      expect(r.candidates.map((c) => c.title),
          containsAll(['Hollow Knight', 'Hades', 'Celeste']));
    });

    test('nothing recognised yields no candidates and no crash', () async {
      final r = await resolver.resolve('see you at six');
      expect(r.hasMatches, isFalse);
      expect(r.hasKeepableLink, isFalse);
    });

    test('an unreadable link is still worth keeping', () async {
      // The link cannot be resolved without the network, but losing it would be
      // the greater harm: saving the source is separate from naming the game.
      final r = await resolver.resolve('https://someblog.example/goty-2026');
      expect(r.hasMatches, isFalse);
      expect(r.hasKeepableLink, isTrue);
      expect(r.kind, SourceKind.web);
    });

    test('a share with no link is recorded as shared text', () async {
      final r = await resolver.resolve('play Hollow Knight');
      expect(r.kind, SourceKind.text);
    });

    test('candidates come back strongest first', () async {
      final r =
          await resolver.resolve('play "Hollow Knight" and maybe Celeste');
      final scores = r.candidates.map((c) => c.confidence).toList();
      final sorted = [...scores]..sort((a, b) => b.compareTo(a));
      expect(scores, sorted);
    });

    test('the same game reached twice is offered once', () async {
      final r = await resolver.resolve('Hollow Knight, hollow knight');
      expect(r.candidates.where((c) => c.title == 'Hollow Knight'), hasLength(1));
    });
  });

  group('title normalisation', () {
    test('collapses the spellings people actually type', () {
      const expected = 'hollow knight';
      for (final variant in const [
        'Hollow Knight',
        'hollow knight',
        'HOLLOW KNIGHT!',
        'Hollow  Knight',
        'Hollow-Knight',
      ]) {
        expect(normaliseTitle(variant), expected, reason: variant);
      }
    });

    test('drops a leading article', () {
      expect(normaliseTitle('The Last of Us'), 'last of us');
    });
  });

  group('the interpreter seam', () {
    test('ships as a no-op', () async {
      final r = await const NullInterpreter().interpret(parseShare('anything'));
      expect(r, isEmpty);
    });

    test('is consulted only when the deterministic tiers find nothing',
        () async {
      final spy = _SpyInterpreter();
      final resolver = ShareResolver(
        catalog: FixtureCatalog.of([g(4, 'Hollow Knight')]),
        interpreter: spy,
      );

      await resolver.resolve('play Hollow Knight');
      expect(spy.calls, 0, reason: 'a confident match must not cost a call');

      await resolver.resolve('that game with the bug in the dead kingdom');
      expect(spy.calls, 1);
    });
  });
}

class _SpyInterpreter implements Interpreter {
  int calls = 0;

  @override
  Future<List<Candidate>> interpret(ParsedShare share) async {
    calls++;
    return const [];
  }
}
