import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/common/loading_disc.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(backgroundColor: const Color(0xFF0B0A1C), body: child),
      ),
    );

void main() {
  group('DelayedSearchDisc', () {
    testWidgets('stays hidden under the flicker threshold', (tester) async {
      await tester.pumpWidget(_host(const DelayedSearchDisc()));
      await tester.pump(kSearchDiscDelay - const Duration(milliseconds: 50));
      expect(find.byKey(const Key('search-disc')), findsNothing);
      expect(find.byType(LoadingDisc), findsNothing);
    });

    testWidgets('appears once the wait is real, announced as Searching',
        (tester) async {
      await tester.pumpWidget(_host(const DelayedSearchDisc()));
      await tester.pump(kSearchDiscDelay + const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('search-disc')), findsOneWidget);
      expect(find.bySemanticsLabel('Searching'), findsOneWidget);
      // Spinning: the rotation value moves between frames.
      final rot = tester.widget<RotationTransition>(
          find.descendant(
              of: find.byType(LoadingDisc),
              matching: find.byType(RotationTransition)));
      final a = rot.turns.value;
      await tester.pump(const Duration(milliseconds: 200));
      expect(rot.turns.value, isNot(a));
      // Unmount mid-spin must not leak a ticker.
      await tester.pumpWidget(_host(const SizedBox()));
    });

    testWidgets('a result arriving first cancels the disc cleanly',
        (tester) async {
      await tester.pumpWidget(_host(const DelayedSearchDisc()));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(_host(const Text('results')));
      await tester.pump(kSearchDiscDelay * 2);
      expect(find.byType(LoadingDisc), findsNothing);
    });
  });

  group('LoadingDisc', () {
    testWidgets('reduced motion draws it still', (tester) async {
      await tester.pumpWidget(_host(
          const Center(child: LoadingDisc(diameter: 60)),
          reduceMotion: true));
      final rot = tester.widget<RotationTransition>(find.descendant(
          of: find.byType(LoadingDisc),
          matching: find.byType(RotationTransition)));
      final a = rot.turns.value;
      await tester.pump(const Duration(milliseconds: 500));
      expect(rot.turns.value, a);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('spinning: false parks the ticker', (tester) async {
      await tester.pumpWidget(
          _host(const Center(child: LoadingDisc(diameter: 60, spinning: false))));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('DiscCover', () {
    testWidgets('no url shows the placeholder, never a disc', (tester) async {
      await tester.pumpWidget(_host(const DiscCover(
          url: null,
          width: 40,
          height: 53,
          placeholder: Text('no-cover'))));
      expect(find.text('no-cover'), findsOneWidget);
      expect(find.byType(LoadingDisc), findsNothing);
    });
  });

  // Not an assertion: writes build/disc_capture.png so the drawing can be
  // looked at. Green tests do not prove a painted thing looks right.
  testWidgets('capture', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(_host(Center(
      child: RepaintBoundary(
        key: key,
        child: Container(
          color: const Color(0xFF0B0A1C),
          padding: const EdgeInsets.all(16),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            LoadingDisc(diameter: 160, spinning: false),
            SizedBox(width: 16),
            LoadingDisc(diameter: 72, spinning: false),
            SizedBox(width: 16),
            LoadingDisc(diameter: 34, spinning: false),
          ]),
        ),
      ),
    )));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/disc_capture.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
