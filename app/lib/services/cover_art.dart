// A title in, a cover image URL out -- with no key and no deployed proxy.
//
// The live IGDB source already fills `Game.coverUrl`; this exists for every
// game that DIDN'T come from it: the bundled 609-title asset ships with none by
// design (docs note: "no ids, no cover art, no publisher"), and the fixture rows
// have none either. Without this, a row for anything not fetched live is
// permanently text-only, which is what made the collection read as a plain
// list rather than a library.
//
// Wikipedia's REST summary endpoint answers unauthenticated and returns the
// infobox image for a well-known topic -- the same "reading a page needs no
// credentials" fact link_metadata.dart already leans on for page titles. It is
// not IGDB-quality (wrong image for an ambiguous title, no image for an obscure
// one), so a miss is silent and never blocks or degrades anything else.
//
// Deliberately excluded from `check.ps1` rule 3 (no bare IGDB hostname) and
// rule 11 (fetch only inside safe_fetch.ts): neither rule concerns this file --
// this never talks to IGDB, and rule 11 scopes the Deno proxy directory only.

import 'dart:convert';

import 'link_metadata.dart' show HttpPageTransport, PageTransport;

/// One title's lookup result. Cached by the caller; this class does not cache.
class CoverArtReader {
  CoverArtReader({PageTransport? transport})
      : _transport = transport ?? HttpPageTransport();

  final PageTransport _transport;

  /// The best cover image for [title], or null when nothing usable was found.
  ///
  /// Never throws. A game whose art cannot be found must cost nothing but a
  /// blank placeholder, the same way an unreadable link costs one extra tap
  /// rather than the feature.
  Future<String?> coverFor(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;

    try {
      final url = Uri.https(
        'en.wikipedia.org',
        '/api/rest_v1/page/summary/${_pageTitle(trimmed)}',
      );
      final response = await _transport.get(url);
      if (!response.ok) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      // A disambiguation or missing page carries no thumbnail at all, which is
      // exactly the case this must stay silent on rather than guess.
      final thumbnail = decoded['thumbnail'];
      if (thumbnail is! Map<String, dynamic>) return null;

      final source = thumbnail['source'];
      if (source is! String || source.isEmpty) return null;
      return source;
    } catch (_) {
      return null;
    }
  }

  /// Wikipedia's summary endpoint takes the page title with spaces as
  /// underscores, percent-encoded. It resolves ordinary redirects itself (a
  /// disambiguated title still lands on the right page most of the time), so
  /// no separate search step is needed.
  static String _pageTitle(String title) =>
      Uri.encodeComponent(title.replaceAll(' ', '_'));
}
