// The home screen's tree must not collide with its floating chrome.
//
// This exists because it already shipped broken. On a real device the first row
// sat under the headline and the status-bar clock: the content computed its own
// top inset and budgeted for ONE line of display type while the header renders
// two (headline over subline). It was invisible on a 1600x900 desktop window,
// where width was the binding constraint, and obvious on a phone.
//
// RETARGETED IN STAGE 2. The assertions used to measure a scrolling list of
// branch rows (`Key('tree-scroll')`, its padding, its scroll position). The home
// screen now renders `ProceduralTreeView`, which is a single fixed canvas with no
// viewport, no rows and no scroll -- so those handles no longer exist. Every
// invariant they protected still does, and is restated here against covers on the
// tree. Two changed shape honestly:
//
//   * "the last row clears the add control" is now measured on the lowest COVER
//     rather than on a padding value, which is a stronger check: it measures what
//     is painted instead of what was budgeted.
//   * "the scrim never swallows a scroll gesture" became "the scrim never
//     swallows a TAP", because there is no scroll to swallow. The underlying risk
//     is unchanged -- a hit-testable scrim makes the bottom band of the screen
//     dead to touch.
//
// The test measures GEOMETRY rather than re-deriving the arithmetic, which is the
// whole point. A test that recomputed the same sum would have agreed with the bug.
//
// Every database call goes through `tester.runAsync`. testWidgets runs its body
// in a FakeAsync zone and sqflite does real file I/O that never completes under
// fake time, so mounting outside runAsync holds the database lock and the run
// hangs instead of failing. See docs/CONSTRAINTS.md and check.ps1 rule 8.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/main.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/share_intake.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/map/game_node.dart';
import 'package:ludeck/ui/shell/add_menu.dart';
import 'package:ludeck/ui/tokens.dart';
import 'package:ludeck/ui/roadmap/roadmap_view.dart';

