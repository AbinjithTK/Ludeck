// The dominant-colour extractor, tested on synthetic pixels.
//
// No network, no image decode: these buffers are built by hand, so each rule of
// the extraction is exercised directly. This is the "extraction is pure and
// tested" half of Stage 3.

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludeck/services/dominant_color.dart';
import 'package:ludeck/ui/tokens.dart';

/// Build a WxH RGBA buffer from a function giving each pixel's RGBA (0..255).
Uint8List buf(int w, int h, List<int> Function(int x, int y) px) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = px(x, y);
      final i = (y * w + x) * 4;
      out[i] = p[0];
      out[i + 1] = p[1];
      out[i + 2] = p[2];
      out[i + 3] = p[3];
    }
  }
  return out;
}

/// Distance between two colours in summed channel space (0..3).
double dist(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

void main() {
  test('a solid vivid image returns that colour', () {
    final c = dominantColor(buf(16, 16, (_, __) => [220, 30, 40, 255]), 16, 16);
    expect(c, isNotNull);
    // Red-dominant, low green and blue.
    expect(c!.r, greaterThan(0.7));
    expect(c.g, lessThan(0.3));
    expect(c.b, lessThan(0.3));
  });

  test('a fully transparent image returns null, not a colour', () {
    final c = dominantColor(buf(16, 16, (_, __) => [200, 50, 50, 0]), 16, 16);
    expect(c, isNull);
  });

  test('a uniformly grey image returns null, not mud', () {
    // Grey has zero saturation, so no pixel contributes weight.
    final c = dominantColor(buf(16, 16, (_, __) => [128, 128, 128, 255]), 16, 16);
    expect(c, isNull);
  });

  test('a vivid accent beats a grey majority', () {
    // 90% near-grey box art, 10% vivid blue accent. A plain average would be
    // grey-blue; saturation weighting must return blue.
    final c = dominantColor(
      buf(20, 20, (x, y) {
        final grey = (y * 20 + x) % 10 != 0; // 9 in 10 pixels grey
        return grey ? [120, 122, 118, 255] : [30, 60, 230, 255];
      }),
      20,
      20,
    );
    expect(c, isNotNull);
    expect(c!.b, greaterThan(c.r), reason: 'the blue accent should win');
    expect(c.b, greaterThan(c.g));
  });

  test('two opposite vivid colours do not average into grey', () {
    // Half vivid red, half vivid green in equal measure. Bucketing takes the
    // heaviest single bucket, so the result is red OR green, never the muddy
    // yellow-grey their average would give.
    final c = dominantColor(
      buf(20, 20, (x, _) => x < 10 ? [230, 20, 20, 255] : [20, 230, 20, 255]),
      20,
      20,
    );
    expect(c, isNotNull);
    final red = c!.r > 0.7 && c.g < 0.4;
    final green = c.g > 0.7 && c.r < 0.4;
    expect(red || green, isTrue,
        reason: 'expected a decisive red or green, got $c');
  });

  test('a gold-ish cover is pushed away from harvest gold', () {
    final gold = Tokens.palette.accent;
    // A cover whose dominant colour is close to the accent gold.
    final goldish = [
      (gold.r * 255).round(),
      (gold.g * 255).round(),
      (gold.b * 255).round(),
      255,
    ];
    final c = dominantColor(buf(16, 16, (_, __) => goldish), 16, 16);
    expect(c, isNotNull);
    // It must NOT still read as gold -- gold is the one reward signal.
    expect(dist(c!, gold), greaterThan(0.28),
        reason: 'a gold cover must not light the tree in the harvest colour');
    // But it stays a real, saturated colour rather than being greyed out.
    final maxC = [c.r, c.g, c.b].reduce((a, b) => a > b ? a : b);
    final minC = [c.r, c.g, c.b].reduce((a, b) => a < b ? a : b);
    expect(maxC - minC, greaterThan(0.15), reason: 'it should stay vivid');
  });

  test('a non-gold vivid colour is left alone', () {
    // Vivid teal is nowhere near gold, so the guard must not touch it.
    final c = dominantColor(buf(16, 16, (_, __) => [20, 200, 190, 255]), 16, 16);
    expect(c, isNotNull);
    expect(c!.g, greaterThan(0.5));
    expect(c.b, greaterThan(0.5));
    expect(c.r, lessThan(0.4));
  });

  test('degenerate inputs return null rather than throwing', () {
    expect(dominantColor(Uint8List(0), 0, 0), isNull);
    expect(dominantColor(Uint8List(4), 4, 4), isNull); // buffer too small
  });

  test('extraction is deterministic for the same pixels', () {
    List<int> px(int x, int y) =>
        (x + y).isEven ? [200, 40, 40, 255] : [40, 40, 200, 255];
    final a = dominantColor(buf(24, 24, px), 24, 24);
    final b = dominantColor(buf(24, 24, px), 24, 24);
    expect(a, equals(b));
  });
}
