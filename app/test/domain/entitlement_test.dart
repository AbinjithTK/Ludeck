import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/domain/entitlement.dart';

void main() {
  test('a free user is allowed every capability that is not paid', () {
    for (final c in Capability.values) {
      if (isFree(c)) {
        expect(allows(c, isPro: false), isTrue,
            reason: '$c is marked free, so a free user must be allowed it');
      }
    }
  });

  test('a pro user is allowed absolutely everything, with no exception', () {
    for (final c in Capability.values) {
      expect(allows(c, isPro: true), isTrue);
    }
  });

  test('a free user is refused every capability that is paid', () {
    for (final c in Capability.values) {
      if (!isFree(c)) {
        expect(allows(c, isPro: false), isFalse,
            reason: '$c is paid, and isPro is false, so it must be refused');
      }
    }
  });

  test('the reasoned pick is paid, the plain pick is not gated by this file '
      'at all', () {
    // There is no Capability for the plain pick. choosePick with no filters
    // is free because nothing here can refuse it: only the filtered version
    // is behind Capability.reasonedPick. This test exists so that adding a
    // gate to the plain pick becomes a conscious, visible change here rather
    // than something added quietly in a screen.
    expect(isFree(Capability.reasonedPick), isFalse);
    expect(Capability.values.length, 4,
        reason: 'if this grows, check whether the new value accidentally '
            'covers the ungated plain pick');
  });

  test('collection size is never a Capability, so it can never be gated by '
      'this mechanism', () {
    // QuestLog gates at 15 games and Cibby at 10. Ludeck does not, on purpose.
    // The proof that stays true as the enum grows: no member's name can even
    // plausibly mean "how many games you may own".
    final names = Capability.values.map((c) => c.name.toLowerCase());
    for (final n in names) {
      expect(n, isNot(contains('limit')));
      expect(n, isNot(contains('count')));
      expect(n, isNot(contains('size')));
      expect(n, isNot(contains('max')));
    }
  });

  test('sharing is never a Capability, so it can never be gated by this '
      'mechanism', () {
    final names = Capability.values.map((c) => c.name.toLowerCase());
    for (final n in names) {
      expect(n, isNot(contains('share')));
      expect(n, isNot(contains('public')));
    }
  });
}
