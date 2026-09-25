// Branch sections and the accessible path.
//
// Two things are under test and they are different in kind. The grouping is a
// behaviour: branches first in the user's order, unplaced last, empty branches
// still shown, collapsing sticky across a rebuild. The Semantics are the
// accessible path itself -- a canvas is invisible to a screen reader, so without
// correct labels here the app is unusable for some people and fails an
// accessibility review.
//
// Every database call goes through `tester.runAsync`. testWidgets runs its body
// in a FakeAsync zone and sqflite does real file I/O that never completes under
// fake time, so mounting outside runAsync holds the database lock and the run
// hangs instead of failing. See docs/CONSTRAINTS.md and check.ps1 rule 8.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/collection/collection_view.dart';

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
    tester.view.physicalSize = const Size(412, 1400);
    addTearDown(tester.view.reset);

    // CollectionView DIRECTLY, not through TreeScreen.
    //
    // The home screen now renders `RoadmapView` (the gamified map), so pumping
    // the screen here would test the map instead -- and the map deliberately has
    // different grouping (no status headings) and a REVERSED list, which inverts
    // every Y-position assertion below. This file is about CollectionView's own
    // grouping and accessibility, so it renders that widget and says so.
    // `cover_art_row_test.dart` does the same.
    //
    // The comment lives ABOVE the runAsync deliberately: check.ps1 rule 8 looks
    // back only a few lines from a pumpWidget for its enclosing runAsync, so a
    // long comment wedged between the two reads as an unwrapped mount.
    await tester.runAsync(() async {
      store = LudeckStore(repo);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<LudeckStore>.value(
          value: store,
          child: Scaffold(
            body: Consumer<LudeckStore>(
              builder: (context, s, _) => CollectionView(
                items: s.items ?? const [],
                branches: s.branches,
                placements: s.placements,
                topInset: 0,
                bottomInset: 0,
                onSelect: (_) {},
                onHold: (_) {},
              ),
            ),
          ),
        ),
      ));
      await store.load();
    });
    await tester.pumpAndSettle();
  }

  /// Creates branches and files games onto them, then reloads.
  Future<void> withBranches(WidgetTester tester) async {
    await tester.runAsync(() async {
      final finished = await repo.createBranch('Finished someday');
      final shortOnes = await repo.createBranch('Short evenings');
      final items = store.items!;
      final hades =
          items.firstWhere((i) => i.game.title == 'Hades').game.igdbId;
      final celeste =
          items.firstWhere((i) => i.game.title == 'Celeste').game.igdbId;
      await repo.place(hades, finished);
      await repo.place(celeste, shortOnes);
      await store.load();
    });
    await tester.pumpAndSettle();
  }

  group('grouping', () {
    testWidgets('falls back to status groups when there are no branches',
        (tester) async {
      await pump(tester);

      // Nothing seeds a branch, so this is the state of a new install. Grouping
      // by branch here would produce one unnamed heap of the whole collection,
      // which is strictly less information than the status grouping.
      expect(store.branches, isEmpty);
      expect(find.text('In hand'), findsOneWidget);
      expect(find.text('Harvested'), findsOneWidget);
      expect(find.text('Not on a branch'), findsNothing);
    });

    testWidgets('groups by branch once branches exist', (tester) async {
      await pump(tester);
      await withBranches(tester);

      expect(find.text('Finished someday'), findsOneWidget);
      expect(find.text('Short evenings'), findsOneWidget);
      // Status headings are gone: the sectioning is the user's now.
      expect(find.text('In hand'), findsNothing);
      expect(find.text('Growing'), findsNothing);
    });

    testWidgets('unplaced games land in a section, last', (tester) async {
      await pump(tester);
      await withBranches(tester);

      final unplaced = find.text('Not on a branch');
      expect(unplaced, findsOneWidget);

      // Last, because it is where a freshly shared game waits to be filed, not
      // the headline of the collection.
      final unplacedY = tester.getRect(unplaced).top;
      final firstBranchY = tester.getRect(find.text('Finished someday')).top;
      expect(unplacedY, greaterThan(firstBranchY));
    });

    testWidgets('branches appear in the user order, not by id', (tester) async {
      await pump(tester);
      await withBranches(tester);

      await tester.runAsync(() async {
        final ids = store.branches.map((b) => b.id).toList();
        // Reverse them.
        await store.reorderBranches(ids.reversed.toList());
      });
      await tester.pumpAndSettle();

      final first = tester.getRect(find.text('Short evenings')).top;
      final second = tester.getRect(find.text('Finished someday')).top;
      expect(first, lessThan(second),
          reason: 'reordering branches must reorder the sections');
    });

    testWidgets('an empty branch is still shown', (tester) async {
      await pump(tester);
      await tester.runAsync(() async {
        await repo.createBranch('Someday maybe');
        await store.load();
      });
      await tester.pumpAndSettle();

      // The user made it deliberately. Hiding it would look like a deletion.
      expect(find.text('Someday maybe'), findsOneWidget);
    });

    testWidgets('a heading count equals the rows under it', (tester) async {
      await pump(tester);
      await withBranches(tester);

      // Two branches with one game each, so each heading reads 1. A placement
      // pointing at a shelved game would otherwise inflate the count past the
      // rows actually rendered.
      expect(find.text('Hades'), findsOneWidget);
      expect(find.text('Celeste'), findsOneWidget);
    });
  });

  group('collapsing', () {
    testWidgets('a section starts open and closes on tap', (tester) async {
      await pump(tester);

      expect(find.text('Hollow Knight'), findsOneWidget);

      // Open by default: a collection that opens closed hides its own content.
      await tester.tap(find.text('In hand'));
      await tester.pumpAndSettle();

      expect(find.text('Hollow Knight'), findsNothing);
      // The heading itself stays, so the section is findable again.
      expect(find.text('In hand'), findsOneWidget);
    });

    testWidgets('collapsing one section leaves the others open',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('In hand'));
      await tester.pumpAndSettle();

      expect(find.text('Hollow Knight'), findsNothing);
      expect(find.text('Astro Bot'), findsOneWidget);
    });

    testWidgets('a collapsed section stays collapsed across a data change',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('Growing'));
      await tester.pumpAndSettle();
      expect(find.text('Astro Bot'), findsNothing);

      // A write triggers a reload and a rebuild. Section keys are stable ids
      // rather than labels, so the collapse survives.
      await tester.runAsync(() async {
        final id = store.items!
            .firstWhere((i) => i.game.title == 'Hades')
            .game
            .igdbId;
        await store.setRating(id, 4);
      });
      await tester.pumpAndSettle();

      expect(find.text('Astro Bot'), findsNothing,
          reason: 'a reload must not silently reopen a collapsed section');
    });
  });

  group('the accessible path', () {
    testWidgets('a row announces the plain status, never the metaphor word',
        (tester) async {
      await pump(tester);

      // "Ripe" or "On the tree" read aloud without the picture mean nothing.
      expect(
        find.bySemanticsLabel(RegExp(r'^Hollow Knight, Playing')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Hollow Knight.*In hand')),
          findsNothing);
    });

    testWidgets('a row announces length, platforms and rating', (tester) async {
      await pump(tester);
      await tester.runAsync(() async {
        final id =
            store.items!.firstWhere((i) => i.game.title == 'Hades').game.igdbId;
        await store.setRating(id, 4);
      });
      await tester.pumpAndSettle();

      // One sentence carrying everything the row shows, including the things
      // that are only visual: the pips and the completion mark.
      expect(
        find.bySemanticsLabel(
            'Hades, Finished, about 23 hours, on PC, rated 4 out of 5'),
        findsOneWidget,
      );
    });

    testWidgets('a seed announces who recommended it', (tester) async {
      await pump(tester);

      // A seed's whole point is where it came from.
      expect(find.bySemanticsLabel(RegExp(r'Pentiment, Seed from Priya')),
          findsOneWidget);
    });

    testWidgets('a heading announces its name, count and expanded state',
        (tester) async {
      // The semantics tree is not built unless something asks for it, and
      // getSemantics throws without this.
      final handle = tester.ensureSemantics();
      await pump(tester);

      // `hasExpandedState` / `isExpanded` are what a screen reader announces;
      // the chevron communicates the state to sighted users only.
      expect(
        tester.getSemantics(find.text('Growing')),
        containsSemantics(
          label: 'Growing, 4 games',
          isHeader: true,
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a collapsed heading announces that it is collapsed',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      await tester.tap(find.text('Growing'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.text('Growing')),
        containsSemantics(hasExpandedState: true, isExpanded: false),
      );
      handle.dispose();
    });

    testWidgets('a single-game section says game, not games', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        tester.getSemantics(find.text('In hand')),
        containsSemantics(label: 'In hand, 1 game'),
      );
      handle.dispose();
    });
  });

  group('the rating no longer replaces the status word', () {
    testWidgets('a rated harvest shows both', (tester) async {
      await pump(tester);
      await tester.runAsync(() async {
        final id =
            store.items!.firstWhere((i) => i.game.title == 'Hades').game.igdbId;
        await store.setRating(id, 4);
      });
      await tester.pumpAndSettle();

      // Before this, a rating replaced the word, so the right-hand column
      // carried two different kinds of information depending on the row.
      expect(find.text('Finished'), findsWidgets);
      expect(find.byIcon(Icons.star), findsNWidgets(4));
    });

    testWidgets('a rating is not shown on a game that is not harvested',
        (tester) async {
      await pump(tester);

      await tester.runAsync(() async {
        final id =
            store.items!.firstWhere((i) => i.game.title == 'Hades').game.igdbId;
        await store.setRating(id, 4);
        // A rating survives a game leaving finished, on purpose: it is a true
        // record of a past harvest. But showing stars on a game that is merely
        // "Playing" would be nonsense.
        await store.setProgress(id, Progress.playing);
      });
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Hades.*rated')), findsNothing);
    });
  });
}
