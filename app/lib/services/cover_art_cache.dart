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
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'cover_art.dart';
import 'dominant_color.dart';

class CoverArtCache {
  CoverArtCache({CoverArtReader? reader}) : _reader = reader ?? CoverArtReader();

  final CoverArtReader _reader;

  /// igdbId -> the pending or finished lookup. Present means "do not ask
  /// again this session", whether it eventually resolves to a URL or to null.
  final Map<int, Future<String?>> _inFlight = {};

  /// igdbId -> its cover's dominant colour, once extracted. Session-only, same
  /// reasoning as the URL cache: a HIT is cheap to recompute next launch and a
  /// MISS is not a durable fact. Read synchronously by the tree painter.
  final Map<int, ui.Color> _bloom = {};

  /// igdbIds whose extraction is already running, so a rebuild does not decode
  /// the same image twice.
  final Set<int> _bloomInFlight = {};

  /// The dominant colours known so far, for the painter's bloom pass. A copy, so
  /// the painter compares a stable snapshot in `shouldRepaint`.
  Map<int, ui.Color> get bloomTints => Map.unmodifiable(_bloom);

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

  /// Extract [igdbId]'s cover colour from [url] once, calling [onColour] when it
  /// lands. Fire-and-forget and idempotent per id, like [request]. Any decode
  /// failure is swallowed: a fruit with no bloom is a fine outcome, a thrown
  /// exception in a paint path is not.
  void requestBloom(int igdbId, String url, void Function(ui.Color) onColour) {
    if (_bloom.containsKey(igdbId) || _bloomInFlight.contains(igdbId)) return;
    _bloomInFlight.add(igdbId);
    _extractBloom(url).then((colour) {
      _bloomInFlight.remove(igdbId);
      if (colour == null) return;
      _bloom[igdbId] = colour;
      onColour(colour);
    }).catchError((_) {
      _bloomInFlight.remove(igdbId);
    });
  }

  Future<ui.Color?> _extractBloom(String url) async {
    final provider = NetworkImage(url);
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<ui.Image>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final image = await completer.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return dominantColor(
      data.buffer.asUint8List(),
      image.width,
      image.height,
    );
  }
}
