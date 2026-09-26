// Renders the shareable RoadmapStoryCard to PNGs so the shared "story" image
// can be JUDGED from real pixels: a winding roadmap of status-ringed nodes, the
// gold ones lit, with the level/harvest header and branding. Writes to
// docs/shots; asserts a frame was produced. Run:
//   flutter test test/share_story_capture_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/ui/publish/roadmap_story_card.dart';
import 'package:ludeck/ui/tokens.dart';

void main() {
  PublishedGame pg(String title, Progress status, {int? rating}) =>
      PublishedGame(
        igdbId: title.hashCode,
        title: title,
        coverUrl: null,
        status: status,
        rating: rating,
        branchName: 'PC',
      );

  Future<void> capture(
    WidgetTester tester,
    String name,
    List<PublishedGame> games,
    int level,
  ) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(440 * 2, 620 * 2);
    addTearDown(tester.view.reset);

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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: RepaintBoundary(
                    key: key,
                    child: RoadmapStoryCard(games: games, level: level),
                  ),
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
      File('${dir.path}/share-$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(bytes.lengthInBytes, greaterThan(0));
    });
  }

  testWidgets('share story: a mixed journey', (tester) async {
    await capture(tester, 'mixed', [
      pg('Hades', Progress.finished, rating: 5),
      pg('Celeste', Progress.finished, rating: 5),
      pg('Hollow Knight', Progress.playing),
      pg('Outer Wilds', Progress.untouched),
      pg('Tunic', Progress.finished),
      pg('Disco Elysium', Progress.abandoned),
    ], 4);
  });

  testWidgets('share story: empty', (tester) async {
    await capture(tester, 'empty', const [], 1);
  });

  testWidgets('share story: many (capped)', (tester) async {
    await capture(tester, 'many', [
      for (var i = 0; i < 14; i++)
        pg('Game $i', Progress.values[i % Progress.values.length]),
    ], 7);
  });
}
