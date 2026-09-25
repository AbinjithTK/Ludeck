// The roadmap view.
//
// A pure widget test -- RoadmapView takes plain lists, so there is no database,
// no runAsync and no check.ps1 rule 8 concern. What is asserted is the GROUPING
// contract (which is where the tree logic actually lives) and the invariants that
// would otherwise regress silently: an unplaced game must not vanish, an empty
// branch must still appear, and no node may ever render a locked state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/map/roadmap_view.dart';

TreeItem _item(
  int id,
  String title, {
  Progress progress = Progress.untouched,
  Ownership ownership = Ownership.owned,
  int? rating,
  String? coverUrl,
}) =>
    TreeItem(
      game: Game(igdbId: id, title: title, coverUrl: coverUrl),
      entry: Entry(
        igdbId: id,
        ownership: ownership,
        progress: progress,
        rating: rating,
      ),
      copies: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<TreeItem> items,
  List<Branch> branches = const [],
  Map<int, List<int>> placements = const {},
  void Function(TreeItem)? onSelect,
  void Function(TreeItem)? onHold,
}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RoadmapView(
        items: items,
        branches: branches,
        placements: placements,
        topInset: 0,
        bottomInset: 0,
        onSelect: onSelect ?? (_) {},
        onHold: onHold ?? (_) {},
      ),
    ),
  ));
}

void main() {
  group('grouping follows the tree, not a second model', () {
    testWidgets('no branches yet renders ONE continuous road', (tester) async {
      // A new install has no branches. Grouping by branch would produce a single
      // unnamed heap, so the view shows one unlabelled road instead -- the same
      // call CollectionView makes when it falls back to status grouping.
      await _pump(tester, items: [
        _item(1, 'Hades'),
        _item(2, 'Celeste'),
        _item(3, 'Tunic'),
      ]);

      expect(find.byKey(const Key('roadmap-list')), findsOneWidget);
      // No waypoint sign, because there is no branch to name.
      expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
      // And nothing is filed as "not on a branch", which would be a lie here.
      expect(find.textContaining('NOT ON A BRANCH'), findsNothing);
    });

    testWidgets('branches become named stretches in the user order',
        (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hades'), _item(2, 'Celeste')],
        branches: const [
          (id: 10, name: 'First stretch', sortOrder: 0),
          (id: 11, name: 'Second stretch', sortOrder: 1),
        ],
        placements: const {
          10: [1],
          11: [2],
        },
      );

      expect(find.text('First stretch'), findsOneWidget);
      expect(find.text('Second stretch'), findsOneWidget);
    });

    testWidgets('an empty branch still gets a stretch', (tester) async {
      // The user made it deliberately. Dropping it from the map would look
      // exactly like it had been deleted.
      await _pump(
        tester,
        items: [_item(1, 'Hades')],
        branches: const [
          (id: 10, name: 'Has one', sortOrder: 0),
          (id: 11, name: 'Deliberately empty', sortOrder: 1),
        ],
        placements: const {
          10: [1],
        },
      );

      expect(find.text('Deliberately empty'), findsOneWidget);
      expect(find.text('No games on this branch yet'), findsOneWidget);
    });

    testWidgets('an unplaced game goes to the tray, never nowhere',
        (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hades'), _item(2, 'Unfiled game')],
        branches: const [(id: 10, name: 'A branch', sortOrder: 0)],
        placements: const {
          10: [1],
        },
      );

      expect(find.byKey(const Key('roadmap-staging')), findsOneWidget);
      expect(find.textContaining('NOT ON A BRANCH'), findsOneWidget);
    });

    testWidgets('no tray at all when everything is filed', (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hades')],
        branches: const [(id: 10, name: 'A branch', sortOrder: 0)],
        placements: const {
          10: [1],
        },
      );

      expect(find.byKey(const Key('roadmap-staging')), findsNothing);
    });

    testWidgets('a placement pointing at a missing game is skipped, not drawn',
        (tester) async {
      // A placement can name a shelved game. The count on the sign must equal
      // the nodes on the road, so the dangling id is dropped rather than drawn.
      await _pump(
        tester,
        items: [_item(1, 'Hades')],
        branches: const [(id: 10, name: 'Branch', sortOrder: 0)],
        placements: const {
          10: [1, 999],
        },
      );

      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('1'), findsOneWidget,
          reason: 'the sign must count the node actually drawn, not the '
              'placement rows');
    });
  });

  group('the road climbs', () {
    testWidgets('the list is reversed, so the path starts at the bottom',
        (tester) async {
      await _pump(tester, items: [_item(1, 'Hades'), _item(2, 'Celeste')]);

      final list = tester.widget<ListView>(find.byKey(const Key('roadmap-list')));
      expect(list.reverse, isTrue,
          reason: 'a roadmap that starts at the top is a list, not a road');
    });
  });

  group('no locked state exists', () {
    // docs/DECISIONS.md forbids marking what the user has not done, and a
    // Duolingo path is normally built on locked future levels. These assert the
    // shape is not reachable -- a padlock or a "locked"/"complete N first"
    // string appearing here would be the regression.
    testWidgets('no padlock is ever drawn', (tester) async {
      await _pump(tester, items: [
        _item(1, 'Unstarted', progress: Progress.untouched),
        _item(2, 'Playing', progress: Progress.playing),
        _item(3, 'Done', progress: Progress.finished, rating: 4),
      ]);

      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.textContaining('Locked'), findsNothing);
      expect(find.textContaining('locked'), findsNothing);
    });

    testWidgets('a harvested game is marked, an unharvested one is not nagged',
        (tester) async {
      await _pump(tester, items: [
        _item(1, 'Done', progress: Progress.finished),
        _item(2, 'Not done', progress: Progress.untouched),
      ]);

      // Exactly one check mark: the harvested one. Completion is rewarded and
      // incompletion carries no counterpart mark.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('callbacks keep the TreeScene contract', () {
    testWidgets('tapping a node selects it', (tester) async {
      TreeItem? selected;
      await _pump(
        tester,
        items: [_item(1, 'Hades')],
        onSelect: (i) => selected = i,
      );

      await tester.tap(find.byType(InkWell).first);
      expect(selected?.game.title, 'Hades');
    });

    testWidgets('long-pressing a node holds it', (tester) async {
      TreeItem? held;
      await _pump(
        tester,
        items: [_item(1, 'Hades')],
        onHold: (i) => held = i,
      );

      await tester.longPress(find.byType(InkWell).first);
      expect(held?.game.title, 'Hades');
    });
  });

  group('the empty collection', () {
    testWidgets('names the action rather than the absence', (tester) async {
      await _pump(tester, items: const []);

      expect(find.text('The road starts with one game.'), findsOneWidget);
      // No guilt, no count of what is missing -- DECISIONS.md forbids both.
      expect(find.textContaining('0'), findsNothing);
      expect(find.byKey(const Key('roadmap-list')), findsNothing);
    });
  });

  group('a node with no cover still reads', () {
    testWidgets('renders the placeholder rather than an empty dark card',
        (tester) async {
      // Stage 1 found a no-glow, no-image node is an invisible dark disc. A game
      // with no cover art is exactly that case on the map.
      await _pump(tester, items: [_item(1, 'No cover game')]);

      expect(find.byIcon(Icons.videogame_asset_outlined), findsOneWidget);
    });

    testWidgets('renders the image when a cover exists', (tester) async {
      await _pump(tester, items: [
        _item(1, 'Has cover', coverUrl: 'https://example.com/a.png'),
      ]);

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.videogame_asset_outlined), findsNothing);
    });
  });
}
