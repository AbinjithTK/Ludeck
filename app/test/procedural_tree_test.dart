// Stage 1 verification: the procedural tree engine's geometry invariants.
//
// Pure `test()`, not `testWidgets()` -- the engine is Flutter-free by design, so
// these run on the VM with no canvas, no fake clock and no database. That is the
// point of keeping the geometry in its own file.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/tree/procedural_tree.dart';

const _canvas = Size(412, 700);

Branch _branch(int id, String name, int order) =>
    (id: id, name: name, sortOrder: order);

TreeItem _item(
  int id,
  String title, {
  bool harvested = false,
  bool seed = false,
  bool shelved = false,
}) =>
    TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: seed ? Ownership.spotted : Ownership.owned,
        progress: harvested ? Progress.finished : Progress.untouched,
        shelved: shelved,
      ),
      copies: const [],
    );

ProceduralTree _build({
  List<Branch> branches = const [],
  Map<int, List<int>> placements = const {},
  List<TreeItem> items = const [],
}) =>
    ProceduralTree.build(
      canvas: _canvas,
      branches: branches,
      placements: placements,
      items: items,
      fruitRadius: 22,
      trunkWidth: 32,
    );

void main() {
  group('determinism', () {
    test('the same collection produces an identical tree', () {
      final branches = [_branch(1, 'Cozy', 0), _branch(2, 'Someday', 1)];
      final items = [_item(10, 'Hades'), _item(11, 'Celeste')];
      final placements = {1: [10], 2: [11]};

      final a = _build(branches: branches, placements: placements, items: items);
      final b = _build(branches: branches, placements: placements, items: items);

      expect(a.seed, b.seed);
      expect(a.trunk.spine, b.trunk.spine);
      expect(a.trunk.halfWidth, b.trunk.halfWidth);
      for (var i = 0; i < a.limbs.length; i++) {
        expect(a.limbs[i].stem.spine, b.limbs[i].stem.spine,
            reason: 'a tree that reshuffles on rebuild is a screensaver');
        expect(a.limbs[i].fruit.map((f) => f.centre),
            b.limbs[i].fruit.map((f) => f.centre));
      }
    });

    test('load order does not change the shape', () {
      final branches = [_branch(1, 'Cozy', 0)];
      final placements = {1: [10, 11]};
      final forward = [_item(10, 'Hades'), _item(11, 'Celeste')];
      final reversed = [_item(11, 'Celeste'), _item(10, 'Hades')];

      final a = _build(
          branches: branches, placements: placements, items: forward);
      final b = _build(
          branches: branches, placements: placements, items: reversed);

      // A collection is a SET; the seed is taken over sorted ids for exactly
      // this reason.
      expect(a.seed, b.seed);
      expect(a.trunk.spine, b.trunk.spine);
    });
  });

  group('what hangs where', () {
    test('a game on two branches hangs on both', () {
      final tree = _build(
        branches: [_branch(1, 'PC', 0), _branch(2, 'Switch', 1)],
        placements: {1: [10], 2: [10]},
        items: [_item(10, 'Hades')],
      );

      final appearances =
          tree.allFruit.where((f) => f.item.game.igdbId == 10).toList();
      expect(appearances, hasLength(2),
          reason: 'owning a game on two platforms is true; one position is a lie');
      expect(appearances.map((f) => f.branchId).toSet(), {1, 2});
    });

    test('an unplaced owned game hangs on the trunk exactly once', () {
      final tree = _build(
        branches: [_branch(1, 'Cozy', 0)],
        placements: {1: [10]},
        items: [_item(10, 'Hades'), _item(11, 'Celeste')],
      );

      expect(tree.trunkFruit, hasLength(1));
      expect(tree.trunkFruit.single.item.game.igdbId, 11);
      expect(tree.trunkFruit.single.branchId, ProceduralTree.trunkBranchId);
      expect(tree.allFruit.where((f) => f.item.game.igdbId == 11), hasLength(1));
    });

    test('a collection with no branches still fills the tree', () {
      // The exact case that rendered an empty canvas before: games exist, no
      // branch has ever been made.
      final tree = _build(
        items: [_item(10, 'Hades'), _item(11, 'Celeste'), _item(12, 'Tunic')],
      );

      expect(tree.limbs, isEmpty);
      expect(tree.trunkFruit, hasLength(3));
      expect(tree.fruitCount, 3);
    });

    test('seeds go to the soil and never onto wood', () {
      final tree = _build(
        items: [_item(10, 'Hades'), _item(99, 'Pentiment', seed: true)],
      );

      expect(tree.soil, hasLength(1));
      expect(tree.soil.single.item.game.igdbId, 99);
      expect(tree.allFruit.map((f) => f.item.game.igdbId), isNot(contains(99)));
    });

    test('a shelved game appears nowhere', () {
      final tree = _build(
        branches: [_branch(1, 'Cozy', 0)],
        placements: {1: [10]},
        items: [_item(10, 'Hades', shelved: true), _item(11, 'Celeste')],
      );

      expect(tree.allFruit.map((f) => f.item.game.igdbId), isNot(contains(10)));
      expect(tree.soil, isEmpty);
    });

    test('one limb per branch, in the user order', () {
      final tree = _build(
        branches: [
          _branch(7, 'Third', 2),
          _branch(3, 'First', 0),
          _branch(5, 'Second', 1),
        ],
      );

      expect(tree.limbs.map((l) => l.name), ['First', 'Second', 'Third']);
    });

    test('harvested fruit sits further out than unfinished fruit', () {
      final tree = _build(
        branches: [_branch(1, 'Cozy', 0)],
        placements: {1: [10, 11]},
        items: [_item(10, 'Aaa'), _item(11, 'Zzz', harvested: true)],
      );

      final limb = tree.limbs.single;
      final base = limb.stem.base;
      final unfinished =
          limb.fruit.firstWhere((f) => !f.harvested).centre;
      final harvested = limb.fruit.firstWhere((f) => f.harvested).centre;

      expect((harvested - base).distance, greaterThan((unfinished - base).distance),
          reason: 'a finished game belongs where the light is, without a legend');
    });
  });

  group('botanical structure', () {
    test("limb thickness obeys da Vinci's rule against the trunk", () {
      final tree = _build(
        branches: [_branch(1, 'A', 0), _branch(2, 'B', 1), _branch(3, 'C', 2)],
        placements: {
          1: [10, 11, 12, 13],
          2: [14, 15],
          3: [16],
        },
        items: [
          for (var id = 10; id <= 16; id++) _item(id, 'Game $id'),
        ],
      );

      // Measured against the trunk ABOVE the root flare, not at the soil line.
      // The flare is a buttress spreading load into the ground and carries no
      // branches, so counting it here would demand limbs thick enough to match a
      // cross-section that never branches.
      final trunkArea =
          math.pow(tree.trunkStructuralHalfWidth, 2).toDouble();
      final limbArea = tree.limbs.fold<double>(
          0, (sum, l) => sum + math.pow(l.stem.baseHalfWidth, 2).toDouble());

      // Sum of children's cross-section equals the parent's. Allow a little
      // slack for the minimum-width clamp that keeps an empty branch visible.
      expect(limbArea, lessThanOrEqualTo(trunkArea * 1.02));
      expect(limbArea, greaterThan(trunkArea * 0.9));
    });

    test('the trunk flares where it meets the ground', () {
      final tree = _build(
        items: [for (var id = 10; id <= 16; id++) _item(id, 'Game $id')],
      );
      // A trunk that meets the soil at the same width it carries branches at
      // reads as a post pushed into the ground rather than something grown out
      // of it.
      expect(
        tree.trunk.baseHalfWidth,
        greaterThan(tree.trunkStructuralHalfWidth * 1.15),
      );
      // ...and the flare is local to the base, not a general fattening.
      expect(
        tree.trunk.baseHalfWidth,
        lessThan(tree.trunkStructuralHalfWidth * 2.0),
      );
    });

    test('a loaded branch grows a thicker limb than an empty one', () {
      final tree = _build(
        branches: [_branch(1, 'Loaded', 0), _branch(2, 'Empty', 1)],
        placements: {
          1: [10, 11, 12, 13, 14],
          2: const <int>[],
        },
        items: [for (var id = 10; id <= 14; id++) _item(id, 'Game $id')],
      );

      final loaded = tree.limbs.firstWhere((l) => l.name == 'Loaded');
      final empty = tree.limbs.firstWhere((l) => l.name == 'Empty');
      expect(loaded.stem.baseHalfWidth,
          greaterThan(empty.stem.baseHalfWidth),
          reason: 'a loaded branch should read as loaded');
    });

    test('every stem tapers and never thickens outward', () {
      final tree = _build(
        branches: [_branch(1, 'A', 0), _branch(2, 'B', 1)],
        placements: {1: [10], 2: [11]},
        items: [_item(10, 'Hades'), _item(11, 'Celeste')],
      );

      for (final stem in [tree.trunk, ...tree.limbs.map((l) => l.stem)]) {
        for (var i = 1; i < stem.halfWidth.length; i++) {
          expect(stem.halfWidth[i], lessThanOrEqualTo(stem.halfWidth[i - 1]),
              reason: 'wood does not get thicker as it grows away from its root');
        }
      }
    });

    test('limbs bend upward instead of running straight', () {
      final tree = _build(
        branches: [_branch(1, 'Low', 0), _branch(2, 'High', 1)],
      );

      for (final limb in tree.limbs) {
        final spine = limb.stem.spine;
        // Gravitropism: the final segment is more vertical than the first, so
        // the limb is a curve and not a stroke.
        double verticality(Offset a, Offset b) {
          final d = b - a;
          return d.distance == 0 ? 0 : (-d.dy) / d.distance;
        }

        final first = verticality(spine[0], spine[1]);
        final last = verticality(spine[spine.length - 2], spine.last);
        expect(last, greaterThan(first),
            reason: '${limb.name} should straighten upward along its length');
        expect(limb.stem.tip.dy, lessThan(limb.stem.base.dy),
            reason: 'a limb tip is above where it left the trunk');
      }
    });

    test('the trunk stays planted and rises', () {
      final tree = _build(items: [_item(10, 'Hades')]);

      expect(tree.trunk.base.dy, closeTo(tree.soilY, 0.001));
      expect(tree.trunk.base.dx, closeTo(_canvas.width / 2, 0.001),
          reason: 'sway is scaled by height so the base does not slide');
      expect(tree.trunk.tip.dy, lessThan(tree.trunk.base.dy));
      expect(tree.trunk.length, greaterThan(_canvas.height * 0.3));
    });

    test('the tree grows taller as branches are added', () {
      final items = [for (var id = 10; id <= 15; id++) _item(id, 'Game $id')];

      final sapling = _build(items: items);
      final grown = _build(
        branches: [
          for (var i = 1; i <= 6; i++) _branch(i, 'B$i', i - 1),
        ],
        placements: {for (var i = 1; i <= 6; i++) i: [9 + i]},
        items: items,
      );

      expect(grown.trunk.length, greaterThan(sapling.trunk.length),
          reason: 'organising the collection is what makes the tree grow');
      expect(grown.trunk.tip.dy, lessThan(sapling.trunk.tip.dy));
    });

    test('the walked length of a curved trunk exceeds its straight line', () {
      final tree = _build(items: [_item(10, 'Hades')]);
      final straight = (tree.trunk.tip - tree.trunk.base).distance;
      expect(tree.trunk.length, greaterThanOrEqualTo(straight));
    });
  });

  group('the crown', () {
    test('exists even for an empty collection', () {
      final tree = _build();

      expect(tree.crown.length, greaterThanOrEqualTo(3),
          reason: 'a tree has twigs whether or not a branch has been named');
      for (final twig in tree.crown) {
        expect(twig.tip.dy, lessThan(twig.base.dy));
      }
    });

    test('an unorganised tree gets a wider crown than an organised one', () {
      final items = [for (var id = 10; id <= 17; id++) _item(id, 'Game $id')];

      final unorganised = _build(items: items);
      final organised = _build(
        branches: [for (var i = 1; i <= 6; i++) _branch(i, 'B$i', i - 1)],
        placements: {for (var i = 1; i <= 6; i++) i: [9 + i]},
        items: items,
      );

      double widest(ProceduralTree t) => t.crown
          .map((c) => (c.tip - c.base).distance)
          .fold<double>(0, math.max);

      // With no limbs the crown IS the canopy, so it has to carry the form.
      expect(widest(unorganised), greaterThan(widest(organised)));
      expect(unorganised.crown.length,
          greaterThanOrEqualTo(organised.crown.length));
    });

    test('unplaced fruit spreads across the crown, not up the trunk', () {
      final tree = _build(
        items: [for (var id = 10; id <= 17; id++) _item(id, 'Game $id')],
      );

      expect(tree.trunkFruit, hasLength(8));

      // The kebab this replaced put every unplaced fruit within a fruit's width
      // of the trunk's centreline. A real crown scatters them.
      final xs = tree.trunkFruit.map((f) => f.centre.dx).toList();
      final spread = xs.reduce(math.max) - xs.reduce(math.min);
      expect(spread, greaterThan(_canvas.width * 0.25),
          reason: 'fruit threaded up the trunk read as a kebab, not a tree');
    });
  });

  group('edges and hit-testing', () {
    test('an empty collection produces a bare trunk and does not throw', () {
      final tree = _build();

      expect(tree.limbs, isEmpty);
      expect(tree.trunkFruit, isEmpty);
      expect(tree.soil, isEmpty);
      expect(tree.fruitCount, 0);
      expect(tree.trunk.spine, isNotEmpty);
    });

    test('fruit hang above the soil', () {
      final tree = _build(
        branches: [_branch(1, 'A', 0)],
        placements: {1: [10, 11, 12]},
        items: [for (var id = 10; id <= 12; id++) _item(id, 'Game $id')],
      );

      for (final f in tree.allFruit) {
        expect(f.centre.dy, lessThan(tree.soilY),
            reason: 'nothing hangs underground');
      }
    });

    test('a tap on a fruit finds it, and empty canvas finds nothing', () {
      final tree = _build(
        branches: [_branch(1, 'A', 0)],
        placements: {1: [10]},
        items: [_item(10, 'Hades')],
      );

      final fruit = tree.allFruit.single;
      expect(tree.hitTest(fruit.centre)?.game.igdbId, 10);
      expect(tree.hitTest(const Offset(2, 2)), isNull);
    });

    test('overlapping fruit resolve to the nearest', () {
      final tree = _build(
        branches: [_branch(1, 'A', 0)],
        placements: {1: [10, 11]},
        items: [_item(10, 'Aaa'), _item(11, 'Bbb')],
      );

      final first = tree.allFruit.first;
      final probe = first.centre + const Offset(1, 1);
      expect(tree.hitTest(probe)?.game.igdbId, first.item.game.igdbId);
    });
  });
}
