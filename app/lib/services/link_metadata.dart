// A link in, the page's own title out.
//
// This is the tier that makes "share a video to Ludeck" work for links that do not
// carry a game id. It needs NO credentials of any kind, and that is worth stating
// plainly because it was previously recorded as blocked on a deployed proxy and an
// API key. Neither is true for a title:
//
//   * oEmbed endpoints answer unauthenticated on the hosts that matter most, and
//     return the video's title as JSON. That includes YouTube -- the Data API key
//     is needed for statistics and captions, not for a title.
//   * Every other page is read through Open Graph, Twitter card, JSON-LD, or the
//     plain <title> element, all of which are in the public HTML.
//
// The IGDB proxy is still required to look a game UP. It was never required to read
// a web page, and conflating the two is what kept this tier unbuilt.
//
// No `http` package: the transport is injected and the real one uses dart:io, the
// same pattern as the catalogue's.

import 'dart:convert';
import 'dart:io';

/// What a fetch returned. Deliberately small.
class PageResponse {
  const PageResponse({
    required this.statusCode,
    required this.body,
    this.contentType,
  });

  final int statusCode;
  final String body;
  final String? contentType;

  bool get ok => statusCode >= 200 && statusCode < 300;
}

abstract class PageTransport {
  /// GETs [url] and returns the response. Throws on a transport failure.
  Future<PageResponse> get(Uri url);
}

/// Why a URL will not be fetched.
enum LinkRefusal {
  /// Not https. A plain-http fetch would leak the URL being looked up.
  scheme,

  /// Points at the device, the local network, or a link-local address.
  privateAddress,

  /// Carries a username or password.
  credentials,

  /// A port other than the default.
  port,

  /// Not a URL this can act on at all.
  shape,
}

const int kMaxBodyBytes = 512 * 1024;
const Duration kFetchTimeout = Duration(seconds: 6);
const int kMaxRedirects = 3;

/// Whether this URL may be fetched, and why not when it may not.
///
/// NARROWER than the proxy's SSRF policy in `url_guard.ts`, and intentionally so:
/// the threats differ. A server fetching an attacker-supplied URL can be walked
/// into its own metadata service and its neighbours; a phone cannot reach any of
/// that. What a phone CAN be walked into is the user's own home network -- probing
/// their router from inside their LAN -- and leaking the link over plain http. Those
/// two are what this refuses.
///
/// It does not resolve DNS, so a hostname pointing at a private address is not
/// caught here. That gap is real and is named rather than papered over: closing it
/// requires pinning the connection to a vetted address, which Dart's HttpClient
/// cannot express with correct TLS naming, exactly as the proxy documents.
LinkRefusal? refuseLink(Uri url) {
  if (!url.hasScheme || url.host.isEmpty) return LinkRefusal.shape;
  if (url.scheme.toLowerCase() != 'https') return LinkRefusal.scheme;
  if (url.userInfo.isNotEmpty) return LinkRefusal.credentials;
  if (url.hasPort && url.port != 443) return LinkRefusal.port;

  final host = url.host.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.home') ||
      host.endsWith('.lan')) {
    return LinkRefusal.privateAddress;
  }

  // Literal addresses only. A name is not resolved here; see the doc comment.
  final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
      .firstMatch(host);
  if (ipv4 != null) {
    final octets = [
      for (var i = 1; i <= 4; i++) int.parse(ipv4.group(i)!),
    ];
    if (octets.any((o) => o > 255)) return LinkRefusal.shape;
    final a = octets[0], b = octets[1];
    if (a == 0 ||
        a == 10 ||
        a == 127 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 100 && b >= 64 && b <= 127) ||
        a >= 224) {
      return LinkRefusal.privateAddress;
    }
  }
  if (host.startsWith('[')) {
    // Any IPv6 literal. Not worth a full policy on the client: no legitimate
    // shared link is an IPv6 literal, so refusing all of them costs nothing.
    return LinkRefusal.privateAddress;
  }
  return null;
}

/// Hosts whose title is available from an unauthenticated oEmbed endpoint.
///
/// Preferred over scraping the page for two reasons: these pages render their
/// title with JavaScript, so the HTML often does not contain it at all, and a
/// documented JSON endpoint does not break when the markup is redesigned.
Uri? oEmbedEndpointFor(Uri url) {
  final host = url.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final target = Uri.encodeQueryComponent(url.toString());

  return switch (host) {
    'youtube.com' || 'youtu.be' || 'm.youtube.com' => Uri.parse(
        'https://www.youtube.com/oembed?url=$target&format=json'),
    'tiktok.com' || 'vm.tiktok.com' =>
      Uri.parse('https://www.tiktok.com/oembed?url=$target'),
    'vimeo.com' =>
      Uri.parse('https://vimeo.com/api/oembed.json?url=$target'),
    'x.com' || 'twitter.com' => Uri.parse(
        'https://publish.x.com/oembed?url=$target&omit_script=true'),
    'reddit.com' || 'old.reddit.com' =>
      Uri.parse('https://www.reddit.com/oembed?url=$target'),
    _ => null,
  };
}

