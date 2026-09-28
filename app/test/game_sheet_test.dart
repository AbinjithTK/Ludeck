// The game sheet: every answer visible at once, the current one marked for a
// screen reader as well as by eye, and each tap reported once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/orchard/game_sheet.dart';
import 'package:ludeck/ui/tokens.dart';

TreeItem _item(Progress p, {int? rating}) => TreeItem(
      game: const Game(igdbId: 7, title: 'Hades'),
      entry: Entry(
          igdbId: 7,
          ownership: Ownership.owned,
          progress: p,
          rating: rating),
      copies: const [],
    );

Future<void> _pump(WidgetTester tester, Widget sheet) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: sheet)));

void main() {
  testWidgets('the current answers are announced as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
        tester,
        GameSheet(
          item: _item(Progress.playing),
          trees: [(id: 1, name: 'Cozy', swatch: Tokens.palette.text)],
          currentTree: 1,
          onProgress: (_) {},
          onOwnership: (_) {},
          onTree: (_) {},
        ));
    expect(tester.getSemantics(find.bySemanticsLabel('Playing')),
        matchesSemantics(isButton: true, isSelected: true, hasSelectedState: true,
            hasTapAction: true, label: 'Playing'));
    expect(find.text('Cozy'), findsOneWidget);
    expect(find.text('Playing  ·  On Cozy'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('answers are plain words, not the orchard vocabulary',
      (tester) async {
    // 2026-09-28: "say what a person can understand easily, real actions,
    // instead of things like harvested".
    await _pump(
        tester,
        GameSheet(
          item: _item(Progress.playing),
          trees: const [],
          currentTree: null,
          onProgress: (_) {},
          onOwnership: (_) {},
          onTree: (_) {},
        ));
    for (final w in ['Not started', 'Installed', 'Playing', 'Finished',
        'Set aside', 'Want it', 'Own it', 'Gave it away']) {
      expect(find.text(w), findsOneWidget, reason: w);
    }
    for (final w in ['Growing', 'Within reach', 'In hand', 'Harvested',
        'Pressed', 'Bud', 'On the tree', 'Given away']) {
      expect(find.text(w), findsNothing, reason: w);
    }
  });

  testWidgets('the close button closes; it is announced as Close',
      (tester) async {
    final handle = tester.ensureSemantics();
    var closed = 0;
    await _pump(
        tester,
        GameSheet(
          item: _item(Progress.playing),
          trees: const [],
          currentTree: null,
          onProgress: (_) {},
          onOwnership: (_) {},
          onTree: (_) {},
          onClose: () => closed++,
        ));
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-sheet-close')));
    expect(closed, 1);
    handle.dispose();
  });

  testWidgets('no close button when nothing can close it', (tester) async {
    await _pump(
        tester,
        GameSheet(
          item: _item(Progress.playing),
          trees: const [],
          currentTree: null,
          onProgress: (_) {},
          onOwnership: (_) {},
          onTree: (_) {},
        ));
    expect(find.byKey(const Key('game-sheet-close')), findsNothing);
  });

  testWidgets('a tap reports its answer', (tester) async {
    Progress? got;
    int? tree = -1;
    await _pump(
        tester,
        GameSheet(
          item: _item(Progress.untouched),
          trees: [(id: 4, name: 'Must play', swatch: Tokens.palette.text)],
          currentTree: 4,
          onProgress: (p) => got = p,
          onOwnership: (_) {},
          onTree: (id) => tree = id,
        ));
    await tester.tap(find.text('Finished'));
    expect(got, Progress.finished);
    await tester.tap(find.text('On the ground'));
    expect(tree, isNull);
  });

  testWidgets('no trees, no tree row; rating only when harvested',
      (tester) async {
    await _pump(
        tester,
        GameSheet(
          item: _item(Progress.playing),
          trees: const [],
          currentTree: null,
          onProgress: (_) {},
          onOwnership: (_) {},
          onTree: (_) {},
          onRate: () {},
        ));
    expect(find.text('Which tree'), findsNothing);
    expect(find.text('What did you think'), findsNothing);

    await _pump(
        tester,
        GameSheet(
          item: _item(Progress.finished, rating: 4),
          trees: const [],
          currentTree: null,
          onProgress: (_) {},
          onOwnership: (_) {},
          onTree: (_) {},
          onRate: () {},
        ));
    expect(find.text('Rated 4 out of 5'), findsOneWidget);
  });
}
