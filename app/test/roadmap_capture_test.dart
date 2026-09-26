// Renders RoadmapView to PNGs so the winding-path layout and the rounded elbow
// connectors can be JUDGED from real pixels, not asserted from geometry alone.
// A green layout test proves nodes do not overlap; it cannot prove the path
// reads as a journey. This harness is the "render it and look" step.
//
// Not a golden test: it writes PNGs to docs/shots for a human (and me) to look
// at, and asserts only that a frame was produced. Run:
//   flutter test test/roadmap_capture_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/roadmap/roadmap_view.dart';
import 'package:ludeck/ui/tokens.dart';

void main() {
  Future<void> capture(
    WidgetTester tester,
    String name,
    List<TreeItem> items,
  ) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(412 * 2, 900 * 2);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Tokens.cosmos.deep.first,
            body: RepaintBoundary(
              key: key,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: Tokens.cosmos.deep,
                  ),
                ),
                child: RoadmapView(
                  items: items,
                  animateArrivals: false,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('../docs/shots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/roadmap-$name.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.existsSync(), isTrue);
    });
  }

  TreeItem game(int id, String title, Ownership o, Progress p) => TreeItem(
        game: Game(igdbId: id, title: title),
        entry: Entry(igdbId: id, ownership: o, progress: p),
        copies: const [],
      );

  testWidgets('empty roadmap', (tester) async {
    await capture(tester, 'empty', const []);
  });

  testWidgets('few nodes', (tester) async {
    await capture(tester, 'few', [
      game(1, 'Hollow Knight', Ownership.owned, Progress.playing),
      game(2, 'Celeste', Ownership.owned, Progress.finished),
      game(3, 'Outer Wilds', Ownership.spotted, Progress.untouched),
      game(4, 'Hades', Ownership.owned, Progress.untouched),
    ]);
  });

  testWidgets('many nodes', (tester) async {
    await capture(tester, 'many', [
      for (var i = 0; i < 12; i++)
        game(100 + i, 'Game $i', Ownership.owned,
            Progress.values[i % Progress.values.length]),
    ]);
  });

  testWidgets('lifecycle states', (tester) async {
    // One node per lifecycle state, in order, so each ring can be judged: a
    // wishlist bud (dim ring), untouched, installed, playing (accent ring),
    // finished (gold glow ring).
    await capture(tester, 'states', [
      game(1, 'Wishlist bud', Ownership.spotted, Progress.untouched),
      game(2, 'Not started', Ownership.owned, Progress.untouched),
      game(3, 'Installed', Ownership.owned, Progress.installed),
      game(4, 'Playing now', Ownership.owned, Progress.playing),
      game(5, 'Finished', Ownership.owned, Progress.finished),
    ]);
  });

  // The settled end state of the draw-line creation from the REAL RoadmapView:
  // the new node popped in with its connector fully drawn. A headless widget
  // test cannot reliably FREEZE an animation mid-frame (real-time controller vs
  // the test clock), so the progressive-draw MECHANISM is proven separately by
  // roadmap_draw_test.dart (partial path length grows with t), and the live
  // motion is captured on-device in Stage 6. This frame proves the end result.
  testWidgets('draw-line creation: settled', (tester) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(412 * 2, 900 * 2);
    addTearDown(tester.view.reset);

    const addedId = 99;
    final items = [
      game(1, 'First', Ownership.owned, Progress.finished),
      game(2, 'Second', Ownership.owned, Progress.playing),
      game(addedId, 'New game', Ownership.spotted, Progress.untouched),
    ];

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Tokens.cosmos.deep.first,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Tokens.cosmos.deep,
                ),
              ),
              child: RepaintBoundary(
                key: key,
                child: RoadmapView(
                  items: items,
                  animateArrivals: false,
                  justAddedIgdbId: addedId,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('../docs/shots');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('${dir.path}/roadmap-draw-settled.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
