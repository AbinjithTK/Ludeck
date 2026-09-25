// CoverArtCache: at most one lookup per game per session, no matter how many
// times a rebuilding row asks.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/services/cover_art.dart';
import 'package:ludeck/services/cover_art_cache.dart';
import 'package:ludeck/services/link_metadata.dart' show PageResponse, PageTransport;

/// Answers every request with a fixed cover, and counts how many actually
/// reached the transport -- which is what proves the cache, not the reader,
/// is doing the deduplication.
class _CountingTransport implements PageTransport {
  int callCount = 0;

  @override
  Future<PageResponse> get(Uri url) async {
    callCount++;
    return PageResponse(
      statusCode: 200,
      contentType: 'application/json',
      body: '{"thumbnail":{"source":"https://x/cover.png"}}',
    );
  }
}

void main() {
  group('CoverArtCache', () {
    test('asking twice for the same game only reaches the network once',
        () async {
      final transport = _CountingTransport();
      final cache = CoverArtCache(reader: CoverArtReader(transport: transport));

      final found = <String>[];
      cache.request(1, 'Hades', found.add);
      cache.request(1, 'Hades', found.add);

      // Let both fire-and-forget futures settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(transport.callCount, 1);
    });

    test('calls onFound once a cover resolves', () async {
      final transport = _CountingTransport();
      final cache = CoverArtCache(reader: CoverArtReader(transport: transport));

      final found = <String>[];
      cache.request(42, 'Celeste', found.add);
      await Future<void>.delayed(Duration.zero);

      expect(found, ['https://x/cover.png']);
    });

    test('different games are looked up independently', () async {
      final transport = _CountingTransport();
      final cache = CoverArtCache(reader: CoverArtReader(transport: transport));

      cache.request(1, 'Hades', (_) {});
      cache.request(2, 'Celeste', (_) {});
      await Future<void>.delayed(Duration.zero);

      expect(transport.callCount, 2);
    });

    test('a miss never calls onFound', () async {
      final cache = CoverArtCache(
        reader: CoverArtReader(transport: _MissTransport()),
      );

      var called = false;
      cache.request(1, 'Nothing Findable', (_) => called = true);
      await Future<void>.delayed(Duration.zero);

      expect(called, isFalse);
    });
  });
}

class _MissTransport implements PageTransport {
  @override
  Future<PageResponse> get(Uri url) async =>
      const PageResponse(statusCode: 404, body: '');
}
