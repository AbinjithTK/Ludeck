import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/branch_tree.dart';
import 'package:ludeck/ui/orchard/night_sky.dart';
import 'package:ludeck/ui/orchard/orchard_view.dart';
import 'package:ludeck/ui/orchard/rive_tree.dart';
import 'package:ludeck/ui/tokens.dart';

Branch _b(int id, String name, {int? parent, int order = 0}) =>
    (id: id, name: name, sortOrder: order, parentId: parent, collapsed: false);

TreeItem _i(int id) => TreeItem(
      game: Game(igdbId: id, title: 'G$id'),
      entry: Entry(
          igdbId: id,
          ownership: Ownership.owned,
          progress: Progress.values.first),
      copies: const [],
    );

void main() {
  test('trees are the top-level branches, in the user order', () {
    final trees = treesOf([
      _b(3, 'C', order: 2),
      _b(1, 'A', order: 0),
      _b(9, 'nested', parent: 1),
      _b(2, 'B', order: 1),
    ]);
    expect(trees.map((b) => b.name), ['A', 'B', 'C']);
  });

  test('a tree carries the games on its sub-branches, each once, stably', () {
    final branches = [_b(1, 'Tree'), _b(2, 'Sub', parent: 1)];
    final shape = BranchTree(branches, {
      1: [10, 11],
      2: [11, 12], // 11 is on both: counted once
    });
    final byId = {for (final id in [10, 11, 12]) id: _i(id)};
    final games = gamesOnTree(branches.first, shape, byId);
    expect(games.map((g) => g.game.igdbId).toSet(), {10, 11, 12});
    expect(games.length, 3);
    // Stable: the same inputs give the same order (fruit never reshuffles).
    expect(gamesOnTree(branches.first, shape, byId).map((g) => g.game.igdbId),
        games.map((g) => g.game.igdbId));
  });

  group('orchard camera', () {
    // A Pixel 8 portrait page: 411x914, soil line 204pt above the bottom.
    const box = Size(411, 914);
    const groundY = 914.0 - 204;

    test('the soil line lands exactly on groundY at every zoom', () {
      for (final z in [1.0, 1.15, 1.3]) {
        final r = treeFrame(box, groundY, z);
        final s = r.width / kTreeArtW;
        expect(r.top + kTreeBaseY * s, moreOrLessEquals(groundY, epsilon: 0.01));
        expect(r.center.dx, moreOrLessEquals(box.width / 2, epsilon: 0.01));
      }
    });

    test('a full tree never reaches into the title band', () {
      // Width-bound phone, and a short landscape box where height binds.
      for (final b in [box, const Size(914, 411)]) {
        final g = b.height - 120;
        final r = treeFrame(b, g, treeZoom(kTreeSlots));
        final canopyTop = r.top + kCanopyTop * (r.width / kTreeArtW);
        expect(canopyTop, greaterThanOrEqualTo(140 - 0.01));
      }
    });

    test('zoom only ever eases back as a tree fills, never closer', () {
      var last = double.infinity;
      for (var g = 0; g <= kTreeSlots; g++) {
        final z = treeZoom(g);
        expect(z, lessThanOrEqualTo(last));
        last = z;
      }
      expect(treeZoom(0), 1.3);
      expect(treeZoom(4), 1.0);
      expect(treeZoom(kTreeSlots), 1.0);
    });

    test('on screen the tree still only grows as the camera eases back', () {
      // Sapling to full canopy spans artboard 501 -> 185 (measured on device),
      // travelled along the file's size, which is treeSize(games).
      double onScreen(int g) {
        final top = 501 - (501 - kCanopyTop) * (treeSize(g.toDouble()) / kTreeSlots);
        return (kTreeBaseY - top) * treeZoom(g);
      }
      for (var g = 1; g <= kTreeSlots; g++) {
        expect(onScreen(g), greaterThan(onScreen(g - 1)),
            reason: 'the tree must never look smaller after a game is added '
                '(DECISIONS.md)');
      }
    });
  });

  group('growth curve', () {
    test('every game grows the tree, the first ones the most', () {
      var last = treeSize(0);
      var lastStep = double.infinity;
      expect(last, 0);
      for (var g = 1; g <= kTreeSlots; g++) {
        final s = treeSize(g.toDouble());
        expect(s, greaterThan(last), reason: 'game $g must grow the tree');
        expect(s - last, lessThanOrEqualTo(lastStep + 1e-9),
            reason: 'front-loaded: no later game grows it more than an earlier one');
        lastStep = s - last;
        last = s;
      }
      expect(treeSize(kTreeSlots.toDouble()), moreOrLessEquals(kTreeSlots.toDouble()));
      expect(treeSize(3), greaterThan(0.4 * kTreeSlots),
          reason: 'three games already read as a real tree');
    });

    test('past the last slot the tree holds at full size', () {
      expect(treeSize(40), moreOrLessEquals(kTreeSlots.toDouble()));
    });
  });

  group('night sky', () {
    Future<Color> sample(NightSkyPainter p, Size size, Offset at) async {
      final rec = ui.PictureRecorder();
      p.paint(Canvas(rec), size);
      final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
      final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final i = ((at.dy.toInt() * size.width.toInt()) + at.dx.toInt()) * 4;
      final b = data.buffer.asUint8List();
      return Color.fromARGB(b[i + 3], b[i], b[i + 1], b[i + 2]);
    }

    testWidgets('the hill ridge meets the soil line under the trunk, sky above it',
        (tester) async {
      await tester.runAsync(() async {
      const size = Size(411, 914);
      const groundY = 710.0;
      final p = NightSkyPainter(tree: treeFrame(size, groundY, 1), groundY: groundY);
      final below = await sample(p, size, const Offset(205, groundY + 6));
      final above = await sample(p, size, const Offset(205, groundY - 6));
      final hill = Tokens.cosmos.hillTop;
      double dist(Color a, Color b) =>
          ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255;
      expect(dist(below, hill), lessThan(12), reason: 'just under the soil is hill');
      expect(dist(above, hill), greaterThan(12), reason: 'just above it is sky');
      // The screen corners under the ridge are ground too, not sky: the hill
      // spans the full width with nothing showing through at the edges.
      final corner = await sample(p, size, const Offset(2, 912));
      expect(dist(corner, Tokens.cosmos.hillDeep), lessThan(16));
      });
    });
  });
}
