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
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/main.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/share_intake.dart';
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
          child: TreeScreen(
            repo: repo,
            intake: FakeShareIntake(null),
            catalog: FixtureCatalog(),
          ),
        ),
      ));
    });
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the list viewport starts below the header', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final list = tester.getRect(find.byKey(const Key('collection-list')));

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
    final list = tester.getRect(find.byKey(const Key('collection-list')));

    expect(list.top, greaterThanOrEqualTo(header.bottom));
  });

  testWidgets('no row overlaps the header at rest', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));

    // Every visible row title must be painted below the header. Measured per
    // row rather than trusting the padding, because a row could still intrude
    // through a negative margin or an unexpected transform.
    final titles = find.descendant(
      of: find.byKey(const Key('collection-list')),
      matching: find.byType(Text),
    );
    expect(titles, findsWidgets);

    for (var i = 0; i < titles.evaluate().length; i++) {
      final rect = tester.getRect(titles.at(i));
      // Rows scrolled out of view can report offscreen rects; only judge what
      // is actually on screen.
      if (rect.bottom < 0) continue;
      expect(
        rect.top,
        greaterThanOrEqualTo(header.bottom),
        reason: 'a row is painted over the header',
      );
    }
  });

  testWidgets('the last row clears the add control', (tester) async {
    await pump(tester);

    final list = tester.widget<ListView>(
        find.byKey(const Key('collection-list')));
    final padding = list.padding! as EdgeInsets;
    final addMenu = tester.getRect(find.byType(AddMenu));
    final viewport = tester.getRect(find.byKey(const Key('collection-list')));

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

    final list = tester.widget<ListView>(
        find.byKey(const Key('collection-list')));
    final padding = list.padding! as EdgeInsets;

    // Padding alone only fixes where the list comes to REST. The scrim is what
    // hides rows while the list is being dragged, so it must cover the same
    // band -- a scrim shorter than the inset leaves a strip where a row is
    // visible half-behind the control.
    final scrim = tester.getRect(find.byKey(const Key('scrim-bottom')));
    final viewport = tester.getRect(find.byKey(const Key('collection-list')));

    expect(scrim.height, moreOrLessEquals(padding.bottom, epsilon: 0.5));
    expect(scrim.bottom, moreOrLessEquals(viewport.bottom, epsilon: 0.5));
  });

  testWidgets('the header is left aligned, not centred', (tester) async {
    await pump(tester);

    final header = tester.getRect(find.byKey(const Key('screen-header')));
    final screen = tester.getRect(find.byType(Scaffold));

    // Regression guard. Making the header a Column child centred it, because a
    // Column centres on the cross axis and so shrink-wrapped the block to its
    // text width. The header is specified top-LEFT, and a centred headline over
    // a left-aligned list reads as a mistake.
    expect(header.left, moreOrLessEquals(Tokens.space.md, epsilon: 0.5));
    expect(
      header.width,
      moreOrLessEquals(screen.width - Tokens.space.md * 2, epsilon: 0.5),
      reason: 'the header shrink-wrapped instead of filling the width',
    );
  });

  testWidgets('the scrim never swallows a scroll gesture', (tester) async {
    // A deliberately short surface, so the seeded collection definitely
    // overflows. On a tall screen the rows can fit, the list is then not
    // scrollable at all, and a drag that moves nothing would prove nothing
    // about whether the scrim is passing pointers through.
    await pump(tester, size: const Size(412, 420));

    final scrollable = find.descendant(
      of: find.byKey(const Key('collection-list')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0),
        reason: 'the list does not overflow, so this test cannot prove '
            'anything about hit testing');

    final before = position.pixels;

    // Drag upward starting INSIDE the bottom band, which is where the scrim is
    // painted. If the scrim were hit-testable this would move nothing and the
    // bottom of the screen would be dead to touch.
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
