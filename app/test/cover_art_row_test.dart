// A row's cover art: a placeholder tile when the game has none, a real image
// when it does, and a lazy lookup for the ones that could get one.
//
// CollectionView is pumped directly, without TreeScreen, so this stays a pure
// widget test with no database and no `tester.runAsync` -- there is nothing
// here that touches sqflite.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/services/cover_art.dart';
import 'package:ludeck/services/cover_art_cache.dart';
import 'package:ludeck/services/link_metadata.dart' show PageResponse, PageTransport;
import 'package:ludeck/ui/collection/collection_view.dart';

TreeItem _item(int id, String title, {String? coverUrl}) => TreeItem(
      game: Game(igdbId: id, title: title, coverUrl: coverUrl),
      entry: const Entry(
        igdbId: 0,
        ownership: Ownership.owned,
        progress: Progress.playing,
      ),
      copies: const [],
    );

Future<void> _pump(WidgetTester tester, List<TreeItem> items,
    {CoverArtCache? coverCache, void Function(int, String)? onCoverFound}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CollectionView(
        items: items,
        onSelect: (_) {},
        onHold: (_) {},
        topInset: 0,
        bottomInset: 0,
        coverCache: coverCache,
        onCoverFound: onCoverFound,
      ),
    ),
  ));
}

class _RespondingTransport implements PageTransport {
  @override
  Future<PageResponse> get(Uri url) async => const PageResponse(
        statusCode: 200,
        contentType: 'application/json',
        body: '{"thumbnail":{"source":"https://x/found.png"}}',
      );
}

void main() {
  group('row cover art', () {
    testWidgets('a game with a coverUrl renders an Image, not the placeholder',
        (tester) async {
      await _pump(tester, [
        _item(1, 'Hades', coverUrl: 'https://example.com/hades.png'),
      ]);

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.videogame_asset_outlined), findsNothing);
    });

    testWidgets('a game with no coverUrl and no cache shows the placeholder',
        (tester) async {
      await _pump(tester, [_item(1, 'Hollow Knight')]);

      expect(find.byIcon(Icons.videogame_asset_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets(
        'a game with no coverUrl asks the cache, and onCoverFound reports the result',
        (tester) async {
      final cache =
          CoverArtCache(reader: CoverArtReader(transport: _RespondingTransport()));
      final found = <int>[];

      await _pump(
        tester,
        [_item(7, 'Celeste')],
        coverCache: cache,
        onCoverFound: (id, url) => found.add(id),
      );
      // The lookup is fire-and-forget from build(); pump lets it settle.
      await tester.pump(const Duration(milliseconds: 10));

      expect(found, [7]);
    });

    testWidgets('a game that already has a coverUrl never asks the cache',
        (tester) async {
      var asked = false;
      final cache = CoverArtCache(
        reader: CoverArtReader(transport: _AssertingTransport(() => asked = true)),
      );

      await _pump(
        tester,
        [_item(1, 'Hades', coverUrl: 'https://example.com/hades.png')],
        coverCache: cache,
      );
      await tester.pump(const Duration(milliseconds: 10));

      expect(asked, isFalse);
    });

    testWidgets('a broken image URL falls back to the placeholder, not a red X',
        (tester) async {
      // Image.network against a URL this test harness cannot actually load
      // exercises errorBuilder rather than a real decode -- there is no network
      // in a widget test regardless of the host named.
      await _pump(tester, [
        _item(1, 'Hades', coverUrl: 'https://example.invalid/nope.png'),
      ]);
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byIcon(Icons.videogame_asset_outlined), findsOneWidget);
    });
  });
}

class _AssertingTransport implements PageTransport {
  _AssertingTransport(this.onCalled);
  final void Function() onCalled;

  @override
  Future<PageResponse> get(Uri url) async {
    onCalled();
    return const PageResponse(statusCode: 404, body: '');
  }
}
