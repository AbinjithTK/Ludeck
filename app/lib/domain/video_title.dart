// A noisy page title in, candidate game names out.
//
// Pure, no I/O. This is the half of link resolution that has nothing to do with
// the network, and it is the half most likely to be wrong, so it is testable on
// its own.
//
// The input is what a page actually calls itself:
//
//   "GTA 5 in 2026 is STILL Amazing | Full Playthrough Part 1 [4K 60FPS]"
//   "Hades II - Early Access Review - The best roguelike sequel yet?"
//   "I beat ELDEN RING without dodging 😱 #shorts"
//
// None of those strings is a game name, and all three contain one. The approach is
// to generate MANY candidates and let the catalogue reject the nonsense, because a
// phrase that is not a game simply does not match anything. The opposite approach
// -- trying to identify the one true title with clever rules -- fails on the first
// video whose creator used a separator nobody predicted.
//
// The one thing this must not do is produce a candidate so generic that it matches
// the WRONG game. That is why noise words are stripped rather than trusted to miss,
// and why the resolver only accepts an exact or acronym hit from a link title.

/// Words and fragments that are about the video, not the game.
///
/// Deliberately conservative: every entry here is a word that essentially never
/// appears alone in a real game title. "Ending" and "Guide" are borderline and
/// included because as a WHOLE candidate they are noise, and a real title
/// containing them survives as part of a longer candidate.
const Set<String> _noiseWords = {
  '4k', '8k', '60fps', '120fps', 'hdr', 'hd', 'fullhd',
  'gameplay', 'walkthrough', 'playthrough', 'letsplay', 'longplay',
  'review', 'reviewed', 'preview', 'trailer', 'teaser', 'announcement',
  'official', 'reveal', 'gamescom', 'e3',
  'part', 'pt', 'episode', 'ep', 'chapter', 'day', 'week',
  'live', 'livestream', 'stream', 'streamed', 'vod', 'clip', 'clips',
  'highlights', 'montage', 'compilation', 'shorts', 'short', 'reel',
  'reaction', 'reacting', 'firstlook', 'impressions', 'thoughts',
  'ending', 'endings', 'finale', 'final', 'speedrun', 'nodeath', 'nohit',
  'guide', 'tips', 'tricks', 'tutorial', 'howto', 'build', 'builds',
  'tierlist', 'ranked', 'ranking', 'top', 'best', 'worst',
  'funny', 'moments', 'fails', 'bestmoments',
  'nocommentary', 'commentary', 'spoilers', 'spoilerfree',
  'update', 'patch', 'dlc', 'news', 'leak', 'leaks',
  'bossfight', 'boss', 'allbosses', 'secret', 'secrets',
  'ps5', 'ps4', 'xbox', 'pc', 'switch', 'steamdeck', 'vr',
  'game', 'games', 'gaming', 'playing', 'played', 'beat', 'beating',
  'i', 'im', 'my', 'the', 'a', 'an', 'is', 'in', 'it', 'and', 'of', 'to',
  'this', 'that', 'was', 'so', 'but', 'with', 'without', 'vs', 'versus',
  'no', 'yes', 'not', 'on', 'at', 'for', 'from', 'all', 'more', 'most',
  'still', 'finally', 'actually', 'literally', 'insane', 'amazing', 'crazy',
  'why', 'how', 'what', 'when', 'who', 'new', 'first', 'last', 'full',
};

/// Separators a title is split on.
///
/// Note what is NOT here: the colon and the plain hyphen. Real titles are full of
/// both -- "Half-Life: Alyx", "Spider-Man", "Like a Dragon: Infinite Wealth" --
/// so splitting on them would destroy the very names being looked for. A SPACED
/// hyphen is different: " - " is a separator in practice and never appears inside
/// a title.
final RegExp _separators = RegExp(
  r'[|‖•·»«【】\[\]\(\)\{\}"“”\n\r]|\s[-–—~]\s|[!?]+\s|,\s',
);

/// Characters that carry no meaning for matching: emoji, symbols, stray marks.
final RegExp _decoration = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{2190}-\u{21FF}'
  r'\u{2B00}-\u{2BFF}#@*_=+^<>]',
  unicode: true,
);

/// A word reduced for noise comparison only: lowercase, letters and digits.
String _bare(String word) =>
    word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _isNoise(String word) {
  final b = _bare(word);
  if (b.isEmpty) return true;
  // A bare number is an episode number far more often than a title.
  if (RegExp(r'^\d{1,4}$').hasMatch(b)) return true;
  return _noiseWords.contains(b);
}

/// True when the whole phrase is noise and could never be a game name.
bool _allNoise(String phrase) =>
    phrase.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(_isNoise);

/// Candidate game names found in [raw], longest first.
///
/// Every contiguous run of words is a candidate. That sounds crude and is the
/// point: the alternative -- deleting the words that look like noise and keeping
/// what is left -- destroys real titles, because the noise list necessarily
/// contains "of", "the", "final" and "last". Strip those from inside a phrase and
/// *Call of Duty*, *Final Fantasy* and *The Last of Us* stop existing.
///
/// So noise is used only to REJECT a candidate that is entirely noise, never to
/// edit one. A window that is not a game simply matches nothing, and the caller
/// scores a longer match higher, so "Hades II" beats "Hades" on a video about the
/// sequel without either being special-cased.
///
/// [limit] is generous because each candidate costs one in-memory lookup against
/// precomputed keys, and cutting the list short is how the right answer gets lost.
List<String> videoTitlePhrases(String raw, {int limit = 40}) {
  if (raw.trim().isEmpty) return const [];

  final cleaned = raw.replaceAll(_decoration, ' ').replaceAll(RegExp(r'\s+'), ' ');

  // Segments, in the order they appear. The game name is usually in the first
  // one, but "Let's Play | Elden Ring" happens too, so all of them are kept.
  final segments = cleaned
      .split(_separators)
      .map((s) => s.trim())
      .where((s) => s.length >= 2)
      .toList();

  final out = <String>[];
  final seen = <String>{};

  void add(String phrase) {
    final p = phrase.trim();
    if (p.length < 2) return;
    if (_allNoise(p)) return;
    final key = p.toLowerCase();
    if (seen.add(key)) out.add(p);
  }

  for (final segment in segments) {
    final words = segment.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) continue;

    // Longest windows first, left to right within a length. The full segment is
    // the first window, so the best case -- the segment IS the title -- is tried
    // before anything is discarded.
    for (var length = words.length; length >= 1; length--) {
      for (var start = 0; start + length <= words.length; start++) {
        add(words.skip(start).take(length).join(' '));
        if (out.length >= limit) return out;
      }
    }
  }

  return out.take(limit).toList();
}