/// Reads a page's own title. Returns null when there is nothing readable, which
/// is a normal outcome and not an error.
class LinkMetadataReader {
  LinkMetadataReader({PageTransport? transport})
      : _transport = transport ?? HttpPageTransport();

  final PageTransport _transport;

  /// The best title available for [url], or null.
  ///
  /// Never throws for an ordinary failure. A link that cannot be read must cost
  /// the user one extra tap, never the feature: the share sheet still offers to
  /// keep the link and to search by name.
  Future<String?> titleFor(Uri url) async {
    if (refuseLink(url) != null) return null;

    final oembed = oEmbedEndpointFor(url);
    if (oembed != null) {
      final title = await _tryOEmbed(oembed);
      if (title != null) return title;
      // Fall through: an oEmbed miss (a deleted video, an unsupported URL shape)
      // does not mean the page itself is unreadable.
    }
    return _tryPage(url);
  }

  Future<String?> _tryOEmbed(Uri endpoint) async {
    try {
      final response = await _transport.get(endpoint);
      if (!response.ok) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final title = decoded['title'];
      if (title is String && title.trim().isNotEmpty) return title.trim();

      // X returns the post text inside an HTML blockquote rather than a title.
      final html = decoded['html'];
      if (html is String) {
        final text = _stripTags(html);
        if (text.isNotEmpty) return text;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _tryPage(Uri url) async {
    try {
      final response = await _transport.get(url);
      if (!response.ok) return null;
      final type = response.contentType?.toLowerCase() ?? '';
      // A PDF or an image has no title to read and would be a pointless parse.
      if (type.isNotEmpty &&
          !type.contains('html') &&
          !type.contains('text/plain') &&
          !type.contains('json')) {
        return null;
      }
      return titleFromHtml(response.body);
    } catch (_) {
      return null;
    }
  }

  static String _stripTags(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

final RegExp _ogTitle = RegExp(
  r'''<meta[^>]+(?:property|name)\s*=\s*["'](?:og:title|twitter:title)["'][^>]*''',
  caseSensitive: false,
);
final RegExp _contentAttr = RegExp(
  r'''content\s*=\s*["']([^"']*)["']''',
  caseSensitive: false,
);
final RegExp _titleTag =
    RegExp(r'<title[^>]*>([\s\S]{1,300}?)</title>', caseSensitive: false);
final RegExp _jsonLdName = RegExp(
  r'''"name"\s*:\s*"((?:[^"\\]|\\.){2,200})"''',
  caseSensitive: false,
);

/// The page's title, from the most reliable source present.
///
/// Order is deliberate. Open Graph is what the page WANTS to be called when
/// shared, which is closer to the content than the <title> element, and <title>
/// often carries site furniture ("... | IGN").
String? titleFromHtml(String html) {
  final og = _ogTitle.firstMatch(html);
  if (og != null) {
    final content = _contentAttr.firstMatch(og.group(0)!);
    final value = content?.group(1);
    if (value != null && value.trim().isNotEmpty) return _unescape(value);
  }

  final ld = _jsonLdName.firstMatch(html);
  if (ld != null) {
    final value = ld.group(1);
    if (value != null && value.trim().isNotEmpty) return _unescape(value);
  }

  final tag = _titleTag.firstMatch(html);
  if (tag != null) {
    final value = tag.group(1);
    if (value != null && value.trim().isNotEmpty) return _unescape(value);
  }
  return null;
}

String _unescape(String raw) => raw
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll(r'\/', '/')
    .replaceAll(r'\"', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The real transport. dart:io, because the project ships no `http` package.
class HttpPageTransport implements PageTransport {
  HttpPageTransport({HttpClient? client})
      : _client = client ?? (HttpClient()..connectionTimeout = kFetchTimeout);

  final HttpClient _client;

  @override
  Future<PageResponse> get(Uri url) async {
    final request = await _client.getUrl(url);
    request.followRedirects = true;
    request.maxRedirects = kMaxRedirects;
    // Some hosts serve a stub to an unrecognised agent, and an honest one is
    // better manners than pretending to be a browser.
    request.headers.set(HttpHeaders.userAgentHeader, 'Ludeck/1.0 (+link preview)');
    request.headers.set(HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/json;q=0.9');

    final response = await request.close().timeout(kFetchTimeout);

    // Capped read. An unbounded page on a phone is a memory problem, and nothing
    // useful lives past the first half megabyte of markup anyway.
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
      if (chunks.length > kMaxBodyBytes) break;
    }

    return PageResponse(
      statusCode: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      body: utf8.decode(
        chunks.take(kMaxBodyBytes).toList(),
        allowMalformed: true,
      ),
    );
  }
}
