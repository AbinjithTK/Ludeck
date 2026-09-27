// The ground tray, fruit looks and the living meadow: the pure parts pinned
// as arithmetic, the tray driven as a widget.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
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
                height: 66,
                child: GroundTray(
                  items: items,
                  addButton: const SizedBox(key: Key('add'), width: 56, height: 56),
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
      expect(find.text('5 on the ground'), findsOneWidget);
      expect(find.byKey(const Key('ground-strip')), findsNothing);
      final closedAdd = tester.getRect(find.byKey(const Key('add')));

      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ground-strip')), findsOneWidget);
      final openAdd = tester.getRect(find.byKey(const Key('add')));
      expect(openAdd.left, greaterThan(closedAdd.left),
          reason: 'the add button rides the tray open to the right');
      // Open, the tray (and its end cap) reaches the right edge: 1pt border
      // and 4pt inset inside a 412pt box.
      expect(openAdd.right, moreOrLessEquals(412 - 5, epsilon: 1));

      await tester.tap(find.byKey(const Key('orchard-ground')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ground-strip')), findsNothing);
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

    testWidgets('empty ground: only the add button', (tester) async {
      await pump(tester, const []);
      expect(find.byKey(const Key('orchard-ground')), findsNothing);
      expect(find.byKey(const Key('add')), findsOneWidget);
    });
  });
}
