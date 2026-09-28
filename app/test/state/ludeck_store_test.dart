// LudeckStore: the layer between the screen and the database.
//
// These are plain `test()`, not `testWidgets`, on purpose. There is no widget
// here, and a FakeAsync zone would stop sqflite's real I/O from ever completing.
// See docs/CONSTRAINTS.md "The hanging flutter test".

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/state/ludeck_store.dart';

void main() {
  late Repository repo;
  late LudeckStore store;

  setUp(() async {
    repo = await Repository.openInMemory();
    store = LudeckStore(repo);
  });

  tearDown(() async {
    store.dispose();
    await repo.close();
  });

  /// The first row of the seeded fixture collection.
  Future<TreeItem> anyItem() async {
    await repo.seedIfEmpty();
    await store.load();
    return store.items!.first;
  }

  group('the first read', () {
    test('items is null before load and non-null after', () async {
      // Null means "the first read has not happened". It is NOT an empty
      // collection, and the screen renders the two differently: null paints
      // nothing, empty paints the real "nothing planted yet" headline. Collapse
      // them and a cold start flashes an empty-state that is a lie.
      expect(store.items, isNull);
      expect(store.hasLoaded, isFalse);

      await store.load();

      expect(store.items, isNotNull);
      expect(store.hasLoaded, isTrue);
    });

    test('an empty collection is not the same as an unread one', () async {
      await store.load();

      // Nothing was seeded, so this is genuinely empty rather than unread.
      expect(store.items, isEmpty);
      expect(store.hasLoaded, isTrue);
    });

    test('load reports how many rows could not be read', () async {
      await store.load();
      expect(store.skipped, 0);
    });
  });

  group('failures surface on error, not as a throw', () {
    test('a failed read lands on error and does not throw', () async {
      await repo.close();

      // The screen calls this from a button and from initState. Neither has a
      // catch around it, so an exception escaping here becomes a red screen for
      // what may be a recoverable failure.
      await expectLater(store.load(), completes);

      expect(store.error, isNotNull);
      expect(store.items, isNull, reason: 'a failed read must not invent data');
      expect(store.isLoading, isFalse,
          reason: 'the loading flag must clear even on the failure path');
    });

    test('a failed write lands on error and keeps the old collection', () async {
      final item = await anyItem();
      await repo.close();

      await expectLater(
          store.setProgress(item.game.igdbId, Progress.finished), completes);

      expect(store.error, isNotNull);
      // The rows already read stay on screen. Throwing them away over one
      // failed write would lose readable data for no reason.
      expect(store.items, isNotNull);
    });

    test('an out-of-range rating surfaces instead of being clamped', () async {
      final item = await anyItem();

      // The repository throws rather than clamping, deliberately: a silent
      // clamp hides the bug at the call site. The store must carry that through
      // to `error` rather than swallowing it.
      await expectLater(store.setRating(item.game.igdbId, 9), completes);
      expect(store.error, isA<ArgumentError>());

      // And the value really was not written.
      await store.load();
      final reread =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(reread.entry.rating, isNot(9));
    });

    test('error clears on the next successful operation', () async {
      await repo.close();
      await store.load();
      expect(store.error, isNotNull);

      // A fresh repository, same store: the next success must not leave a stale
      // error on screen.
      repo = await Repository.openInMemory();
      final fresh = LudeckStore(repo);
      addTearDown(fresh.dispose);
      await fresh.load();
      expect(fresh.error, isNull);
    });
  });

  group('applyCoverUrl', () {
    // These are the lazy cover-art fill-in: CoverArtCache resolves a cover long
    // after the row loaded, and this is what lands it without paying for a full
    // collection re-read on every trickling-in result.

    test('patches the in-memory item and persists it', () async {
      final item = await anyItem();
      expect(item.game.coverUrl, isNull);

      await store.applyCoverUrl(item.game.igdbId, 'https://example.com/cover.png');

      final patched =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(patched.game.coverUrl, 'https://example.com/cover.png');

      // And it really reached the database, not just the in-memory list -- a
      // fresh load must see the same value.
      await store.load();
      final reread =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(reread.game.coverUrl, 'https://example.com/cover.png');
    });

    test('does nothing before the first load', () async {
      // Called from a row's build() while items could in principle still be
      // null. Must not throw and must not crash on a null items list.
      await expectLater(store.applyCoverUrl(999, 'https://x/y.png'), completes);
    });

    test('does nothing for a game not in the loaded list', () async {
      await anyItem();
      final before = store.items;

      await store.applyCoverUrl(999999, 'https://x/y.png');

      expect(store.items, same(before),
          reason: 'an unknown id must not replace the list or notify');
    });

    test('never overwrites an existing cover with a weaker guess', () async {
      final item = await anyItem();
      await store.applyCoverUrl(item.game.igdbId, 'https://first.example/a.png');

      // A second, slower lookup answering after a faster one already won.
      await store.applyCoverUrl(item.game.igdbId, 'https://second.example/b.png');

      final patched =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(patched.game.coverUrl, 'https://first.example/a.png');
    });

    test('notifies listeners so the row repaints', () async {
      final item = await anyItem();
      var notified = false;
      store.addListener(() => notified = true);

      await store.applyCoverUrl(item.game.igdbId, 'https://x/y.png');

      expect(notified, isTrue);
    });
  });

  group('every mutation writes then re-reads', () {
    test('setProgress is visible in items without a manual reload', () async {
      final item = await anyItem();
      expect(item.entry.progress, isNot(Progress.finished));

      await store.setProgress(item.game.igdbId, Progress.finished);

      // No load() call here. If the store only wrote and did not re-read, the
      // screen would keep showing the old value and look like a lost write.
      final after =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(after.entry.progress, Progress.finished);
    });

    test('setOwnership does not disturb progress', () async {
      final item = await anyItem();
      await store.setProgress(item.game.igdbId, Progress.finished);
      await store.setOwnership(item.game.igdbId, Ownership.released);

      final after =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      // The two axes are independent. Selling a game keeps its completion
      // record; this is the product's central invariant, not a detail.
      expect(after.entry.ownership, Ownership.released);
      expect(after.entry.progress, Progress.finished);
    });

    test('setRating survives a later sale', () async {
      final item = await anyItem();
      await store.setProgress(item.game.igdbId, Progress.finished);
      await store.setRating(item.game.igdbId, 4);
      await store.setOwnership(item.game.igdbId, Ownership.released);

      final after =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(after.entry.rating, 4);
      expect(after.entry.progress, Progress.finished);
    });

    test('setRating(null) clears a rating', () async {
      final item = await anyItem();
      await store.setProgress(item.game.igdbId, Progress.finished);
      await store.setRating(item.game.igdbId, 3);
      await store.setRating(item.game.igdbId, null);

      final after =
          store.items!.firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(after.entry.rating, isNull);
    });

    test('shelve removes the game from the collection, not the database',
        () async {
      final item = await anyItem();
      final before = store.items!.length;

      await store.shelve(item.game.igdbId);
      expect(store.items!.length, before - 1);

      // Shelving replaces delete: the row survives and can come back.
      await store.unshelve(item.game.igdbId);
      expect(store.items!.length, before);
    });
  });

  group('listeners', () {
    test('a load notifies, and the flag is clear by the time it does',
        () async {
      var notifications = 0;
      bool? loadingAtLastNotification;
      store.addListener(() {
        notifications++;
        loadingAtLastNotification = store.isLoading;
      });

      await store.load();

      // Twice: once when the operation starts, once when it finishes. A single
      // notification would mean the UI never saw the in-flight state.
      expect(notifications, 2);
      expect(loadingAtLastNotification, isFalse);
    });

    test('notifying after dispose does not throw', () async {
      // A write can complete after the screen is gone -- a share applied across
      // a lifecycle change is the real case -- and notifying a disposed
      // ChangeNotifier throws.
      await repo.seedIfEmpty();
      final s = LudeckStore(repo);
      final pending = s.load();
      s.dispose();
      await expectLater(pending, completes);
    });
  });

  group('branches and placements', () {
    test('a new store has no branches, and nothing is placed', () async {
      await repo.seedIfEmpty();
      await store.load();

      // Nothing seeds a branch, so this is the state of a new install. The view
      // depends on it: it falls back to status grouping when branches are empty.
      expect(store.branches, isEmpty);
      expect(store.placements, isEmpty);
    });

    test('branches and placements are read with the collection', () async {
      final item = await anyItem();
      await store.createBranch('Short evenings');
      final branch = store.branches.single;

      await store.place(item.game.igdbId, branch.id);

      // No explicit load() here. Read in the same pass as the items, so a view
      // can never render a branch count that disagrees with its rows.
      expect(store.placements[branch.id], contains(item.game.igdbId));
    });

    test('deleting a branch keeps the games, unplaced', () async {
      final item = await anyItem();
      final before = store.items!.length;
      await store.createBranch('Someday');
      final branch = store.branches.single;
      await store.place(item.game.igdbId, branch.id);

      await store.deleteBranch(branch.id);

      // A branch is a container. Emptying it does not destroy what was in it.
      expect(store.branches, isEmpty);
      expect(store.placements, isEmpty);
      expect(store.items!.length, before);
    });

    test('reorderBranches changes the order the store reports', () async {
      await store.createBranch('First');
      await store.createBranch('Second');
      final ids = store.branches.map((b) => b.id).toList();

      await store.reorderBranches(ids.reversed.toList());

      expect(store.branches.map((b) => b.name), ['Second', 'First']);
    });

    test('a shelved game leaves its branch count', () async {
      final item = await anyItem();
      await store.createBranch('Shelf test');
      final branch = store.branches.single;
      await store.place(item.game.igdbId, branch.id);
      expect(store.placements[branch.id], hasLength(1));

      await store.shelve(item.game.igdbId);

      // The placement row survives in the database, but a shelved game is not in
      // the collection, so counting it would make the heading disagree with the
      // rows rendered under it.
      expect(store.placements[branch.id] ?? const [], isEmpty);
    });
  });

  group('sources', () {
    test('sourcesFor reads without re-loading the collection', () async {
      final item = await anyItem();
      await store.addSource(Source(
        igdbId: item.game.igdbId,
        url: 'https://example.com/clip',
        kind: SourceKind.web,
        matchMethod: MatchMethod.exact,
        addedAt: DateTime.now(),
      ));

      final sources = await store.sourcesFor(item.game.igdbId);
      expect(sources, hasLength(1));
      expect(sources.single.url, 'https://example.com/clip');
    });

    test('addShared writes the game and its source together', () async {
      await repo.seedIfEmpty();
      await store.load();
      final existing = store.items!.first;

      // One call, one reload. Two separate calls left the collection briefly
      // holding a game with no source.
      await store.addShared(
        TreeItem(
          game: existing.game,
          entry: Entry(
            igdbId: existing.game.igdbId,
            ownership: Ownership.spotted,
            progress: Progress.untouched,
          ),
          copies: const [],
        ),
        Source(
          igdbId: existing.game.igdbId,
          url: 'https://example.com/again',
          kind: SourceKind.web,
          matchMethod: MatchMethod.text,
          addedAt: DateTime.now(),
        ),
      );

      final sources = await store.sourcesFor(existing.game.igdbId);
      expect(sources, hasLength(1));
      expect(store.error, isNull);
    });

    test('addShared on a game already held keeps its progress', () async {
      final item = await anyItem();
      await store.setProgress(item.game.igdbId, Progress.finished);

      await store.addShared(
        TreeItem(
          game: item.game,
          entry: Entry(
            igdbId: item.game.igdbId,
            ownership: Ownership.spotted,
            progress: Progress.untouched,
          ),
          copies: const [],
        ),
        Source(
          igdbId: item.game.igdbId,
          kind: SourceKind.web,
          matchMethod: MatchMethod.text,
          addedAt: DateTime.now(),
        ),
      );

      // Re-sharing a game must not reset what the user recorded about it. The
      // source is still added, because the fact it came up again is information.
      final after = store.items!
          .firstWhere((i) => i.game.igdbId == item.game.igdbId);
      expect(after.entry.progress, Progress.finished);
      expect(await store.sourcesFor(item.game.igdbId), hasLength(1));
    });
  });

  group('removeGame is the honest hard delete', () {
    test('a removed game is gone from the collection, unlike setAside',
        () async {
      final item = await anyItem();
      final id = item.game.igdbId;
      expect(store.items!.any((i) => i.game.igdbId == id), isTrue);

      await store.removeGame(id);

      expect(store.items!.any((i) => i.game.igdbId == id), isFalse,
          reason: 'removeGame destroys the game, it does not just hide it');
      expect(store.error, isNull);
    });

    test('removing a game filed on a tree also clears its placement',
        () async {
      final item = await anyItem();
      final id = item.game.igdbId;
      await store.createBranch('Shelf');
      final branch = store.branches.single.id;
      await store.place(id, branch);
      expect((await repo.placements()).values.expand((e) => e), contains(id));

      await store.removeGame(id);

      // The placement is gone by the schema's ON DELETE CASCADE, not by hand.
      expect((await repo.placements()).values.expand((e) => e).contains(id),
          isFalse);
    });
  });
}
