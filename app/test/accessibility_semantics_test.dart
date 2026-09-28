// Accessibility coverage for the three screens a device `uiautomator dump`
// appeared to show as unlabelled: the tree header, the share card, and the
// visitor view.
//
// The dump was misleading. `uiautomator dump` attaches as an accessibility
// service, which is what makes Flutter build its semantics tree in the first
// place -- so the first dump after attaching can read a tree that has not been
// populated yet and report almost nothing. Flutter's OWN semantics tree, which
// is what TalkBack actually consumes, is the authority, and `ensureSemantics`
// is how a test reads it. These tests exist so the question is never settled by
// eyeballing a dump again.

import 'package:flutter/material.dart' hide Form;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:ludeck/ui/publish/share_card.dart';
import 'package:ludeck/ui/shell/tree_header.dart';
import 'package:ludeck/ui/visit/visit_screen.dart';

const _game = PublishedGame(
  igdbId: 113112,
  title: 'Hades',
  status: Progress.finished,
  branchName: 'On the trunk',
  rating: 5,
);

void main() {
  group('tree header', () {
    testWidgets('every header control is announced', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TreeHeader(
              total: 8,
              harvested: 1,
              seeds: 2,
              branches: 0,
              skipped: 0,
              onSkippedTap: () {},
              onBranchesTap: () {},
              onProfileTap: () {},
            ),
          ),
        ));
      });

      // The orb is the only route to the profile, so it must say so rather
      // than announcing a bare number. One harvest is level 2.
      expect(find.bySemanticsLabel('Level 2. Open your profile'),
          findsOneWidget);
      // The progress pill is a painted bar with no text of its own.
      expect(find.bySemanticsLabel(RegExp(r'percent to level')), findsOneWidget);
      // The branches icon carries no visible text at all.
      expect(find.bySemanticsLabel('Branches'), findsOneWidget);
      // The counts, which a large-type user loses visually by design.
      expect(find.bySemanticsLabel('1 finished'), findsOneWidget);
      expect(find.bySemanticsLabel('2 on wishlist'), findsOneWidget);
      expect(find.bySemanticsLabel('0 branches'), findsOneWidget);

      handle.dispose();
    });
  });

  group('share card', () {
    testWidgets('both actions on a live tree are announced', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
          home: ShareCardScreen(games: [_game], level: 2, handle: 'ada'),
        ));
      });

      expect(find.bySemanticsLabel('Copy link'), findsOneWidget);
      expect(find.bySemanticsLabel('See what a visitor sees'), findsOneWidget);
      // The link itself must be readable, not only copyable -- a screen-reader
      // user cannot inspect the clipboard to find out what they just shared.
      expect(find.bySemanticsLabel(RegExp(r'/t/\?h=ada')), findsWidgets);

      handle.dispose();
    });

    testWidgets('a private save announces that there is no link',
        (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() async {
        await tester.pumpWidget(const MaterialApp(
          home: ShareCardScreen(games: [_game], level: 2, handle: ''),
        ));
      });

      expect(find.bySemanticsLabel('Copy link'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Only you can see this')),
          findsOneWidget);

      handle.dispose();
    });
  });

  group('visitor view', () {
    late Repository repo;

    setUp(() async {
      repo = await Repository.openInMemory();
      FakeSocialBackend.resetShared();
    });

    tearDown(() async => repo.close());

    testWidgets('the audience verbs are announced', (tester) async {
      final semantics = tester.ensureSemantics();
      final backend = FakeSocialBackend(configured: true);

      await tester.runAsync(() async {
        await backend.signIn();
        await backend.publish(games: const [_game], level: 2, isPublic: true);
        final store = LudeckStore(repo);
        await tester.pumpWidget(MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<SocialBackend>.value(value: backend),
              ChangeNotifierProvider<LudeckStore>.value(value: store),
            ],
            child: VisitScreen(handle: backend.currentProfile!.handle),
          ),
        ));
        await store.load();
      });
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Admire'), findsOneWidget);
      expect(find.bySemanticsLabel('Wishlist'), findsOneWidget);
      expect(find.bySemanticsLabel('Played too'), findsOneWidget);
      expect(find.bySemanticsLabel('Follow'), findsOneWidget);
      // Plant is the one thing a visitor can do to a row.
      expect(find.bySemanticsLabel(RegExp('Plant')), findsWidgets);

      semantics.dispose();
    });
  });
}
