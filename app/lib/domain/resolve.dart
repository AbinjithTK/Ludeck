// Turning a share into candidate games. Pure Dart, no network, no I/O.
//
// The input is TEXT, not a URL. Everything people share is text: a bare link, a
// link wrapped in prose, or prose with no link at all. Pulling links out is the
// first pass, not the interface.
//
// This file decides WHAT a share might refer to and how much to trust each
// guess. It never decides that a game exists: that needs a catalogue, which is
// `CatalogSource`. Keeping those apart is what makes this testable without a
// network and what lets the fixture catalogue stand in for IGDB until the proxy
// is deployed.

import '../data/enums.dart';
import 'title_match.dart';

/// Confidence at or above which the confirm sheet pre-ticks a candidate.
///
/// Below it a candidate is still SHOWN, just unticked. The user sees everything
/// the resolver thought of and nothing enters the library unseen.
const double kAutoTickThreshold = 0.6;

/// A link found inside shared text.
class SharedLink {
  const SharedLink({required this.uri, required this.kind, this.id});

  final Uri uri;
  final SourceKind kind;

  /// The platform's own identifier when the URL carries one: a Twitch clip
  /// slug, a YouTube video id, a Steam appid. Null when the shape is unknown.
  ///
  /// Present does not mean exact. A YouTube video id still needs a metadata
  /// call; only [carriesGameId] means the game itself can be looked up.
  final String? id;

  /// Whether this link can name a game outright, with no matching.
  ///
  /// Twitch CLIPS carry a game id, verified against the Helix reference. Twitch
  /// VODs do not: Get Videos returns no game field at all, so a VOD is metadata
  /// at best. Steam store pages carry an appid, which IGDB maps through
  /// `external_games`.
  bool get carriesGameId =>
      id != null &&
      (kind == SourceKind.steam ||
          (kind == SourceKind.twitch && _isTwitchClip));

  bool get _isTwitchClip =>
      uri.host.startsWith('clips.') || uri.pathSegments.contains('clip');

  @override
  String toString() => 'SharedLink($kind, ${uri.host}, id=$id)';
}

/// A game the resolver believes a share refers to.
///
/// [title] is a guess until a catalogue confirms it, which is why [igdbId] is
/// separate and nullable rather than this carrying a fabricated id.
class Candidate {
  const Candidate({
    required this.title,
    required this.method,
    required this.confidence,
    this.igdbId,
    this.link,
  });

  final String title;
  final int? igdbId;
  final MatchMethod method;

  /// 0 to 1. Compared against [kAutoTickThreshold], never shown as a number:
  /// a percentage invites the user to audit arithmetic they cannot see.
  final double confidence;

  /// The link this came from, when it came from one.
  final SharedLink? link;

  bool get shouldAutoTick => confidence >= kAutoTickThreshold;

  Candidate withIgdbId(int id) => Candidate(
        title: title,
        method: method,
        confidence: confidence,
        igdbId: id,
        link: link,
      );

  @override
  String toString() =>
      'Candidate($title, $method, ${confidence.toStringAsFixed(2)})';
}

/// The structure pulled out of one share.
class ParsedShare {
  const ParsedShare({
    required this.raw,
    required this.links,
    required this.prose,
    required this.hasGamingContext,
    required this.phrases,
  });

  final String raw;
  final List<SharedLink> links;

  /// The text with links removed. What a human would have typed.
  final String prose;

  /// Whether the text reads like it is about games at all.
  ///
  /// This is the whole defence against false positives, so it is recorded on
  /// the parse rather than recomputed: `Control`, `Journey`, `Inside`, `Limbo`,
  /// `Portal` and `Prey` are all real games and all ordinary English words.
  final bool hasGamingContext;

  /// Phrases from the prose that could be titles, longest first.
  final List<String> phrases;

  bool get isEmpty => links.isEmpty && phrases.isEmpty;
}

/// Where the resolver escalates when the deterministic tiers find nothing.
///
/// Ships as [NullInterpreter]. A language model behind this interface would
/// handle the case nothing else can, a description with no title in it at all
/// ("that game where you play a bug in a dead kingdom"), but it costs an
/// account, a key and money per share, and the deterministic ladder covers the
/// realistic cases. The seam exists so that decision stays reversible.
abstract class Interpreter {
  Future<List<Candidate>> interpret(ParsedShare share);
}

/// Interprets nothing. The shipping default.
class NullInterpreter implements Interpreter {
  const NullInterpreter();

