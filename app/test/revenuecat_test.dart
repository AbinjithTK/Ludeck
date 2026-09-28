import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/services/entitlement_service.dart';
import 'package:ludeck/services/revenuecat_entitlement_source.dart';
import 'package:ludeck/ui/paywall/paywall_screen.dart';

/// The RevenueCat wiring that can be proven without a store: product-id
/// mapping, the store-less fallback, and the paywall showing the store's own
/// prices and trials. A real purchase is proven on a device with a Play
/// licence tester (docs/SUBMISSION.md), not here.
void main() {
  group('baseProductId', () {
    test('drops the Google base plan after the colon', () {
      expect(baseProductId('pro_annual:yearly'), 'pro_annual');
      expect(baseProductId('pro_monthly:monthly-base'), 'pro_monthly');
    });

    test('leaves a one-time product as it is', () {
      expect(baseProductId('pro_lifetime'), 'pro_lifetime');
    });

    test('the product ids are the frozen three', () {
      expect({...kSubscriptionProducts, ...kOneTimeProducts},
          {'pro_annual', 'pro_monthly', 'pro_lifetime'});
      expect(kProEntitlement, 'pro');
    });
  });

  group('a build with no store', () {
    test('nobody is Pro and a purchase fails instead of granting it', () async {
      final s = EntitlementService(UnavailableEntitlementSource());
      expect(s.isPro, isFalse);
      await expectLater(s.purchase('pro_annual'), throwsStateError);
      expect(s.isPro, isFalse, reason: 'never Pro for free');
      await s.restore();
      expect(s.isPro, isFalse);
      expect(await s.offers(), isEmpty);
    });

    test('a keyless build resolves to the store-less source, not the fake',
        () async {
      final s = await resolveEntitlementService('');
      await expectLater(s.purchase('pro_annual'), throwsStateError);
      expect(s.isPro, isFalse);
    });
  });

  group('paywall with store prices', () {
    Future<EntitlementService> pump(
        WidgetTester tester, Map<String, StoreOffer> offers) async {
      final source = FakeEntitlementSource()..storeOffers = offers;
      final service = EntitlementService(source);
      await tester.pumpWidget(MaterialApp(home: PaywallScreen(service: service)));
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('shows the store price in the buyer currency', (tester) async {
      await pump(tester, const {
        'pro_annual': StoreOffer(price: '₹1,650.00', trialDays: 7),
        'pro_monthly': StoreOffer(price: '₹250.00'),
      });
      expect(find.text('₹1,650.00'), findsOneWidget);
      expect(find.text('₹250.00'), findsOneWidget);
      // Not reported by the store yet: the fallback stands.
      expect(find.text('\$39.99'), findsOneWidget);
    });

    testWidgets('promises only the trial the store reports', (tester) async {
      await pump(tester, const {'pro_annual': StoreOffer(price: '\$19.99', trialDays: 7)});
      expect(find.text('Start 7 days free'), findsOneWidget);
      expect(find.text('Start 30 days free'), findsNothing);
    });

    testWidgets('no trial in the store means no trial on the button',
        (tester) async {
      await pump(tester, const {'pro_annual': StoreOffer(price: '\$19.99')});
      expect(find.text('Continue'), findsOneWidget);
      expect(find.textContaining('days free'), findsNothing);
    });
  });
}
