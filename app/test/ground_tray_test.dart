// The ground tray, fruit looks and the living meadow: the pure parts pinned
// as arithmetic, the tray driven as a widget.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/common/glass.dart';
import 'package:ludeck/ui/orchard/fruit_look.dart';
import 'package:ludeck/ui/orchard/fruit_slots.g.dart';
import 'package:ludeck/ui/orchard/ground_tray.dart';
import 'package:ludeck/ui/orchard/meadow.dart';
import 'package:ludeck/ui/orchard/rive_tree.dart';

TreeItem item(int id, String title,
        {Ownership o = Ownership.owned, Progress p = Progress.untouched}) =>
    TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(igdbId: id, ownership: o, progress: p),
      copies: const [],
    );

void main() {
  group('fruit looks', () {
    test('each state has its own look; gold only for finished', () {
      expect(lookOf(item(1, 'A', o: Ownership.spotted)), FruitLook.bud);
      expect(lookOf(item(1, 'A')), FruitLook.plain);
      expect(lookOf(item(1, 'A', p: Progress.installed)), FruitLook.plain);
      expect(lookOf(item(1, 'A', p: Progress.playing)), FruitLook.playing);
      expect(lookOf(item(1, 'A', p: Progress.finished)), FruitLook.harvested);
      // A recommendation you finished elsewhere is still not yours: bud wins.
      expect(lookOf(item(1, 'A', o: Ownership.spotted, p: Progress.finished)),
          FruitLook.bud);
    });

    Future<(int, int, int, int)> pixel(Uint8List png, int x, int y) async {
      final img = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
      expect(img.width, kFruitW);
      expect(img.height, kFruitH);
      final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final i = (y * img.width + x) * 4;
      return (data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2),
          data.getUint8(i + 3));
    }

    Future<ui.Image> red() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 60, 80),
          Paint()..color = const Color(0xFFE02020));
      return rec.endRecording().toImage(60, 80);
    }

    testWidgets('harvested wears a gold rim, bud is drained of colour',
        (tester) async {
      await tester.runAsync(() async {
        final plain = await composeFruit(await red(), 'X', FruitLook.plain);
        final gold = await composeFruit(await red(), 'X', FruitLook.harvested);
        final bud = await composeFruit(await red(), 'X', FruitLook.bud);
        final playing = await composeFruit(await red(), 'X', FruitLook.playing);

        final p = await pixel(plain, 10, 160);
        expect(p.$1, greaterThan(200), reason: 'plain keeps its cover');
        final g = await pixel(gold, 10, 160); // on the rim
        expect(g.$1, greaterThan(200));
        expect(g.$2, greaterThan(150), reason: 'rim is gold, not the red cover');
        expect(g.$3, lessThan(120));
        final b = await pixel(bud, 120, 60);
        final spread = [b.$1, b.$2, b.$3].reduce((a, c) => a > c ? a : c) -
            [b.$1, b.$2, b.$3].reduce((a, c) => a < c ? a : c);
        expect(spread, lessThan(60), reason: 'bud is nearly grey ($b)');
        // The play mark sits in the corner; the rest of the cover is untouched.
        final corner = await pixel(playing, kFruitW - 54, kFruitH - 54);
        expect(corner.$1, greaterThan(200), reason: 'play glyph is light');
        final open = await pixel(playing, 40, 60);
        expect(open.$1, greaterThan(200));
      });
    });

    testWidgets('a game with no cover becomes a lettered card, not blank',
        (tester) async {
      await tester.runAsync(() async {
        final png = await composeFruit(null, 'Zelda', FruitLook.plain);
        final bg = await pixel(png, 6, 6);
        expect(bg.$4, 255, reason: 'the card is filled');
      });
    });
  });

  group('fruit slots', () {
    test('one row per game count, each card inside the artboard', () {
      expect(kFruitCentres.length, kTreeSlots);
      for (var n = 1; n <= kTreeSlots; n++) {
        expect(kFruitCentres[n - 1].length, n);
        for (final (x, y, sc) in kFruitCentres[n - 1]) {
          expect(x, inInclusiveRange(0, kTreeArtW));
          expect(y, inInclusiveRange(kCanopyTop - 40, kTreeBaseY));
          expect(sc, inInclusiveRange(0.5, 1.0));
        }
      }
    });
  });

  group('meadow life', () {
    test('a finger parts the grass: away from it, bounded, gone past its reach', () {
      const f = Offset(100, 500);
      expect(touchLean(110, 500, f, 1), greaterThan(0), reason: 'right of it leans right');
      expect(touchLean(90, 500, f, 1), lessThan(0));
      expect(touchLean(100 + kTouchReach + 1, 500, f, 1), 0);
      expect(touchLean(110, 500, null, 1), 0);
      expect(touchLean(101, 500, f, 1).abs(), lessThanOrEqualTo(0.9));
      expect(touchLean(110, 500, f, 0.5), lessThan(touchLean(110, 500, f, 1)));
    });

    test('a tap throws petals up that fall and fade, and bounces a flower there', () {
      final c = MeadowClock();
      c.advance(1 / 60, 0);
      c.poke(const Offset(200, 600));
      expect(c.petals, isNotEmpty);
      final start = c.petalAt(c.petals.first).$1;
      for (var i = 0; i < 12; i++) {
        c.advance(1 / 60, 0);
      }
      expect(c.petalAt(c.petals.first).$1.dy, lessThan(start.dy), reason: 'thrown up');
      expect(c.pokeNod(200, 600).abs(), greaterThan(0));
      expect(c.pokeNod(200 + kPokeReach + 5, 600), 0);
      for (var i = 0; i < 120; i++) {
        c.advance(1 / 60, 0);
      }
      expect(c.petals, isEmpty, reason: 'gone after their life');
      expect(c.pokes, isEmpty);
    });

    test('a pressed finger eases in, and the grass springs back after', () {
      final c = MeadowClock()..pointerDown(const Offset(1, 1));
      for (var i = 0; i < 10; i++) {
        c.advance(1 / 60, 0);
      }
      expect(c.touchK, greaterThan(0.9));
      c.pointerUp();
      for (var i = 0; i < 90; i++) {
        c.advance(1 / 60, 0);
      }
      expect(c.touch, isNull);
    });
    test('still when stopped, and bounded when moving', () {
      expect(swayAt(123, 0, 0, 0.4), 0);
      var most = 0.0;
      for (var t = 0.01; t < 40; t += 0.37) {
        for (var x = 0.0; x < 2000; x += 53) {
          final s = swayAt(x, t, 0, 0.5).abs();
          if (s > most) most = s;
        }
      }
      expect(most, lessThanOrEqualTo(kSwayLean + 1e-9));
      expect(most, greaterThan(kSwayLean * 0.5), reason: 'it does move');
    });

    test('a swipe blows the grass the way the ground trails, then it settles', () {
      final c = MeadowClock();
      var scroll = 0.0;
      for (var i = 0; i < 20; i++) {
        scroll += 40; // 2400 px/s
        c.advance(1 / 60, scroll);
      }
      expect(c.wind, greaterThan(0.2));
      expect(c.wind, lessThanOrEqualTo(kWindMax));
      for (var i = 0; i < 40; i++) {
        c.advance(1 / 60, scroll);
      }
      expect(c.wind.abs(), lessThan(0.02), reason: 'settles within ~0.7s');
    });
  });

  group('ground tray', () {
    test('open or closed is decided by where the pull was heading', () {
      expect(trayProjectsOpen(0.4, 0), isFalse);
      expect(trayProjectsOpen(0.6, 0), isTrue);
      expect(trayProjectsOpen(0.3, 1.0), isTrue, reason: 'a flick open');
      expect(trayProjectsOpen(0.8, -1.2), isFalse, reason: 'a flick shut');
    });

    Future<void> pump(WidgetTester tester, List<TreeItem> items,
        {bool reduce = false,
        void Function(TreeItem)? onOpen,
        void Function(String)? log}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: kTrayH,
                child: GroundTray(
                  items: items,
                  onOpen: onOpen ?? (_) {},
                  onLift: (i, from, at) => log?.call('lift ${i.game.title}'),
                  onLiftMove: (_) => log?.call('move'),
                  onLiftEnd: (_, v) => log?.call('end'),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    final five = [for (var i = 0; i < 5; i++) item(i + 1, 'Game $i')];

    testWidgets('collapsed shows the count; a tap opens the strip, another closes it',
        (tester) async {
      await pump(tester, five);
      expect(find.textContaining('on the ground', findRichText: true), findsNothing,
          reason: 'no words on the ground, only the count badge');
      expect(find.descendant(
              of: find.byKey(const Key('tray-count')), matching: find.text('5')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('5 games on the ground')), findsOneWidget,
          reason: 'a screen reader still hears what the number counts');
      expect(find.byKey(const Key('ground-strip')), findsNothing);
      final closed = tester.getRect(find.byType(GroundTray));
      final closedPill = tester.getSize(find.descendant(
          of: find.byType(GroundTray), matching: find.byType(Glass)).first);

      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ground-strip')), findsOneWidget);
      final openPill = tester.getSize(find.descendant(
          of: find.byType(GroundTray), matching: find.byType(Glass)).first);
      expect(closedPill.width, lessThan(closed.width), reason: 'closed hugs the pile');
      expect(openPill.width, moreOrLessEquals(closed.width, epsilon: 0.5),
          reason: 'open, the tray reaches the end of its space (the add button)');

      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ground-strip')), findsNothing);
    });

    testWidgets('no outline, and the open strip fades out at its far end',
        (tester) async {
      // Mixed statuses, so "drawn as it is" is actually tested.
      await pump(tester, [
        item(1, 'Game 0', p: Progress.finished),
        item(2, 'Game 1', p: Progress.playing),
        item(3, 'Game 2', o: Ownership.spotted),
        item(4, 'Game 3'),
        item(5, 'Game 4'),
      ]);
      Glass glass() => tester.widget<Glass>(find.descendant(
          of: find.byType(GroundTray), matching: find.byType(Glass)).first);
      expect(glass().rim, isFalse, reason: 'the tray is glass with no edge');
      expect(
          tester.widget<AnimatedOpacity>(find.byKey(const Key('tray-drop-glass'))).opacity,
          0,
          reason: 'at rest there is no capsule: the covers sit on the meadow');
      double fade() => tester.widget<TrayFade>(find.byType(TrayFade)).fade;
      expect(fade(), 0, reason: 'closed, nothing to fade');
      expect(tester.getSize(find.descendant(
          of: find.byType(GroundTray), matching: find.byType(Glass)).first).height,
          kTrayH);

      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pumpAndSettle();
      expect(fade(), kTrayFadeW);
      expect(tester.getSize(find.byKey(const ValueKey('ground-1'))).width, kTrayCoverW);
      // No status marks on the ground: every cover is drawn as it is and
      // with no card framing it, whatever its status on the tree.
      for (final f in tester.widgetList<FruitImage>(find.descendant(
          of: find.byType(GroundTray), matching: find.byType(FruitImage)))) {
        expect(f.look, FruitLook.plain);
        expect(f.bare, isTrue);
      }
    });

    testWidgets('the deal: covers travel from the pile, nearest first, and land '
        'exactly where the strip puts them', (tester) async {
      await pump(tester, five);
      await tester.tap(find.byKey(const Key('orchard-ground')));
      // Mid-deal: covers are in flight and card 0 is further along than card 4.
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.byKey(const Key('ground-strip')), findsNothing,
          reason: 'mid-deal the cards are animated, not the list');
      await tester.pumpAndSettle();
      // Settled: the list's first cover sits where dealPose(0, 1) put it.
      final pill = tester.getRect(find.descendant(
          of: find.byType(GroundTray), matching: find.byType(Glass)).first);
      final first = tester.getRect(find.byKey(const ValueKey('ground-1')));
      final pose = dealPose(0, 1, 0).rect.shift(pill.topLeft + const Offset(kTrayInset, kTrayInset));
      expect(first.left, moreOrLessEquals(pose.left, epsilon: 0.5));
      expect(first.top, moreOrLessEquals(pose.top, epsilon: 0.5));
      expect(first.width, moreOrLessEquals(pose.width, epsilon: 0.5));
    });

    testWidgets('reduce motion: it opens in one frame', (tester) async {
      await pump(tester, five, reduce: true);
      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pump();
      expect(find.byKey(const Key('ground-strip')), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a pull that is let go early still opens if it was flung',
        (tester) async {
      await pump(tester, five);
      await tester.fling(
          find.byKey(const Key('orchard-ground')), const Offset(60, 0), 900);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ground-strip')), findsOneWidget);
    });

    testWidgets('tap opens a game; hold lifts it and reports the carry',
        (tester) async {
      final log = <String>[];
      TreeItem? opened;
      await pump(tester, five, onOpen: (i) => opened = i, log: log.add);
      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pumpAndSettle();
      final cover = find.byKey(const ValueKey('ground-1'));
      await tester.tap(cover);
      await tester.pump();
      expect(opened?.game.title, 'Game 0');

      final g = await tester.startGesture(tester.getCenter(cover));
      await tester.pump(kLiftDelay + const Duration(milliseconds: 30));
      await g.moveBy(const Offset(0, -80));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(log, ['lift Game 0', 'move', 'end']);
    });

    testWidgets('a quick sideways swipe scrolls the strip, it does not lift',
        (tester) async {
      final log = <String>[];
      final many = [for (var i = 0; i < 20; i++) item(i + 1, 'Game $i')];
      await pump(tester, many, log: log.add);
      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('ground-strip')), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      expect(find.byKey(const ValueKey('ground-1')), findsNothing,
          reason: 'the first cover scrolled out of view');
    });

    testWidgets('empty ground: no tray at all', (tester) async {
      await pump(tester, const []);
      expect(find.byKey(const Key('orchard-ground')), findsNothing);
      expect(find.byType(FruitImage), findsNothing);
    });

    test('each card starts in the pile and deals later than the one before', () {
      for (var i = 0; i < 8; i++) {
        expect(dealT(0, i), 0);
        expect(dealT(1, i), 1);
        if (i > 0) expect(dealT(0.3, i), lessThanOrEqualTo(dealT(0.3, i - 1)));
      }
      // Hidden cards (under the pile) fade in on their way out.
      expect(dealPose(5, 0, 0).opacity, 0);
      expect(dealPose(5, 1, 0).opacity, 1);
      expect(dealPose(1, 0, 0).opacity, 1);
      // The pile's cards are smaller and turned; the strip's are upright.
      expect(dealPose(0, 0, 0).angle, isNot(0));
      expect(dealPose(0, 1, 0).angle, 0);
      expect(dealPose(0, 0, 0).rect.width, lessThan(dealPose(0, 1, 0).rect.width));
    });
  });
}
