// Home-screen layout, REFRAMED for the orchard (2026-09-26: the orchard replaced
// the node-tree outline as home). Each intent the node-tree version protected is
// kept against the new premise:
//
//   old: content starts below the header / survives a wrapped headline
//   now: a tree's name sits top-left, inside the safe area, and a 2x text scale
//        lays out without overflow
//   old: the first game is on screen and a tap opens the status sheet
//   now: the tree's count is a real button; its shelf lists every game on the
//        tree and a shelf game opens the status sheet. (The Rive fruit is not
//        drawn headless -- no native library -- so the accessible route is the
//        one a test can drive, and it is also the screen-reader route.)
//   old: rows never overlap one another
//   now: the tree dots are one per tree plus the planting patch, and do not
//        overlap each other or the add control's column
//   old: header text is left aligned, not centred
//   now: the tree name is flush with the left margin
//   new: games on no tree appear as the ground pile, which opens the library
//
// Every database call goes through `tester.runAsync` (check.ps1 rule 8).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/main.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/share_intake.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/orchard/orchard_view.dart';
import 'package:ludeck/ui/tokens.dart';

void main() {
  late Repository repo;

  setUp(() async {
    repo = await Repository.openInMemory();
    await repo.seedIfEmpty();
  });

  tearDown(() async => repo.close());

  /// Plants [trees] trees and puts the first [perTree] seeded games on each.
  Future<void> plant(WidgetTester tester, int trees, int perTree) async {
    await tester.runAsync(() async {
      final items = await repo.load();
      var g = 0;
      for (var t = 0; t < trees; t++) {
        final id = await repo.createBranch('Tree ${t + 1}', sortOrder: t);
        for (var k = 0; k < perTree && g < items.length; k++, g++) {
          await repo.place(items[g].game.igdbId, id);
        }
      }
    });
  }

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(412, 915), double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: ChangeNotifierProvider<LudeckStore>(
            create: (_) => LudeckStore(repo)..load(),
            child: TreeScreen(
              intake: FakeShareIntake(null),
              catalog: FixtureCatalog(),
            ),
          ),
        ),
      ));
    });
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      if (find.byType(OrchardView).evaluate().isNotEmpty) break;
    }
    expect(find.byType(OrchardView), findsOneWidget,
        reason: 'the collection never loaded into the orchard');
  }

  testWidgets('with no trees, home is the planting patch', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('orchard-plant')), findsOneWidget);
    expect(find.bySemanticsLabel('Plant a new tree'), findsOneWidget);
  });

  testWidgets('games on no tree show as the ground pile, which opens the library',
      (tester) async {
    await pump(tester);
    final ground = find.byKey(const Key('orchard-ground'));
    expect(ground, findsOneWidget);
    await tester.tap(ground);
    await tester.pumpAndSettle();
    expect(find.byType(OrchardView), findsNothing,
        reason: 'the ground pile should take you to the library');
  });

  testWidgets('a tree name sits top-left inside the safe area, not centred',
      (tester) async {
    await plant(tester, 2, 3);
    await pump(tester);
    final name = tester.getRect(find.byKey(const Key('orchard-tree-name')).first);
    expect(name.left, moreOrLessEquals(Tokens.space.lg, epsilon: 0.5));
    expect(name.top, greaterThanOrEqualTo(0));
    expect(name.top, lessThan(915 * 0.2), reason: 'the name should lead the screen');
  });

  testWidgets('2x text scale lays out without overflow', (tester) async {
    await plant(tester, 1, 4);
    await pump(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('orchard-tree-name')), findsWidgets);
  });

  testWidgets('the count opens the shelf, and a shelf game opens its sheet',
      (tester) async {
    await plant(tester, 1, 4);
    await pump(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^4 games on Tree 1')));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget, reason: 'shelf did not open');

    await tester.tap(find.descendant(
        of: find.byType(GridView), matching: find.byType(GestureDetector)).first);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsWidgets,
        reason: 'a shelf game should open its status sheet');
  });

  testWidgets('one dot per tree plus the patch; dots never overlap',
      (tester) async {
    await plant(tester, 3, 2);
    await pump(tester);
    final dots = find.bySemanticsLabel(RegExp(r'^Go to (Tree \d|a new tree)$'));
    expect(dots, findsNWidgets(4));
    final rects = [for (final e in dots.evaluate()) tester.getRect(find.byElementPredicate((x) => x == e))];
    for (var a = 0; a < rects.length; a++) {
      for (var b = a + 1; b < rects.length; b++) {
        final o = rects[a].intersect(rects[b]);
        expect(o.width <= 0 || o.height <= 0, isTrue,
            reason: 'dots $a and $b overlap');
      }
    }
  });

  testWidgets('tapping a dot pages to that tree', (tester) async {
    await plant(tester, 2, 2);
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Go to Tree 2'));
    await tester.pumpAndSettle();
    final pv = tester.widget<PageView>(find.byType(PageView));
    expect(pv.controller!.page, closeTo(1, 0.01));
  });

  testWidgets('customise: a swatch and a prop save to the tree, live',
      (tester) async {
    await plant(tester, 1, 2);
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Customise Tree 1'));
    await tester.pumpAndSettle();
    expect(find.text('Wood'), findsOneWidget, reason: 'the sheet is open');

    await tester.tap(find.bySemanticsLabel('Frost blossom'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Birch wood'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('decor-lantern')));
    await tester.tap(find.byKey(const Key('decor-lantern')));
    await tester.pumpAndSettle();
    // The writes are real sqflite I/O: let them land.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => repo.treeStyles());
    final row = saved!.values.single;
    expect(row['blossom'], 'frost');
    expect(row['wood'], 'birch');
    expect(row['decor'], contains('lantern'));

    await tester.tap(find.byKey(const Key('customise-done')));
    await tester.pumpAndSettle();
    expect(find.text('Wood'), findsNothing);
  });

  testWidgets('customise sheet lays out at 2x text scale', (tester) async {
    await plant(tester, 1, 1);
    await pump(tester, textScale: 2.0);
    await tester.tap(find.bySemanticsLabel('Customise Tree 1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a planted tree is saved in a colour no other tree has',
      (tester) async {
    await plant(tester, 1, 1);
    await tester.runAsync(() => repo.setTreeStyle(1,
        blossom: 'blossom', wood: 'plum', decor: ''));
    await pump(tester);
    // Page to the patch and plant.
    await tester.tap(find.bySemanticsLabel('Go to a new tree'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orchard-plant')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Second');
    await tester.tap(find.text('Plant'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect((await tester.runAsync(() => repo.branches()))!, hasLength(2),
        reason: 'the tree was planted');
    final saved = (await tester.runAsync(() => repo.treeStyles()))!;
    expect(saved, hasLength(2));
    final blossoms = saved.values.map((r) => r['blossom']).toSet();
    expect(blossoms, hasLength(2), reason: 'the new tree differs from the first');
  });
}
