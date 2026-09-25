// The branching tree.
//
// This file replaces roadmap_view_test.dart and roadmap_arrival_test.dart: the
// roadmap layout was superseded, so its tests were ported rather than deleted --
// every invariant they protected still matters here (grouping follows the tree,
// an unplaced game is never dropped, an empty branch still shows, no locked
// state is reachable, the first build does not animate).
//
// The NEW contracts are the ones worth the most attention:
//   - a branch's name is never PAINTED but is always ANNOUNCED
//   - a long-press drag from one branch to another reports a move, once
//   - a drop onto the game's own branch is refused

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/map/branching_tree_view.dart';

TreeItem _item(
  int id,
  String title, {
  Progress progress = Progress.untouched,
  Ownership ownership = Ownership.owned,
  String? coverUrl,
}) =>
    TreeItem(
      game: Game(igdbId: id, title: title, coverUrl: coverUrl),
      entry: Entry(igdbId: id, ownership: ownership, progress: progress),
      copies: const [],
    );

const _branchA = (id: 10, name: 'Metroidvanias', sortOrder: 0);
const _branchB = (id: 11, name: 'Short evenings', sortOrder: 1);

class _Harness extends StatefulWidget {
  const _Harness({
    required this.items,
    this.branches = const [],
    this.placements = const {},
    this.onMove,
  });

  final List<TreeItem> items;
  final List<Branch> branches;
  final Map<int, List<int>> placements;
  final void Function(GameDrag, int?)? onMove;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<TreeItem> _items = widget.items;

