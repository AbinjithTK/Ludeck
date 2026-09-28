// Where a shared orchard lives on the web, and how a tapped link comes back
// into the app. One file so the page (site/t/index.html), the share sheet and
// the deep-link handler cannot disagree about the shape of a link.

/// The public site, served by GitHub Pages from `site/` (docs/SITE.md).
/// Override per build with `--dart-define=SITE_BASE_URL=https://...`.
const String kSiteBaseUrl = String.fromEnvironment('SITE_BASE_URL',
    defaultValue: 'https://abinjithtk.github.io/Ludeck');

/// The web address a shared orchard opens at: `<site>/t/?h=<handle>`.
/// A query rather than a path, because a static host has no route for
/// `/t/<handle>`; `/t/` is one page that reads the handle.
String treeLinkFor(String handle) =>
    '$kSiteBaseUrl/t/?h=${Uri.encodeQueryComponent(handle)}';

/// The handle a link into the app names, or null when it is not a tree link.
///
/// Accepts the app's own scheme, which the web page's "Open in Ludeck" button
/// fires (`com.ludeck.android://t/<handle>`), and the web link itself, so a
/// verified App Link can be added later without touching this. Anything else
/// (the Google sign-in callback arrives on the same scheme) is not ours.
String? visitHandleFrom(Uri uri) {
  String? handle;
  if (uri.scheme == 'com.ludeck.android' && uri.host == 't') {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    handle = segs.isEmpty ? uri.queryParameters['h'] : segs.first;
  } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.toString().startsWith('$kSiteBaseUrl/t/')) {
    handle = uri.queryParameters['h'];
  }
  if (handle == null) return null;
  // The server's own handle rule (migration 0001): nothing else is looked up.
  return RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(handle) ? handle : null;
}
