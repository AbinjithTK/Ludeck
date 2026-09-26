// Capture the harvest burst mid-animation, headless.
//
// A still cannot prove motion, but a STRIP of frames at t = 0.15/0.4/0.7 shows
// the burst expanding and fading -- the ring growing outward, the rays reaching
// further, both losing alpha. Skipped unless LUDECK_CAPTURE is set. This is the
// look-at-the-pixels check the project relies on, done headless so it needs no
// device drive of the full harvest flow (which the store tests already prove
// fires correctly).

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/tokens.dart';
import 'package:ludeck/ui/tree/procedural_tree_view.dart';

TreeItem _item(int id, String title, {bool harvested = false}) => TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: Ownership.owned,
        progress: harvested ? Progress.finished : Progress.untouched,
      ),
      copies: const [],
    );

void main() {
  testWidgets('render the harvest burst over a fruit', (tester) async {
    final dir = io.Platform.environment['LUDECK_CAPTURE'];
    if (dir == null) return;

    const phone = Size(412, 760);
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A small tree with one harvested game; the burst fires over id 1.
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: Tokens.canopy.sky,
              ),
            ),
            child: ProceduralTreeView(
              items: [
                _item(1, 'Hades', harvested: true),
                for (var i = 0; i < 4; i++) _item(10 + i, 'Game $i'),
              ],
              animateArrivals: false,
              burstIgdbId: 1,
            ),
          ),
        ),
      ),
    ));

    // Step the burst and grab frames across its life. runAsync for toImage,
    // which waits on the raster side the fake clock never advances.
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    for (final ms in const [80, 220, 400]) {
      await tester.pump(Duration(milliseconds: ms));
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        io.File('$dir/burst-$ms.png').writeAsBytesSync(
          bytes!.buffer.asUint8List(),
          flush: true,
        );
      });
    }
  });
}
