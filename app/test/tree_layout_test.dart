import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/ui/tree/tree_layout.dart';

/// These test the tree's RULES, not its pixels.
///
/// The canvas cannot be judged from code, but its rules can, and every rule
/// here is a design decision from DESIGN.md that a refactor could silently
/// break. This is what stands in for looking at the screen.

const _canvas = Size(400, 800);

TreeLayout _layout(List<TreeItem> items) => TreeLayout.build(
      canvas: _canvas,
      items: items,
      fruitRadius: 22,
      trunkWidth: 22,
    );

TreeItem _item({
  required int id,
  required String title,
  Ownership ownership = Ownership.owned,
  Progress progress = Progress.untouched,
  int? seconds = 36000,
  List<Platform> platforms = const [Platform.pc],
}) =>
    TreeItem(
      game: Game(igdbId: id, title: title, timeToBeatSeconds: seconds),
      entry: Entry(igdbId: id, ownership: ownership, progress: progress),
      copies: platforms
          .map((p) => Copy(
                igdbId: id,
                platform: p,
                form: Form.digital,
                acquired: Acquired.bought,
              ))
          .toList(),
    );

void main() {
  group('branches exist only for platforms actually owned', () {
    test('a PC-only collection grows exactly one branch', () {
      final l = _layout([_item(id: 1, title: 'A')]);
      expect(l.branches.length, 1);
      expect(l.branches.single.platform, Platform.pc);
    });

    test('no games means no branches, and that is not an error state', () {
      final l = _layout([]);
      expect(l.branches, isEmpty);
      expect(l.fruitCount, 0);
    });

    test('branches follow the Platform enum order, lowest first', () {
      final l = _layout([
        _item(id: 1, title: 'A', platforms: [Platform.quest]),
        _item(id: 2, title: 'B', platforms: [Platform.pc]),
      ]);
      expect(l.branches.map((b) => b.platform).toList(),
          [Platform.pc, Platform.quest]);
    });
  });

  group('a game owned twice hangs twice', () {
    test('two platforms produce two fruit, not one', () {
      final l = _layout([
        _item(id: 1, title: 'A', platforms: [Platform.pc, Platform.switch_]),
      ]);
      expect(l.branches.length, 2);
      expect(l.fruitCount, 2, reason: 'one per copy, which is the truth');
    });
  });

  group('completion is the only status the tree shows', () {
    test('a finished game is marked harvested', () {
      final l = _layout([
        _item(id: 1, title: 'A', seconds: 36000, progress: Progress.finished)
      ]);
      expect(l.branches.single.fruit.single.harvested, isTrue);
    });

    test('a short game is not harvested just for being short', () {
      final l = _layout([_item(id: 1, title: 'A', seconds: 36000)]); // 10h
      expect(l.branches.single.fruit.single.harvested, isFalse,
          reason: 'length is not an achievement');
    });

    test('a game being played is not harvested yet', () {
      final l = _layout([
        _item(id: 1, title: 'A', seconds: 36000, progress: Progress.playing)
      ]);
      expect(l.branches.single.fruit.single.harvested, isFalse);
    });

    test('a game set aside is not harvested, because it is not the same event',
        () {
      final l = _layout([
        _item(id: 1, title: 'A', seconds: 36000, progress: Progress.abandoned)
      ]);
      expect(l.branches.single.fruit.single.harvested, isFalse);
    });

    test('length no longer changes how a fruit is marked at all', () {
      final short = _layout([_item(id: 1, title: 'A', seconds: 36000)]);
      final long = _layout([_item(id: 1, title: 'A', seconds: 360000)]);
      final unknown = _layout([_item(id: 1, title: 'A', seconds: null)]);
      expect(short.branches.single.fruit.single.harvested,
          long.branches.single.fruit.single.harvested);
      expect(short.branches.single.fruit.single.harvested,
          unknown.branches.single.fruit.single.harvested);
    });
  });

  group('harvested fruit sits nearer the branch tip', () {
    test('the finished one is further along than the unfinished one', () {
      final l = _layout([
        _item(id: 1, title: 'Unfinished', seconds: 36000),
        _item(
            id: 2,
            title: 'Finished',
            seconds: 36000,
            progress: Progress.finished),
      ]);
      final b = l.branches.single;
      final done = b.fruit.firstWhere((f) => f.harvested);
      final notDone = b.fruit.firstWhere((f) => !f.harvested);
      final dDone = (done.centre - b.start).distance;
      final dNotDone = (notDone.centre - b.start).distance;
      expect(dDone, greaterThan(dNotDone),
          reason: 'what you finished should catch the light');
    });
  });

  group('seeds are not on the tree', () {
    test('a spotted game is a seed in soil, on no branch', () {
      final l = _layout([
        _item(id: 1, title: 'Rec', ownership: Ownership.spotted, platforms: []),
      ]);
      expect(l.branches, isEmpty);
      expect(l.seeds.length, 1);
      expect(l.seeds.single.centre.dy, greaterThanOrEqualTo(l.soilY));
    });
  });

  group('branch thickness follows load', () {
    test('a branch with more fruit is thicker', () {
      final thin = _layout([_item(id: 1, title: 'A')]).branches.single;
      final thick = _layout([
        for (var i = 0; i < 12; i++) _item(id: i, title: 'G$i'),
      ]).branches.single;
      expect(thick.thickness, greaterThan(thin.thickness));
    });
  });

  group('hit testing', () {
    test('a tap on a fruit centre finds that fruit', () {
      final l = _layout([_item(id: 42, title: 'Target')]);
      final f = l.branches.single.fruit.single;
      expect(l.hitTest(f.centre)?.game.igdbId, 42);
    });

    test('a tap on empty canvas finds nothing and is not an error', () {
      final l = _layout([_item(id: 1, title: 'A')]);
      expect(l.hitTest(const Offset(2, 2)), isNull);
    });

    test('a near miss still hits, because a finger is not a pixel', () {
      final l = _layout([_item(id: 42, title: 'Target')]);
      final f = l.branches.single.fruit.single;
      final near = f.centre + Offset(f.radius + 6, 0);
      expect(l.hitTest(near)?.game.igdbId, 42);
    });

    test('a tap on a branch finds its platform', () {
      final l = _layout([_item(id: 1, title: 'A', platforms: [Platform.xbox])]);
      final b = l.branches.single;
      final mid = Offset.lerp(b.start, b.tip, 0.5)!;
      expect(l.hitTestBranch(mid), Platform.xbox);
    });
  });

  group('physics helpers match the values Apple ships', () {
    test('momentum projects forward, not backward', () {
      expect(projectMomentum(1000, 0.998), greaterThan(0));
      expect(projectMomentum(-1000, 0.998), lessThan(0));
    });

    test('a faster flick projects further', () {
      expect(projectMomentum(2000, 0.998),
          greaterThan(projectMomentum(1000, 0.998)));
    });

    test('rubber-banding resists more the further past the bound', () {
      final small = rubberBand(10, 100, 0.55);
      final large = rubberBand(100, 100, 0.55);
      expect(large, greaterThan(small));
      expect(large, lessThan(100),
          reason: 'resistance must compress, never track 1:1');
    });
  });

  group('hours convert exactly once', () {
    test('36000 seconds is 10 hours', () {
      expect(const Game(igdbId: 1, title: 'A', timeToBeatSeconds: 36000).hours,
          10);
    });

    test('a null length stays null rather than becoming zero', () {
      expect(const Game(igdbId: 1, title: 'A').hours, isNull);
    });
  });
}
