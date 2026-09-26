// Stage 3 of the tree redesign: nested branches (schema v4).
//
// Covers the repository rules the tree view will lean on -- nesting, moving
// without cycles, deleting without losing sub-branches or games, moving one
// placement without touching the others -- plus the v3 -> v4 upgrade on a real
// on-disk file, and the pure BranchTree built from the flat rows.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/db/database.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/domain/branch_tree.dart';
import 'package:ludeck/state/ludeck_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<void> addGame(Repository repo, int id, String title) => repo.upsert(
      TreeItem(
        game: Game(igdbId: id, title: title),
        entry: Entry(
          igdbId: id,
          ownership: Ownership.owned,
          progress: Progress.untouched,
        ),
        copies: const [],
      ),
    );

Branch byName(List<Branch> all, String name) =>
    all.singleWhere((b) => b.name == name);

void main() {
  group('repository: nested branches', () {
    late Repository repo;
    setUp(() async => repo = await Repository.openInMemory());
    tearDown(() async => repo.close());

    test('a new branch grows from the trunk, expanded', () async {
      await repo.createBranch('Couch co-op');
      final b = (await repo.branches()).single;
      expect(b.parentId, isNull);
      expect(b.collapsed, isFalse);
    });

    test('a sub-branch records its parent', () async {
      final coop = await repo.createBranch('Couch co-op');
      await repo.createBranch('With Sam', parentId: coop);
      expect(byName(await repo.branches(), 'With Sam').parentId, coop);
    });

    test('a sub-branch onto a missing parent is refused', () async {
      await expectLater(
          repo.createBranch('Orphan', parentId: 999), throwsA(anything));
    });

    test('collapse state persists', () async {
      final id = await repo.createBranch('Horror');
      await repo.setBranchCollapsed(id, true);
      expect((await repo.branches()).single.collapsed, isTrue);
      await repo.setBranchCollapsed(id, false);
      expect((await repo.branches()).single.collapsed, isFalse);
    });

    test('moveBranch re-parents and renumbers both sibling groups', () async {
      final a = await repo.createBranch('A', sortOrder: 0);
      final b = await repo.createBranch('B', sortOrder: 1);
      final c = await repo.createBranch('C', sortOrder: 2);
      final a1 = await repo.createBranch('A1', parentId: a, sortOrder: 0);

      // B moves inside A, in front of A1.
      await repo.moveBranch(b, newParentId: a, position: 0);
      final all = await repo.branches();
      final tree = BranchTree(all);
      expect(tree.roots.map((x) => x.id), [a, c]);
      expect(tree.childrenOf(a).map((x) => x.id), [b, a1]);
      // Old siblings closed the gap rather than keeping 0 and 2.
      expect(tree.roots.map((x) => x.sortOrder), [0, 1]);
      expect(tree.childrenOf(a).map((x) => x.sortOrder), [0, 1]);
    });

    test('moveBranch back to the trunk, with no position, goes last', () async {
      final a = await repo.createBranch('A', sortOrder: 0);
      final b = await repo.createBranch('B', sortOrder: 1);
      final a1 = await repo.createBranch('A1', parentId: a);
      await repo.moveBranch(a1);
      expect(BranchTree(await repo.branches()).roots.map((x) => x.id),
          [a, b, a1]);
    });

    test('a branch cannot move into itself or its own descendant', () async {
      final a = await repo.createBranch('A');
      final a1 = await repo.createBranch('A1', parentId: a);
      final a11 = await repo.createBranch('A11', parentId: a1);

      await expectLater(repo.moveBranch(a, newParentId: a), throwsArgumentError);
      await expectLater(
          repo.moveBranch(a, newParentId: a11), throwsArgumentError);
      // Refused atomically: nothing moved.
      final all = await repo.branches();
      expect(byName(all, 'A').parentId, isNull);
      expect(byName(all, 'A11').parentId, a1);
    });

    test('deleting a branch lifts its sub-branches into its slot', () async {
      final x = await repo.createBranch('X', sortOrder: 0);
      final mid = await repo.createBranch('Mid', sortOrder: 1);
      final y = await repo.createBranch('Y', sortOrder: 2);
      final k1 = await repo.createBranch('K1', parentId: mid, sortOrder: 0);
      final k2 = await repo.createBranch('K2', parentId: mid, sortOrder: 1);
      final deep = await repo.createBranch('Deep', parentId: k1);

      await repo.deleteBranch(mid);

      final tree = BranchTree(await repo.branches());
      expect(tree.roots.map((b) => b.id), [x, k1, k2, y]);
      expect(tree.roots.map((b) => b.sortOrder), [0, 1, 2, 3]);
      // Grandchildren keep their own parent.
      expect(tree[deep]!.parentId, k1);
      expect(await repo.foreignKeyViolations(), isEmpty);
    });

    test('deleting a branch keeps the games, which become unplaced', () async {
      await addGame(repo, 1, 'It Takes Two');
      final b = await repo.createBranch('Couch co-op');
      await repo.place(1, b);
      await repo.deleteBranch(b);
      expect(await repo.unplacedGameIds(), [1]);
    });

    test('moveGame moves one placement and leaves the others', () async {
      await addGame(repo, 1, 'Hades');
      final chill = await repo.createBranch('Chill');
      final short = await repo.createBranch('20-minute');
      final roguelite = await repo.createBranch('Roguelite');
      await repo.place(1, chill);
      await repo.place(1, short);

      await repo.moveGame(1, fromBranchId: chill, toBranchId: roguelite);

      final p = await repo.placements();
      expect(p[chill], isNull);
      expect(p[short], [1]);
      expect(p[roguelite], [1]);
    });

    test('moveGame onto a branch it is already on does not duplicate',
        () async {
      await addGame(repo, 1, 'Hades');
      final a = await repo.createBranch('A');
      final b = await repo.createBranch('B');
      await repo.place(1, a);
      await repo.place(1, b);
      await repo.moveGame(1, fromBranchId: a, toBranchId: b);
      expect((await repo.placements())[b], [1]);
    });
  });

  group('store: nested branches', () {
    late Repository repo;
    late LudeckStore store;
    setUp(() async {
      repo = await Repository.openInMemory();
      store = LudeckStore(repo);
      await store.load();
    });
    tearDown(() async => repo.close());

    test('a new sub-branch goes last among its siblings, not the trunk',
        () async {
      await store.createBranch('Root A');
      await store.createBranch('Root B');
      final a = byName(store.branches, 'Root A').id;
      await store.createBranch('Kid 1', parentId: a);
      await store.createBranch('Kid 2', parentId: a);

      final tree = store.tree;
      expect(tree.roots.map((b) => b.name), ['Root A', 'Root B']);
      expect(tree.childrenOf(a).map((b) => b.name), ['Kid 1', 'Kid 2']);
      expect(tree.childrenOf(a).map((b) => b.sortOrder), [0, 1]);
    });

    test('moveBranch, setBranchCollapsed and moveGame re-read', () async {
      await addGame(repo, 7, 'Unpacking');
      await store.createBranch('A');
      await store.createBranch('B');
      final a = byName(store.branches, 'A').id;
      final b = byName(store.branches, 'B').id;
      await store.place(7, a);

      await store.moveBranch(b, newParentId: a);
      await store.setBranchCollapsed(a, true);
      await store.moveGame(7, fromBranchId: a, toBranchId: b);

      expect(store.tree[b]!.parentId, a);
      expect(store.tree[a]!.collapsed, isTrue);
      expect(store.tree.gamesOn(b), [7]);
      expect(store.tree.gamesUnder(a), [7]);
    });
  });

  group('BranchTree', () {
    Branch br(int id, String name, {int? parent, int order = 0}) => (
          id: id,
          name: name,
          sortOrder: order,
          parentId: parent,
          collapsed: false,
        );

    final tree = BranchTree(
      [
        br(1, 'Couch co-op', order: 1),
        br(2, 'Chill', order: 0),
        br(3, 'With Sam', parent: 1, order: 0),
        br(4, 'Party', parent: 1, order: 1),
        br(5, 'Sam weekdays', parent: 3),
      ],
      {
        1: [10],
        3: [11, 12],
        4: [12, 13],
        5: [14],
      },
    );

    test('roots and children come out in sibling order', () {
      expect(tree.roots.map((b) => b.name), ['Chill', 'Couch co-op']);
      expect(tree.childrenOf(1).map((b) => b.name), ['With Sam', 'Party']);
    });

    test('pathTo is root-first, the breadcrumb', () {
      expect(tree.pathTo(5).map((b) => b.id), [1, 3, 5]);
      expect(tree.depthOf(5), 2);
      expect(tree.depthOf(2), 0);
    });

    test('gamesUnder counts a game on two sub-branches once', () {
      expect(tree.gamesUnder(1), [10, 11, 12, 14, 13]);
      expect(tree.gamesUnder(4), [12, 13]);
      expect(tree.gamesOn(1), [10]);
    });

    test('canMove refuses self and descendants only', () {
      expect(tree.canMove(1, 5), isFalse);
      expect(tree.canMove(1, 1), isFalse);
      expect(tree.canMove(5, 2), isTrue);
      expect(tree.canMove(3, null), isTrue);
    });

    test('a missing parent or a loop is shown at the trunk, not hidden', () {
      final bad = BranchTree([
        br(1, 'Lost parent', parent: 99),
        br(2, 'Loop A', parent: 3),
        br(3, 'Loop B', parent: 2),
      ]);
      expect(bad.roots.map((b) => b.id).toSet(), {1, 2, 3});
    });
  });

  group('migration v3 -> v4', () {
    late io.Directory dir;
    setUp(() async =>
        dir = await io.Directory.systemTemp.createTemp('ludeck_v4_'));
    tearDown(() async => dir.delete(recursive: true));

    Future<Map<String, Object?>> schemaOf(Database db) async => {
          'columns': [
            for (final c in await db.rawQuery('PRAGMA table_info(branches)'))
              '${c['name']}|${c['type']}|${c['notnull']}|${c['dflt_value']}'
          ],
          'keys': [
            for (final k
                in await db.rawQuery('PRAGMA foreign_key_list(branches)'))
              '${k['from']}->${k['table']}.${k['to']} ${k['on_delete']}'
          ],
          'indexes': [
            for (final i in await db.rawQuery('PRAGMA index_list(branches)'))
              i['name']
          ]..sort((a, b) => '$a'.compareTo('$b')),
        };

    test('keeps every branch and placement, flat, and matches a fresh install',
        () async {
      final path = p.join(dir.path, 'v3.db');
      // Only the tables v4 touches or references, as v3 shipped them.
      final old = await openDatabase(path, version: 3,
          onCreate: (db, _) async {
        await db.execute('CREATE TABLE games (igdb_id INTEGER PRIMARY KEY, '
            'title TEXT NOT NULL, cover_url TEXT, release_year INTEGER, '
            'time_to_beat_seconds INTEGER)');
        await db.execute('''
  CREATE TABLE IF NOT EXISTS branches (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT    NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  )
  ''');
        await db.execute('CREATE TABLE placements (branch_id INTEGER NOT NULL '
            'REFERENCES branches(id) ON DELETE CASCADE, igdb_id INTEGER NOT '
            'NULL REFERENCES games(igdb_id) ON DELETE CASCADE, position '
            'INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (branch_id, igdb_id))');
      });
      await old.insert('games', {'igdb_id': 1, 'title': 'Hades'});
      await old.insert('branches',
          {'id': 5, 'name': 'Chill', 'sort_order': 0, 'created_at': 1});
      await old.insert('branches',
          {'id': 6, 'name': 'Co-op', 'sort_order': 1, 'created_at': 2});
      await old.insert('placements', {'branch_id': 5, 'igdb_id': 1});
      await old.close();

      final db = await openLudeckDatabaseAt(path);
      addTearDown(db.close);
      expect(await db.getVersion(), kSchemaVersion);

      final rows = await db.query('branches', orderBy: 'id');
      expect(rows.map((r) => r['name']), ['Chill', 'Co-op']);
      expect(rows.map((r) => r['parent_id']), [null, null]);
      expect(rows.map((r) => r['collapsed']), [0, 0]);
      expect(await db.query('placements'), hasLength(1));

      // Nesting works on the upgraded file, with its delete rule live.
      await db.update('branches', {'parent_id': 5},
          where: 'id = ?', whereArgs: [6]);
      await db.delete('branches', where: 'id = ?', whereArgs: [5]);
      final kid = (await db.query('branches')).single;
      expect(kid['parent_id'], isNull, reason: 'ON DELETE SET NULL');

      // Same branches table as a brand-new install.
      final fresh = await openLudeckDatabaseAt(p.join(dir.path, 'fresh.db'));
      addTearDown(fresh.close);
      expect(await schemaOf(db), await schemaOf(fresh));
    });
  });
}
