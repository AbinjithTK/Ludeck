// A portrait's trees must stand ON the meadow, never above it.
//
// 2026-09-28 ("these trees are in air"): the ridge had one crest at the
// picture's centre while two or three trees stood at slot centres, where the
// ridge dips, so every trunk ended in mid-air above the hill.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludeck/ui/orchard/meadow.dart';
import 'package:ludeck/ui/orchard/orchard_portrait.dart';
import 'package:ludeck/ui/orchard/rive_tree.dart';

void main() {
  const sizes = [Size(360, 260), Size(412, 300), Size(600, 340), Size(1080, 560)];
  const counts = <List<int>>[
    [1],
    [6, 2],
    [3, 9, 1],
    [0, 4, 12],
    [5, 5, 5, 5, 5],
  ];

  for (final size in sizes) {
    for (final games in counts) {
      test('trunks planted at ${size.width}x${size.height}, ${games.length} trees', () {
        final soil = size.height * 0.2;
        final groundY = size.height - soil;
        final frames = portraitFrames(size, soil, games);
        expect(frames, hasLength(games.length));
        final slotW = size.width / games.length;
        for (var i = 0; i < frames.length; i++) {
          final f = frames[i];
          final s = f.width / kTreeArtW;
          final foot = Offset(f.left + kTreeBaseX * s, f.top + kTreeBaseY * s);
          final surface = ridgeY(foot.dx, slotW, groundY);
          // On or just into the ground: never above it, never buried.
          expect(foot.dy, greaterThanOrEqualTo(surface - 0.01),
              reason: 'tree $i floats ${surface - foot.dy}px above the hill');
          expect(foot.dy - surface, lessThanOrEqualTo(kFootSink + 0.01));
          // Each trunk stands in its own slot, on that slot's crest.
          expect(foot.dx, moreOrLessEquals(slotW * (i + 0.5), epsilon: 0.01));
          expect(surface, moreOrLessEquals(groundY, epsilon: 0.01));
        }
      });
    }
  }

  test('the old single-crest ridge really left two trees in the air', () {
    // Control: the bug this guards. With the picture's full width as the
    // ridge period, slot centres at 1/4 and 3/4 sit deep in a dip.
    const w = 412.0, groundY = 240.0;
    expect(ridgeY(w * 0.25, w, groundY) - groundY, greaterThan(5));
  });
}
