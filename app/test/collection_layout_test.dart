// The home screen's tree must not collide with its floating chrome.
//
// This exists because it already shipped broken. On a real device the first row
// sat under the headline and the status-bar clock: the content computed its own
// top inset and budgeted for ONE line of display type while the header renders
// two (headline over subline). It was invisible on a 1600x900 desktop window,
// where width was the binding constraint, and obvious on a phone.
//
// RETARGETED for the NODE TREE (Abin's 2026-09-26 steer away from the painted
// canopy). The home now renders `NodeTreeView`: a scrolling indented outline of
// branch panels and game rows, not a fixed canvas. Every invariant the earlier
// versions protected still holds and is restated here against game ROWS:
//
//   * Games are rows in a `SliverList`, so they physically cannot overlap each
//     other -- but the "nothing hidden behind another" intent is kept as a rows-
//     do-not-collide check, which a list guarantees and a regression to overlap
//     layout would break.
//   * "content starts below the header" and "first game is in the viewport and
//     tappable -> opens the sheet" are unchanged in spirit: measured on the first
//     keyed game row, which is always in view.
//   * The scrim (`Key('scrim-bottom')`) still softens the bottom band; a scrim
//     that eats the pointer is still the risk the tap test guards.
//
// Game rows are found by their stable `ValueKey('game-node-<igdbId>')` rather
// than a private widget type, so the test does not couple to the view's internals.
//
// Every database call goes through `tester.runAsync`: testWidgets runs in a
// FakeAsync zone and sqflite does real file I/O that never completes under fake
// time, so mounting outside runAsync holds the lock and the run hangs. See
// docs/CONSTRAINTS.md and check.ps1 rule 8.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/main.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/share_intake.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/shell/add_menu.dart';
import 'package:ludeck/ui/tokens.dart';
import 'package:ludeck/ui/nodetree/node_tree_view.dart';
import 'package:ludeck/ui/roadmap/roadmap_view.dart';

void main() {
  late Repository repo;

  setUp(() async {
    repo = await Repository.openInMemory();
    await repo.seedIfEmpty();
  });

  tearDown(() async => repo.close());

  /// Every game row currently laid out, by its stable key.
  Finder gameRows() => find.byWidgetPredicate((w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('game-node-'));

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

    // Poll for the first read to land rather than guessing a delay (fragile
    // under full-suite concurrency).
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      if (gameRows().evaluate().isNotEmpty) break;
    }
    expect(
      gameRows(),
      findsWidgets,
      reason: 'the collection never loaded, so nothing below can be measured',
    );
  }

  /// Whichever home view is showing: the node tree by default, or the roadmap.
  final homeView = find.byWidgetPredicate(
      (w) => w is RoadmapView || w is NodeTreeView,
      description: 'the home tree view');

  /// The rects of every visible game row.
  List<Rect> rows(WidgetTester tester) => [
        for (final e in gameRows().evaluate())
          tester.getRect(find.byElementPredicate((x) => x == e)),
      ];

  testWidgets('the tree starts below the header', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final tree = tester.getRect(homeView);

    expect(
      tree.top,
      greaterThanOrEqualTo(header.bottom),
      reason: 'the tree (${tree.top}) starts above the header bottom '
          '(${header.bottom}), so rows will render under the headline',
    );
  });

  testWidgets('the header survives a wrapped headline at large text scale',
      (tester) async {
    await pump(tester, textScale: 2.0);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final tree = tester.getRect(homeView);

    expect(tree.top, greaterThanOrEqualTo(header.bottom));
  });

  testWidgets('no game row overlaps the header', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final all = rows(tester);
    expect(all, isNotEmpty);

    for (final rect in all) {
      // A row scrolled up under the header is clipped by the viewport, so only
      // the FIRST visible row's top matters for the "starts under the headline"
      // bug this guards. Rows fully above the header bottom are off-screen, not
      // painted over it.
      if (rect.bottom <= header.bottom) continue;
      expect(
        rect.top,
        greaterThanOrEqualTo(header.bottom - 0.5),
        reason: 'a row at $rect is painted over the header '
            '(bottom ${header.bottom})',
      );
      break; // first on-screen row is the binding one
    }
  });

  testWidgets('the topmost game row sits within the visible viewport',
      (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final first = tester.getRect(gameRows().first);

    expect(
      first.top,
      greaterThanOrEqualTo(header.bottom - 0.5),
      reason: 'the first row at y=${first.top} is under the header '
          '(bottom ${header.bottom})',
    );
    expect(
      first.top,
      lessThan(915),
      reason: 'the first row at y=${first.top} starts below the fold, so the '
          'tree opens looking empty',
    );
  });

  testWidgets('the scrim covers the band the tree reserves', (tester) async {
    await pump(tester);

    final scrim = tester.getRect(find.byKey(const Key('scrim-bottom')));
    final addMenu = tester.getRect(find.byType(AddMenu));

    // The scrim must reach at least as high as the add control it softens.
    expect(scrim.top, lessThanOrEqualTo(addMenu.top));
    expect(scrim.height, greaterThan(0));
  });

  testWidgets('game rows never overlap one another', (tester) async {
    await pump(tester, size: const Size(412, 915));

    final rects = rows(tester);
    expect(rects.length, greaterThan(4));

    var worst = 0.0;
    for (var a = 0; a < rects.length; a++) {
      for (var b = a + 1; b < rects.length; b++) {
        final o = rects[a].intersect(rects[b]);
        if (o.width <= 0 || o.height <= 0) continue;
        final smaller = math.min(
          rects[a].width * rects[a].height,
          rects[b].width * rects[b].height,
        );
        final fraction = (o.width * o.height) / smaller;
        if (fraction > worst) worst = fraction;
      }
    }

    // A SliverList lays rows out end to end, so any overlap at all is a
    // regression to a stacking layout. Tiny epsilon for sub-pixel rounding.
    expect(worst, lessThan(0.02),
        reason: 'game rows overlap by ${(worst * 100).toStringAsFixed(0)}% -- '
            'a list must lay them out without collision');
  });

  testWidgets('the header text is left aligned, not centred', (tester) async {
    await pump(tester);

    final texts = find.descendant(
      of: find.byKey(const Key('screen-header')),
      matching: find.byType(Text),
    );
    final subline = tester.getRect(texts.at(1));

    expect(
      subline.left,
      moreOrLessEquals(Tokens.space.md, epsilon: 0.5),
      reason: 'the header text is not flush with the left margin, so the block '
          'is centred',
    );
  });

  testWidgets('a game tap opens the status sheet', (tester) async {
    await pump(tester, size: const Size(412, 915));

    final scrim = tester.getRect(find.byKey(const Key('scrim-bottom')));
    expect(scrim.height, greaterThan(0));

    await tester.tap(gameRows().first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: 'tapping a game opened nothing, so something is eating pointer '
          'events on the tree',
    );
  });
}
