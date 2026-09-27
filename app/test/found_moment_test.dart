// The found-a-game moment: the physics as pure functions, then the moment
// itself driven through real gestures.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/found/found_moment.dart';

const _game = Game(igdbId: 7, title: 'Hollow Knight');
const _trees = <FoundTree>[
  (id: 1, name: 'Cozy', count: 4),
  (id: 2, name: 'Couch co-op', count: 0),
];

/// What the last opened moment returned.
FoundChoice? last;

void main() {
  group('physics', () {
    test('flick projection is Apple decay, not v^2/2a', () {
      // 1000 px/s at 0.998 carries 1 * 0.998 / 0.002 = 499px.
      expect(projectFlick(1000), moreOrLessEquals(499, epsilon: 0.01));
      expect(projectFlick(-1000), moreOrLessEquals(-499, epsilon: 0.01));
      expect(projectFlick(0), 0);
    });

    test('rubber-band resists more the further past the edge', () {
      final a = rubberBand(50, 900);
      final b = rubberBand(200, 900);
      expect(a, lessThan(50));
      expect(b, lessThan(200));
      expect(b / 200, lessThan(a / 50), reason: 'resistance must grow');
    });

    test('a throw lands on the nearest chip only once it reaches the row', () {
      final chips = [
        const Rect.fromLTWH(20, 800, 100, 50),
        const Rect.fromLTWH(140, 800, 100, 50),
        const Rect.fromLTWH(260, 800, 100, 50),
      ];
      expect(
          landingChip(projected: const Offset(200, 600), chips: chips, rowTop: 780),
          isNull,
          reason: 'short of the row springs home');
      expect(
          landingChip(projected: const Offset(200, 900), chips: chips, rowTop: 780),
          1);
      expect(
          landingChip(projected: const Offset(900, 1400), chips: chips, rowTop: 780),
          2,
          reason: 'past the end of the row still picks the end chip');
    });

    test('a chip not built yet (no rect) can never win', () {
      final chips = [Rect.zero, const Rect.fromLTWH(300, 800, 100, 50)];
      expect(
          landingChip(projected: const Offset(0, 900), chips: chips, rowTop: 780),
          1);
    });
  });

  group('the moment', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);
      last = null;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => last = await showFoundMoment(context,
                    game: _game, trees: _trees),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the game and one chip per tree plus a new tree',
        (tester) async {
      await open(tester);
      expect(find.text('New find'), findsOneWidget);
      expect(find.text('Hollow Knight'), findsOneWidget);
      expect(find.bySemanticsLabel('Hang it on Cozy'), findsOneWidget);
      expect(find.bySemanticsLabel('Hang it on Couch co-op'), findsOneWidget);
      // Last in the row; at the test font's width it is past the scroll edge.
      await tester.scrollUntilVisible(
          find.bySemanticsLabel('Plant a new tree for it'), 120,
          scrollable: find.byType(Scrollable).last);
      expect(find.bySemanticsLabel('Plant a new tree for it'), findsOneWidget);
    });

    testWidgets('tapping a tree files onto it', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('Hang it on Couch co-op'));
      await tester.pumpAndSettle();
      expect(find.text('New find'), findsNothing);
      expect(last?.treeId, 2);
    });

    testWidgets('Not now leaves it on the ground', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('found-not-now')));
      await tester.pumpAndSettle();
      expect(find.text('New find'), findsNothing);
      expect(last?.isNotNow, isTrue);
    });

    testWidgets('system back is Not now, never a lost game', (tester) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('New find'), findsNothing);
      expect(last?.isNotNow, isTrue);
    });

    testWidgets('a flick toward the row lands on the tree it points at',
        (tester) async {
      await open(tester);
      final card = find.bySemanticsLabel('Hollow Knight, new find');
      final target =
          tester.getCenter(find.bySemanticsLabel('Hang it on Cozy'));
      final from = tester.getCenter(card);
      // A short, fast drag: it reaches nowhere near the row by itself, only
      // the projection carries it there.
      final dir = (target - from) / (target - from).distance;
      await tester.flingFrom(from, dir * 80, 2500);
      await tester.pumpAndSettle();
      expect(find.text('New find'), findsNothing);
      expect(last?.treeId, 1);
    });

    testWidgets('a weak drag that misses every tree springs home',
        (tester) async {
      await open(tester);
      final card = find.bySemanticsLabel('Hollow Knight, new find');
      final home = tester.getCenter(card);
      await tester.dragFrom(home, const Offset(30, 40));
      await tester.pumpAndSettle();
      expect(find.text('New find'), findsOneWidget, reason: 'still choosing');
      expect(last, isNull);
      expect(tester.getCenter(card).dx, moreOrLessEquals(home.dx, epsilon: 0.5));
      expect(tester.getCenter(card).dy, moreOrLessEquals(home.dy, epsilon: 0.5));
    });

    testWidgets('reduced motion: fully shown on the first frame',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(412, 915), disableAnimations: true),
          child: FoundMoment(game: _game, trees: _trees),
        ),
      ));
      await tester.pump(); // the post-frame callback that sets the entrance
      await tester.pump();
      final title = tester.widget<Opacity>(find
          .ancestor(of: find.text('Hollow Knight'), matching: find.byType(Opacity))
          .first);
      expect(title.opacity, 1.0,
          reason: 'reduced motion resolves the entrance, it does not play it');
    });
  });
}
