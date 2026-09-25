// The rating sheet, on its own. No database, no store, no screen.
//
// Deliberately separate from rating_test.dart, which drives the same sheet
// through the real screen and a real sqflite database. A file that imports the
// repository is held to check.ps1 rule 8 (every pumpWidget inside runAsync),
// and these tests genuinely have no database to wait for -- so they live here
// rather than being wrapped in runAsync to satisfy a rule that is not about
// them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/harvest/rating_sheet.dart';

void main() {
  group('the sheet itself', () {
    testWidgets('a tap returns that rating and closes', (tester) async {
      RatingChoice? result;
      var returned = false;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showRatingSheet(context, title: 'Hades');
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Hades'), findsOneWidget);

      // One tap commits. A rating that needed a confirm button would be friction
      // on something the user is free to skip.
      await tester.tap(find.bySemanticsLabel('Rate 4 out of 5'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(result?.rating, 4);
    });

    testWidgets('skip returns null, which means write nothing', (tester) async {
      RatingChoice? result;
      var returned = false;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showRatingSheet(context, title: 'Hades');
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      // Null and RatingChoice(null) are different answers: skip writes nothing,
      // clear writes null. Collapsing them would make a skip erase a rating.
      expect(result, isNull);
    });

    testWidgets('remove is offered only when there is a rating to remove',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRatingSheet(context, title: 'Hades'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // A "remove" control on an unrated game is a button that does nothing.
      expect(find.text('Remove rating'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('remove returns a choice carrying null, not a skip',
        (tester) async {
      RatingChoice? result;
      var returned = false;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showRatingSheet(context, title: 'Hades', initial: 3);
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove rating'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(result, isNotNull, reason: 'remove is an instruction to write');
      expect(result!.rating, isNull);
    });

    testWidgets('an existing rating is shown filled', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRatingSheet(context, title: 'Hades', initial: 3),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Readable by form, not only colour: three filled against two outlined
      // survives colour blindness and a greyscale screenshot.
      expect(find.byIcon(Icons.star), findsNWidgets(3));
      expect(find.byIcon(Icons.star_border), findsNWidgets(2));
    });

    testWidgets('every star reads as a whole instruction', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRatingSheet(context, title: 'Hades'),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // "Star 3" would tell a screen-reader user nothing about what pressing it
      // does.
      for (var i = 1; i <= 5; i++) {
        expect(find.bySemanticsLabel('Rate $i out of 5'), findsOneWidget);
      }
    });
  });

}
