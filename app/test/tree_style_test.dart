import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/db/database.dart';
import 'package:ludeck/data/repository.dart';
import 'package:ludeck/ui/orchard/tree_style.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('TreeStyle', () {
    test('neighbouring unstyled trees get different blossoms', () {
      final looks = [for (var i = 0; i < TreeBlossom.values.length; i++) TreeStyle.defaultFor(i).blossom];
      expect(looks.toSet(), hasLength(TreeBlossom.values.length));
      expect(TreeStyle.defaultFor(0).decor, isNotEmpty,
          reason: 'a first tree is never on bare ground');
    });

    test('a new tree takes the blossom the orchard has least of', () {
      expect(leastUsedBlossom([]), TreeBlossom.blossom);
      expect(leastUsedBlossom([TreeBlossom.blossom, TreeBlossom.maple]),
          TreeBlossom.jade);
      expect(leastUsedBlossom([...TreeBlossom.values, TreeBlossom.blossom]),
          TreeBlossom.maple);
    });

    test('decorations survive storage; unknown names are dropped, not fatal', () {
      const s = TreeStyle(
          blossom: TreeBlossom.frost,
          wood: TreeWood.birch,
          decor: {TreeDecor.lantern, TreeDecor.fence});
      final back = TreeStyle.fromRow(
          {'blossom': 'frost', 'wood': 'birch', 'decor': s.decorCsv});
      expect(back, s);
      final odd = TreeStyle.fromRow(
          {'blossom': 'gone', 'wood': 'gone', 'decor': 'lantern,teapot'});
      expect(odd.blossom, TreeBlossom.blossom);
      expect(odd.wood, TreeWood.plum);
      expect(odd.decor, {TreeDecor.lantern});
    });

    test('every look has its baked tree file', () {
      // A missing variant would silently show nothing on that page.
      for (final b in TreeBlossom.values) {
        for (final w in TreeWood.values) {
          final s = TreeStyle(blossom: b, wood: w);
          expect(File(s.asset).existsSync(), isTrue, reason: s.asset);
        }
      }
    });

    test('saved looks win; unsaved trees default by position', () {
      final looks = resolveTreeStyles([7, 9], {
        9: {'blossom': 'jade', 'wood': 'oak', 'decor': ''},
      });
      expect(looks[7], TreeStyle.defaultFor(0));
      expect(looks[9]!.blossom, TreeBlossom.jade);
      expect(looks[9]!.wood, TreeWood.oak);
    });
  });

  group('tree_styles storage', () {
    late Repository repo;
    setUp(() async => repo = await Repository.openInMemory());
    tearDown(() async => repo.close());

    test('round-trips, replaces, and goes with its tree', () async {
      final id = await repo.createBranch('Cozy');
      await repo.setTreeStyle(id, blossom: 'maple', wood: 'oak', decor: 'fence');
      await repo.setTreeStyle(id,
          blossom: 'frost', wood: 'birch', decor: 'lantern,stones');
      final rows = await repo.treeStyles();
      expect(rows.keys, [id]);
      expect(rows[id]!['blossom'], 'frost');
      expect(rows[id]!['decor'], 'lantern,stones');

      await repo.deleteBranch(id);
      expect(await repo.treeStyles(), isEmpty);
    });
  });

  test('a v4 database upgrades to v5 keeping its trees', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('ludeck_v5_');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'v4.db');
    // A real v4 file: the current opener, then rolled back to version 4 with
    // the v5 table removed, exactly as a v4 install left it.
    final v = await openLudeckDatabaseAt(path);
    await v.insert('branches', {'id': 3, 'name': 'Cozy', 'sort_order': 0, 'created_at': 1});
    await v.execute('DROP TABLE tree_styles');
    await v.setVersion(4);
    await v.close();

    final db = await openLudeckDatabaseAt(path);
    addTearDown(db.close);
    expect(await db.getVersion(), 5);
    expect((await db.query('branches')).single['name'], 'Cozy');
    await db.insert('tree_styles',
        {'branch_id': 3, 'blossom': 'jade', 'wood': 'oak', 'decor': ''});
    expect(await db.query('tree_styles'), hasLength(1));
  });
}
