// How a typed query finds a game.
//
// Pure functions, no I/O, no catalogue. Written as its own file because the
// matching is the part that decides whether search feels broken, and it needs to
// be testable without an asset, a network or a database.
//
// The motivating failure was real and reported from a device: searching "gta v"
// returned nothing while `Grand Theft Auto V` sat in the catalogue. A substring
// search cannot ever find it, because the query is an ACRONYM of the title and
// shares only three letters with it in that order. People type what they say,
// and nobody says "grand theft auto".

/// Lowercased, punctuation and article stripped, whitespace collapsed.
///
/// Titles arrive spelled every possible way: "Hollow Knight", "hollow knight",
/// "HOLLOW KNIGHT!", "Hollow  Knight". All four are the same game and none of
/// them is a reason to miss it.
String normaliseTitle(String raw) {
  var s = raw.toLowerCase().trim();
  // Curly apostrophes are cosmetic here.
  s = s.replaceAll(RegExp(r"[\u2019'\u2018]"), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // A leading article is never the distinguishing part of a title.
  for (final article in const ['the ', 'a ', 'an ']) {
    if (s.startsWith(article)) {
      s = s.substring(article.length);
      break;
    }
  }
  return s;
}

/// The normalised form WITHOUT dropping a leading article.
///
/// Articles are noise for a full-title match and load-bearing for an acronym:
/// people write "TLoZ: BotW", so the T has to survive somewhere. Used only to
/// build acronym keys.
String normaliseKeepingArticle(String raw) {
  var s = raw.toLowerCase().trim();
  s = s.replaceAll(RegExp(r"[\u2019'\u2018]"), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The one key two catalogue sources are compared on to decide they mean the same
/// game.
///
/// Normalised AND numeral-folded, so a live source spelling it "Grand Theft Auto
/// 5" suppresses the bundled "Grand Theft Auto V" instead of sitting beside it.
/// Two entries that look identical to the user but carry different ids become two
/// rows in their collection, which is the visible form of this bug.
String catalogDedupKey(String title) => arabicNumerals(normaliseTitle(title));

const Map<String, String> _romanToArabic = {
  'i': '1',
  'ii': '2',
  'iii': '3',
  'iv': '4',
  'v': '5',
  'vi': '6',
  'vii': '7',
  'viii': '8',
  'ix': '9',
  'x': '10',
  'xi': '11',
  'xii': '12',
  'xiii': '13',
  'xiv': '14',
  'xv': '15',
  'xvi': '16',
  'xvii': '17',
  'xviii': '18',
  'xix': '19',
  'xx': '20',
};

/// The same string with standalone roman numerals written as digits.
///
/// `Civilization V` and `Civilization 5` are the same game, and a series is
/// numbered whichever way its cover art felt like that year -- `Final Fantasy X`
/// beside `Final Fantasy 7 Remake`. This runs on BOTH the title and the query,
/// so either spelling reaches the other.
///
/// It converts words, never substrings: `Ix` inside a word is left alone. A wrong
/// conversion is harmless anyway, because the result is added as an EXTRA key
/// rather than replacing the original.
String arabicNumerals(String normalised) => normalised
    .split(' ')
    .map((w) => _romanToArabic[w] ?? w)
    .join(' ');

/// The initials of each word, digits kept whole.
///
/// "grand theft auto 5" -> "gta5", and "grand theft auto v" -> "gtav". Both are
/// produced for every title, which is what lets "gta 5" and "gta v" find the same
/// row no matter which way the title itself is spelled.
String acronym(String normalised) {
  if (normalised.isEmpty) return '';
  final out = StringBuffer();
  for (final word in normalised.split(' ')) {
    if (word.isEmpty) continue;
    // A number is part of the name, not an initial: "half life 2" -> "hl2", and
    // taking only "2"'s first character would be the same thing by luck. A
    // multi-digit number like "76" would not be.
    if (RegExp(r'^\d+$').hasMatch(word)) {
      out.write(word);
    } else {
      out.write(word[0]);
    }
  }
  return out.toString();
}

/// How well a query matched, highest first. The order is the whole point.
enum MatchTier {
  /// The query IS the title.
  exact,

  /// The query is the title's acronym, or the subtitle's. "gta v", "botw".
  ///
  /// Ranked directly below exact because an acronym is a deliberate, specific
  /// thing to type. Someone who types "botw" is not casting a wide net.
  acronym,

  /// The title starts with the query. "hollow" -> Hollow Knight.
  prefix,

  /// The query appears somewhere in the title.
  contains,
}

/// Every string that should find this title.
///
/// A set rather than one canonical form, because a title has several honest
/// names: `The Legend of Zelda: Breath of the Wild` is searched for as the full
/// thing, as "breath of the wild", and as "botw", and all three are correct.
class TitleKeys {
  TitleKeys(this.title)
      : full = {},
        acronyms = {} {
    final n = normaliseTitle(title);
    if (n.isEmpty) return;

    void addFull(String s) {
      if (s.isEmpty) return;
      full.add(s);
      final digits = arabicNumerals(s);
      if (digits != s) full.add(digits);
    }

    void addAcronym(String s) {
      if (s.isEmpty) return;
      final a = acronym(s);
      // A one-letter acronym is noise: it would make "h" match Hades, Hollow
      // Knight and Halo equally, which is worse than not matching at all.
      if (a.length >= 2) acronyms.add(a);
      final digits = acronym(arabicNumerals(s));
      if (digits.length >= 2) acronyms.add(digits);
    }

    addFull(n);
    addAcronym(n);
    // The same acronym with the leading article kept, so "tlozbotw" forms as well
    // as "lozbotw". Both are ways real people write it.
    addAcronym(normaliseKeepingArticle(title));

    // Subtitles. A colon usually separates a series name from the part people
    // actually say: nobody asks whether you have played "The Legend of Zelda",
    // they ask about "Tears of the Kingdom".
    final raw = title.toLowerCase();
    if (raw.contains(':') || raw.contains(' - ')) {
      final parts = raw.split(RegExp(r':|\s-\s'));
      for (final part in parts) {
        final p = normaliseTitle(part);
        if (p.isEmpty) continue;
        addFull(p);
        addAcronym(p);
      }
      // The acronym of the WHOLE thing, subtitle included: "tlozbotw" is a real
      // way people write it.
      addAcronym(n);

      // The series as initials, the subtitle in words: "COD Vanguard", "GTA San
      // Andreas", "AC Valhalla". This is how video titles and hashtags name a
      // sequel far more often than either the full title or a pure acronym.
      final series = normaliseTitle(parts.first);
      final rest = normaliseTitle(parts.skip(1).join(' '));
      final initials = acronym(series);
      if (initials.length >= 2 && rest.isNotEmpty) {
        acronyms.add(initials + rest.replaceAll(' ', ''));
        acronyms.add(initials + arabicNumerals(rest).replaceAll(' ', ''));
      }
    }
  }

  final String title;

  /// Full-form names: the title, its subtitle, and their digit variants.
  final Set<String> full;

  /// Acronym forms, at least two characters.
  final Set<String> acronyms;

  /// The strongest tier this query reaches on this title, or null for no match.
  MatchTier? tierFor(String query) {
    final q = normaliseTitle(query);
    if (q.isEmpty) return null;
    final qDigits = arabicNumerals(q);
    // "gta v" and "gtav" are the same intent typed two ways.
    final qTight = q.replaceAll(' ', '');
    final qTightDigits = qDigits.replaceAll(' ', '');

    if (full.contains(q) || full.contains(qDigits)) return MatchTier.exact;
    if (acronyms.contains(qTight) || acronyms.contains(qTightDigits)) {
      return MatchTier.acronym;
    }
    for (final f in full) {
      if (f.startsWith(q) || f.startsWith(qDigits)) return MatchTier.prefix;
    }
    for (final f in full) {
      if (f.contains(q) || f.contains(qDigits)) return MatchTier.contains;
    }
    return null;
  }
}

/// Ranks entries against a query, best first.
///
/// Generic over the payload so a source that has precomputed its [TitleKeys] can
/// pass them straight in. Rebuilding keys per keystroke is fine for ten fixture
/// rows and wasteful for six hundred, and this is the seam that lets both be
/// right.
///
/// Every catalogue source routes through this, so search ordering cannot differ
/// depending on which source answered -- which it silently did before, because the
/// fixture had its own hand-rolled ordering and nothing else shared it.
List<T> rankByKeys<T>(
  Iterable<({T value, TitleKeys keys})> entries,
  String query, {
  int limit = 30,
}) {
  final scored = <({T value, MatchTier tier, int length, String title})>[];
  for (final entry in entries) {
    final tier = entry.keys.tierFor(query);
    if (tier == null) continue;
    scored.add((
      value: entry.value,
      tier: tier,
      length: normaliseTitle(entry.keys.title).length,
      title: entry.keys.title,
    ));
  }

  scored.sort((a, b) {
    final byTier = a.tier.index.compareTo(b.tier.index);
    if (byTier != 0) return byTier;
    // A shorter title matched the query with less left over, so it is the more
    // specific answer: "Hades" outranks "Hades II" for the query "hades".
    final byLength = a.length.compareTo(b.length);
    if (byLength != 0) return byLength;
    // Alphabetical last, so the order is stable rather than dependent on the
    // asset's row order.
    return a.title.compareTo(b.title);
  });

  return scored.take(limit).map((s) => s.value).toList();
}

/// A stable id for a game that has no catalogue id of its own.
///
/// NEGATIVE, always, and that is the entire design. The database's primary key is
/// an IGDB id, which is positive, so a negative id can never collide with a real
/// one -- and when the catalogue proxy is deployed, a game carrying a negative id
/// is immediately recognisable as one that came from the bundled asset and has not
/// been reconciled yet.
///
/// Derived from the TITLE rather than the row's position in the asset. Position
/// would be simpler and would be a data-corruption bug: inserting one game into
/// the asset would shift every id after it, and every row the user had already
/// saved would silently start pointing at a different game.
int bundledIdFor(String title) {
  // FNV-1a, 32-bit. Chosen because it is four lines, deterministic across
  // platforms and releases, and has no dependency -- not because it is strong.
  // Nothing here is security-relevant.
  var hash = 0x811c9dc5;
  for (final unit in normaliseTitle(title).codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  // Into a positive 31-bit range, then negated and offset so zero is impossible.
  return -((hash % 0x7FFFFFFE) + 1);
}
