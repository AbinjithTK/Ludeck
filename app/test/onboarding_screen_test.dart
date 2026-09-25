// Stage 7 verification: onboarding is shown once, skippable at every step,
// and re-openable from the profile at any time -- the three acceptance
// criteria this stage was filed against, and the direct fix for this
// project's own critique finding that nothing on screen taught the
// interaction.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ludeck/ui/onboarding/onboarding_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('hasSeenOnboarding persistence', () {
    test('false before onboarding has ever completed', () async {
      expect(await hasSeenOnboarding(), isFalse);
    });

    testWidgets('completing via Get started marks it seen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

      // Walk through every page rather than assume a count, so this does not
      // silently stop testing pages if one is added or removed later.
      while (find.text('Next').evaluate().isNotEmpty) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Get started'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(await hasSeenOnboarding(), isTrue);
    });

    testWidgets('tapping Skip on the first page also marks it seen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

      expect(await hasSeenOnboarding(), isFalse);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(await hasSeenOnboarding(), isTrue);
    });
  });

  group('re-opening', () {
    testWidgets('onDone is honoured instead of a pop when supplied, so it can '
        'be reused as a re-open route with nothing to pop back to', (tester) async {
      var doneCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onDone: () => doneCalled = true),
      ));

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(doneCalled, isTrue);
      // No navigator to pop, so this only passes if onDone -- not Navigator.pop
      // -- was actually used.
      expect(tester.takeException(), isNull);
    });

    testWidgets('pushed as a normal route (the profile re-open path), Skip '
        'pops back to the caller', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Your games, as a tree'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsOneWidget); // back on the caller screen.
      expect(find.text('Your games, as a tree'), findsNothing);
    });
  });
}
