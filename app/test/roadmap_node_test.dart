// Stage 4: the lifecycle shows on the node. The status sheet already writes the
// transition (rating_test covers that flow); this proves the NODE RESTYLES for
// each state -- a finished node glows gold, a playing node rings accent, a
// spotted bud rings dim -- so a transition through the sheet visibly changes the
// node once the store re-read rebuilds it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/roadmap/roadmap_node.dart';
import 'package:ludeck/ui/tokens.dart';

void main() {
  TreeItem game(Ownership o, Progress p) => TreeItem(
        game: const Game(igdbId: 1, title: 'Game'),
        entry: Entry(igdbId: 1, ownership: o, progress: p),
        copies: const [],
      );

  Future<BoxDecoration> pumpRing(WidgetTester tester, TreeItem item) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoadmapNode(
          item: item,
          diameter: 78,
          titleSide: NodeTitleSide.right,
          onTap: () {},
        ),
      ),
    ));
    // The ring is the outer Container's circular BoxDecoration (the first
    // Container with a circle shape and a border).
    final container = tester.widgetList<Container>(find.byType(Container)).firstWhere(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).shape == BoxShape.circle,
        );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('a finished node glows gold', (tester) async {
    final d = await pumpRing(tester, game(Ownership.owned, Progress.finished));
    expect(d.border!.top.color, Tokens.palette.accent,
        reason: 'finished rings in the accent gold');
    expect(d.boxShadow, isNotNull, reason: 'finished glows');
    expect(d.boxShadow!.first.color, Tokens.palette.accent.withValues(alpha: 0.4));
  });

  testWidgets('a playing node rings accent-glow, no gold glow shadow',
      (tester) async {
    final d = await pumpRing(tester, game(Ownership.owned, Progress.playing));
    expect(d.border!.top.color, Tokens.cosmos.glow);
    expect(d.boxShadow, isNull, reason: 'only finished glows');
  });

  testWidgets('a spotted bud rings dim', (tester) async {
    final d = await pumpRing(tester, game(Ownership.spotted, Progress.untouched));
    expect(d.border!.top.color, Tokens.palette.textDim);
    expect(d.boxShadow, isNull);
  });

  testWidgets('an untouched owned game rings plain', (tester) async {
    final d = await pumpRing(tester, game(Ownership.owned, Progress.untouched));
    expect(d.border!.top.color, Tokens.cosmos.panelEdge);
  });
}
