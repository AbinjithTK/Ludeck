// The share sheet (ui/publish/share_sheet.dart): the card first, "Share
// image" publishes nothing, the public link is OFF until switched on and says
// what it does before it is touched, and nothing private reaches the screen.

import 'package:flutter/material.dart' hide Form;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/publish_export.dart';
import 'package:ludeck/services/social/tree_links.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/ui/publish/orchard_story_card.dart';
import 'package:ludeck/ui/publish/share_sheet.dart';

final _item = TreeItem(
  game: const Game(igdbId: 113112, title: 'Hades', coverUrl: 'c'),
  entry: const Entry(
    igdbId: 113112,
    ownership: Ownership.owned,
    progress: Progress.finished,
    note: 'a secret only I should see',
    recommendedBy: 'Priya',
  ),
  copies: const [],
);

const _me = SocialProfile(id: 'me', handle: 'ada', displayName: 'Ada');

Future<FakeSocialStore> _pump(WidgetTester tester) async {
  final store = FakeSocialStore();
  final backend = FakeSocialBackend(signedInAs: _me, store: store);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ShareSheet(
            backend: backend, games: toPublished([_item], 'Cozy'), level: 2),
      ),
    ),
  ));
  await tester.pump();
  return store;
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  testWidgets('the card comes first, and the link starts private', (tester) async {
    final store = await _pump(tester);
    expect(find.byType(OrchardStoryCard), findsOneWidget);
    expect(find.byKey(const Key('share-out')), findsOneWidget);
    final sw = tester.widget<Switch>(find.byKey(const Key('share-public')));
    expect(sw.value, isFalse, reason: 'FEATURES.md: default private');
    expect(find.textContaining('only you can see'), findsOneWidget,
        reason: 'the consequence is written before the switch is touched');
    expect(store.trees, isEmpty, reason: 'opening the sheet publishes nothing');
  });

  testWidgets('Share image publishes nothing', (tester) async {
    final store = await _pump(tester);
    await tester.tap(find.byKey(const Key('share-out')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(store.trees, isEmpty,
        reason: 'an image goes only where you send it: no account, no publish');
  });

  testWidgets('switching the link on publishes and shows it; off unpublishes',
      (tester) async {
    final store = await _pump(tester);
    await tester.tap(find.byKey(const Key('share-public')));
    await tester.pumpAndSettle();
    expect(store.trees.keys, ['ada']);
    expect(find.text(treeLinkFor('ada')), findsOneWidget);

    await tester.tap(find.byKey(const Key('share-copy')));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget,
        reason: 'said in place: a snackbar would sit under the sheet');
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('share-public')));
    await tester.pumpAndSettle();
    expect(store.trees, isEmpty);
    expect(find.text(treeLinkFor('ada')), findsNothing);
  });

  testWidgets('nothing private is on screen', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('share-public')));
    await tester.pumpAndSettle();
    final all = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(all, isNot(contains('secret')));
    expect(all, isNot(contains('Priya')));
  });

  group('sharing one tree', () {
    TreeItem game(int id, String title, Progress p) => TreeItem(
          game: Game(igdbId: id, title: title),
          entry: Entry(igdbId: id, ownership: Ownership.owned, progress: p),
          copies: const [],
        );
    final cozy = toPublished(
        [game(1, 'Stardew', Progress.playing), game(2, 'Unpacking', Progress.finished)],
        'Cozy');
    final action = toPublished([game(3, 'Hades', Progress.untouched)], 'Action');

    Future<FakeSocialStore> pumpTrees(WidgetTester tester) async {
      final store = FakeSocialStore();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ShareSheet(
              backend: FakeSocialBackend(signedInAs: _me, store: store),
              games: [...cozy, ...action],
              level: 2,
              trees: [
                (name: 'Cozy', swatch: const Color(0xFFC8457A), games: cozy),
                (name: 'Action', swatch: const Color(0xFFD0562F), games: action),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      return store;
    }

    OrchardStoryCard card(WidgetTester tester) =>
        tester.widget<OrchardStoryCard>(find.byType(OrchardStoryCard));

    testWidgets('opens on the whole orchard', (tester) async {
      await pumpTrees(tester);
      expect(card(tester).treeName, isNull);
      expect(card(tester).games, hasLength(3));
      expect(find.text('3 games in my orchard'), findsOneWidget);
    });

    testWidgets('choosing a tree puts only that tree on the card', (tester) async {
      await pumpTrees(tester);
      await tester.tap(find.byKey(const Key('share-scope-Cozy')));
      await tester.pumpAndSettle();
      expect(card(tester).treeName, 'Cozy');
      expect(card(tester).games.map((g) => g.title), ['Stardew', 'Unpacking'],
          reason: 'a card never carries more than its scope');
      expect(find.text('MY TREE'), findsOneWidget);
      expect(find.text('Cozy'), findsWidgets);
      expect(find.textContaining('2 games'), findsOneWidget);

      await tester.tap(find.byKey(const Key('share-scope-Whole orchard')));
      await tester.pumpAndSettle();
      expect(card(tester).games, hasLength(3));
    });

    testWidgets('a one-tree share says the link is still the whole orchard',
        (tester) async {
      await pumpTrees(tester);
      expect(find.byKey(const Key('share-link-scope')), findsNothing);
      await tester.tap(find.byKey(const Key('share-scope-Action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-link-scope')), findsOneWidget);
    });

    testWidgets('choosing a tree publishes nothing', (tester) async {
      final store = await pumpTrees(tester);
      await tester.tap(find.byKey(const Key('share-scope-Cozy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-out')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(store.trees, isEmpty);
    });

    testWidgets('no trees, no choice row', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('share-scope')), findsNothing);
    });
  });
}
