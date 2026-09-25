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

    test('a recommendation hangs on the wood as a BUD, not in a strip below', () {
      final tree = _build(
        items: [_item(10, 'Hades'), _item(99, 'Pentiment', seed: true)],
      );

      // The inversion of the old rule. Recommendations used to be forbidden from
      // the wood and laid out in soil; on a real collection that put more than
      // half the games in a bar under a sparse tree.
      final ids = tree.allFruit.map((f) => f.item.game.igdbId);
      expect(ids, contains(99));
      expect(tree.buds.map((f) => f.item.game.igdbId), [99]);
      expect(tree.buds.single.anchor, isNotNull);
    });

    test('a bud is smaller than a fruit, so not-yet-yours reads without a label',
        () {
      final tree = _build(
        items: [_item(10, 'Hades'), _item(99, 'Pentiment', seed: true)],
      );

      final fruit = tree.allFruit.firstWhere((f) => !f.bud);
      final bud = tree.buds.single;
      expect(bud.radius, lessThan(fruit.radius));
      // Small enough to differ, large enough to identify the cover art.
      expect(bud.radius / fruit.radius, inInclusiveRange(0.45, 0.80));
    });

    test('a recommendation can be filed onto a named branch', () {
      final tree = _build(
        branches: [_branch(1, 'Someday', 0)],
        placements: {1: [99]},
        items: [_item(10, 'Hades'), _item(99, 'Pentiment', seed: true)],
      );

      // Before buds, `placements` silently dropped any id that was not owned, so
      // a recommendation could not be organised at all.
      final limb = tree.limbs.single;
      expect(limb.fruit.map((f) => f.item.game.igdbId), [99]);
      expect(limb.fruit.single.bud, isTrue);
      expect(limb.fruit.single.branchId, 1);
    });

    test('a bud survives the separation pass with every field intact', () {
      // The separation pass RECONSTRUCTS each fruit to move it, by listing fields
      // by hand. When `bud` was added that list was not updated, so every
      // recommendation came out as a full-size fruit -- and it compiled, because
      // the field has a default. This is a crowded tree, so the pass definitely
      // runs and definitely moves things.
      final tree = _build(
        items: [
          for (var i = 0; i < 9; i++) _item(100 + i, 'Owned $i'),
          for (var i = 0; i < 5; i++) _item(200 + i, 'Rec $i', seed: true),
        ],
      );

      expect(tree.buds, hasLength(5));
      for (final b in tree.buds) {
        expect(b.item.isSeed, isTrue);
        expect(b.anchor.dx.isFinite, isTrue);
        expect(b.radius, greaterThan(0));
        expect(b.harvested, isFalse);
      }
      // And the owned games did not become buds.
      expect(tree.allFruit.where((f) => !f.bud), hasLength(9));
    });

    test("a bud's calyx is never covered by the card above it", () {
      // The calyx is painted on the card's shoulder, so "cards may touch" is not
      // good enough for a bud: a legally-touching neighbour above it hid the cap
      // and the not-yours-yet signal disappeared. Caught on a capture, not by a
      // test, which is why it is pinned here now.
      //
      // Run at BOTH the fixture radius and the one the view actually ships
      // (`Tokens.size.fruit / 2` = 28 at 412pt width). The property is scale
      // invariant in principle, and arguing that is worse than asserting the
      // number the user's phone uses.
      for (final fruitRadius in const [22.0, 28.0]) {
        final tree = ProceduralTree.build(
          canvas: const Size(412, 760),
          branches: const [],
          placements: const {},
          items: [
            for (var i = 0; i < 3; i++) _item(400 + i, 'Owned $i'),
            for (var i = 0; i < 7; i++) _item(500 + i, 'Rec $i', seed: true),
          ],
          fruitRadius: fruitRadius,
          trunkWidth: 32,
        );

        expect(tree.buds, hasLength(7), reason: 'r=$fruitRadius');
        final all = tree.allFruit.toList();
        for (final bud in tree.buds) {
          // The calyx occupies roughly 1.30 to 1.60 radii above the centre.
          final capTop = bud.centre.dy - bud.radius * 1.60;
          final capBottom = bud.centre.dy - bud.radius * 1.30;
          for (final other in all) {
            if (other.centre == bud.centre) continue;
            final oTop = other.centre.dy - other.radius * 1.33;
            final oBottom = other.centre.dy + other.radius * 1.33;
            final overlapsY = oTop < capBottom && oBottom > capTop;
            final overlapsX =
                (other.centre.dx - bud.centre.dx).abs() < other.radius * 0.85;
            expect(overlapsY && overlapsX, isFalse,
                reason: 'r=$fruitRadius: a card covers the calyx of the bud '
                    'at ${bud.centre}');
          }
        }
      }
    });

    test('a shelved game appears nowhere', () {
      final tree = _build(
        branches: [_branch(1, 'Cozy', 0)],
        placements: {1: [10]},
        items: [_item(10, 'Hades', shelved: true), _item(11, 'Celeste')],
      );

      expect(tree.allFruit.map((f) => f.item.game.igdbId), isNot(contains(10)));
      expect(tree.buds, isEmpty);
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
      expect(tree.buds, isEmpty);
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
