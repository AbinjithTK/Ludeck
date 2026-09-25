// Level and progress, derived from harvested games.
//
// Pure functions, so these are plain `test()` -- no widget, no database. What is
// worth asserting is not "it returns a number" but the rules the number has to
// obey, because a level is a promise: DECISIONS.md says gamification may only
// reward what already happened, so it must never go DOWN, and never depend on
// anything that can shrink.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/domain/level.dart';

void main() {
  group('the ladder', () {
    test('a brand new tree is level 1, not level 0', () async {
      // Level 0 would read as "you have nothing", which is the empty-state guilt
      // DECISIONS.md forbids. Having a tree at all is level 1.
      final start = levelFor(0);
      expect(start.level, 1);
      expect(start.progress, 0.0);
    });

    test('the first harvest reaches level 2', () {
      // The first step is deliberately cheap: it is the moment the number starts
      // meaning something.
      expect(levelFor(1).level, 2);
    });

    test('level never decreases as harvests increase', () {
      // The load-bearing property. If this can fail, the number is a score that
      // punishes, not a record of what happened.
      var previous = 0;
      for (var harvested = 0; harvested <= 80; harvested++) {
        final level = levelFor(harvested).level;
        expect(level, greaterThanOrEqualTo(previous),
            reason: 'level dropped at $harvested harvests');
        previous = level;
      }
    });

    test('progress is always a usable fraction', () {
      for (var harvested = 0; harvested <= 80; harvested++) {
        final p = levelFor(harvested).progress;
        expect(p.isFinite, isTrue, reason: 'NaN at $harvested');
        expect(p, inInclusiveRange(0.0, 1.0), reason: 'out of range at $harvested');
      }
    });

    test('progress rises within a level and resets on reaching the next', () {
      // Level 3 spans 3..5 harvests (threshold 3, next 6).
      final atFloor = levelFor(3);
      final midway = levelFor(4);
      final justBelow = levelFor(5);
      final nextLevel = levelFor(6);

      expect(atFloor.level, 3);
      expect(atFloor.progress, 0.0);
      expect(midway.progress, greaterThan(atFloor.progress));
      expect(justBelow.progress, greaterThan(midway.progress));
      expect(nextLevel.level, 4);
      expect(nextLevel.progress, 0.0);
    });

    test('the top of the ladder reads as complete, not as stuck at zero', () {
      // Past the last threshold there is no next level. Showing 0% would say the
      // user had just started, which is the opposite of the truth.
      final top = levelFor(1000);
      expect(top.level, kLevelThresholds.length);
      expect(top.progress, 1.0);
      expect(top.neededForNext, 0);
    });

    test('neededForNext counts down to the next level', () {
      // Level 3 tops out at 6 harvests.
      expect(levelFor(3).neededForNext, 3);
      expect(levelFor(5).neededForNext, 1);
    });

    test('a negative count is clamped rather than throwing', () {
      // Not reachable from the collection, but a guard is cheaper than trusting
      // every future caller.
      expect(levelFor(-5).level, 1);
      expect(levelFor(-5).progress, 0.0);
    });

    test('the thresholds strictly increase', () {
      // A flat or decreasing step would make a level span zero harvests and
      // divide by zero in the progress calculation.
      for (var i = 1; i < kLevelThresholds.length; i++) {
        expect(kLevelThresholds[i], greaterThan(kLevelThresholds[i - 1]),
            reason: 'threshold $i does not increase');
      }
    });
  });
}