  @override
  Future<List<Candidate>> interpret(ParsedShare share) async => const [];
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Matches http and https URLs. Deliberately greedy on the path and trimmed
/// afterwards: trailing sentence punctuation is far more common in a real share
/// than a URL legitimately ending in a full stop.
final RegExp _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// Characters stripped from the end of a captured URL.
const String _trailingJunk = '.,;:!?)]}\'"\u2019\u201d';

/// Words that make a share read as being about games.
///
/// Presence of ONE of these is what lets an ambiguous title through. The list
/// is deliberately about the ACT of playing rather than genre names, because
/// "play" and "finished" appear in real messages while "metroidvania" mostly
/// appears in reviews.
const Set<String> _gamingWords = {
  'play', 'plays', 'played', 'playing', 'playthrough',
  'game', 'games', 'gaming', 'gamer',
  'beat', 'beating', 'finish', 'finished',
  'completed', 'complete', // check:ignore English words a person types in a share, not status values; Progress says `finished`
  'coop', 'co-op', 'multiplayer', 'singleplayer',
  'speedrun', 'boss', 'bosses', 'gameplay', 'campaign', 'level', 'levels',
  'dlc', 'achievement', 'achievements', 'platinum', 'trophy', 'trophies',
  'console', 'steam', 'switch', 'playstation', 'xbox', 'pc', 'deck',
  'indie', 'roguelike', 'roguelite', 'metroidvania', 'soulslike', 'rpg', 'fps',
  'install', 'installed', 'download', 'downloaded',
  'recommend', 'recommends', 'recommended',
  'review', 'trailer', 'release', 'released', 'launch', 'launched',
};

/// Game titles that are also ordinary English words or phrases.
///
/// A share naming one of these with NO gaming context nearby is dropped
/// entirely rather than offered at low confidence, because "I need control of
/// my schedule" must not put Control in someone's library.
///
/// Not exhaustive and cannot be: there is no offline English dictionary here,
/// so this is the set of titles common enough to actually collide. Add to it
/// when a real false positive turns up rather than guessing ahead.
const Set<String> _ambiguousTitles = {
  'control', 'journey', 'inside', 'limbo', 'portal', 'prey', 'doom', 'rage',
  'fallout', 'destiny', 'braid', 'bound', 'flower', 'rime', 'spore', 'evolve',
  'grid', 'dirt', 'halo', 'myst', 'sable', 'among us', 'fall guys', 'the last',
  'returnal', 'observation', 'everything', 'gone home', 'firewatch', 'unpacking',
};

/// Words that never start a title, used to trim leading filler from a phrase.
const Set<String> _leadingFiller = {
  'a', 'an', 'the', 'this', 'that', 'my', 'your', 'his', 'her', 'their', 'our',
  'is', 'was', 'are', 'were', 'be', 'been', 'am',
  'i', 'you', 'he', 'she', 'we', 'they', 'it',
  'and', 'but', 'or', 'so', 'then', 'also', 'just', 'really', 'very',
  'try', 'trying', 'check', 'look', 'see', 'watch', 'get', 'got',
  'should', 'could', 'would', 'must', 'need', 'want', 'love', 'loved', 'like',
  'liked', 'hate', 'hated', 'buy', 'bought', 'start', 'started',
};

/// Splits prose into fragments that could each name a different game.
///
/// "Elden Ring, Hades and Celeste" is three recommendations, not one ambiguous
/// title, so a share can legitimately produce several games.
final RegExp _fragmentSplit = RegExp(
  r'[,;\n\r]|\s+(?:and|&|plus|then|also)\s+|\s+[-\u2013\u2014]\s+',
  caseSensitive: false,
);

/// Pulls structure out of shared text.
ParsedShare parseShare(String raw) {
  final links = <SharedLink>[];
  var prose = raw;

  for (final match in _urlPattern.allMatches(raw)) {
    final cleaned = _trimUrl(match.group(0)!);
    final uri = Uri.tryParse(cleaned);
    if (uri == null || !uri.hasAuthority) continue;
    links.add(_classify(uri));
    prose = prose.replaceFirst(match.group(0)!, ' ');
  }

  prose = prose.replaceAll(RegExp(r'\s+'), ' ').trim();

  return ParsedShare(
    raw: raw,
    links: links,
    prose: prose,
    hasGamingContext: _hasGamingContext(prose, links),
    phrases: _phrases(prose),
  );
}

String _trimUrl(String s) {
  var out = s;
  while (out.isNotEmpty && _trailingJunk.contains(out[out.length - 1])) {
    out = out.substring(0, out.length - 1);
  }
  // A URL wrapped in parentheses keeps its own balanced pairs but not the
  // wrapper's closing bracket, which the loop above already removed.
  return out;
}

SharedLink _classify(Uri uri) {
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (host == 'youtu.be') {
    return SharedLink(
      uri: uri,
      kind: SourceKind.youtube,
      id: segments.isNotEmpty ? segments.first : null,
    );
  }
  if (host.endsWith('youtube.com')) {
    return SharedLink(
      uri: uri,
      kind: SourceKind.youtube,
      id: uri.queryParameters['v'] ??
          (segments.length >= 2 && (segments.first == 'shorts' ||
                  segments.first == 'live' ||
                  segments.first == 'embed')
              ? segments[1]
              : null),
    );
  }
  if (host.endsWith('twitch.tv')) {
    // clips.twitch.tv/<slug> and twitch.tv/<channel>/clip/<slug> are the same
    // thing reached two ways. Both carry a game id; /videos/<id> does not.
    String? id;
    if (host.startsWith('clips.')) {
      id = segments.isNotEmpty ? segments.first : null;
    } else {
      final i = segments.indexOf('clip');
      if (i >= 0 && i + 1 < segments.length) id = segments[i + 1];
      final v = segments.indexOf('videos');
      if (id == null && v >= 0 && v + 1 < segments.length) id = segments[v + 1];
    }
    return SharedLink(uri: uri, kind: SourceKind.twitch, id: id);
  }
  if (host.endsWith('tiktok.com')) {
    final i = segments.indexOf('video');
    return SharedLink(
      uri: uri,
      kind: SourceKind.tiktok,
      id: i >= 0 && i + 1 < segments.length ? segments[i + 1] : null,
    );
  }
  if (host.endsWith('instagram.com')) {
    // /p/<code>, /reel/<code> and /tv/<code> all identify one post.
    final id = segments.length >= 2 &&
            (segments.first == 'p' ||
                segments.first == 'reel' ||
                segments.first == 'reels' ||
                segments.first == 'tv')
        ? segments[1]
        : null;
    return SharedLink(uri: uri, kind: SourceKind.instagram, id: id);
  }
  if (host.endsWith('x.com') || host.endsWith('twitter.com')) {
    final i = segments.indexOf('status');
    return SharedLink(
      uri: uri,
      kind: SourceKind.x,
      id: i >= 0 && i + 1 < segments.length ? segments[i + 1] : null,
    );
  }
  if (host.endsWith('reddit.com') || host == 'redd.it') {
    return SharedLink(uri: uri, kind: SourceKind.reddit, id: null);
  }
  if (host.endsWith('steampowered.com') || host.endsWith('steamcommunity.com')) {
    final i = segments.indexOf('app');
    final appid = i >= 0 && i + 1 < segments.length ? segments[i + 1] : null;
    // Only digits are an appid. A malformed one must not be treated as exact.
    final valid = appid != null && RegExp(r'^\d+$').hasMatch(appid);
    return SharedLink(
      uri: uri,
      kind: SourceKind.steam,
      id: valid ? appid : null,
    );
  }
  return SharedLink(uri: uri, kind: SourceKind.web, id: null);
}

bool _hasGamingContext(String prose, List<SharedLink> links) {
  // A link to a games platform is context by itself. A blog link is not: the
  // whole point of tier 4 is that any page might be about anything.
  for (final l in links) {
    if (l.kind == SourceKind.twitch ||
        l.kind == SourceKind.steam ||
        l.kind == SourceKind.youtube) {
      return true;
    }
  }
  final words = _words(prose);
  for (final w in words) {
    if (_gamingWords.contains(w)) return true;
  }
  return false;
}

List<String> _words(String s) => s
    .toLowerCase()
    .split(RegExp(r"[^a-z0-9'\-]+"))
    .where((w) => w.isNotEmpty)
    .toList();

/// Candidate title phrases from prose, longest first.
List<String> _phrases(String prose) {
  if (prose.isEmpty) return const [];

  final out = <String>[];

  // Quoted text is the strongest signal a human can give, so it is taken whole
  // and taken first.
  for (final m in RegExp(r'["\u201c]([^"\u201d]{2,60})["\u201d]')
      .allMatches(prose)) {
    final q = m.group(1)!.trim();
    if (q.isNotEmpty) out.add(q);
  }

  for (final fragment in prose.split(_fragmentSplit)) {
    final trimmed = _stripFiller(fragment.trim());
    if (trimmed.isEmpty) continue;

    // Title Case runs. "you should play Hollow Knight" -> "Hollow Knight".
    for (final m
        in RegExp(r'\b([A-Z][\w\u2019\x27\-]*(?:\s+[A-Z0-9][\w\u2019\x27\-]*)*)')
            .allMatches(trimmed)) {
      final run = m.group(1)!.trim();
      if (run.length >= 2 && !out.contains(run)) out.add(run);
    }

    // A short fragment may BE the title, lowercase and all. People type
    // "hollow knight" without capitals constantly.
    final wordCount = trimmed.split(RegExp(r'\s+')).length;
    if (wordCount <= 5 && !out.contains(trimmed)) out.add(trimmed);
  }

  out.sort((a, b) => b.length.compareTo(a.length));
  return out;
}

/// Removes leading filler words so "the new Hades" yields "Hades".
String _stripFiller(String fragment) {
  final parts = fragment.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  var start = 0;
  while (start < parts.length &&
      _leadingFiller.contains(_bare(parts[start]).toLowerCase())) {
    start++;
  }
  return parts.sublist(start).join(' ').trim();
}

String _bare(String w) => w.replaceAll(RegExp(r"[^A-Za-z0-9'\-]"), '');

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

/// Whether a phrase is too ambiguous to offer without gaming context.
bool isAmbiguous(String phrase) =>
    _ambiguousTitles.contains(phrase.toLowerCase().trim());

/// Confidence for a phrase matched against the catalogue by text.
///
/// The corroboration rule lives here. An exact catalogue hit is not enough on
/// its own: an ambiguous title with no gaming context nearby scores zero and is
/// dropped, because the cost of a wrong add is a user who stops trusting their
/// own library.
double textConfidence({
  required String phrase,
  required bool exactCatalogueHit,
  required bool hasGamingContext,
  required bool wasQuoted,
}) {
  if (isAmbiguous(phrase) && !hasGamingContext) return 0;

  var score = exactCatalogueHit ? 0.55 : 0.3;
  if (hasGamingContext) score += 0.2;
  if (wasQuoted) score += 0.15;

  // Multi-word titles are far less likely to be coincidence than one word.
  if (phrase.trim().contains(' ')) score += 0.1;

  return score.clamp(0, 1);
}

/// Confidence for a candidate that came from a link.
double linkConfidence(SharedLink link) {
  if (link.carriesGameId) return 1;
  if (link.id != null) return 0.7;
  return 0.5;
}

/// The method a link's candidate should be recorded under.
MatchMethod linkMethod(SharedLink link) =>
    link.carriesGameId ? MatchMethod.exact : MatchMethod.metadata;

/// How much to trust a game matched from a page's own title.
///
/// Sits deliberately BETWEEN the two neighbouring tiers. Above prose, because a
/// page title is about the thing being shared while shared prose is about whatever
/// the sender felt like typing. Below an id-carrying link, because that one is not
/// a guess at all -- and so this never reaches 1.0, no matter how good the match.
///
/// The corroboration rule is the same one prose obeys, for the same reason. A
/// one-word window like "Journey", "Control" or "Inside" will match a real game by
/// pure coincidence, and generating every contiguous window of a title makes that
/// certain rather than unlikely. So an ambiguous phrase needs gaming context
/// somewhere in the page title before it is offered at all.
///
/// The phrase length bonus is the honest part: a candidate that used five words of
/// the title accounted for more of it than one that used a single word, and is
/// correspondingly less likely to be a coincidence.
double metadataConfidence({
  required MatchTier tier,
  required String phrase,
  required SharedLink link,
  required bool hasGamingContext,
}) {
  if (isAmbiguous(phrase) && !hasGamingContext) return 0;

  final base = switch (tier) {
    MatchTier.exact => 0.80,
    MatchTier.acronym => 0.74,
    // Weaker tiers are refused by the caller and never reach here. Scored low
    // rather than thrown on, so a future caller cannot get a confident answer by
    // accident.
    _ => 0.30,
  };
  final words = phrase.trim().split(RegExp(r'\s+')).length;
  final lengthBonus = 0.02 * (words.clamp(1, 6) - 1);
  // A link that at least identified itself (a known host with an id in the path)
  // is marginally better evidence than a bare page.
  final linkBonus = link.id != null ? 0.02 : 0.0;
  final score = base + lengthBonus + linkBonus;
  return score > 0.92 ? 0.92 : score;
}
