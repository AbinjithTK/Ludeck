// The shake (the orchard's roulette): what can fall, how often, and that
// "shake again" never hands back the same game while there is another.

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
  test('only what can be played tonight falls', () {
    final tree = [
      item(1, p: Progress.finished),
      item(2, o: Ownership.spotted),
      item(3, p: Progress.abandoned),
      item(4, shelved: true),
    ];
    expect(shakePick(tree, math.Random(1)), isNull,
        reason: 'finished, a bud, set aside and shelved never fall');
    final pick = shakePick([...tree, item(5)], math.Random(1));
    expect(pick?.item.game.igdbId, 5);
    expect(pick?.reason, isNotEmpty, reason: 'every pick says why');
  });

  test('a game in hand falls about three times as often as one not started', () {
    final tree = [item(1, p: Progress.playing), item(2)];
    final rnd = math.Random(42);
    var inHand = 0;
    for (var i = 0; i < 4000; i++) {
      if (shakePick(tree, rnd)!.item.game.igdbId == 1) inHand++;
    }
    expect(inHand / 4000, closeTo(0.75, 0.03));
  });

  test('shake again never repeats while there is another, and can when not', () {
    final tree = [item(1), item(2), item(3)];
    final rnd = math.Random(7);
    for (var i = 0; i < 200; i++) {
      final last = rnd.nextInt(3) + 1;
      expect(shakePick(tree, rnd, avoid: last)!.item.game.igdbId, isNot(last));
    }
    expect(shakePick([item(9)], rnd, avoid: 9)!.item.game.igdbId, 9,
        reason: 'one game on the tree still falls');
  });
}
