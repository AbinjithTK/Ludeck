// The reduced-motion duration helper, pure.
//
// DECISIONS.md requires reduced motion be honoured by RESOLVING instantly, not
// by skipping in a way that loses state. The helper collapses a duration to
// zero when the OS setting is on; a zero-duration controller still runs to its
// end value, so nothing is left half-built. Callers pass
// MediaQuery.disableAnimationsOf(context); this tests the pure bool -> Duration.

import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/tokens.dart';

void main() {
  test('normal motion keeps the duration', () {
    expect(
      Tokens.motion.maybe(Tokens.motion.harvest, reduceMotion: false),
      Tokens.motion.harvest,
    );
  });

  test('reduced motion collapses to zero, not a skip', () {
    // Zero, not "don't run": a zero-duration animation still fires listeners and
    // lands on its end value, so a node arrives at full size and a burst reaches
    // its final frame. That is the DECISIONS.md requirement.
    expect(
      Tokens.motion.maybe(Tokens.motion.grow, reduceMotion: true),
      Duration.zero,
    );
    expect(
      Tokens.motion.maybe(Tokens.motion.harvest, reduceMotion: true),
      Duration.zero,
    );
  });
}
