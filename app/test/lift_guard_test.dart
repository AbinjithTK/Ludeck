// Games left their trees on device (2026-09-28): the Rive file's `pressed`
// is only reset by a press on the sky, so a long-press anywhere (a slow tap
// on the ground tray, a finger resting on the grass) lifted whatever fruit
// was touched last, and letting go over the tray put it on the ground. A
// lift now needs the press to be on the fruit itself.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/orchard/orchard_view.dart';

void main() {
  const card = Rect.fromLTWH(100, 300, 40, 53);

  test('a press on the fruit lifts it, with a finger of slack', () {
    expect(liftHits(card, card.center), isTrue);
    expect(liftHits(card, card.topLeft - const Offset(8, 8)), isTrue);
  });

  test('a press anywhere else lifts nothing', () {
    expect(liftHits(card, const Offset(120, 700)), isFalse,
        reason: 'the ground tray, far below the canopy');
    expect(liftHits(card, card.bottomRight + const Offset(12, 12)), isFalse);
  });
}
