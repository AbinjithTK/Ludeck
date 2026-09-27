// Stage 4 verification: publish consent defaults private, "Save and share" is
// total for both segments, and -- the one PomoDeck subtask this stage names
// explicitly -- the rendered payload/card never carries `note` or
// `recommendedBy`, even though the fixture item used here has both set.

import 'package:flutter/material.dart' hide Form;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/ui/publish/orchard_story_card.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/services/social/fake_social_backend.dart';
import 'package:ludeck/services/social/publish_export.dart';
import 'package:ludeck/services/social/social_backend.dart';
import 'package:ludeck/ui/publish/publish_screen.dart';
import 'package:ludeck/ui/publish/share_card.dart';

// A collection item carrying exactly the two forbidden fields, so a leak would
// be visible in this test rather than merely absent from a clean fixture.
final _sensitiveItem = TreeItem(
  game: const Game(igdbId: 113112, title: 'Hades', coverUrl: 'c'),
  entry: const Entry(
    igdbId: 113112,
    ownership: Ownership.owned,
    progress: Progress.finished,
    rating: 5,
    note: 'a secret only I should see',
    recommendedBy: 'Priya',
  ),
  copies: const [
    Copy(igdbId: 113112, platform: Platform.pc, form: Form.digital,
        acquired: Acquired.bought),
  ],
);

Widget _wrap(Widget child, SocialBackend backend) => MaterialApp(
      home: Provider<SocialBackend>.value(value: backend, child: child),
    );

void main() {
  setUp(() {
    FakeSocialBackend.resetShared();
    // Clipboard.setData in a widget test does not resolve without an explicit
    // handler on the platform-channel mock -- flutter_test's default binding
    // has none wired for the clipboard method channel, so an un-mocked
    // await hangs rather than throwing, which is what made this look like a
    // pump-timing problem. Installing the handler is the standard fix; no
    // amount of extra pump()/runAsync() calls resolves an await nothing ever
    // answers.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });
  });

  group('PublishBody defaults and total save', () {
    testWidgets('defaults to Private, and the CTA always reads Save and share',
        (tester) async {
      final backend = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'me', handle: 'ada', displayName: 'Ada'));
      final games = toPublished([_sensitiveItem], 'Metroidvanias');

      await tester.pumpWidget(_wrap(
        PublishBody(backend: backend, games: games, level: 3),
        backend,
      ));

      expect(find.text('Save and share'), findsOneWidget);
      final privateSemantics = tester.widget<Semantics>(find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Private visibility',
      ));
      expect(privateSemantics.properties.selected, isTrue);
    });

    testWidgets(
        'saving Public publishes, then the share card renders with a copy link '
        'button, and NEITHER the note nor recommendedBy ever appear on screen',
        (tester) async {
      final backend = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'me', handle: 'ada', displayName: 'Ada'));
      final games = toPublished([_sensitiveItem], 'Metroidvanias');

      await tester.pumpWidget(_wrap(
        PublishBody(backend: backend, games: games, level: 3),
        backend,
      ));

      await tester.tap(find.text('Public'));
      await tester.pump();
      await tester.tap(find.text('Save and share'));
      await tester.pumpAndSettle();

      // Landed on the share card.
      expect(find.text('Your tree is live'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      // The story card renders the collection as a roadmap of nodes, not a
      // sample title in text -- so assert the card is present rather than a game
      // name (which now appears only as a node/cover, never as rendered text).
      expect(find.byType(OrchardStoryCard), findsOneWidget);
      expect(find.byKey(const Key('share-out')), findsOneWidget,
          reason: 'one tap to the system share sheet');

      // The privacy assertion: scan every Text widget's rendered string.
      final allText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(allText.contains('Priya'), isFalse,
          reason: 'recommendedBy rendered on the share card');
      expect(allText.contains('a secret only I should see'), isFalse,
          reason: 'note rendered on the share card');

      // And the backend actually received the privacy-safe projection only.
      final published = await backend.treeByHandle('ada');
      final serialized = published.games.map((g) => g.toString()).join('|');
      expect(serialized.contains('Priya'), isFalse);
      expect(serialized.contains('a secret only I should see'), isFalse);
    });

    testWidgets('saving Private shows the private confirmation, no copy link',
        (tester) async {
      final backend = FakeSocialBackend(
          signedInAs: const SocialProfile(
              id: 'me', handle: 'ada', displayName: 'Ada'));

      await tester.pumpWidget(_wrap(
        PublishBody(backend: backend, games: const [], level: 1),
        backend,
      ));

      await tester.tap(find.text('Save and share'));
      await tester.pumpAndSettle();

      expect(find.text('Saved privately'), findsOneWidget);
      expect(find.text('Copy link'), findsNothing);
    });
  });

  group('ShareCardScreen copy link', () {
    testWidgets('tapping Copy link shows the toast without leaving the screen',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ShareCardScreen(
          games: toPublished([_sensitiveItem], 'Cozy'),
          level: 2,
          handle: 'ada',
        ),
      ));

      await tester.ensureVisible(find.text('Copy link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();

      expect(find.text('Link copied'), findsOneWidget);
      // The share card itself is still mounted -- the toast did not dismiss it.
      expect(find.text('Your tree is live'), findsOneWidget);
    });
  });
}
