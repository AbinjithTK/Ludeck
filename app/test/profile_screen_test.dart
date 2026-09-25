// The profile screen's contracts.
//
// `ProfileBody` is pumped rather than `ProfileScreen` on purpose: the screen
// reads its data with `context.watch<LudeckStore>()`, so mounting it would
// require a Provider over a real `Repository` -- real sqflite I/O, which in a
// `testWidgets` FakeAsync zone deadlocks rather than fails. `ProfileBody` takes
// the same data as plain arguments, so the profile's own behaviour is testable
// without standing up a database.
//
// What is worth protecting here is NOT the layout. It is:
//   * every number traces to `domain/level.dart` or `domain/season.dart`
//   * a released game is not counted, matching the season invariant
//   * a screen reader hears a sentence, never a bare metaphor word
//   * nothing on the screen marks what the user has not done

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/profile/profile_screen.dart';

TreeItem _item(
  int id,
  String title, {
  Progress progress = Progress.untouched,
  Ownership ownership = Ownership.owned,
  bool shelved = false,
}) =>
    TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: ownership,
        progress: progress,
        shelved: shelved,
      ),
      copies: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<TreeItem> items,
  int branches = 0,
}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // No `ensureSemantics` handle here. Disposing it through `addTearDown` runs
  // AFTER the framework's end-of-test check and fails every test with "a
  // SemanticsHandle was active at the end of the test", so these tests read the
  // `Semantics` widgets' own configuration instead (see `_labels`). That asserts
  // the label we set rather than the tree the engine would build from it, which
  // is the part this screen owns.
  await tester.pumpWidget(MaterialApp(
    home: ProfileBody(
      items: items,
      branches: branches,
      // Stands in for the tree portrait. A Container, not a SizedBox.shrink, so
      // the portrait still occupies its aspect box and a layout overflow in the
      // surrounding column would still show up here.
      hero: Container(key: const Key('hero-stub')),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Every semantic label present on screen.
Iterable<String> _labels(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((s) => s.properties.label)
    .whereType<String>();

/// The count rendered on the row whose label is [word].
int _countFor(WidgetTester tester, String word) {
  final row = find.ancestor(
    of: find.text(word),
    matching: find.byType(Row),
  );
  final texts = tester
      .widgetList<Text>(find.descendant(of: row.first, matching: find.byType(Text)))
      .map((t) => t.data)
      .whereType<String>()
      .toList();
  final number = texts.firstWhere((t) => t != word);
  return int.parse(number);
}

void main() {
  group('the tree is the avatar', () {
    testWidgets('the portrait is rendered and announced', (tester) async {
      // `docs/FEATURES.md`: "the tree goes where the avatar is". If this ever
      // becomes a monogram or a generated character, that decision was reversed
      // silently.
      await _pump(tester, items: [_item(1, 'Hades')]);

      expect(find.byKey(const Key('hero-stub')), findsOneWidget);
      expect(
        _labels(tester),
        contains('A portrait of your tree'),
        reason: 'the largest element on the screen carries no text of its own, '
            'so without a semantic label a screen reader finds nothing there',
      );
    });
  });

  group('every number comes from the domain', () {
    testWidgets('the level follows the harvest count, not the collection size',
        (tester) async {
      // Eight games, one finished. `kLevelThresholds` puts level 2 at one
      // harvest, so a level driven by collection size would read differently.
      await _pump(tester, items: [
        _item(1, 'Hades', progress: Progress.finished),
        for (var i = 2; i <= 8; i++) _item(i, 'Game $i'),
      ]);

      expect(find.text('Level 2'), findsOneWidget);
      expect(find.text('2 more harvests to level 3'), findsOneWidget);
    });

    testWidgets('one remaining harvest is singular', (tester) async {
      // Level 2 needs 1 harvest, level 3 needs 3, so two harvests leaves one.
      await _pump(tester, items: [
        _item(1, 'Hades', progress: Progress.finished),
        _item(2, 'Celeste', progress: Progress.finished),
      ]);

      expect(find.text('1 more harvest to level 3'), findsOneWidget);
    });

    testWidgets('the season buckets match the collection', (tester) async {
      await _pump(
        tester,
        items: [
          _item(1, 'Hades', progress: Progress.finished),
          _item(2, 'Celeste', progress: Progress.abandoned),
          _item(3, 'Returnal', progress: Progress.playing),
          _item(4, 'Blue Prince'),
          _item(5, 'Silksong', ownership: Ownership.spotted),
        ],
        branches: 3,
      );

      expect(_countFor(tester, Progress.finished.tree), 1);
      expect(_countFor(tester, Progress.abandoned.tree), 1);
      expect(_countFor(tester, Progress.untouched.tree), 2);
      expect(_countFor(tester, Ownership.spotted.tree), 1);
      expect(_countFor(tester, 'Branches'), 3);
    });

    testWidgets('a released game is in no bucket', (tester) async {
      // The season invariant: ownership and progress stay independent so a sale
      // never erases a completion record, but a game you no longer own must not
      // inflate "what does my collection look like right now".
      await _pump(tester, items: [
        _item(1, 'Hades',
            progress: Progress.finished, ownership: Ownership.released),
      ]);

      expect(_countFor(tester, Progress.finished.tree), 0);
      expect(find.text('Level 1'), findsOneWidget);
    });

    testWidgets('a shelved game is in no bucket', (tester) async {
      await _pump(tester, items: [
        _item(1, 'Hades', progress: Progress.finished, shelved: true),
      ]);

      expect(_countFor(tester, Progress.finished.tree), 0);
    });

    testWidgets('one branch reads in the singular', (tester) async {
      await _pump(tester, items: [_item(1, 'Hades')], branches: 1);

      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Branches'), findsNothing);
    });
  });

  group('the words are the frozen vocabulary', () {
    testWidgets('labels come from the enums, not from this screen',
        (tester) async {
      // Typed metaphor words would silently survive a rewording of the enum.
      await _pump(tester, items: [_item(1, 'Hades')]);

      for (final word in [
        Progress.finished.tree,
        Progress.abandoned.tree,
        Progress.untouched.tree,
        Ownership.spotted.tree,
      ]) {
        expect(find.text(word), findsOneWidget, reason: '$word must be shown');
      }
    });

    testWidgets('a screen reader hears a sentence, not a metaphor word',
        (tester) async {
      // "Pressed 1" tells an unfamiliar listener nothing.
      await _pump(tester, items: [
        _item(1, 'Celeste', progress: Progress.abandoned),
      ]);

      expect(_labels(tester), contains('1 game you set aside'));
    });

    testWidgets('the announcement pluralises', (tester) async {
      await _pump(tester, items: [
        _item(1, 'Celeste', progress: Progress.abandoned),
        _item(2, 'Returnal', progress: Progress.abandoned),
      ]);

      expect(_labels(tester), contains('2 games you set aside'));
      expect(_labels(tester), contains('0 games you finished'));
    });
  });

  group('nothing marks what has not happened', () {
    testWidgets('an empty collection is not scolded', (tester) async {
      // `DECISIONS.md` forbids empty-state guilt, decay and nagging outright, so
      // the empty profile is the case where a well-meant "get started!" would
      // breach it.
      await _pump(tester, items: const []);

      expect(find.text('Level 1'), findsOneWidget);
      for (final banned in [
        'overdue',
        'behind',
        'streak',
        'days',
        'goal',
        'target',
        'nothing yet',
      ]) {
        expect(
          find.textContaining(banned, findRichText: true),
          findsNothing,
          reason: '"$banned" reintroduces a shape DECISIONS.md rules out',
        );
      }
    });

    testWidgets('no percentage of the collection is shown', (tester) async {
      // A completion percentage turns the tree into a backlog gauge.
      await _pump(tester, items: [
        _item(1, 'Hades', progress: Progress.finished),
        _item(2, 'Celeste'),
      ]);

      expect(find.textContaining('%'), findsNothing);
    });
  });
}
