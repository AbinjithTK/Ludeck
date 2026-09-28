import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'entitlement_service.dart';

/// The one file in the app that imports RevenueCat (entitlement_service.dart
/// explains why there is exactly one).
///
/// Entitlement id and product ids are frozen in DECISIONS.md / SUBMISSION.md:
/// entitlement `pro`, products `pro_annual` and `pro_monthly` (subscriptions)
/// and `pro_lifetime` (a one-time purchase).
const kProEntitlement = 'pro';
const kSubscriptionProducts = ['pro_annual', 'pro_monthly'];
const kOneTimeProducts = ['pro_lifetime'];

/// The entitlement source for a build that has a RevenueCat key.
///
/// The key is RevenueCat's PUBLIC Google SDK key (`goog_...`). It is supplied
/// at build time, never committed:
///   flutter build appbundle --dart-define=REVENUECAT_GOOGLE_KEY=goog_...
/// A build without it runs on [FakeEntitlementSource] (see
/// [resolveEntitlementService]), which is also what every test uses.
class RevenueCatEntitlementSource implements EntitlementSource {
  RevenueCatEntitlementSource._() {
    _controller = StreamController<bool>.broadcast(
      onListen: () => _controller.add(_isPro),
    );
  }

  late final StreamController<bool> _controller;
  bool _isPro = false;

  /// Store products by our product id. Google reports a subscription as
  /// `pro_annual:<base-plan>`, so lookups go through [baseProductId].
  final Map<String, StoreProduct> _products = {};

  /// Configures the SDK and reads the current entitlement once. Throws if the
  /// SDK cannot be configured; the resolver falls back to the fake then.
  static Future<RevenueCatEntitlementSource> create(String apiKey) async {
    final source = RevenueCatEntitlementSource._();
    if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    Purchases.addCustomerInfoUpdateListener(source._onCustomerInfo);
    // Neither read may hold up the app's first frame: both go to the network.
    unawaited(source._refresh());
    unawaited(source._loadProducts());
    return source;
  }

  void _onCustomerInfo(CustomerInfo info) => _set(isProIn(info));

  Future<void> _refresh() async {
    try {
      _set(isProIn(await Purchases.getCustomerInfo()));
    } catch (e) {
      // Offline at launch is ordinary. The cached state (if any) arrives
      // through the listener; this only means "not re-checked yet".
      debugPrint('RevenueCat: customer info unavailable: $e');
    }
  }

  Future<void> _loadProducts() async {
    try {
      final subs = await Purchases.getProducts(kSubscriptionProducts);
      final once = await Purchases.getProducts(kOneTimeProducts,
          productCategory: ProductCategory.nonSubscription);
      for (final p in [...subs, ...once]) {
        _products[baseProductId(p.identifier)] = p;
      }
    } catch (e) {
      debugPrint('RevenueCat: products unavailable: $e');
    }
  }

  @override
  Stream<bool> get isPro => _controller.stream;

  @override
  bool get isProNow => _isPro;

  @override
  Future<Map<String, StoreOffer>> offers() async {
    if (_products.isEmpty) await _loadProducts();
    return {
      for (final e in _products.entries)
        e.key: StoreOffer(
          price: e.value.priceString,
          trialDays: _trialDays(e.value.defaultOption?.freePhase?.billingPeriod),
        ),
    };
  }

  @override
  Future<void> restore() async {
    // Throws on a network/store failure, which the paywall reports as "could
    // not check". An empty result is not an error: it is "nothing found".
    _set(isProIn(await Purchases.restorePurchases()));
  }

  @override
  Future<bool> purchase(String productId) async {
    var product = _products[productId];
    if (product == null) {
      await _loadProducts();
      product = _products[productId];
    }
    if (product == null) {
      throw StateError('store product not available: $productId');
    }
    try {
      final result =
          await Purchases.purchase(PurchaseParams.storeProduct(product));
      final pro = isProIn(result.customerInfo);
      _set(pro);
      return pro;
    } on PlatformException catch (e) {
      // Backing out is the most common answer to a paywall, not a failure
      // (EntitlementSource.purchase).
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

  void _set(bool value) {
    if (_isPro == value) return;
    _isPro = value;
    _controller.add(value);
  }

  @override
  Future<void> dispose() async {
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    await _controller.close();
  }
}

/// Whether [info] carries an active `pro` entitlement.
bool isProIn(CustomerInfo info) =>
    info.entitlements.active.containsKey(kProEntitlement);

/// `pro_annual:yearly` -> `pro_annual`. Google Play subscriptions are
/// reported with their base plan after a colon; one-time products are not.
String baseProductId(String storeIdentifier) {
  final i = storeIdentifier.indexOf(':');
  return i < 0 ? storeIdentifier : storeIdentifier.substring(0, i);
}

int? _trialDays(Period? p) {
  if (p == null || p.value <= 0) return null;
  return switch (p.unit) {
    PeriodUnit.day => p.value,
    PeriodUnit.week => p.value * 7,
    PeriodUnit.month => p.value * 30,
    PeriodUnit.year => p.value * 365,
    _ => null,
  };
}

/// The app's entitlement service: RevenueCat when this build carries a key
/// AND runs on Android (the only store this submission ships to).
///
/// Otherwise [UnavailableEntitlementSource], never the fake: the fake grants
/// Pro on any "purchase", so a keyless build falling back to it would hand
/// the paid features out for free. A key that fails to configure falls back
/// the same way, so a store outage can never stop the app from opening.
Future<EntitlementService> resolveEntitlementService(String googleKey) async {
  if (googleKey.isEmpty ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android) {
    return EntitlementService(UnavailableEntitlementSource());
  }
  try {
    return EntitlementService(await RevenueCatEntitlementSource.create(googleKey)
        .timeout(const Duration(seconds: 5)));
  } catch (e) {
    debugPrint('RevenueCat: not configured, running without purchases: $e');
    return EntitlementService(UnavailableEntitlementSource());
  }
}
