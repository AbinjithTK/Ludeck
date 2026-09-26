// Stage 6 verification: the harvest celebration, restored onto the roadmap.
// The tree->roadmap migration dropped the burst wiring (the store still fired
// justHarvested but nothing consumed it). These lock that the roadmap overlays
// a one-shot HarvestBurst over the harvested node when burstIgdbId is set, and
// nothing when it is not.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/harvest/harvest_burst.dart';
import 'package:ludeck/ui/roadmap/roadmap_view.dart';

void main() {
  TreeItem game(int id, String title, Progress p) => TreeItem(
        game: Game(igdbId: id, title: title),
        entry: Entry(igdbId: id, ownership: Ownership.owned, progress: p),
        copies: const [],
      );

  final items = [
    game(1, 'First', Progress.finished),
    game(2, 'Second', Progress.playing),
    game(3, 'Third', Progress.untouched),
  ];

  testWidgets('no burst overlay when burstIgdbId is null', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoadmapView(items: items, animateArrivals: false, onSelect: (_) {}),
      ),
    ));
    expect(find.byType(HarvestBurst), findsNothing);
  });

  testWidgets('a burst overlays the harvested node when set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoadmapView(
          items: items,
          animateArrivals: false,
          burstIgdbId: 2,
          onSelect: (_) {},
        ),
      ),
    ));
    expect(find.byType(HarvestBurst), findsOneWidget);
  });

  testWidgets('a burst for an absent id shows nothing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoadmapView(
          items: items,
          animateArrivals: false,
          burstIgdbId: 999,
          onSelect: (_) {},
        ),
      ),
    ));
    expect(find.byType(HarvestBurst), findsNothing);
  });
}
