// Stage 2 verification: the tree actually RENDERS, and renders games as covers.
//
// No database and no repository import, so `check.ps1` rule 8 does not apply and
// `pumpWidget` needs no `runAsync` -- there is no real disk I/O anywhere in this
// file. That is deliberate: the renderer takes its data as plain arguments, so it
// can be verified without a store, and a hang here would mean a genuine bug
// rather than the documented FakeAsync/sqflite trap.
//
// `animateArrivals: false` throughout, so every node is at final size on the
// first pump. With it on, a node starts at scale 0.6 and a position assertion
// would be measuring the animation rather than the layout.

import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/map/game_node.dart';
import 'package:ludeck/ui/tokens.dart';
import 'package:ludeck/ui/tree/procedural_tree.dart';
import 'package:ludeck/ui/tree/procedural_tree_view.dart';
import 'package:ludeck/ui/tree/tree_painter.dart';

/// A real phone, not flutter_test's ~800x600 default.
///
/// The default surface is wider than a phone, and this project has already
/// shipped a layout bug that passed green on it and clipped on a 412pt device.
const _phone = Size(412, 760);

Branch _branch(int id, String name, int order) =>
    (id: id, name: name, sortOrder: order);

TreeItem _item(
  int id,
  String title, {
  bool harvested = false,
  bool seed = false,
}) =>
    TreeItem(
      game: Game(igdbId: id, title: title),
      entry: Entry(
        igdbId: id,
        ownership: seed ? Ownership.spotted : Ownership.owned,
        progress: harvested ? Progress.finished : Progress.untouched,
      ),
      copies: const [],
    );

