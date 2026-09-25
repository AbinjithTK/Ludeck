// CoverArtReader: a title in, a cover URL out, with no network in this file.
//
// The transport is injected exactly like link_metadata's, so every shape of
// Wikipedia's response -- a real thumbnail, a disambiguation page with none, a
// 404, a malformed body -- is a recorded string rather than a live request.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/services/cover_art.dart';
import 'package:ludeck/services/link_metadata.dart' show PageResponse, PageTransport;

class _FakeTransport implements PageTransport {
  _FakeTransport(this.responses);

  /// Keyed by a substring of the requested URL.
  final Map<String, PageResponse> responses;
  final List<Uri> requested = [];

  @override
  Future<PageResponse> get(Uri url) async {
    requested.add(url);
    for (final entry in responses.entries) {
      if (url.toString().contains(entry.key)) return entry.value;
    }
    throw const _NoRoute();
  }
}

class _NoRoute implements Exception {
  const _NoRoute();
}

PageResponse _json(String body) =>
    PageResponse(statusCode: 200, body: body, contentType: 'application/json');

void main() {
  group('CoverArtReader', () {
    test('returns the thumbnail source when Wikipedia has one', () async {
      final transport = _FakeTransport({
        'Grand_Theft_Auto_V': _json('{"thumbnail":{"source":'
            '"https://upload.wikimedia.org/wikipedia/en/a/a5/Grand_Theft_Auto_V.png",'
            '"width":284,"height":351}}'),
      });
      final reader = CoverArtReader(transport: transport);

      final cover = await reader.coverFor('Grand Theft Auto V');

      expect(cover,
          'https://upload.wikimedia.org/wikipedia/en/a/a5/Grand_Theft_Auto_V.png');
    });

    test('requests the summary endpoint with spaces as underscores', () async {
      final transport = _FakeTransport({
        'page/summary/Hollow_Knight': _json('{"thumbnail":{"source":"https://x/y.png"}}'),
      });
      final reader = CoverArtReader(transport: transport);

      await reader.coverFor('Hollow Knight');

      expect(transport.requested, hasLength(1));
      expect(transport.requested.single.host, 'en.wikipedia.org');
      expect(transport.requested.single.path, contains('Hollow_Knight'));
    });

    test('a page with no thumbnail (disambiguation, stub) returns null',
        () async {
      final transport = _FakeTransport({
        'summary': _json('{"title":"Some Ambiguous Thing"}'),
      });
      final reader = CoverArtReader(transport: transport);

      expect(await reader.coverFor('Some Ambiguous Thing'), isNull);
    });

    test('a 404 (no such page) returns null, not a thrown error', () async {
      final transport = _FakeTransport({
        'summary': const PageResponse(statusCode: 404, body: ''),
      });
      final reader = CoverArtReader(transport: transport);

      expect(await reader.coverFor('Not A Real Game Title Xyz'), isNull);
    });

    test('a malformed JSON body returns null rather than throwing', () async {
      final transport = _FakeTransport({'summary': _json('{not json')});
      final reader = CoverArtReader(transport: transport);

      expect(await reader.coverFor('Whatever'), isNull);
    });

    test('a transport failure returns null rather than throwing', () async {
      final reader = CoverArtReader(transport: _FakeTransport(const {}));

      expect(await reader.coverFor('Anything'), isNull);
    });

    test('a blank title is refused without a request', () async {
      final transport = _FakeTransport(const {});
      final reader = CoverArtReader(transport: transport);

      expect(await reader.coverFor('   '), isNull);
      expect(transport.requested, isEmpty);
    });
  });
}
