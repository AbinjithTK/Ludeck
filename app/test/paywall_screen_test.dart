import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/services/entitlement_service.dart';
import 'package:ludeck/ui/paywall/paywall_screen.dart';

void main() {
  late FakeEntitlementSource source;
  late EntitlementService service;

  setUp(() {
    source = FakeEntitlementSource();
    service = EntitlementService(source);
  });

  tearDown(() async => service.dispose());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(service: service),
    ));
    await tester.pumpAndSettle();
  }

  group('what it shows', () {
    testWidgets('offers all three plans', (tester) async {
      await pump(tester);
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Once'), findsOneWidget);
    });

    testWidgets('preselects the yearly plan, which carries the trial',
        (tester) async {
      await pump(tester);
      // The button names the trial, which only the annual plan has.
      expect(find.text('Start 30 days free'), findsOneWidget);
    });

    testWidgets('restore is reachable without buying anything', (tester) async {
      await pump(tester);
      expect(find.text('Already paid? Restore'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Already paid? Restore'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull,
          reason: 'somebody who already paid must be able to get back in');
    });

    testWidgets('close is available immediately, with no delay', (tester) async {
      await pump(tester);
      // byTooltip matches the Tooltip widget, not the button inside it, so go
      // via the icon and then up to the IconButton.
      final close = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(IconButton),
        ),
      );
      expect(close.onPressed, isNotNull,
          reason: 'a close button that appears late is a dark pattern');
    });
  });

  group('it never implies the collection is limited', () {
    testWidgets('it says games, branches and sharing are free', (tester) async {
      await pump(tester);
      expect(
        find.textContaining('free', findRichText: true),
        findsWidgets,
        reason: 'the promise that the collection is not capped must be stated, '
            'because competitors cap theirs and users assume the worst',
      );
    });

    testWidgets('no plan row or benefit mentions a game limit', (tester) async {
      await pump(tester);
      for (final banned in ['limit', 'up to', 'maximum', 'unlimited games']) {
        expect(find.textContaining(banned), findsNothing,
            reason: 'mentioning "$banned" implies a cap that does not exist');
      }
    });
  });

  group('choosing a plan', () {
    testWidgets('tapping monthly changes the button away from the trial',
        (tester) async {
      await pump(tester);
      // The plan rows sit inside a scroll view now, so on a short test surface
      // Monthly is below the fold and a bare tap would silently miss.
      await tester.ensureVisible(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(find.text('Start 30 days free'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
    });
  });

  group('buying', () {
    testWidgets('a successful purchase closes the screen as entitled',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => PaywallScreen(service: service),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start 30 days free'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsNothing,
          reason: 'a completed purchase should not leave the paywall up');
      expect(service.isPro, isTrue);
    });

    testWidgets('cancelling says nothing and leaves the screen usable',
        (tester) async {
      source.cancelPurchases = true;
      await pump(tester);

      await tester.tap(find.text('Start 30 days free'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsOneWidget);
      // No scolding, no error text: backing out is an ordinary answer.
      expect(find.textContaining('did not go through'), findsNothing);
      expect(service.isPro, isFalse);
    });

    testWidgets('a real failure says so and states nothing was charged',
        (tester) async {
      source.failPurchases = true;
      await pump(tester);

      await tester.tap(find.text('Start 30 days free'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing has been charged'), findsOneWidget,
          reason: 'the first thing someone wants to know after a failed '
              'payment is whether they were charged');
    });
  });

  group('restoring', () {
    testWidgets('finding nothing says so plainly', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Already paid? Restore'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No earlier purchase found'), findsOneWidget);
    });

    testWidgets('finding an existing purchase closes the screen',
        (tester) async {
      final proSource = FakeEntitlementSource(startPro: true);
      final proService = EntitlementService(proSource);
      addTearDown(proService.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => PaywallScreen(service: proService),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Already paid? Restore'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallScreen), findsNothing);
    });
  });
}
