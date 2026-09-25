// One lookup per game per session, no matter how many rows ask.
//
// `CollectionView` rebuilds its rows on every scroll and every store change, and
// a row with no cover asks for one on every build if nothing here remembers
// that it already asked. Without this, scrolling a long list with many
// cover-less rows would fire the same handful of network requests repeatedly,
// and a slow reply arriving twice would double-write harmlessly but wastefully.
//
// Deliberately in-memory only, not persisted: a MISS is not a permanent fact
// worth writing to disk (Wikipedia gains a page, a title gets corrected), and a
// HIT is already persisted by `Repository.setCoverUrl` the moment it resolves --
// this cache exists only to survive one app session's worth of rebuilds, not to
// avoid the lookup on the NEXT app open.
import 'cover_art.dart';

class CoverArtCache {
  CoverArtCache({CoverArtReader? reader}) : _reader = reader ?? CoverArtReader();

  final CoverArtReader _reader;

  /// igdbId -> the pending or finished lookup. Present means "do not ask
  /// again this session", whether it eventually resolves to a URL or to null.
  final Map<int, Future<String?>> _inFlight = {};

  /// Looks up [title]'s cover once, calling [onFound] the FIRST time a
  /// non-null result arrives for [igdbId] (never for a repeat call, and never
  /// for a miss).
  ///
  /// Fire-and-forget by design: a row calls this from `build()` and must not
  /// await it, so the list never blocks on the network for a paint it can
  /// perfectly well complete without an image.
  void request(int igdbId, String title, void Function(String url) onFound) {
    final existing = _inFlight[igdbId];
    if (existing != null) return;

    final future = _reader.coverFor(title);
    _inFlight[igdbId] = future;
    future.then((url) {
      if (url != null) onFound(url);
    });
  }
}
