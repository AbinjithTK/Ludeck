// Stage 6 of the share-to-library feature: the confirm sheet.
//
// The overflow tests are not padding. A fixed column in the paywall overflowed
// on a short screen and failed all ten of its tests, which turned out to be a
// real defect rather than a test artifact: it reproduces on any screen once
// accessibility text is large enough. This sheet is built to scroll for that
// reason, and these tests hold it to it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/domain/resolve.dart';
import 'package:ludeck/services/share_resolver.dart';
import 'package:ludeck/ui/intake/confirm_sheet.dart';

Candidate candidate(String title, double confidence, {int? id}) => Candidate(
      title: title,
      igdbId: id,
      method: MatchMethod.text,
      confidence: confidence,
    );

ShareResolution resolution(
  String shared, {
  List<Candidate> candidates = const [],
}) =>
    ShareResolution(parsed: parseShare(shared), candidates: candidates);

/// Pumps the sheet and returns whatever it popped.
Future<IntakeChoice?> openSheet(
  WidgetTester tester,
  ShareResolution r, {
  Size? surface,
  double textScale = 1.0,
}) async {
  if (surface != null) {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  IntakeChoice? result;
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showIntakeSheet(context, r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('pre-ticks confident candidates and leaves weak ones alone',
      (tester) async {
    await openSheet(
      tester,
      resolution('play Hollow Knight and maybe Control', candidates: [
        candidate('Hollow Knight', 0.85, id: 1),
        candidate('Control', 0.35, id: 2),
      ]),
    );

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes, hasLength(2));
    expect(boxes[0].value, isTrue, reason: 'confident candidate');
    expect(boxes[1].value, isFalse, reason: 'weak candidate must not be chosen');

    // The weak one is still SHOWN. The user sees everything considered.
    expect(find.text('Control'), findsOneWidget);
  });

  testWidgets('the action counts what is actually ticked', (tester) async {
    await openSheet(
      tester,
      resolution('play Hollow Knight and Hades', candidates: [
        candidate('Hollow Knight', 0.85, id: 1),
        candidate('Hades', 0.8, id: 2),
      ]),
    );

    expect(find.text('Add 2 games'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Add 1 game'), findsOneWidget);
  });

  testWidgets('unticking everything disables the action', (tester) async {
    await openSheet(
      tester,
      resolution('play Hades', candidates: [candidate('Hades', 0.8, id: 1)]),
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('Nothing selected'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('returns the ticked candidates and the recommender',
      (tester) async {
    IntakeChoice? choice;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                choice = await showIntakeSheet(
                  context,
                  resolution('play Hollow Knight', candidates: [
                    candidate('Hollow Knight', 0.85, id: 1),
                  ]),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Priya');
    await tester.tap(find.text('Add 1 game'));
    await tester.pumpAndSettle();

    expect(choice, isNotNull);
    expect(choice!.accepted.map((c) => c.title), ['Hollow Knight']);
    expect(choice!.recommendedBy, 'Priya');
  });

  testWidgets('an empty recommender comes back as null, not an empty string',
      (tester) async {
    IntakeChoice? choice;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                choice = await showIntakeSheet(
                  context,
                  resolution('play Hades',
                      candidates: [candidate('Hades', 0.8, id: 1)]),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Add 1 game'));
    await tester.pumpAndSettle();

    expect(choice!.recommendedBy, isNull);
  });

  group('nothing recognised', () {
    testWidgets('does not promise to keep a link it cannot store',
        (tester) async {
      // sources.igdb_id is NOT NULL, so a link with no matched game has nowhere
      // to go. The sheet must not offer storage that does not exist.
      await openSheet(tester, resolution('https://someblog.example/goty'));

      expect(find.text('Nothing recognised'), findsOneWidget);
      expect(find.text('Keep the link'), findsNothing);
      expect(find.text('Search instead'), findsOneWidget);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull,
          reason: 'the way out must stay actionable with nothing ticked');
    });

    testWidgets('offers a search when there was no link either', (tester) async {
      await openSheet(tester, resolution('see you at six'));
      expect(find.text('Search instead'), findsOneWidget);
    });

    testWidgets('shows no recommender field with nothing to attach it to',
        (tester) async {
      await openSheet(tester, resolution('see you at six'));
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('does not overflow', () {
    testWidgets('on a short screen with many candidates', (tester) async {
      await openSheet(
        tester,
        resolution('a long list', candidates: [
          for (var i = 0; i < 12; i++) candidate('Game Number $i', 0.8, id: i),
        ]),
        surface: const Size(360, 480),
      );

      expect(tester.takeException(), isNull);
      // The action stays reachable no matter how long the list is.
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('at large accessibility text', (tester) async {
      await openSheet(
        tester,
        resolution('play Hollow Knight and Hades', candidates: [
          candidate('Hollow Knight', 0.85, id: 1),
          candidate('Hades', 0.8, id: 2),
        ]),
        surface: const Size(360, 560),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  testWidgets('announces the plain method label, not a metaphor word',
      (tester) async {
    final handle = tester.ensureSemantics();
    await openSheet(
      tester,
      resolution('play Hollow Knight',
          candidates: [candidate('Hollow Knight', 0.85, id: 1)]),
    );

    expect(
      find.bySemanticsLabel(RegExp('Hollow Knight, From the text')),
      findsOneWidget,
    );
    handle.dispose();
  });
}
