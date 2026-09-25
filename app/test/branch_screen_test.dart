// The branches screen: "organize" in the Gaming criterion.
//
// The assertions worth having here are not that the buttons exist. They are:
// a new branch lands at the END of an order the user arranged; reorder has a path
// that is not drag and drop; a delete says what happens to the games BEFORE the
// button; and the games really do survive it.
//
// Every database call goes through `tester.runAsync`. testWidgets runs its body
// in a FakeAsync zone and sqflite does real file I/O that never completes under
// fake time, so mounting outside runAsync holds the database lock and the run
// hangs instead of failing. See docs/CONSTRAINTS.md and check.ps1 rule 8.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/branches/branch_screen.dart';

void main() {
  late Repository repo;
  late LudeckStore store;

  setUp(() async {
    repo = await Repository.openInMemory();
    await repo.seedIfEmpty();
  });

  tearDown(() async => repo.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      store = LudeckStore(repo);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<LudeckStore>.value(
          value: store,
          child: const BranchScreen(),
        ),
      ));
      await store.load();
    });
    await tester.pumpAndSettle();
  }

  /// Lets real async work finish, then settles.
  ///
  /// Two separate runAsync calls: pumping the fake clock inside runAsync does not
  /// give a real sqflite future time to resolve.
  ///
  /// POLLS rather than waiting a fixed 40 ms. The constant was enough when this
  /// file was written and turned flaky as the suite grew past four hundred tests:
  /// under full-suite concurrency a real database write can take longer than any
  /// constant someone picked, while passing instantly in isolation. The signature
  /// was a DIFFERENT test in this file failing on each run, which is what says
  /// timing rather than behaviour -- a real bug fails the same test every time.
  Future<void> settle(WidgetTester tester, {Finder? until}) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      if (until == null) {
        // No predicate to wait on. Still a constant, but eight rounds of 20 ms
        // instead of one 40 ms wait: four times the headroom, and the predicate
        // form is used wherever a real signal exists.
        if (attempt >= 7) return;
      } else if (until.evaluate().isNotEmpty) {
        return;
      }
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder, {Finder? until}) async {
    await tester.runAsync(() async => tester.tap(finder));
    await settle(tester, until: until);
  }

  /// Creates a branch through the real dialog rather than the store, so the
  /// dialog's own validation and trimming are exercised.
  Future<void> createViaUi(WidgetTester tester, String name) async {
    await tap(tester, find.byTooltip('New branch'));
    await tester.enterText(find.byType(TextFormField), name);
    // Waits for the new row to actually exist rather than for a fixed duration.
    // This is the write whose latency was being guessed at.
    await tap(tester, find.text('Save'), until: find.text(name.trim()));
  }

  Future<void> openMenu(WidgetTester tester, String branchName) async {
    await tap(tester, find.byTooltip('Options for $branchName'));
  }

  group('the empty state', () {
    testWidgets('explains what a branch is, not just that there are none',
        (tester) async {
      await pump(tester);

      // "No branches yet" plus a plus tells someone who has never met the
      // concept nothing about whether they want one.
      expect(find.text('No branches yet.'), findsOneWidget);
      expect(find.textContaining('A branch is your own grouping'),
          findsOneWidget);
      expect(find.text('Make one'), findsOneWidget);
    });
  });

  group('create', () {
    testWidgets('a created branch appears in the list', (tester) async {
      await pump(tester);
      await createViaUi(tester, 'Short evenings');

      expect(find.text('Short evenings'), findsOneWidget);
      expect(find.text('0 games'), findsOneWidget);
    });

    testWidgets('a blank name is refused in the dialog, not by the write',
        (tester) async {
      await pump(tester);
      await tap(tester, find.byTooltip('New branch'));
      await tester.enterText(find.byType(TextFormField), '   ');
      await tap(tester, find.text('Save'));

      // The dialog stays open with an error rather than closing and failing a
      // write the user then has to infer.
      expect(find.text('A branch needs a name.'), findsOneWidget);
      expect(store.branches, isEmpty);
    });

    testWidgets('a name is trimmed', (tester) async {
      await pump(tester);
      await createViaUi(tester, '  Short evenings  ');

      expect(store.branches.single.name, 'Short evenings');
    });

    testWidgets('a new branch lands at the END of a reordered list',
        (tester) async {
      await pump(tester);
      await createViaUi(tester, 'First');
      await createViaUi(tester, 'Second');

      // Reorder, which writes real 0..n-1 sort values.
      await tester.runAsync(() async {
        final ids = store.branches.map((b) => b.id).toList();
        await store.reorderBranches(ids.reversed.toList());
      });
      await tester.pumpAndSettle();
      expect(store.branches.map((b) => b.name), ['Second', 'First']);

      await createViaUi(tester, 'Third');

      // The repository defaults sortOrder to 0, so a naive create would put the
      // new branch at the FRONT of a list the user had just arranged.
      expect(store.branches.map((b) => b.name), ['Second', 'First', 'Third']);
    });
  });

  group('rename', () {
    testWidgets('renaming changes the row and keeps the games', (tester) async {
      await pump(tester);
      await createViaUi(tester, 'Shrot evenings');

      await tester.runAsync(() async {
        final id = store.items!.first.game.igdbId;
        await store.place(id, store.branches.single.id);
      });
      await tester.pumpAndSettle();
      expect(find.text('1 game'), findsOneWidget);

      await openMenu(tester, 'Shrot evenings');
      await tap(tester, find.text('Rename'));
      await tester.enterText(find.byType(TextFormField), 'Short evenings');
      await tap(tester, find.text('Save'));

      expect(find.text('Short evenings'), findsOneWidget);
      expect(find.text('Shrot evenings'), findsNothing);
      // A rename is not a move: the games stay where they were.
      expect(find.text('1 game'), findsOneWidget);
    });
  });

  group('reorder without dragging', () {
    testWidgets('Move up is offered on every row but the first',
        (tester) async {
      await pump(tester);
      await createViaUi(tester, 'First');
      await createViaUi(tester, 'Second');

      await openMenu(tester, 'First');
      // A disabled "Move up" on the first row is a control that exists to do
      // nothing.
      expect(find.text('Move up'), findsNothing);
      expect(find.text('Move down'), findsOneWidget);
      await tap(tester, find.text('Move down'));

      expect(store.branches.map((b) => b.name), ['Second', 'First']);
    });

    testWidgets('Move down is not offered on the last row', (tester) async {
      await pump(tester);
      await createViaUi(tester, 'First');
      await createViaUi(tester, 'Second');

      await openMenu(tester, 'Second');
      expect(find.text('Move down'), findsNothing);
      expect(find.text('Move up'), findsOneWidget);
      await tap(tester, find.text('Move up'));

      expect(store.branches.map((b) => b.name), ['Second', 'First']);
    });

    testWidgets('a single branch is offered no move at all', (tester) async {
      await pump(tester);
      await createViaUi(tester, 'Only one');

      await openMenu(tester, 'Only one');
      expect(find.text('Move up'), findsNothing);
      expect(find.text('Move down'), findsNothing);
      expect(find.text('Rename'), findsOneWidget);
    });
  });

  group('delete', () {
    testWidgets('the dialog states that the games are kept', (tester) async {
      await pump(tester);
      await createViaUi(tester, 'Short evenings');
      await tester.runAsync(() async {
        final ids = store.items!.take(2).map((i) => i.game.igdbId).toList();
        for (final id in ids) {
          await store.place(id, store.branches.single.id);
        }
      });
      await tester.pumpAndSettle();

      await openMenu(tester, 'Short evenings');
      await tap(tester, find.text('Delete'));

      // This sentence is the point of the dialog, not the button. A user who
      // suspects deleting a branch destroys their games will never delete one.
      expect(
        find.text('The 2 games on this branch are kept. They move to '
            '"Not on a branch".'),
        findsOneWidget,
      );
    });

    testWidgets('the dialog says something honest about an empty branch',
        (tester) async {
      await pump(tester);
      await createViaUi(tester, 'Someday maybe');

      await openMenu(tester, 'Someday maybe');
      await tap(tester, find.text('Delete'));

      // Promising that games are kept when there are none would be noise.
      expect(find.text('Nothing is on this branch, so nothing else changes.'),
          findsOneWidget);
    });

    testWidgets('one game reads "1 game", not "1 games"', (tester) async {
      await pump(tester);
      await createViaUi(tester, 'Short evenings');
      await tester.runAsync(() async {
        await store.place(
            store.items!.first.game.igdbId, store.branches.single.id);
      });
      await tester.pumpAndSettle();

      await openMenu(tester, 'Short evenings');
      await tap(tester, find.text('Delete'));

      expect(
        find.text('The 1 game on this branch is kept. It moves to '
            '"Not on a branch".'),
        findsOneWidget,
      );
    });

    testWidgets('Keep it cancels and changes nothing', (tester) async {
      await pump(tester);
      await createViaUi(tester, 'Short evenings');

      await openMenu(tester, 'Short evenings');
      await tap(tester, find.text('Delete'));
      await tap(tester, find.text('Keep it'));

      expect(store.branches, hasLength(1));
      expect(find.text('Short evenings'), findsOneWidget);
    });

    testWidgets('deleting removes the branch and keeps every game',
        (tester) async {
      await pump(tester);
      final before = store.items!.length;
      await createViaUi(tester, 'Short evenings');
      await tester.runAsync(() async {
        await store.place(
            store.items!.first.game.igdbId, store.branches.single.id);
      });
      await tester.pumpAndSettle();

      await openMenu(tester, 'Short evenings');
      await tap(tester, find.text('Delete'));
      // The dialog's own Delete button, which is the second one now on screen.
      await tap(tester, find.text('Delete').last);

      expect(store.branches, isEmpty);
      // A branch is a container. Emptying it does not destroy what was in it.
      expect(store.items!.length, before);
      expect(store.placements, isEmpty);
      expect(find.text('No branches yet.'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('a row announces its name, count and position', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await createViaUi(tester, 'First');
      await createViaUi(tester, 'Second');

      // "2 of 2" is the only way a screen-reader user can tell whether a move
      // actually landed.
      expect(find.bySemanticsLabel('Second, 0 games, 2 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel('First, 0 games, 1 of 2'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the drag handle is not announced', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await createViaUi(tester, 'First');

      // The menu already offers Move up and Move down, so announcing a drag
      // handle a screen-reader user cannot operate is noise.
      expect(find.bySemanticsLabel(RegExp('drag', caseSensitive: false)),
          findsNothing);
      handle.dispose();
    });
  });
}
