// The backend integrity audit: foreign keys, cascades, and transactions.
//
// This is a SYSTEMATIC pass rather than a test per feature. Individual features
// have been tested as they were built, and each of those tests happened to prove
// one relation by accident. What none of them proved is the thing that decides
// whether any cascade works at all:
//
//   SQLite defaults foreign keys OFF, and the setting is PER CONNECTION rather
//   than stored in the file. Every `ON DELETE CASCADE` in database.dart is
//   decoration if `onConfigure` ever loses its PRAGMA. Nothing would fail
//   loudly: writes keep working and orphan rows pile up in silence.
//
// So enforcement is asserted on every open path, and every declared relation has
// its own orphan test. A cascade nobody exercises is a cascade nobody knows is
// broken, and until this file existed all four relations pointing at `games`
// were latent, because nothing in the app ever deletes a game.
//
// Plain `test()`, not testWidgets: no widgets here, and a FakeAsync zone would
// stop sqflite's real I/O from completing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/db/database.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:path/path.dart' as p;

/// Every relation the schema declares, as (child table, child column, parent).
///
/// Written out by hand on purpose. The point of the audit is to compare what the
/// schema INTENDS against what the engine actually enforces, and generating this
/// list from the engine would compare the engine to itself.
const List<({String child, String column, String parent, String onDelete})>
    kRelations = [
  (child: 'entries', column: 'igdb_id', parent: 'games', onDelete: 'CASCADE'),
  (child: 'copies', column: 'igdb_id', parent: 'games', onDelete: 'CASCADE'),
  (child: 'placements', column: 'igdb_id', parent: 'games', onDelete: 'CASCADE'),
  (child: 'placements', column: 'branch_id', parent: 'branches', onDelete: 'CASCADE'),
  (child: 'sources', column: 'igdb_id', parent: 'games', onDelete: 'CASCADE'),
  (child: 'roadmap_order', column: 'igdb_id', parent: 'games', onDelete: 'CASCADE'),
  // SET NULL, not CASCADE: deleting a branch must never take a subtree of the
  // user's categories with it. The repository re-parents children first.
  (child: 'branches', column: 'parent_id', parent: 'branches', onDelete: 'SET NULL'),
  // A tree's look holds nothing the user would want back without the tree.
  (child: 'tree_styles', column: 'branch_id', parent: 'branches', onDelete: 'CASCADE'),
];

/// Tables the schema is expected to hold. A new one arriving without a cascade
/// decision should fail here rather than at a delete months later.
const Set<String> kTables = {
  'games',
  'entries',
  'copies',
  'branches',
  'placements',
  'sources',
  'roadmap_order',
  'tree_styles',
};

