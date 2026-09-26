import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/add/discovery_tree.dart';

Game _g(int id) => Game(igdbId: id, title: 'Game $id');

void main() {
  group('canopyAlignment', () {
    test('a phone-width box shows the canopy from the top', () {
      // 412 wide: scale 1, a 300-tall window, canopy top at artboard y 185.
      final a = canopyAlignment(412, 300);
      const overflow = 732 - 300;
      final top = (a.y + 1) / 2 * overflow;
      expect(top, closeTo(185, 0.01));
    });

    test('scales with width: the visible band starts at the canopy', () {
      final a = canopyAlignment(824, 600); // scale 2, visible 300 units
      final top = (a.y + 1) / 2 * (732 - 300);
      expect(top, closeTo(185, 0.01));
    });

    test('a box taller than the artboard needs no offset', () {
      expect(canopyAlignment(100, 900), Alignment.center);
    });

    test('degenerate sizes do not divide by zero', () {
      expect(canopyAlignment(0, 300), Alignment.center);
      expect(canopyAlignment(412, 0), Alignment.center);
    });
  });

  group('DiscoveryTree headless', () {
    // The test host has no Rive native library. The tree must degrade to
    // nothing, never throw, because the result list is the real content.
    testWidgets('mounts and updates without throwing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            height: 300, child: DiscoveryTree(games: [_g(1), _g(2)])),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            height: 300, child: DiscoveryTree(games: [_g(3)])),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion shows nothing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
              height: 300, child: DiscoveryTree(games: [_g(1)])),
        ),
      ));
      expect(find.byType(LayoutBuilder), findsNothing);
    });
  });
}