  void setItems(List<TreeItem> items) => setState(() => _items = items);

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: BranchingTreeView(
            items: _items,
            branches: widget.branches,
            placements: widget.placements,
            onMove: widget.onMove,
            topInset: 0,
            bottomInset: 0,
            onSelect: (_) {},
            onHold: (_) {},
          ),
        ),
      );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<TreeItem> items,
  List<Branch> branches = const [],
  Map<int, List<int>> placements = const {},
  void Function(GameDrag, int?)? onMove,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_Harness(
    items: items,
    branches: branches,
    placements: placements,
    onMove: onMove,
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('branch names are visible and announced', () {
    // This REVERSES an earlier decision. Names were hidden for a seamless look,
    // with tap-to-reveal as the escape hatch. On a device that made every branch
    // anonymous until poked, and the reveal itself rendered "Finished someday" as
    // "Finis hed..." because it was squeezed into the 32pt trunk column. Visible
    // by default, on the limb where there is room, is the better trade.

    testWidgets('the branch name is painted on the limb', (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight')],
        branches: const [_branchA],
        placements: const {10: [1]},
      );

      expect(find.text('Metroidvanias'), findsOneWidget);
    });

    testWidgets('an empty branch is named too', (tester) async {
      // An unnamed empty branch is just a stray "nothing here" label with no way
      // to tell which branch it belongs to.
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight')],
        branches: const [_branchA, _branchB],
        placements: const {10: [1]},
      );

      expect(find.text('Short evenings'), findsOneWidget);
      expect(find.text('Nothing on it yet'), findsOneWidget);
    });

    testWidgets('the name is still announced on the game', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight')],
        branches: const [_branchA],
        placements: const {10: [1]},
      );

      expect(
        find.bySemanticsLabel(
            'Hollow Knight, on Metroidvanias, Not started'),
        findsOneWidget,
        reason: 'a screen reader should not have to infer the branch from '
            'layout position',
      );
      handle.dispose();
    });

    testWidgets('and on the junction, so the trunk is navigable', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight')],
        branches: const [_branchA],
        placements: const {10: [1]},
      );

      expect(find.bySemanticsLabel(RegExp('Metroidvanias branch, 1 game')),
          findsOneWidget);
      handle.dispose();
    });
  });

  group('branches alternate sides, so it reads as a tree', () {
    testWidgets('two branches sit on opposite sides of the spine',
        (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight'), _item(2, 'Celeste')],
        branches: const [_branchA, _branchB],
        placements: const {10: [1], 11: [2]},
      );

      // The first branch's game sits right of centre, the second's left of it.
      final centre = tester.getSize(find.byType(BranchingTreeView)).width / 2;
      final first = tester.getCenter(find.text('Hollow Knight')).dx;
      final second = tester.getCenter(find.text('Celeste')).dx;

      expect(first, greaterThan(centre),
          reason: 'the first branch should run right of the trunk');
      expect(second, lessThan(centre),
          reason: 'the second should run left, or it is a list not a tree');
    });
  });

  group('drag and drop between branches', () {
    testWidgets('a long-press drag onto another branch reports the move',
        (tester) async {
      final moves = <(int, int?)>[];
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight'), _item(2, 'Celeste')],
        branches: const [_branchA, _branchB],
        placements: const {10: [1], 11: [2]},
        onMove: (drag, to) => moves.add((drag.item.game.igdbId, to)),
      );

      // Press and hold to pick up, then move onto the other branch and release.
      // 600ms comfortably clears Flutter's ~500ms long-press threshold.
      final start = tester.getCenter(find.text('Hollow Knight'));
      final end = tester.getCenter(find.text('Celeste'));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));

      // The pick-up must be observable before the move: if the long press never
      // won the gesture arena (the limbs scroll horizontally, so the scroll view
      // competes for the same pan) then no amount of moving would drop anything,
      // and the failure would look like a broken DragTarget instead.
      expect(find.byType(Opacity), findsWidgets,
          reason: 'childWhenDragging should be in the tree once picked up');

      // Several steps, not one jump: a DragTarget updates from drag-update
      // events, and a single moveTo can arrive without the intermediate enter.
      for (var i = 1; i <= 5; i++) {
        await gesture.moveTo(Offset(
          start.dx + (end.dx - start.dx) * i / 5,
          start.dy + (end.dy - start.dy) * i / 5,
        ));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(moves, hasLength(1), reason: 'one gesture is one move');
      expect(moves.single.$1, 1);
      expect(moves.single.$2, 11, reason: 'dropped onto the second branch');
    });

    testWidgets('a plain tap does not start a drag', (tester) async {
      final moves = <(int, int?)>[];
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight')],
        branches: const [_branchA, _branchB],
        placements: const {10: [1]},
        onMove: (drag, to) => moves.add((drag.item.game.igdbId, to)),
      );

      await tester.tap(find.text('Hollow Knight'));
      await tester.pumpAndSettle();

      expect(moves, isEmpty,
          reason: 'drag is press-and-hold; a tap must stay a tap or the limbs '
              'could not be scrolled');
    });
  });

  group('ported invariants that still hold', () {
    testWidgets('an unplaced game goes to the soil, never nowhere',
        (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight'), _item(2, 'Unfiled')],
        branches: const [_branchA],
        placements: const {10: [1]},
      );

      expect(find.byKey(const Key('soil-games')), findsOneWidget);
      expect(find.text('Unfiled'), findsOneWidget);
    });

    testWidgets('an empty branch still appears', (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight')],
        branches: const [_branchA, _branchB],
        placements: const {10: [1]},
      );

      expect(find.text('Nothing on it yet'), findsOneWidget);
    });

    testWidgets('a placement naming a missing game is skipped', (tester) async {
      await _pump(
        tester,
        items: [_item(1, 'Hollow Knight')],
        branches: const [_branchA],
        placements: const {10: [1, 999]},
      );

      // The junction count must equal the cards drawn, not the placement rows.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('no locked state is reachable', (tester) async {
      await _pump(
        tester,
        items: [
          _item(1, 'Unstarted'),
          _item(2, 'Done', progress: Progress.finished),
        ],
        branches: const [_branchA],
        placements: const {10: [1, 2]},
      );

      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.textContaining('Locked'), findsNothing);
      // Completion IS marked -- that direction is permitted.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('a cover-less game shows its initials, not a generic tile',
        (tester) async {
      await _pump(tester, items: [_item(1, 'Hollow Knight')]);

      // Initials rather than a repeated controller glyph: a row of identical
      // glyphs reads as a loading failure.
      expect(find.text('HK'), findsOneWidget);
    });

    testWidgets('the empty collection names the action, not the absence',
        (tester) async {
      await _pump(tester, items: const []);

      expect(find.text('The tree starts with one game.'), findsOneWidget);
      expect(find.byKey(const Key('tree-scroll')), findsNothing);
    });
  });

  group('arrival animation survived the layout change', () {
    double opacityOf(WidgetTester tester, String title) => tester
        .widget<Opacity>(find
            .ancestor(of: find.text(title), matching: find.byType(Opacity))
            .first)
        .opacity;

    testWidgets('the first build animates nothing', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_Harness(items: [_item(1, 'Hollow Knight')]));
      await tester.pump();

      expect(opacityOf(tester, 'Hollow Knight'), 1.0,
          reason: 'opening the app is not every game arriving');
    });

    testWidgets('a game added later animates in', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_Harness(items: [_item(1, 'Hollow Knight')]));
      await tester.pump();

      tester
          .state<_HarnessState>(find.byType(_Harness))
          .setItems([_item(1, 'Hollow Knight'), _item(2, 'Celeste')]);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      expect(opacityOf(tester, 'Celeste'), lessThan(1.0));
      expect(opacityOf(tester, 'Hollow Knight'), 1.0);

      await tester.pumpAndSettle();
      expect(opacityOf(tester, 'Celeste'), 1.0);
    });
  });
}
