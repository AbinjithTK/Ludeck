// Stage 4: the node tree announces itself to a screen reader.
//
// The authoritative accessibility check is a widget test that reads the real
// SEMANTICS TREE (not a uiautomator dump, which builds the tree lazily and reads
// back nearly empty -- see docs/CONSTRAINTS.md). Every branch node and game node
// carries a Semantics label; this proves they are present and correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/nodetree/node_tree_view.dart';

Branch br(int id, String name, {int? parent, int order = 0, bool collapsed = false}) =>
    (id: id, name: name, sortOrder: order, parentId: parent, collapsed: collapsed);

TreeItem game(int id, String title, Progress p) => TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(igdbId: id, ownership: Ownership.owned, progress: p),
      copies: const [],
    );

void main() {
  testWidgets('branch and game nodes carry screen-reader labels',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NodeTreeView(
          items: [
            game(101, 'Stardew Valley', Progress.playing),
            game(102, 'Hades', Progress.finished),
          ],
          branches: [
            br(1, 'Chill nights', order: 0),
            br(2, 'Couch co-op', order: 1, collapsed: true),
          ],
          placements: {
            1: [101],
            2: [102],
          },
          onSelect: (_) {},
          onCreateBranch: (_) {},
          onToggleCollapse: (_) {},
          onPick: (_, _) {},
          onSwitchView: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // A branch node announces its name, its count, and its fold state.
    expect(find.bySemanticsLabel('Chill nights, 1 game, expanded'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Couch co-op, 1 game, collapsed'),
        findsOneWidget);

    // A visible game node announces its title and lifecycle. (Couch co-op is
    // folded, so Hades is not in the tree; Stardew, under expanded Chill, is.)
    expect(find.bySemanticsLabel('Stardew Valley, Playing'), findsOneWidget);

    handle.dispose();
  });
}
