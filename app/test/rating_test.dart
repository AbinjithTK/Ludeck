// Rate on harvest.
//
// The rules under test are behavioural, not cosmetic, and each one is a thing a
// well-meaning edit would break:
//
//   - asked on the TRANSITION into finished, never on the finished state
//   - never asked twice, because skipping is an answer and not a deferral
//   - skip writes nothing at all, which is different from clearing
//   - nothing counts or badges what is unrated
//
// Every database call goes through `tester.runAsync`. testWidgets runs its body
// in a FakeAsync zone and sqflite does real file I/O that never completes under
// fake time, so mounting outside runAsync holds the database lock and the run
// hangs instead of failing. See docs/CONSTRAINTS.md and check.ps1 rule 8.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/main.dart';
import 'package:ludeck/services/catalog_service.dart';
import 'package:ludeck/services/share_intake.dart';
import 'package:ludeck/state/ludeck_store.dart';

void main() {
  group('the harvest trigger', () {
    late Repository repo;

    setUp(() async {
      repo = await Repository.openInMemory();
      await repo.seedIfEmpty();
    });

    tearDown(() async => repo.close());

    late LudeckStore store;

    Future<void> pump(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      // WIDE on purpose, not just tall. The home screen is now a branching tree,
      // and the seeded fixture has no branches -- so every game sits in the soil
      // tray, which scrolls HORIZONTALLY. On a 412pt-wide surface only the first
      // few cards are ever built, a finder matches nothing, and `tap` throws "Bad
      // state: No element", which reads as a broken rating flow and is a viewport.
      //
      // This test is about the harvest TRIGGER; collection_layout_test owns
      // geometry. So the surface is sized to hold the row rather than adding
      // scroll choreography to every case.
      tester.view.physicalSize = const Size(1400, 1200);
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        store = LudeckStore(repo);
        await tester.pumpWidget(MaterialApp(
          home: ChangeNotifierProvider<LudeckStore>.value(
            value: store,
            child: TreeScreen(
              intake: FakeShareIntake(null),
              catalog: FixtureCatalog(),
            ),
          ),
        ));
        await store.load();
      });
      await tester.pumpAndSettle();
    }

    /// Opens the status sheet on a game by TAPPING it.
    ///
    /// It used to long-press. The tree now uses press-and-hold to DRAG a game
    /// between branches, and an InkWell long-press inside a LongPressDraggable
    /// wins the gesture arena and stops the drag starting at all -- so the two
    /// cannot share the gesture. Moving between branches kept long-press and the
    /// status sheet moved to tap.
    Future<void> openStatusSheet(WidgetTester tester, String title) async {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    /// Text INSIDE the open sheet.
    ///
    /// Scoped deliberately: "Harvested" is both a status option in the sheet and
    /// a group heading in the list behind it, so an unscoped finder matches two
    /// widgets and `tap` refuses.
    Finder inSheet(String text) => find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(text),
        );

    /// Lets real async work finish, then settles the widget tree.
    ///
    /// Two separate `runAsync` calls matter here. Pumping the fake clock INSIDE
    /// runAsync does not give a real sqflite future time to resolve, so the
    /// continuation never runs and the sheet that should follow the write never
    /// appears. Tap in one, wait in the next, then settle.
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
    }

    /// Taps a control in the sheet and lets the resulting write finish.
    Future<void> tapInSheet(WidgetTester tester, String text) async {
      // The status sheet scrolls once a game is harvested, because it then
      // carries three sections. A control below the fold is found by the finder
      // but the tap misses it, which surfaces only as a warning -- so scroll it
      // into view rather than trusting the find.
      await tester.ensureVisible(inSheet(text));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(inSheet(text));
      });
      await settle(tester);
    }

    /// Taps a star in the rating sheet and lets the write finish.
    Future<void> tapStar(WidgetTester tester, int value) async {
      await tester.runAsync(() async {
        await tester.tap(find.bySemanticsLabel('Rate $value out of 5'));
      });
      await settle(tester);
    }

    TreeItem itemNamed(String title) =>
        store.items!.firstWhere((i) => i.game.title == title);

    testWidgets('finishing an unfinished game asks for a rating',
        (tester) async {
      await pump(tester);
      // Hollow Knight is seeded as playing, so selecting finished is a real
      // transition.
      expect(itemNamed('Hollow Knight').entry.progress, Progress.playing);

      await openStatusSheet(tester, 'Hollow Knight');
      await tapInSheet(tester, 'Harvested');

      expect(find.text('How was it? Optional.'), findsOneWidget);
    });

    testWidgets('a tapped rating is written through the store', (tester) async {
      await pump(tester);
      await openStatusSheet(tester, 'Hollow Knight');
      await tapInSheet(tester, 'Harvested');

      await tapStar(tester, 5);

      final after = itemNamed('Hollow Knight');
      expect(after.entry.rating, 5);
      expect(after.entry.progress, Progress.finished);
    });

    testWidgets('skipping writes no rating at all', (tester) async {
      await pump(tester);
      await openStatusSheet(tester, 'Hollow Knight');
      await tapInSheet(tester, 'Harvested');
      await tapInSheet(tester, 'Skip');

      final after = itemNamed('Hollow Knight');
      expect(after.entry.rating, isNull);
      // The harvest itself still happened. A skipped rating must not undo it.
      expect(after.entry.progress, Progress.finished);
    });

    testWidgets('re-selecting finished on a finished game asks nothing',
        (tester) async {
      await pump(tester);
      // Hades is seeded as finished already, so this is not a transition.
      expect(itemNamed('Hades').entry.progress, Progress.finished);

      await openStatusSheet(tester, 'Hades');
      await tapInSheet(tester, 'Harvested');

      // The harvest already happened. Asking again would make the sheet a nag.
      expect(find.text('How was it? Optional.'), findsNothing);
    });

    testWidgets('a game that was skipped keeps its harvest', (tester) async {
      await pump(tester);

      await openStatusSheet(tester, 'Hollow Knight');
      await tapInSheet(tester, 'Harvested');
      await tapInSheet(tester, 'Skip');

      // Rating it after a skip stays possible, but only when the user asks.
      final after = itemNamed('Hollow Knight');
      expect(after.entry.rating, isNull);
      expect(after.entry.progress, Progress.finished);
    });

    testWidgets('the rating row appears only for harvested games',
        (tester) async {
      await pump(tester);

      // Astro Bot is untouched, so there is nothing to have an opinion about.
      await openStatusSheet(tester, 'Astro Bot');
      expect(find.text('What did you think'), findsNothing);
    });

    testWidgets('a harvested game offers a user-initiated rating row',
        (tester) async {
      await pump(tester);

      await openStatusSheet(tester, 'Hades');
      // Without this, a skipped rating would be permanently unreachable and the
      // "rate" criterion would have no surface at all.
      expect(find.text('What did you think'), findsOneWidget);
      expect(find.text('Rate it'), findsOneWidget);
    });

    testWidgets('the user-initiated row writes a rating', (tester) async {
      await pump(tester);

      await openStatusSheet(tester, 'Hades');
      await tapInSheet(tester, 'Rate it');

      await tapStar(tester, 2);

      expect(itemNamed('Hades').entry.rating, 2);
    });

    testWidgets('nothing anywhere counts or badges unrated games',
        (tester) async {
      await pump(tester);

      // Hades is finished and unrated. The subline must not mention it, and no
      // badge may appear: an unrated count turns a skip into a debt.
      expect(itemNamed('Hades').entry.rating, isNull);
      expect(find.textContaining('unrated'), findsNothing);
      expect(find.textContaining('Unrated'), findsNothing);
      expect(find.textContaining('to rate'), findsNothing);
    });
  });
}