void main() {
  late Repository repo;

  setUp(() async {
    repo = await Repository.openInMemory();
    // openInMemory deliberately does not seed, and an empty collection hangs no
    // covers, so there would be nothing to collide with the header.
    await repo.seedIfEmpty();
  });

  tearDown(() async => repo.close());

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(412, 915), double textScale = 1.0}) async {
    // A phone-shaped surface. The bug was invisible at desktop proportions,
    // where width bound the layout and there was height to spare.
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

    // Wait for the FIRST READ to land, rather than guessing a delay.
    //
    // A fixed 20ms was enough when this file ran alone and too short under the
    // full suite's concurrency: the store's items were still null, the screen
    // rendered its deliberate blank branch, and every `getRect` below failed on a
    // finder that matched nothing. The symptom looked like a layout bug and was a
    // timing one. Polling for the thing the test actually needs is both faster in
    // the common case and immune to load.
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      if (find.byType(GameNode).evaluate().isNotEmpty) break;
    }
    expect(
      find.byType(GameNode),
      findsWidgets,
      reason: 'the collection never loaded, so nothing below can be measured',
    );
  }

  /// Every cover currently on the tree.
  List<Rect> covers(WidgetTester tester) => [
        for (final e in find.byType(GameNode).evaluate())
          tester.getRect(find.byElementPredicate((x) => x == e)),
      ];

  testWidgets('the tree canvas starts below the header', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final tree = tester.getRect(find.byType(RoadmapView));

    // The canvas must begin at or below the header's painted bottom. This is
    // structural now -- they are siblings in a Column -- and the assertion exists
    // so a future change back to an overlay has to face it.
    expect(
      tree.top,
      greaterThanOrEqualTo(header.bottom),
      reason: 'the tree canvas (${tree.top}) starts above the header bottom '
          '(${header.bottom}), so covers will render under the headline',
    );
  });

  testWidgets('the header survives a wrapped headline at large text scale',
      (tester) async {
    // The original bug was a top inset that assumed a single line of display
    // type. At 2x text scale the headline certainly wraps, so if anything still
    // depends on a one-line assumption this is where it shows.
    await pump(tester, textScale: 2.0);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final tree = tester.getRect(find.byType(RoadmapView));

    expect(tree.top, greaterThanOrEqualTo(header.bottom));
  });

  testWidgets('no cover overlaps the header', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final all = covers(tester);
    expect(all, isNotEmpty);

    for (final rect in all) {
      expect(
        rect.top,
        greaterThanOrEqualTo(header.bottom),
        reason: 'a cover at $rect is painted over the header '
            '(bottom ${header.bottom})',
      );
    }
  });

  testWidgets('the topmost cover sits within the visible viewport', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    // The roadmap SCROLLS: lower nodes deliberately sit below the fold, so the
    // tree-era "lowest cover clears the add control" no longer holds and would
    // be a false premise on a scroll view. What must still be true is that the
    // FIRST node lands in the visible band -- below the header, above the
    // bottom of the screen -- so the collection is not empty-looking on open.
    final covers = find.byType(GameNode);
    final first = tester.getRect(covers.first);

    expect(
      first.top,
      greaterThanOrEqualTo(header.bottom),
      reason: 'the first cover at y=${first.top} is under the header '
          '(bottom ${header.bottom})',
    );
    expect(
      first.top,
      lessThan(915),
      reason: 'the first cover at y=${first.top} starts below the fold, so the '
          'roadmap opens looking empty',
    );
  });

  testWidgets('the scrim covers the band the tree reserves', (tester) async {
    await pump(tester);

    final scrim = tester.getRect(find.byKey(const Key('scrim-bottom')));
    final tree = tester.getRect(find.byType(RoadmapView));
    final addMenu = tester.getRect(find.byType(AddMenu));

    // The scrim must reach at least as high as the add control it softens, and
    // must sit flush with the bottom of the content area -- a scrim that stops
    // short leaves a strip where a cover is visible half-behind the button.
    expect(scrim.top, lessThanOrEqualTo(addMenu.top));
    expect(scrim.bottom, moreOrLessEquals(tree.bottom, epsilon: 0.5));
  });

  testWidgets('no cover is hidden behind another, with the real chrome present',
      (tester) async {
    // THE measurement that reflects what ships. `procedural_tree_view_test.dart`
    // takes the same reading with the tree pumped alone and sees about 10%
    // overlap; here the header and the navigation pill are both in the layout, so
    // the tree gets the canvas it actually gets on a phone. A device capture
    // showed two covers substantially stacked while the tree-alone measurement
    // stayed green, and the difference between those two harnesses is the whole
    // reason this test exists in this file rather than that one.
    await pump(tester, size: const Size(412, 915));

    final rects = covers(tester);
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

    // 0.18, a ratchet just above the 10% actually measured here -- not the 0.34 I
    // first guessed at. The guess mattered: I read a device capture as "two covers
    // substantially stacked", built three separate instruments to reproduce it, and
    // all three said about 10%. Re-measuring the capture by hand agreed with them:
    // the worst pair overlaps by roughly a fifth of a card's WIDTH, which is a
    // tenth of its area. The arithmetic was right and the eye was wrong, so the
    // number here is now pinned to what is real rather than to what a screenshot
    // looked like.
    expect(worst, lessThan(0.18),
        reason: 'worst painted overlap ${(worst * 100).toStringAsFixed(0)}% '
            'with the shell present -- a cover you cannot read is the same as '
            'no cover');
  });

  testWidgets('the header text is left aligned, not centred', (tester) async {
    await pump(tester);

    // Measure the SUBLINE, and measure text rather than the container. Two
    // reasons, both learned by probing:
    //
    // The header column sits in an Expanded, so its own rect spans the full width
    // whatever its crossAxisAlignment is -- only its children move inside it. A
    // version of this test that measured the column was silently inert.
    //
    // And the HEADLINE is no good either: at flutter_test's default font every
    // glyph is a full em square, so "8 on the tree." already fills the available
    // width and centring cannot move it. The subline is short enough to move,
    // which is what makes this assertion able to fail.
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

  testWidgets('a cover tap opens the status sheet', (tester) async {
    // The roadmap scrolls, so the lowest node can sit off-screen and is not a
    // valid tap target here. The risk this guards is unchanged: a node must be
    // tappable and open the status sheet, and nothing (scrim, scroll view) may
    // eat the pointer. Proven on the first node, which is always in view.
    await pump(tester, size: const Size(412, 915));

    final scrim = tester.getRect(find.byKey(const Key('scrim-bottom')));
    expect(scrim.height, greaterThan(0));

    await tester.tap(find.byType(GameNode).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: 'tapping a cover opened nothing, so something is eating pointer '
          'events on the roadmap',
    );
  });
}
