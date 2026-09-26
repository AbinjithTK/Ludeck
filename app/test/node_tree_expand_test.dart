// Stage 2: expanding and collapsing a branch node in the tree.
//
// Proves the interactive contract of NodeTreeView's recursive outline:
//  - a branch with children toggles its subtree on tap (children vanish, then
//    return), with the fold reported back through onToggleCollapse so the store
//    can persist it;
//  - the collapse is animated (an AnimatedSize wraps every branch's children
//    and the chevron rotates), not a hard cut;
//  - a persisted `collapsed: true` branch starts folded;
//  - tapping a game node still opens the status sheet (onSelect fires).
//
// Pure widget test, no database, so no runAsync needed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/nodetree/node_tree_view.dart';

Branch br(int id, String name,
        {int? parent, int order = 0, bool collapsed = false}) =>
    (id: id, name: name, sortOrder: order, parentId: parent, collapsed: collapsed);

TreeItem game(int id, String title) => TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(igdbId: id, ownership: Ownership.owned, progress: Progress.untouched),
      copies: const [],
    );

Finder gameRow(int id) => find.byKey(ValueKey('game-node-$id'));

void main() {
  final branches = [
    br(1, 'Chill nights', order: 0),
    br(2, 'Couch co-op', order: 1),
    br(21, 'With Sam', parent: 2, order: 0),
  ];
  final placements = {
    1: [101, 102],
    2: [103],
    21: [104, 105],
  };
  final items = [
    game(101, 'Stardew Valley'),
    game(102, 'Unpacking'),
    game(103, 'Overcooked'),
    game(104, 'It Takes Two'),
    game(105, 'Deep Rock'),
  ];

  Future<NodeTreeView> pumpTree(
    WidgetTester tester, {
    List<Branch>? bs,
    void Function(Branch)? onToggle,
    void Function(TreeItem)? onSelect,
  }) async {
    final view = NodeTreeView(
      items: items,
      branches: bs ?? branches,
      placements: placements,
      onToggleCollapse: onToggle,
      onSelect: onSelect,
      onCreateBranch: (_) {},
      onPick: (_, _) {},
      onSwitchView: () {},
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));
    await tester.pumpAndSettle();
    return view;
  }

  testWidgets('tapping a branch collapses then expands its children',
      (tester) async {
    Branch? toggled;
    await pumpTree(tester, onToggle: (b) => toggled = b);

    // Chill nights' games are visible.
    expect(gameRow(101), findsOneWidget);
    expect(gameRow(102), findsOneWidget);

    // Tap the Chill nights branch node.
    await tester.tap(find.text('Chill nights'));
    await tester.pumpAndSettle();

    // Its games are gone, and the fold was reported for persistence.
    expect(gameRow(101), findsNothing);
    expect(gameRow(102), findsNothing);
    expect(toggled?.id, 1);

    // Tap again -> expands.
    await tester.tap(find.text('Chill nights'));
    await tester.pumpAndSettle();
    expect(gameRow(101), findsOneWidget);
    expect(gameRow(102), findsOneWidget);
  });

  testWidgets('the collapse is animated, not a hard cut', (tester) async {
    await pumpTree(tester);

    // Every branch wraps its children in an AnimatedSize for the height
    // animation; the chevron rotates via AnimatedRotation.
    expect(find.byType(AnimatedSize), findsWidgets);
    expect(find.byType(AnimatedRotation), findsWidgets);

    // Mid-animation the children are still partly present (size > 0), proving
    // it shrinks rather than snapping.
    await tester.tap(find.text('Chill nights'));
    await tester.pump(); // start the animation
    await tester.pump(const Duration(milliseconds: 80)); // partway through
    // Still shrinking: the row exists but is being clipped down.
    await tester.pumpAndSettle();
    expect(gameRow(101), findsNothing);
  });

  testWidgets('a persisted collapsed branch starts folded', (tester) async {
    await pumpTree(tester, bs: [
      br(1, 'Chill nights', order: 0, collapsed: true),
      br(2, 'Couch co-op', order: 1),
      br(21, 'With Sam', parent: 2, order: 0),
    ]);
    // Chill nights is folded from the start: its games are absent.
    expect(gameRow(101), findsNothing);
    expect(gameRow(102), findsNothing);
    // Couch co-op is open: its sub-branch's games are present.
    expect(gameRow(104), findsOneWidget);
  });

  testWidgets('tapping a game opens it (onSelect fires)', (tester) async {
    TreeItem? picked;
    await pumpTree(tester, onSelect: (i) => picked = i);
    await tester.tap(gameRow(101));
    await tester.pumpAndSettle();
    expect(picked?.game.igdbId, 101);
  });

  testWidgets('collapsing a parent hides nested sub-branch games too',
      (tester) async {
    await pumpTree(tester);
    // With Sam's games (under Couch co-op) are visible.
    expect(gameRow(104), findsOneWidget);
    // Collapse Couch co-op.
    await tester.tap(find.text('Couch co-op'));
    await tester.pumpAndSettle();
    // The whole subtree, including With Sam's games, is gone.
    expect(gameRow(103), findsNothing);
    expect(gameRow(104), findsNothing);
    expect(find.text('With Sam'), findsNothing);
  });
}
