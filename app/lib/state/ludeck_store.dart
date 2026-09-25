import 'package:flutter/foundation.dart';

import '../data/enums.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// The collection's state, and the only thing the UI mutates it through.
///
/// Three rules this class exists to hold, taken from `docs/TASKS.md` Phase C:
///
/// 1. [items] is nullable, and null means THE FIRST READ HAS NOT FINISHED. That
///    is not the same as an empty collection and the two must not render the
///    same way. A spinner-free first paint depends on the distinction.
/// 2. Every mutation writes, re-reads, then notifies, in that order. The
///    database is the truth. Mutating the in-memory list and hoping it matches
///    is how a screen ends up lying about what was saved -- and a write that
///    failed silently is exactly the case that matters.
/// 3. No SQL here, and no entitlement SDK. This layer coordinates; it does not
///    know how anything is stored or sold.
///
/// A failed mutation lands on [error] rather than being thrown into the widget
/// tree. A `FutureBuilder`-less screen has nowhere to catch an exception from a
/// callback, so an uncaught one becomes a red screen for what may be a
/// recoverable write.
class LudeckStore extends ChangeNotifier {
  LudeckStore(this._repo);

  final Repository _repo;

  List<TreeItem>? _items;
  int _skipped = 0;
  bool _isLoading = false;
  Object? _error;
  bool _disposed = false;

  /// The collection. Null until the first read completes; never null after.
  List<TreeItem>? get items => _items;

  /// True while a read or a write is in flight.
  bool get isLoading => _isLoading;

  /// The last failure, or null. Cleared when an operation succeeds.
  Object? get error => _error;

  /// How many rows the last load could not interpret.
  ///
  /// Surfaced rather than swallowed: a row that disappears from the count with
  /// no explanation is how someone concludes the app lost their data.
  int get skipped => _skipped;

  /// True once the first read has come back, whatever it found.
  bool get hasLoaded => _items != null;

  /// Reads the whole collection.
  ///
  /// Safe to call repeatedly; every mutation ends with one.
  Future<void> load() => _guard(() async {
        final result = await _repo.loadDetailed();
        _items = result.items;
        _skipped = result.skipped;
      });

  Future<void> setProgress(int igdbId, Progress value) =>
      _write(() => _repo.setProgress(igdbId, value));

  Future<void> setOwnership(int igdbId, Ownership value) =>
      _write(() => _repo.setOwnership(igdbId, value));

  /// Ratings are 1 to 5, or null to clear. The repository throws on anything
  /// else rather than clamping, so a bad call surfaces on [error] here instead
  /// of being quietly rounded into a wrong value.
  Future<void> setRating(int igdbId, int? rating) =>
      _write(() => _repo.setRating(igdbId, rating));

  /// Shelving replaces delete. The row survives; it stops being shown.
  Future<void> shelve(int igdbId) => _write(() => _repo.shelve(igdbId));

  Future<void> unshelve(int igdbId) => _write(() => _repo.unshelve(igdbId));

  /// Adds a game, or leaves an existing entry untouched.
  ///
  /// The repository's upsert deliberately does not overwrite an existing entry:
  /// re-adding a game the user already owns must not reset its progress or its
  /// rating.
  Future<void> upsert(TreeItem item) => _write(() => _repo.upsert(item));

  /// Records where a game came from. One game can have several sources.
  Future<void> addSource(Source source) =>
      _write(() => _repo.addSource(source));

  /// Reads a game's sources. A plain read, so it does not re-load or notify.
  ///
  /// Not routed through [_write] on purpose: a source list is detail for one
  /// game, and re-reading the whole collection to fetch it would make opening a
  /// detail sheet cost a full load.
  Future<List<Source>> sourcesFor(int igdbId) => _repo.sourcesFor(igdbId);

  /// Runs a write, then re-reads, so the screen always shows what is stored.
  Future<void> _write(Future<void> Function() action) => _guard(() async {
        await action();
        final result = await _repo.loadDetailed();
        _items = result.items;
        _skipped = result.skipped;
      });

  /// The one place loading, error state and notification are handled.
  ///
  /// Catching broadly is deliberate here. This is the boundary between the
  /// database and a widget callback, and the alternative is an exception
  /// escaping into the framework from a button press.
  Future<void> _guard(Future<void> Function() body) async {
    _isLoading = true;
    _error = null;
    _notify();
    try {
      await body();
    } catch (e) {
      _error = e;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// A write can finish after the screen is gone -- a share applied during a
  /// lifecycle change, for instance -- and notifying a disposed notifier throws.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