Future<void> _pumpTree(
  WidgetTester tester, {
  List<TreeItem> items = const [],
  List<Branch> branches = const [],
  Map<int, List<int>> placements = const {},
  ValueChanged<TreeItem>? onSelect,
  Size surface = _phone,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RepaintBoundary(
        // The app's own night sky behind the tree.
        //
        // Not decoration for the capture: every bark and foliage value in
        // `Tokens.canopy` was chosen to sit against this gradient, so judging a
        // render on the test harness's white default would be judging the wrong
        // picture. The first capture pass did exactly that.
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Each skin stands against its OWN sky. Judging a colourful tree
              // against the muted default sky would be judging the wrong
              // picture, which the first capture pass in this project did.
              colors: Tokens.canopy.sky,
            ),
          ),
          child: ProceduralTreeView(
            items: items,
            branches: branches,
            placements: placements,
            onSelect: onSelect,
            animateArrivals: false,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('games render as their covers', () {
    testWidgets('every owned game is on the tree with no branches at all',
        (tester) async {
      // The commonest state in the app and the one the old renderer drew as an
      // empty canvas: games owned, no branch ever made.
      final items = [
        for (var i = 0; i < 8; i++) _item(100 + i, 'Game $i'),
      ];
      await _pumpTree(tester, items: items);

      expect(find.byType(GameNode), findsNWidgets(8));
    });

    testWidgets('a placed game announces the branch that is never painted',
        (tester) async {
      await _pumpTree(
        tester,
        items: [_item(10, 'Hades'), _item(11, 'Celeste')],
        branches: [_branch(1, 'Cozy', 0)],
        placements: {1: [10]},
      );

      // The branch name is deliberately not drawn anywhere on the tree, so the
      // spoken label is the only place it exists. Hidden is not absent.
      expect(
        find.bySemanticsLabel(RegExp('Hades.*on Cozy')),
        findsOneWidget,
      );
      // Celeste is on no branch, so it hangs in the crown with no branch named.
      expect(find.bySemanticsLabel(RegExp('Celeste')), findsOneWidget);
    });

    testWidgets('a recommendation renders as a bud on the tree, above the '
        'ground line, smaller than a fruit', (tester) async {
      await _pumpTree(tester, items: [
        _item(10, 'Owned'),
        _item(11, 'Suggested', seed: true),
      ]);

      final nodes = tester.widgetList<GameNode>(find.byType(GameNode)).toList();
      expect(nodes, hasLength(2));

      final fruit = nodes.firstWhere((n) => n.item.game.igdbId == 10);
      final bud = nodes.firstWhere((n) => n.item.game.igdbId == 11);
      // A recommendation is not yet a game you own, and the size says so --
      // while still being big enough to tell one cover from another.
      expect(bud.cardWidth, lessThan(fruit.cardWidth));
      expect(bud.cardWidth, greaterThan(20));

      // THE change. It used to be laid out in a strip BELOW the ground line; it
      // now hangs on the wood, so it must sit above that line like any fruit.
      final surface = tester.getRect(find.byType(ProceduralTreeView));
      final budRect = tester.getRect(
        find.byWidget(bud as Widget),
      );
      final groundLine = surface.top + surface.height * (1 - 0.12);
      expect(budRect.center.dy, lessThan(groundLine),
          reason: 'a bud below the ground line is back in the old soil strip');
    });

    testWidgets('no cover is hidden behind another, measured on the PAINTED '
        'rects at the height the app actually has', (tester) async {
      // The engine's own anti-stacking invariant reasons about centres and radii.
      // This one measures what is actually on screen: `getRect` walks ancestor
      // transforms, so it includes the per-card tilt, which the engine cannot know
      // about. The device showed two covers stacked while the engine test was
      // green, and this is the instrument that can tell those two cases apart.
      await _pumpTree(
        tester,
        items: [
          for (var i = 0; i < 8; i++) _item(600 + i, 'Owned $i'),
          for (var i = 0; i < 2; i++) _item(700 + i, 'Rec $i', seed: true),
        ],
      );

      final nodes = find.byType(GameNode);
      expect(nodes, findsNWidgets(10));
      final rects = [
        for (var i = 0; i < 10; i++) tester.getRect(nodes.at(i)),
      ];

      var worst = 0.0;
      for (var a = 0; a < rects.length; a++) {
        for (var b = a + 1; b < rects.length; b++) {
          final o = rects[a].intersect(rects[b]);
          if (o.width <= 0 || o.height <= 0) continue;
          final smaller = math.min(
            rects[a].width * rects[a].height,
            rects[b].width * rects[b].height,
          );
          worst = math.max(worst, (o.width * o.height) / smaller);
        }
      }

      // 0.18, a ratchet just above the ~10% measured, in both this harness and the
      // one in `collection_layout_test.dart` that includes the real header and
      // pill. Both agree, which is what settled a device capture I had misread as
      // much worse.
      expect(worst, lessThan(0.18),
          reason: 'worst painted overlap ${(worst * 100).toStringAsFixed(0)}% '
              '-- a cover you cannot read is the same as no cover');
    });

    testWidgets('no title is painted under a fruit', (tester) async {
      // A tree with eight captions on it is a contact sheet. The title lives in
      // the spoken label and in the status sheet, not on the canvas.
      await _pumpTree(tester, items: [_item(10, 'Disco Elysium')]);
      final node = tester.widget<GameNode>(find.byType(GameNode));
      expect(node.showTitle, isFalse);
      expect(find.text('Disco Elysium'), findsNothing);
    });
  });

  group('layout holds on a real phone', () {
    testWidgets('every cover stays inside the canvas', (tester) async {
      final items = [
        for (var i = 0; i < 14; i++) _item(200 + i, 'Game $i'),
        for (var i = 0; i < 6; i++) _item(300 + i, 'Seed $i', seed: true),
      ];
      await _pumpTree(
        tester,
        items: items,
        branches: [
          _branch(1, 'Cozy', 0),
          _branch(2, 'Someday', 1),
          _branch(3, 'Finished', 2),
        ],
        placements: {1: [200, 201, 202], 2: [203, 204], 3: [205]},
      );

      final canvas = tester.getRect(find.byType(ProceduralTreeView));
      for (final element in find.byType(GameNode).evaluate()) {
        final rect = tester.getRect(find.byElementPredicate((e) => e == element));
        expect(
          canvas.inflate(1).contains(rect.topLeft) &&
              canvas.inflate(1).contains(rect.bottomRight),
          isTrue,
          reason: 'a cover is clipped by the screen edge: $rect vs $canvas',
        );
      }
    });

    testWidgets('an empty collection still renders a tree, not a blank screen',
        (tester) async {
      await _pumpTree(tester, items: const []);
      // No fruit, but the canvas is painted: a sapling with a crown, which is
      // what "nothing planted yet" should look like in a tree app.
      expect(find.byType(GameNode), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('the portrait is a picture, not a second editor', () {
    testWidgets('with no handlers a tap does nothing', (tester) async {
      var taps = 0;
      await _pumpTree(
        tester,
        items: [_item(10, 'Hades')],
        onSelect: (_) => taps++,
      );
      await tester.tap(find.byType(GameNode).first, warnIfMissed: false);
      expect(taps, 1, reason: 'the interactive tree must respond');

      // Same widget, no handlers: the profile portrait.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProceduralTreeView(
            items: [_item(10, 'Hades')],
            animateArrivals: false,
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byType(GameNode).first, warnIfMissed: false);
      expect(taps, 1, reason: 'the portrait must not be half-interactive');
    });
  });

  group('the canopy', () {
    test('exists even with no branches, and is deterministic', () {
      ProceduralTree build() => ProceduralTree.build(
            canvas: _phone,
            branches: const [],
            placements: const {},
            items: [for (var i = 0; i < 5; i++) _item(10 + i, 'G$i')],
            fruitRadius: 22,
            trunkWidth: 32,
          );

      final a = foliageFor(build());
      final b = foliageFor(build());

      expect(a, isNotEmpty, reason: 'an unorganised tree must still have leaves');
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].centre, b[i].centre);
        expect(a[i].radius, b[i].radius);
        // The per-leaf tilt and tint are seeded too, so a relaunch draws the
        // same leaves at the same angles, not a reshuffled canopy.
        expect(a[i].angle, b[i].angle);
        expect(a[i].hueShift, b[i].hueShift);
      }
    });

    test('the canopy is built from many small leaves at varied angles', () {
      // The Stage-2 change: a spray of leaf shapes, not a few big blobs. Guards
      // against a regression to the smoke look -- if leaf count collapses or all
      // angles are identical, the canopy is a blob field again.
      final foliage = foliageFor(ProceduralTree.build(
        canvas: _phone,
        branches: const [],
        placements: const {},
        items: [for (var i = 0; i < 5; i++) _item(10 + i, 'G$i')],
        fruitRadius: 22,
        trunkWidth: 32,
      ));
      expect(foliage.length, greaterThan(40),
          reason: 'too few shapes -- the canopy has collapsed back to blobs');
      final angles = foliage.map((b) => b.angle).toSet();
      expect(angles.length, greaterThan(10),
          reason: 'leaves all point the same way -- no organic variation');
      final shifts = foliage.where((b) => !b.lit).map((b) => b.hueShift).toSet();
      expect(shifts.length, greaterThan(10),
          reason: 'no per-leaf tint variation -- the mass is one flat green');
    });

    test('far mass is painted before near mass', () {
      final foliage = foliageFor(ProceduralTree.build(
        canvas: _phone,
        branches: [_branch(1, 'A', 0), _branch(2, 'B', 1), _branch(3, 'C', 2)],
        placements: const {},
        items: [for (var i = 0; i < 6; i++) _item(10 + i, 'G$i')],
        fruitRadius: 22,
        trunkWidth: 32,
      ));

      for (var i = 1; i < foliage.length; i++) {
        expect(
          foliage[i].depth,
          lessThanOrEqualTo(foliage[i - 1].depth),
          reason: 'paint order IS the depth cue; an unsorted canopy loses it',
        );
      }
    });

    test('a stem outline is a closed tapered shape, not a stroked line', () {
      final tree = ProceduralTree.build(
        canvas: _phone,
        branches: const [],
        placements: const {},
        items: const [],
        fruitRadius: 22,
        trunkWidth: 32,
      );
      final path = stemPath(tree.trunk);
      final bounds = path.getBounds();
      final base = tree.trunk.base;
      final tip = tree.trunk.tip;
      final w = tree.trunk.baseHalfWidth;

      expect(bounds.width, greaterThan(w));
      // Inside the thick lower trunk, on the centreline and off to one side.
      // (y grows downward, so -6 moves UP into the wood from the soil line.)
      expect(path.contains(base + const Offset(0, -6)), isTrue);
      expect(path.contains(base + Offset(w * 0.7, -6)), isTrue);
      // The same width no longer exists near the tip. That asymmetry IS the
      // taper, and it is what a stroked line of constant width could not express.
      expect(path.contains(tip + Offset(w * 0.7, 6)), isFalse);
    });
  });

  group('crowding', () {
    /// How much two portrait cards overlap, as a fraction of a card.
    ///
    /// Measured in the same y-compressed space the engine separates in, because a
    /// cover is taller than it is wide and a circular measure would call a
    /// vertically stacked pair well separated.
    double worstOverlap(ProceduralTree tree) {
      final all = tree.allFruit.toList();
      var worst = 0.0;
      for (var a = 0; a < all.length; a++) {
        for (var b = a + 1; b < all.length; b++) {
          final want = (all[a].radius + all[b].radius) * 0.94;
          final dx = all[b].centre.dx - all[a].centre.dx;
          final dy = (all[b].centre.dy - all[a].centre.dy) / (4 / 3);
          final dist = math.sqrt(dx * dx + dy * dy);
          final overlap = (want - dist) / want;
          if (overlap > worst) worst = overlap;
        }
      }
      return worst;
    }

    test('no two covers stack, with no branches at all', () {
      // The exact case a device capture caught: eight unplaced games crowded onto
      // the crown, three covers in one stack with only the top one readable.
      final tree = ProceduralTree.build(
        canvas: _phone,
        branches: const [],
        placements: const {},
        items: [for (var i = 0; i < 8; i++) _item(100 + i, 'Game $i')],
        fruitRadius: 28,
        trunkWidth: 32,
      );
      expect(
        worstOverlap(tree),
        lessThan(0.34),
        reason: 'covers are stacked; a cover you cannot read is the same as no '
            'cover at all',
      );
    });

    test('a heavy collection loosens rather than stacking', () {
      final tree = ProceduralTree.build(
        canvas: _phone,
        branches: [
          _branch(1, 'Cozy', 0),
          _branch(2, 'Someday', 1),
          _branch(3, 'Done', 2),
        ],
        placements: const {
          1: [100, 101, 102, 103],
          2: [104, 105, 106],
          3: [107, 108],
        },
        items: [for (var i = 0; i < 16; i++) _item(100 + i, 'Game $i')],
        fruitRadius: 28,
        trunkWidth: 32,
      );
      expect(worstOverlap(tree), lessThan(0.40));
    });

    test('separation is deterministic', () {
      ProceduralTree build() => ProceduralTree.build(
            canvas: _phone,
            branches: const [],
            placements: const {},
            items: [for (var i = 0; i < 9; i++) _item(100 + i, 'Game $i')],
            fruitRadius: 28,
            trunkWidth: 32,
          );
      final a = build().allFruit.toList();
      final b = build().allFruit.toList();
      for (var i = 0; i < a.length; i++) {
        expect(a[i].centre, b[i].centre);
      }
    });

    test('a fruit never strays far from the wood it hangs on', () {
      final tree = ProceduralTree.build(
        canvas: _phone,
        branches: const [],
        placements: const {},
        items: [for (var i = 0; i < 12; i++) _item(100 + i, 'Game $i')],
        fruitRadius: 28,
        trunkWidth: 32,
      );
      for (final f in tree.allFruit) {
        // The stalk is drawn from anchor to cover. If separation could move a
        // cover anywhere, the stalk would become a long line to nothing.
        expect(
          (f.centre - f.anchor).distance,
          lessThan(f.radius * 4.2),
          reason: 'a cover drifted away from its own branch',
        );
      }
    });
  });

  group('capture', () {
    // Not an assertion -- a look at the actual pixels. Green geometry tests have
    // already described an ugly tree once in this project, so this writes a PNG
    // that can be opened and judged. Skipped unless LUDECK_CAPTURE is set, so a
    // normal suite run does no file I/O.
    testWidgets('render the tree to a PNG', (tester) async {
      final dir = io.Platform.environment['LUDECK_CAPTURE'];
      if (dir == null) return;

      Future<void> shoot(String name, List<TreeItem> items,
          List<Branch> branches, Map<int, List<int>> placements) async {
        await _pumpTree(
          tester,
          items: items,
          branches: branches,
          placements: placements,
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        // `toImage` is REAL async -- it waits on the GPU/raster side, which the
        // fake clock a widget test runs under never advances. Outside
        // `runAsync` this call does not fail, it HANGS forever, which is the
        // documented failure mode in this project's CONSTRAINTS.md.
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          io.File('$dir/$name.png').writeAsBytesSync(
            bytes!.buffer.asUint8List(),
            flush: true,
          );
        });
      }

      await shoot('tree-empty', const [], const [], const {});
      // A bud-heavy tree, so the calyx can actually be LOOKED at. The loaded
      // fixture below has five buds among twelve games, which is not enough to
      // judge the bud treatment -- and the first version of the calyx was
      // painted inside the cover card, so it was invisible in exactly that
      // fixture while every test stayed green.
      await shoot(
        'tree-buds',
        [
          for (var i = 0; i < 3; i++) _item(400 + i, 'Owned $i', harvested: i == 0),
          for (var i = 0; i < 7; i++) _item(500 + i, 'Rec $i', seed: true),
        ],
        const [],
        const {},
      );

      // STAGE 1: the colour directions, each at empty / 8 games / 13 games so
      // colour cannot hide the composition defect. Each renders against its own
      // sky (see `_pumpTree`). Restored to the shipped skin in the finally, so a
      // normal suite run is unaffected.
      final original = Tokens.activeSkin;
      final directions = [
        Tokens.skins.midnight,
        Tokens.skins.biolume,
        Tokens.skins.twilight,
        Tokens.skins.neon,
      ];
      final eight =
          [for (var i = 0; i < 8; i++) _item(100 + i, 'Game $i', harvested: i == 1)];
      final thirteen = [
        for (var i = 0; i < 9; i++) _item(200 + i, 'Game $i', harvested: i % 4 == 0),
        for (var i = 0; i < 4; i++) _item(300 + i, 'Rec $i', seed: true),
      ];
      final branches13 = [
        _branch(1, 'Cozy', 0),
        _branch(2, 'Someday', 1),
        _branch(3, 'Finished', 2),
      ];
      const placements13 = {
        1: [200, 201, 202, 203],
        2: [204, 205],
        3: [206, 207],
      };
      try {
        for (final skin in directions) {
          Tokens.activeSkin = skin;
          await shoot('skin-${skin.name}-empty', const [], const [], const {});
          await shoot('skin-${skin.name}-8', eight, const [], const {});
          await shoot('skin-${skin.name}-13', thirteen, branches13, placements13);
        }
      } finally {
        Tokens.activeSkin = original;
      }

      // Stage 3: the bloom pass, driven with synthetic per-fruit colours so it
      // can be SEEN without a network decode. Vivid, deliberately varied hues so
      // the "colour from the games" effect is visible on the wood and foliage.
      final blooms = <int, ui.Color>{
        100: const ui.Color(0xFFE84B5A), // red
        101: const ui.Color(0xFF4B7BE8), // blue
        102: const ui.Color(0xFF9C4BE8), // violet
        103: const ui.Color(0xFF4BE8C8), // teal
        104: const ui.Color(0xFFE87A4B), // orange
        105: const ui.Color(0xFF4BE85A), // green
        106: const ui.Color(0xFFE84BC8), // magenta
        107: const ui.Color(0xFF4BC8E8), // cyan
      };
      final bloomItems =
          [for (var i = 0; i < 8; i++) _item(100 + i, 'Game $i', harvested: i == 1)];
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      final tree = ProceduralTree.build(
        canvas: _phone,
        branches: const [],
        placements: const {},
        items: bloomItems,
        fruitRadius: 28,
        trunkWidth: 32,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Tokens.canopy.sky,
                ),
              ),
              child: SizedBox(
                width: _phone.width,
                height: _phone.height,
                child: CustomPaint(
                  painter: ProceduralTreePainter(
                    tree: tree,
                    foliage: foliageFor(tree),
                    bloomTints: blooms,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final b = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final image = await b.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        io.File('$dir/bloom-8.png').writeAsBytesSync(
          bytes!.buffer.asUint8List(),
          flush: true,
        );
      });
    });
  });
}
