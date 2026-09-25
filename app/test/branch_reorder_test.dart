// The index arithmetic behind dragging a branch to a new position.
//
// This exists because the drag path had NO test. `branch_screen_test.dart`
// reorders by calling the store directly -- its own group is named "reorder
// without dragging" -- so when Flutter 3.41 deprecated `onReorder` in favour of
// `onReorderItem`, nothing in the suite could have caught the difference between
// them, and the difference is an off-by-one that silently drops a branch in the
// wrong slot.
//
// The two callbacks disagree about what the destination index MEANS:
//
//   onReorder     (deprecated) -- a PRE-removal insertion index. Moving an item
//                                 downward overshoots by one, so the caller had
//                                 to apply `to > from ? to - 1 : to` itself.
//   onReorderItem (current)    -- a POST-removal index. The framework already
//                                 applies that correction in
//                                 `_handleReorderItem` before calling back, so a
//                                 caller that applies it AGAIN subtracts twice.
//
// `reorderedIds` therefore must NOT correct the index. These tests fail if the
// correction is ever reintroduced.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/branches/branch_screen.dart';

void main() {
  group('reorderedIds treats the destination as a post-removal index', () {
    test('dragging the first branch down two places puts it third', () {
      // The user drags index 0 past index 2. The framework sees a pre-removal
      // insertion index of 3, applies its own `newIndex -= 1`, and calls back
      // with (0, 2). The branch must end up AT index 2.
      //
      // Reintroducing `to > from ? to - 1 : to` yields [20, 10, 30, 40] here --
      // one slot short -- which is exactly the regression this guards.
      expect(reorderedIds([10, 20, 30, 40], 0, 2), [20, 30, 10, 40]);
    });

    test('dragging the last branch up two places puts it second', () {
      // Upward moves never needed the correction, so they are the control: this
      // case passes under both callbacks and proves the test is not simply
      // asserting "no adjustment" everywhere.
      expect(reorderedIds([10, 20, 30, 40], 3, 1), [10, 40, 20, 30]);
    });

    test('dragging a branch to the end keeps every id exactly once', () {
      final out = reorderedIds([10, 20, 30, 40], 0, 3);
      expect(out, [20, 30, 40, 10]);
      expect(out.toSet(), hasLength(4), reason: 'no id may be lost or doubled');
    });

    test('a move to the same index changes nothing', () {
      // The framework filters this case out before calling back, but the
      // function must not corrupt the list if it ever arrives.
      expect(reorderedIds([10, 20, 30], 1, 1), [10, 20, 30]);
    });

    test('the input iterable is not mutated', () {
      // The widget passes `branches.map((b) => b.id)`, a lazy iterable over
      // store state. Reordering must not write back through it.
      final source = [10, 20, 30];
      reorderedIds(source, 0, 2);
      expect(source, [10, 20, 30]);
    });
  });
}
