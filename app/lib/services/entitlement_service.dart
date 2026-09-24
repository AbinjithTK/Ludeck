import 'dart:async';

import '../domain/entitlement.dart';

/// Where "is this person paying" comes from.
///
/// This interface exists so that exactly one class in the entire app ever
/// imports the RevenueCat package. When the real keys arrive, a
/// `RevenueCatEntitlementSource` implements this and nothing else changes: no
/// screen, no test, no widget. That is the whole reason for the indirection,
/// and it is also what lets the paywall be built and tested today, before the
/// store account exists at all.
///
/// Deliberately small. It answers one question and performs two actions. Any
/// temptation to add "what products are available" or "what is the price"
/// belongs in a catalogue type, not here: pricing is presentation and this is
/// permission.
abstract class EntitlementSource {
  /// Emits whenever entitlement changes, and emits the current value on listen
  /// so a late subscriber is never left with nothing.
  Stream<bool> get isPro;

  /// The value right now, for a synchronous read during a build.
  bool get isProNow;

  /// Re-checks with the store. Must be reachable WITHOUT a purchase: a person
  /// who already paid on another device has to be able to get their access
  /// back, and hiding restore behind a purchase button is how that becomes
  /// impossible.
  Future<void> restore();

  /// Attempts a purchase. Returns whether the user ended up entitled.
  ///
  /// A user cancelling is NOT an error and must not throw: cancelling is the
  /// most common outcome of showing a paywall and it is a normal answer, so it
  /// returns false like any other non-purchase.
  Future<bool> purchase(String productId);

  Future<void> dispose();
}

/// A local source with no network and no store.
///
/// Used for every test, and as the app's source until RevenueCat exists. It is
/// not a mock in the testing sense: it is a real, working implementation whose
/// backing store happens to be a variable, which means the paywall screen built
/// against it is genuinely exercised rather than stubbed out.
class FakeEntitlementSource implements EntitlementSource {
  FakeEntitlementSource({bool startPro = false}) : _isPro = startPro {
    // Seeded so a listener that subscribes later still receives current state.
    _controller = StreamController<bool>.broadcast(
      onListen: () => _controller.add(_isPro),
    );
  }

  late final StreamController<bool> _controller;
  bool _isPro;

  /// Set true to make [purchase] fail, so the paywall's failure path can be
  /// exercised without a store. Cancelling and failing are different things and
  /// both need testing.
  bool failPurchases = false;

  /// Set true to make [purchase] return false as though the user backed out.
  bool cancelPurchases = false;

  @override
  Stream<bool> get isPro => _controller.stream;

  @override
  bool get isProNow => _isPro;

  @override
  Future<void> restore() async {
    // A restore against a fake finds whatever the fake already holds. It
    // deliberately does not grant access: a restore that always succeeds would
    // make the paywall untestable in its most important state.
    _controller.add(_isPro);
  }

  @override
  Future<bool> purchase(String productId) async {
    if (failPurchases) {
      throw StateError('purchase failed: $productId');
    }
    if (cancelPurchases) return false;
    _set(true);
    return true;
  }

  /// Test affordance: move entitlement without going through a purchase, for
  /// setting up a scenario.
  void grant() => _set(true);

  void revoke() => _set(false);

  void _set(bool value) {
    if (_isPro == value) return;
    _isPro = value;
    _controller.add(value);
  }

  @override
  Future<void> dispose() => _controller.close();
}

/// The only thing screens talk to about permission.
///
/// It holds a source and forwards the free-or-paid decision to
/// `domain/entitlement.dart`. It contains no rules of its own on purpose: if
/// the rules lived here they would need a source to test, and the point of
/// keeping them in the domain layer is that they need nothing at all.
class EntitlementService {
  EntitlementService(this._source);

  final EntitlementSource _source;

  /// Current entitlement, for a synchronous check.
  bool get isPro => _source.isProNow;

  /// Entitlement changes, for a widget that should rebuild when a purchase
  /// lands.
  Stream<bool> get changes => _source.isPro;

  /// The question a screen actually asks. Note it takes a [Capability], not a
  /// boolean: a screen asking "is this person pro" is asking the wrong
  /// question, because it then has to know which features are paid, and that
  /// knowledge would end up copied into every screen that asks.
  bool allowed(Capability capability) =>
      allows(capability, isPro: isPro);

  /// Reachable without a purchase, always. See [EntitlementSource.restore].
  Future<void> restore() => _source.restore();

  /// Returns whether the user ended up entitled. False covers cancelling,
  /// which is ordinary and not a failure.
  Future<bool> purchase(String productId) => _source.purchase(productId);

  Future<void> dispose() => _source.dispose();
}
