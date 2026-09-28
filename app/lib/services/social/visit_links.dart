import 'dart:async';

import 'package:app_links/app_links.dart';

import 'tree_links.dart';

/// Orchard handles from links that open the app: the one it was launched
/// with (a cold start from the web page's "Open in Ludeck"), then every later
/// one. Links that are not orchard links, such as the Google sign-in
/// callback that supabase_flutter handles on the same scheme, are dropped.
Stream<String> appVisitLinks([AppLinks? links]) {
  final l = links ?? AppLinks();
  final out = StreamController<String>();
  StreamSubscription<Uri>? sub;
  out.onListen = () async {
    try {
      final first = await l.getInitialLink();
      final h = first == null ? null : visitHandleFrom(first);
      if (h != null) out.add(h);
    } catch (_) {
      // No initial link, or no platform (a test host): nothing to open.
    }
    sub = l.uriLinkStream.listen((uri) {
      final h = visitHandleFrom(uri);
      if (h != null) out.add(h);
    }, onError: (Object _) {});
  };
  out.onCancel = () => sub?.cancel();
  return out.stream;
}
