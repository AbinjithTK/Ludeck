// Share text in, ranked candidate games out.
//
// This is the orchestrator: `parseShare` finds structure, `CatalogSource`
// supplies facts, and this decides what to offer and in what order. It does no
// parsing and knows no titles of its own.

import '../data/enums.dart';
import '../domain/resolve.dart';
import '../domain/video_title.dart';
import 'catalog_service.dart';
import 'link_metadata.dart';

/// What the confirm sheet renders.
class ShareResolution {
  const ShareResolution({
    required this.parsed,
    required this.candidates,
  });

  final ParsedShare parsed;

  /// Distinct games, best first. One share can name several.
  final List<Candidate> candidates;

  /// True when the share was understood well enough to offer something.
  bool get hasMatches => candidates.isNotEmpty;

  /// True when there was a link worth keeping even though no game was matched.
  ///
  /// Saving the source is separate from identifying the game: an unreadable
  /// platform costs one extra tap, never the feature.
  bool get hasKeepableLink => parsed.links.isNotEmpty;

  /// The best guess at where this share came from, for the source row.
  SourceKind get kind =>
      parsed.links.isEmpty ? SourceKind.text : parsed.links.first.kind;
}

class ShareResolver {
  ShareResolver({
    required CatalogSource catalog,
    Interpreter interpreter = const NullInterpreter(),
    LinkMetadataReader? metadata,
  })  : _catalog = catalog,
        _interpreter = interpreter,
        _metadata = metadata;

  final CatalogSource _catalog;
  final Interpreter _interpreter;

  /// Reads a link's page title. Null disables tiers 2 and 3 entirely, which is
  /// what every existing test wants: a resolver under test must not reach the
  /// network, and a null here is louder than a fake that silently returns nothing.
  final LinkMetadataReader? _metadata;