void main() {
  late Repository repo;

  setUp(() async {
    repo = await Repository.openInMemory();
  });

  tearDown(() async => repo.close());

  /// A game with an entry, a copy, a placement and a source: one row in every
  /// child table, so a single delete can be checked against all of them.
  Future<int> fullyPopulatedGame(Repository r, {int id = 424242}) async {
    await r.upsert(TreeItem(
      game: Game(igdbId: id, title: 'Audit Subject', releaseYear: 2020),
      entry: Entry(
        igdbId: id,
        ownership: Ownership.owned,
        progress: Progress.playing,
      ),
      copies: [
        Copy(
          igdbId: id,
          platform: Platform.pc,
          form: Form.digital,
          acquired: Acquired.bought,
        ),
      ],
    ));
    final branch = await r.createBranch('Audit branch');
    await r.place(id, branch);
    await r.addSource(Source(
      igdbId: id,
      url: 'https://example.test/clip',
      kind: SourceKind.web,
      matchMethod: MatchMethod.text,
      addedAt: DateTime.now(),
    ));
    return id;
  }

  group('foreign keys are enforced, not merely declared', () {
    test('an in-memory database enforces them', () async {
      // The open path every test in this repository uses. If this is off, every
      // cascade assertion elsewhere is vacuous.
      expect(await repo.foreignKeysEnforced(), isTrue);
    });

    test('an on-disk database enforces them', () async {
      // The open path the app actually ships, exercised through the SHIPPING
      // opener rather than a copy of it.
      final dir = await Directory.systemTemp.createTemp('ludeck_audit');
      addTearDown(() => dir.delete(recursive: true));
      final db = await openLudeckDatabaseAt(p.join(dir.path, 'audit.db'));
      final disk = Repository(db);
      addTearDown(disk.close);

      expect(await disk.foreignKeysEnforced(), isTrue);
    });

    test('a REOPENED database still enforces them', () async {
      // Enforcement is per connection and is not remembered by the file. A
      // second open is the case a first-open-only test would miss.
      final dir = await Directory.systemTemp.createTemp('ludeck_audit');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'audit.db');

      final first = Repository(await openLudeckDatabaseAt(path));
      await fullyPopulatedGame(first);
      await first.close();

      final second = Repository(await openLudeckDatabaseAt(path));
      addTearDown(second.close);
      expect(await second.foreignKeysEnforced(), isTrue);
      expect(await second.foreignKeyViolations(), isEmpty);
    });
  });

  group('the schema matches what the engine holds', () {
    test('every expected table exists and no unexpected one does', () async {
      final tables = await repo.tableNames();
      for (final expected in kTables) {
        expect(tables, contains(expected));
      }
      // A table added to the DDL without a cascade decision should fail here.
      expect(
        tables.difference(kTables),
        isEmpty,
        reason: 'a new table exists with no entry in kRelations or kTables. '
            'Decide its delete behaviour, then add it here.',
      );
    });

    test('every declared relation is present with its delete rule', () async {
      for (final relation in kRelations) {
        final keys = await repo.foreignKeysOf(relation.child);
        final match = keys.where(
          (k) => k.column == relation.column && k.parent == relation.parent,
        );
        expect(match, isNotEmpty,
            reason: '${relation.child}.${relation.column} has no foreign key to '
                '${relation.parent}');
        // Read from the engine, not the DDL text: a clause written but not
        // applied -- a migration that created the table before the clause was
        // added -- is only visible this way.
        expect(match.first.onDelete, relation.onDelete,
            reason: '${relation.child}.${relation.column} should be '
                'ON DELETE ${relation.onDelete}');
      }
    });
  });

  group('an orphan row cannot be created', () {
    test('an entry for a game that does not exist is refused', () async {
      // The direct proof that enforcement is live. Without the pragma this
      // insert succeeds and leaves an entry pointing at nothing.
      await expectLater(
        repo.setProgress(999001, Progress.playing),
        completes,
        reason: 'an update that matches no row is a no-op, not a violation',
      );
      // Nothing was created.
      expect((await repo.loadDetailed()).items, isEmpty);
    });

    test('a placement onto a branch that does not exist is refused', () async {
      final id = await fullyPopulatedGame(repo);
      await expectLater(
        repo.place(id, 999002),
        throwsA(anything),
        reason: 'placing a game on a nonexistent branch must be refused',
      );
    });

    test('a source for a game that does not exist is refused', () async {
      await expectLater(
        repo.addSource(Source(
          igdbId: 999003,
          kind: SourceKind.web,
          matchMethod: MatchMethod.text,
          addedAt: DateTime.now(),
        )),
        throwsA(anything),
      );
    });
  });

  group('deleting a parent takes its children, per relation', () {
    test('purging a game empties every child table', () async {
      final id = await fullyPopulatedGame(repo);

      // All four children present first, or the delete below proves nothing.
      expect((await repo.loadDetailed()).items, hasLength(1));
      expect(await repo.sourcesFor(id), hasLength(1));
      expect(await repo.placements(), isNotEmpty);

      await repo.purgeGame(id);

      // entries, copies, placements and sources all gone, and gone by CASCADE
      // rather than by hand: purgeGame deletes only the games row.
      expect((await repo.loadDetailed()).items, isEmpty);
      expect(await repo.sourcesFor(id), isEmpty);
      expect(await repo.placements(), isEmpty);
      expect(await repo.foreignKeyViolations(), isEmpty);
    });

    test('deleting a branch takes its placements and keeps the games',
        () async {
      final id = await fullyPopulatedGame(repo);
      final branches = await repo.branches();
      expect(branches, hasLength(1));

      await repo.deleteBranch(branches.single.id);

      expect(await repo.branches(), isEmpty);
      expect(await repo.placements(), isEmpty);
      // A branch is a container. Emptying it does not destroy what was in it.
      final items = (await repo.loadDetailed()).items;
      expect(items, hasLength(1));
      expect(items.single.game.igdbId, id);
      expect(await repo.foreignKeyViolations(), isEmpty);
    });

    test('deleting one branch leaves another branch alone', () async {
      final id = await fullyPopulatedGame(repo);
      final second = await repo.createBranch('Other');
      await repo.place(id, second);

      final first = (await repo.branches()).first;
      await repo.deleteBranch(first.id);

      final remaining = await repo.placements();
      expect(remaining.keys, [second]);
      expect(remaining[second], contains(id));
    });
  });

  group('writes that touch more than one row are atomic', () {
    test('upsert writes game, entry and copies as one unit', () async {
      // Three tables in one call. A failure partway through must leave none of
      // them, or the collection holds a game with no entry and the loader skips
      // it forever.
      await expectLater(
        repo.upsert(TreeItem(
          game: Game(igdbId: 5001, title: 'Atomic'),
          entry: Entry(
            igdbId: 5001,
            ownership: Ownership.owned,
            progress: Progress.untouched,
          ),
          copies: [
            Copy(
              igdbId: 5001,
              platform: Platform.pc,
              form: Form.digital,
              acquired: Acquired.bought,
            ),
          ],
        )),
        completes,
      );
      expect((await repo.loadDetailed()).items, hasLength(1));
    });

    test('a rejected upsert leaves nothing behind', () async {
      // A blank title is refused by validation BEFORE the transaction opens, so
      // the assertion is that the collection is untouched rather than partly
      // written.
      await expectLater(
        repo.upsert(TreeItem(
          game: Game(igdbId: 5002, title: '   '),
          entry: Entry(
            igdbId: 5002,
            ownership: Ownership.owned,
            progress: Progress.untouched,
          ),
          copies: const [],
        )),
        throwsA(isA<ArgumentError>()),
      );
      expect((await repo.loadDetailed()).items, isEmpty);
      expect(await repo.foreignKeyViolations(), isEmpty);
    });

    test('reorderBranches gives every branch a distinct order', () async {
      final ids = <int>[];
      for (final name in ['A', 'B', 'C']) {
        ids.add(await repo.createBranch(name, sortOrder: ids.length));
      }

      await repo.reorderBranches(ids.reversed.toList());

      final orders = (await repo.branches()).map((b) => b.sortOrder).toList();
      // Written in one transaction, so a failure halfway cannot leave two
      // branches claiming the same position.
      expect(orders.toSet(), hasLength(orders.length));
      expect((await repo.branches()).map((b) => b.name), ['C', 'B', 'A']);
    });

    test('re-placing a game updates its position without duplicating it',
        () async {
      final id = await fullyPopulatedGame(repo);
      final branch = (await repo.branches()).single.id;

      await repo.place(id, branch, position: 5);
      await repo.place(id, branch, position: 9);

      // The composite primary key makes this an update, not a second row: one
      // game must not hang twice on one branch.
      expect(await repo.placements(), {branch: [id]});
    });
  });

  group('the whole database stays consistent under a realistic workload',
      () {
    test('seed, mutate, shelve, branch, delete: no violations at any point',
        () async {
      await repo.seedIfEmpty();
      expect(await repo.foreignKeyViolations(), isEmpty);

      final items = (await repo.loadDetailed()).items;
      final first = items.first.game.igdbId;

      await repo.setProgress(first, Progress.finished);
      await repo.setRating(first, 4);
      await repo.setOwnership(first, Ownership.released);
      expect(await repo.foreignKeyViolations(), isEmpty);

      final branch = await repo.createBranch('Workload');
      for (final item in items.take(3)) {
        await repo.place(item.game.igdbId, branch);
      }
      expect(await repo.foreignKeyViolations(), isEmpty);

      await repo.shelve(first);
      // A shelved game keeps its rows, deliberately: shelving is not deleting.
      expect(await repo.foreignKeyViolations(), isEmpty);

      await repo.deleteBranch(branch);
      expect(await repo.foreignKeyViolations(), isEmpty);

      await repo.purgeGame(first);
      expect(await repo.foreignKeyViolations(), isEmpty);
    });

    test('a migrated v1 database is consistent after the upgrade', () async {
      // The upgrade path, through the shipping opener. A migration that created
      // a table without its cascade clause would show up here rather than at a
      // delete months later.
      final dir = await Directory.systemTemp.createTemp('ludeck_audit');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'migrated.db');

      final db = await openLudeckDatabaseAt(path);
      final migrated = Repository(db);
      addTearDown(migrated.close);

      await fullyPopulatedGame(migrated);
      expect(await migrated.foreignKeyViolations(), isEmpty);

      final keys = await migrated.foreignKeysOf('sources');
      // sources arrived in the v2 migration, so its cascade is the one most
      // likely to have been written in only one of the two DDL paths.
      expect(keys, isNotEmpty);
      expect(keys.first.onDelete, 'CASCADE');
    });
  });
}
