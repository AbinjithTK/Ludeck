import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/domain/entitlement.dart';
import 'package:ludeck/services/entitlement_service.dart';

void main() {
  late FakeEntitlementSource source;
  late EntitlementService service;

  setUp(() {
    source = FakeEntitlementSource();
    service = EntitlementService(source);
  });

  tearDown(() async => service.dispose());

  group('a free user', () {
    test('is refused every paid capability', () {
      for (final c in Capability.values) {
        expect(service.allowed(c), isFalse,
            reason: '$c is paid and this user has not paid');
      }
    });

    test('reports not pro', () {
      expect(service.isPro, isFalse);
    });
  });

  group('a paying user', () {
    test('is allowed every capability after a purchase', () async {
      final entitled = await service.purchase('pro_annual');
      expect(entitled, isTrue);
      for (final c in Capability.values) {
        expect(service.allowed(c), isTrue);
      }
    });

    test('is allowed everything when starting already entitled', () {
      final s = EntitlementService(FakeEntitlementSource(startPro: true));
      expect(s.isPro, isTrue);
      for (final c in Capability.values) {
        expect(s.allowed(c), isTrue);
      }
    });
  });

  group('cancelling is an ordinary outcome, not an error', () {
    test('a cancelled purchase returns false and does not throw', () async {
      source.cancelPurchases = true;
      expect(await service.purchase('pro_annual'), isFalse);
      expect(service.isPro, isFalse);
    });

    test('the user can still use every free part of the app afterwards', () async {
      source.cancelPurchases = true;
      await service.purchase('pro_annual');
      // Nothing in the app breaks. There is no Capability for collection size
      // or sharing, so no amount of declining changes access to either.
      expect(Capability.values.any((c) => c.name.contains('share')), isFalse);
      expect(service.isPro, isFalse);
    });
  });

  group('a failed purchase is distinct from a cancelled one', () {
    test('a genuine failure throws, so a screen can tell the two apart',
        () async {
      source.failPurchases = true;
      expect(() => service.purchase('pro_annual'), throwsStateError);
    });
  });

  group('restore', () {
    test('is callable without any purchase having been attempted', () async {
      await service.restore();
      expect(service.isPro, isFalse,
          reason: 'restore finds what exists; it does not grant access');
    });

    test('surfaces entitlement that already existed', () async {
      final s = EntitlementService(FakeEntitlementSource(startPro: true));
      await s.restore();
      expect(s.isPro, isTrue);
      await s.dispose();
    });
  });

  group('entitlement changes are observable', () {
    test('a listener is given the current value on subscribing', () async {
      expect(await service.changes.first, isFalse);
    });

    test('a purchase emits to listeners so a screen can rebuild', () async {
      final seen = <bool>[];
      final sub = service.changes.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await service.purchase('pro_annual');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, contains(true));
    });

    test('granting the same value twice does not emit twice', () async {
      final seen = <bool>[];
      final sub = service.changes.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      source.grant();
      source.grant();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen.where((v) => v == true).length, 1,
          reason: 'a duplicate emission would rebuild screens for nothing');
    });

    test('revoking emits, so a lapsed subscription closes access', () async {
      final s = FakeEntitlementSource(startPro: true);
      final svc = EntitlementService(s);
      final seen = <bool>[];
      final sub = svc.changes.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      s.revoke();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, contains(false));
      expect(svc.allowed(Capability.seasonSummary), isFalse,
          reason: 'a lapsed subscription must actually close the gate');
      await svc.dispose();
    });
  });

  group('the service holds no rules of its own', () {
    test('it agrees with the domain layer for every capability and both states',
        () {
      for (final c in Capability.values) {
        expect(service.allowed(c), allows(c, isPro: false));
      }
      final pro = EntitlementService(FakeEntitlementSource(startPro: true));
      for (final c in Capability.values) {
        expect(pro.allowed(c), allows(c, isPro: true));
      }
    });
  });
}