  Future<ShareResolution> resolve(String sharedText) async {
    final parsed = parseShare(sharedText);
    final byId = <int, Candidate>{};
    final byTitle = <String, Candidate>{};

    void offer(Candidate c) {
      if (c.confidence <= 0) return;
      final id = c.igdbId;
      if (id != null) {
        final existing = byId[id];
        // The same game reached two ways keeps the stronger reading. A Twitch
        // clip's exact id must not be demoted by a weaker prose guess that
        // happened to land on the same game.
        if (existing == null || c.confidence > existing.confidence) {
          byId[id] = c;
        }
        return;
      }
      final key = normaliseTitle(c.title);
      final existing = byTitle[key];
      if (existing == null || c.confidence > existing.confidence) {
        byTitle[key] = c;
      }
    }

    // Tier 1: links that name a game outright.
    for (final link in parsed.links) {
      if (!link.carriesGameId) continue;
      final game = await _catalog.byExternalId(
        twitchGameId: link.kind == SourceKind.twitch ? link.id : null,
        steamAppId: link.kind == SourceKind.steam ? link.id : null,
      );
      if (game == null) continue;
      offer(Candidate(
        title: game.title,
        igdbId: game.igdbId,
        method: MatchMethod.exact,
        confidence: linkConfidence(link),
        link: link,
      ));
    }

    // Tiers 2 and 3: the page's own title.
    //
    // This used to be a comment saying it needed the deployed proxy. That was
    // wrong, and the mistake cost the feature: reading a page's title needs no
    // credentials at all, only looking a game UP does. A link that carries no game
    // id now resolves through what the page calls itself.
    final reader = _metadata;
    // Every link's title is read at once, and then EVERY candidate phrase --
    // from those titles and from the prose -- goes to the catalogue in one
    // batch. This used to be one sequential search per phrase: a long video
    // title makes ~40 phrases, and at ~1s per round trip that was a
    // half-minute share. Scoring below is unchanged; only the lookups moved.
    final titled = <(SharedLink, String)>[];
    // Games a title named as a WHOLE segment ("| COD Vanguard"). When one
    // exists, a game found only inside a longer segment is a weaker guess.
    final segmentHits = <int>{};
    if (reader != null) {
      final links = [
        for (final link in parsed.links)
          if (!(link.carriesGameId && byId.isNotEmpty)) link,
      ];
      final titles =
          await Future.wait(links.map((l) => reader.titleFor(l.uri)));
      for (final (i, t) in titles.indexed) {
        if (t != null) titled.add((links[i], t));
      }
    }
    final titlePhrases = {
      for (final (_, t) in titled) t: videoTitlePhrases(t),
    };
    // Whole title segments and the prose phrases first: they get IGDB's full
    // relevance search (acronyms, alternative names). Every other window only
    // needs an exact-name hit, which the batch answers in one request.
    final broadFirst = <String>{
      for (final (_, t) in titled) ...videoTitleSegments(t),
      ...parsed.phrases,
    };
    final hitsFor = await searchAll(
      _catalog,
      [
        ...broadFirst,
        for (final ps in titlePhrases.values) ...ps,
      ],
      broad: broadFirst.length.clamp(1, 5),
    );

    for (final (link, pageTitle) in titled) {
      {
        // Gaming context is read from the PAGE TITLE, not from the shared prose,
        // because a bare link has no prose. "Control walkthrough" carries its own
        // corroboration; "the best controller settings" does not.
        final pageContext = parseShare(pageTitle).hasGamingContext;

        final segments = {
          for (final s in videoTitleSegments(pageTitle)) normaliseTitle(s),
        };

        for (final phrase in titlePhrases[pageTitle]!) {
          final hits = hitsFor[phrase] ?? const [];
          if (hits.isEmpty) continue;
          final whole = segments.contains(normaliseTitle(phrase));
          // "Elden Ring" names Elden Ring, not its Collector's Edition or
          // Nightreign, even though both match through their series name. When
          // some hit's full title IS the phrase, only those hits count.
          final want = normaliseTitle(phrase);
          final fullHits =
              hits.where((g) => normaliseTitle(g.title) == want).toList();
          final pool = fullHits.isNotEmpty ? fullHits : hits.take(10);

          for (final game in pool) {
            // Only an exact or acronym hit is trusted from a page title. A
            // substring hit off a noisy video title is how "Part 1 of my Control
            // playthrough" would confidently offer the wrong game -- the phrase
            // did not name it, it merely contained letters that appear in it.
            final tier = TitleKeys(game.title).tierFor(phrase);
            if (tier == null) continue;
            if (tier != MatchTier.exact && tier != MatchTier.acronym) continue;

            if (whole) segmentHits.add(game.igdbId);
            offer(Candidate(
              title: game.title,
              igdbId: game.igdbId,
              method: MatchMethod.metadata,
              confidence: metadataConfidence(
                tier: tier,
                phrase: phrase,
                link: link,
                hasGamingContext: pageContext,
                wholeSegment: whole,
              ),
              link: link,
            ));
          }
        }
      }
    }

    // Tier 4: prose. Every phrase is checked against the catalogue, and the
    // corroboration rule decides whether a hit is trustworthy.
    final quoted = _quotedPhrases(parsed.prose);
    for (final phrase in parsed.phrases) {
      final hits = hitsFor[phrase] ?? const [];
      if (hits.isEmpty) continue;

      final normalisedPhrase = normaliseTitle(phrase);
      for (final game in hits.take(3)) {
        final isExact = normaliseTitle(game.title) == normalisedPhrase;
        final score = textConfidence(
          phrase: phrase,
          exactCatalogueHit: isExact,
          hasGamingContext: parsed.hasGamingContext,
          wasQuoted: quoted.contains(phrase),
        );
        offer(Candidate(
          title: game.title,
          igdbId: game.igdbId,
          method: MatchMethod.text,
          confidence: score,
          link: parsed.links.isEmpty ? null : parsed.links.first,
        ));
      }
    }

    var candidates = [...byId.values, ...byTitle.values];

    // "(PS5) Merville 1944 Behind Enemy Lines | ... | COD Vanguard" names one
    // game, in its own segment. "Behind Enemy Lines" is also a real game, found
    // inside a longer segment. Both stay on the sheet, but only the one the
    // creator set apart is pre-ticked -- otherwise one share adds two games.
    if (segmentHits.isNotEmpty) {
      candidates = [
        for (final c in candidates)
          // A single word lifted out of a longer segment ("Enemy", "Ghost",
          // "PASS") next to a game the title actually named is noise, not an
          // alternative worth showing.
          if (!(c.method == MatchMethod.metadata &&
              !segmentHits.contains(c.igdbId) &&
              (!c.title.trim().contains(' ') || c.confidence < 0.52)))
            c.method == MatchMethod.metadata &&
                  !segmentHits.contains(c.igdbId) &&
                  c.confidence >= kAutoTickThreshold
              ? Candidate(
                  title: c.title,
                  igdbId: c.igdbId,
                  method: c.method,
                  confidence: kAutoTickThreshold - 0.05,
                  link: c.link,
                )
              : c,
      ];
    }

    // Last resort. Ships as a no-op; see `Interpreter`.
    //
    // Copied rather than assigned: an implementation is free to return a const
    // list, and sorting one of those throws.
    if (candidates.isEmpty) {
      candidates = [...await _interpreter.interpret(parsed)];
    }

    candidates.sort((a, b) {
      final byConfidence = b.confidence.compareTo(a.confidence);
      if (byConfidence != 0) return byConfidence;
      return a.title.compareTo(b.title);
    });

    return ShareResolution(parsed: parsed, candidates: candidates);
  }

  Set<String> _quotedPhrases(String prose) => RegExp(
        r'["\u201c]([^"\u201d]{2,60})["\u201d]',
      ).allMatches(prose).map((m) => m.group(1)!.trim()).toSet();
}
