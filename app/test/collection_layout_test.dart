// The home screen's content layer must not collide with its floating chrome.
//
// This exists because it already shipped broken. On a real device the first row
// sat under the headline and the status-bar clock: the list computed its own top
// inset and budgeted for ONE line of display type while the header renders two
// (headline over subline). It was invisible on a 1600x900 desktop window, where
// width was the binding constraint, and obvious on a phone.
//
// The test measures GEOMETRY rather than re-deriving the arithmetic, which is
// the whole point. A test that recomputed the same sum would have agreed with
// the bug.
//
// Every database call goes through `tester.runAsync`. testWidgets runs its body
// in a FakeAsync zone and sqflite does real file I/O that never completes under
// fake time, so mounting outside runAsync holds the database lock and the run
// hangs instead of failing. See docs/CONSTRAINTS.md and check.ps1 rule 8.

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

void main() {
  late Repository repo;

  setUp(() async {
    repo = await Repository.openInMemory();
    // openInMemory deliberately does not seed, and an empty collection renders
    // no rows, so there would be nothing to collide with the header.
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
    // rendered its deliberate blank branch, and every `getRect` below failed on
    // a finder that matched nothing. The symptom looked like a layout bug and was
    // a timing one. Polling for the thing the test actually needs is both faster
    // in the common case and immune to load.
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      if (find.byKey(const Key('tree-scroll')).evaluate().isNotEmpty) break;
    }
    expect(
      find.byKey(const Key('tree-scroll')),
      findsOneWidget,
      reason: 'the collection never loaded, so nothing below can be measured',
    );
  }

  testWidgets('the list viewport starts below the header', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final list = tester.getRect(find.byKey(const Key('tree-scroll')));

    // The list's own viewport must begin at or below the header's painted
    // bottom. This is structural now -- they are siblings in a Column -- and the
    // assertion exists so a future change back to an overlay has to face it.
    expect(
      list.top,
      greaterThanOrEqualTo(header.bottom),
      reason: 'the list viewport (${list.top}) starts above the header bottom '
          '(${header.bottom}), so rows will render under the headline',
    );
  });

  testWidgets('the header survives a wrapped headline at large text scale',
      (tester) async {
    // The original bug was a top inset that assumed a single line of display
    // type. At 2x text scale the headline certainly wraps, so if anything still
    // depends on a one-line assumption this is where it shows.
    await pump(tester, textScale: 2.0);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final list = tester.getRect(find.byKey(const Key('tree-scroll')));

    expect(list.top, greaterThanOrEqualTo(header.bottom));
  });

  testWidgets('no row overlaps the header at rest', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final viewport = tester.getRect(find.byKey(const Key('tree-scroll')));

    // Every visible node title must be painted below the header. Measured per
    // node rather than trusting the padding, because one could still intrude
    // through a negative margin or an unexpected transform.
    final titles = find.descendant(
      of: find.byKey(const Key('tree-scroll')),
      matching: find.byType(Text),
    );
    expect(titles, findsWidgets);

    var judged = 0;
    for (var i = 0; i < titles.evaluate().length; i++) {
      final rect = tester.getRect(titles.at(i));
      // Only judge what is actually INSIDE the list's own viewport.
      //
      // The list is reversed now, and a reversed viewport keeps off-screen items
      // built in its cache extent ABOVE the visible area -- so a node the user
      // cannot see legitimately reports a rect overlapping the header, and the
      // old `rect.bottom < 0` guard was not enough to exclude it. Clipping to the
      // viewport keeps the assertion about what is on screen, which is what it
      // was always meant to check.
      if (rect.bottom <= viewport.top || rect.top >= viewport.bottom) continue;
      judged++;
      expect(
        rect.top,
        greaterThanOrEqualTo(header.bottom),
        reason: 'a node is painted over the header',
      );
    }
    expect(judged, greaterThan(0),
        reason: 'nothing was inside the viewport, so this proved nothing');
  });

  testWidgets('the last row clears the add control', (tester) async {
    await pump(tester);

    final list = tester.widget<SingleChildScrollView>(find.byKey(const Key('tree-scroll')));
    final padding = list.padding! as EdgeInsets;
    final addMenu = tester.getRect(find.byType(AddMenu));
    final viewport = tester.getRect(find.byKey(const Key('tree-scroll')));

    // The reserved bottom band must reach at least as high as the add control's
    // top, or the final row sits behind the button that covers it.
    expect(
      viewport.bottom - padding.bottom,
      lessThanOrEqualTo(addMenu.top),
      reason: 'the bottom inset (${padding.bottom}) does not clear the add '
          'control at y=${addMenu.top}',
    );
  });

  testWidgets('the scrim covers exactly the band the list pads for',
      (tester) async {
    await pump(tester);

    final list = tester.widget<SingleChildScrollView>(find.byKey(const Key('tree-scroll')));
    final padding = list.padding! as EdgeInsets;

    // Padding alone only fixes where the list comes to REST. The scrim is what
    // hides rows while the list is being dragged, so it must cover the same
    // band -- a scrim shorter than the inset leaves a strip where a row is
    // visible half-behind the control.
    final scrim = tester.getRect(find.byKey(const Key('scrim-bottom')));
    final viewport = tester.getRect(find.byKey(const Key('tree-scroll')));

    expect(scrim.height, moreOrLessEquals(padding.bottom, epsilon: 0.5));
    expect(scrim.bottom, moreOrLessEquals(viewport.bottom, epsilon: 0.5));
  });

  testWidgets('the header text is left aligned, not centred', (tester) async {
    await pump(tester);

    // Measure the SUBLINE, and measure text rather than the container. Two
    // reasons, both learned by probing:
    //
    // The header column sits in an Expanded, so its own rect spans the full
    // width whatever its crossAxisAlignment is -- only its children move inside
    // it. A version of this test that measured the column was silently inert.
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

  testWidgets('the scrim never swallows a scroll gesture', (tester) async {
    // Branches FIRST, so the tree actually overflows.
    //
    // The seeded fixture has no branches, so every game sits in the single soil
    // tray -- roughly 200pt tall, which fits a short surface. The viewport then
    // does not scroll at all and this test's own precondition fails, correctly
    // reporting that it cannot prove anything about hit testing. Real branch rows
    // are what make the content taller than the screen.
    await tester.runAsync(() async {
      for (var i = 0; i < 4; i++) {
        final id = await repo.createBranch('Branch $i', sortOrder: i);
        final games = await repo.load();
        if (i < games.length) await repo.place(games[i].game.igdbId, id);
      }
    });

    // A deliberately short surface, so the tree definitely overflows. On a tall
    // screen the rows can fit, the viewport is then not scrollable at all, and a
    // drag that moves nothing would prove nothing about the scrim.
    await pump(tester, size: const Size(412, 420));

    // The tree's OWN vertical scroller. Scoped by axis, because every branch limb
    // and the soil tray is a horizontal scroller too -- an unscoped Scrollable
    // finder now matches several and `state` throws "Too many elements".
    final scrollable = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0),
        reason: 'the list does not overflow, so this test cannot prove '
            'anything about hit testing');

    final before = position.pixels;

    // Drag UPWARD starting INSIDE the bottom band, which is where the scrim is
    // painted. If the scrim were hit-testable this would move nothing and the
    // bottom of the screen would be dead to touch.
    //
    // Upward again: the branching tree scrolls normally, unlike the reversed
    // roadmap it replaced, so the direction that advances the viewport is the
    // ordinary one. The reversal is exactly the kind of detail that made this
    // assertion look like a scrim bug twice.
    final scrim = tester.getRect(find.byKey(const Key('scrim-bottom')));
    await tester.dragFrom(scrim.center, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      isNot(equals(before)),
      reason: 'the list did not scroll, so the scrim ate the drag',
    );
  });
}
