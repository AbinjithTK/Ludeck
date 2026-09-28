// The shake (the orchard's roulette): every game on the tree can fall, what
// you can play tonight falls most, a run of shakes goes round the whole tree
// before anything falls twice, and "shake again" never hands back the same
// game while there is another.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/data/enums.dart';
import 'package:ludeck/data/models.dart';
import 'package:ludeck/domain/pick.dart';

TreeItem item(int id,
        {Ownership o = Ownership.owned,
        Progress p = Progress.untouched,
        bool shelved = false}) =>
    TreeItem(
      game: Game(igdbId: id, title: 'Game $id'),
      entry: Entry(igdbId: id, ownership: o, progress: p, shelved: shelved),
      copies: const [],
    );

void main() {
  test('every game hanging on the tree can fall', () {
    final tree = [
      item(1, p: Progress.finished),
      item(2, o: Ownership.spotted),
      item(3, p: Progress.abandoned),
      item(4, shelved: true),
      item(5, p: Progress.playing),
      item(6, o: Ownership.released),
    ];
    final seen = <int>{};
    final rnd = math.Random(3);
    for (var i = 0; i < 600; i++) {
      final p = shakePick(tree, rnd)!;
      expect(p.reason, isNotEmpty, reason: 'every pick says why');
      seen.add(p.item.game.igdbId);
    }
    expect(seen, {1, 2, 3, 4, 5, 6},
        reason: 'before 2026-09-28 only owned, unfinished games fell: on a '
            'real six-game tree that was two of six, and read as broken. A '
            'given-away game kept on the tree (Red Dead Redemption 2 on '
            'device) hung there and never came down either');
    expect(shakePick(const [], rnd), isNull, reason: 'an empty tree drops nothing');
  });

  test('a game in hand falls six times as often as a finished one', () {
    final tree = [item(1, p: Progress.playing), item(2, p: Progress.finished)];
    final rnd = math.Random(42);
    var inHand = 0;
    for (var i = 0; i < 7000; i++) {
      if (shakePick(tree, rnd)!.item.game.igdbId == 1) inHand++;
    }
    expect(inHand / 7000, closeTo(6 / 7, 0.02));
  });

  test('a run of shakes goes round the whole tree before a repeat', () {
    // Six not started and one in hand: heavily weighted, still once a round.
    final tree = [for (var i = 1; i <= 6; i++) item(i), item(7, p: Progress.playing)];
    final bag = ShakeBag();
    final rnd = math.Random(11);
    for (var round = 0; round < 30; round++) {
      final fell = <int>{
        for (var k = 0; k < tree.length; k++)
          bag.shake(1, tree, rnd)!.item.game.igdbId,
      };
      expect(fell.length, tree.length,
          reason: 'round $round: every game falls once per round');
    }
  });

  test('never the same game twice in a row while there is another', () {
    final tree = [item(1), item(2), item(3)];
    final bag = ShakeBag();
    final rnd = math.Random(7);
    int? last;
    for (var i = 0; i < 300; i++) {
      final id = bag.shake(1, tree, rnd)!.item.game.igdbId;
      expect(id, isNot(last), reason: 'including across a round boundary');
      last = id;
    }
    expect(bag.shake(2, [item(9)], rnd)!.item.game.igdbId, 9);
    expect(bag.shake(2, [item(9)], rnd)!.item.game.igdbId, 9,
        reason: 'one game on the tree still falls every time');
  });

  test('a game taken off the tree leaves the round', () {
    final bag = ShakeBag();
    final rnd = math.Random(5);
    final tree = [item(1), item(2), item(3)];
    final first = bag.shake(1, tree, rnd)!.item.game.igdbId;
    final rest = tree.where((i) => i.game.igdbId != first).toList();
    final fell = {
      bag.shake(1, rest, rnd)!.item.game.igdbId,
      bag.shake(1, rest, rnd)!.item.game.igdbId,
    };
    expect(fell, rest.map((i) => i.game.igdbId).toSet());
  });

  test('bags are per tree', () {
    final bag = ShakeBag();
    final rnd = math.Random(9);
    final a = [item(1), item(2)], b = [item(1), item(2)];
    bag.shake(1, a, rnd);
    bag.shake(1, a, rnd);
    final onB = {bag.shake(2, b, rnd)!.item.game.igdbId, bag.shake(2, b, rnd)!.item.game.igdbId};
    expect(onB, {1, 2});
  });
}
