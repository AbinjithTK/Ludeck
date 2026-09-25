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
  List<Branch> _branches = const [];
  Map<int, List<int>> _placements = const {};
  int _skipped = 0;
  bool _isLoading = false;
  Object? _error;
  bool _disposed = false;

  /// The collection. Null until the first read completes; never null after.
  List<TreeItem>? get items => _items;

  /// The user's branches, in their own order. Empty is the normal starting
  /// state: nothing seeds a branch, so a new install has none.
  List<Branch> get branches => _branches;

  /// Which game ids hang on which branch id.
  ///
  /// Read in the same pass as the collection so the two cannot disagree. A view
  /// that loaded them separately could render a branch count that did not match
  /// the rows under it.
  Map<int, List<int>> get placements => _placements;

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
  Future<void> load() => _guard(_read);

  /// The single read used by [load] and by every mutation.
  ///
  /// Branches and placements are read here, with the items, deliberately: a view
  /// grouping rows by branch needs all three to describe the same instant.
  Future<void> _read() async {
    final result = await _repo.loadDetailed();
    final branches = await _repo.branches();
    final placements = await _repo.placements();
    _items = result.items;
    _skipped = result.skipped;
    _branches = branches;
    _placements = placements;
  }

  /// Creates a branch at the END of the list, then re-reads.
  ///
  /// The sort order is computed rather than left to the repository's default of
  /// 0. With every branch at 0 the order falls back to insertion id, which looks
  /// correct until the user reorders: `reorderBranches` then writes real 0..n-1
  /// values, and the next new branch would arrive at position 0 and jump to the
  /// front of a list the user had just arranged.
  Future<void> createBranch(String name) => _write(() async {
        final existing = await _repo.branches();
        final next = existing.isEmpty
            ? 0
            : existing.map((b) => b.sortOrder).reduce((a, b) => a > b ? a : b) +
                1;
        await _repo.createBranch(name, sortOrder: next);
      });

  Future<void> renameBranch(int id, String name) =>
      _write(() => _repo.renameBranch(id, name));

  /// Removes a branch. The games on it survive and become unplaced.
  Future<void> deleteBranch(int id) => _write(() => _repo.deleteBranch(id));

  Future<void> reorderBranches(List<int> idsInOrder) =>
      _write(() => _repo.reorderBranches(idsInOrder));

  Future<void> place(int igdbId, int branchId) =>
      _write(() => _repo.place(igdbId, branchId));

  Future<void> unplace(int igdbId, int branchId) =>
      _write(() => _repo.unplace(igdbId, branchId));

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

  /// Adds a shared game AND records where it came from, with ONE re-read.
  ///
  /// Exists because calling `upsert` then `addSource` costs two full reload
  /// cycles per game, and the collection is briefly in a state where the game
  /// exists with no source. Batching them is both faster and the honest unit of
  /// work: a shared game and its provenance are one event.
  ///
  /// The source is still written when the game was already present. That is the
  /// point: re-encountering a game is information, and the entry is left alone.
  Future<void> addShared(TreeItem item, Source source) => _write(() async {
        await _repo.upsert(item);
        await _repo.addSource(source);
      });

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
        await _read();
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
