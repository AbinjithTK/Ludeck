// Stage 3: dragging a game onto a branch node.
//
// Proves the drag-to-branch wiring end to end at the widget layer: a game row
// is a LongPressDraggable whose payload is the game, a branch node is a
// DragTarget, and dropping fires onMoveGame(game, targetBranch). The move-vs-
// also-add CHOICE and the store writes live in main.dart's _dropGameOnBranch
// (exercised by the store's own move/place tests); here we prove the gesture
// reaches the callback with the right arguments, which is the part the view owns.
//
// Pure widget test, no database.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/nodetree/node_tree_view.dart';

Branch br(int id, String name, {int? parent, int order = 0}) =>
    (id: id, name: name, sortOrder: order, parentId: parent, collapsed: false);

TreeItem game(int id, String title) => TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(igdbId: id, ownership: Ownership.owned, progress: Progress.untouched),
      copies: const [],
    );

void main() {
  final branches = [
    br(1, 'Chill nights', order: 0),
    br(2, 'Couch co-op', order: 1),
  ];
  final placements = {
    1: [101],
    2: [102],
  };
  final items = [game(101, 'Stardew Valley'), game(102, 'Overcooked')];

  Future<void> pumpTree(
    WidgetTester tester, {
    void Function(TreeItem, Branch)? onMove,
    ValueChanged<Branch>? onBranchHold,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NodeTreeView(
          items: items,
          branches: branches,
          placements: placements,
          onMoveGame: onMove,
          onBranchHold: onBranchHold,
          onSelect: (_) {},
          onCreateBranch: (_) {},
          onToggleCollapse: (_) {},
          onPick: (_, _) {},
          onSwitchView: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('dragging a game onto another branch fires onMoveGame with the '
      'game and the target', (tester) async {
    TreeItem? movedGame;
    Branch? target;
    await pumpTree(tester, onMove: (g, b) {
      movedGame = g;
      target = b;
    });

    // Long-press-drag Stardew Valley (on Chill nights) onto the Couch co-op node.
    final gameFinder = find.byKey(const ValueKey('game-node-101'));
    final targetFinder = find.text('Couch co-op');
    expect(gameFinder, findsOneWidget);
    expect(targetFinder, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(gameFinder));
    await tester.pump(const Duration(milliseconds: 600)); // trigger long-press
    await gesture.moveTo(tester.getCenter(targetFinder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(movedGame?.game.igdbId, 101);
    expect(target?.id, 2);
  });

  testWidgets('a branch long-press opens its menu (onBranchHold fires)',
      (tester) async {
    Branch? held;
    await pumpTree(tester, onBranchHold: (b) => held = b);

    await tester.longPress(find.text('Chill nights'));
    await tester.pumpAndSettle();
    expect(held?.id, 1);
  });

  testWidgets('with no move handler, a game is not draggable (read-only view)',
      (tester) async {
    await pumpTree(tester); // onMove null
    // The row still renders and is tappable; it is simply not wrapped in an
    // active draggable. Dragging it onto a branch changes nothing (no handler).
    expect(find.byKey(const ValueKey('game-node-101')), findsOneWidget);
    expect(find.byType(LongPressDraggable<TreeItem>), findsNothing);
  });
}
