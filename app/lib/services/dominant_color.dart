// Extract one representative colour from a cover image.
//
// This is what makes the tree take its colour from the user's OWN games: each
// fruit casts a bloom in its cover's dominant hue, so a library of neon shooters
// lights the wood differently from a library of cosy farm sims, and two people's
// trees genuinely differ. It is data-driven colour, not decoration added on top.
//
// PURE on purpose. It takes raw RGBA bytes and returns a Color, with no network,
// no `dart:ui` image decode and no canvas, so every rule of the extraction is
// unit-tested with synthetic pixel data. The async decode that produces those
// bytes lives in `CoverArtCache`, where it can be mocked; the interesting logic
// -- which pixels count, how they are bucketed, how gold is protected -- is here
// and is tested directly.

import 'dart:typed_data';
import 'dart:ui';

import '../ui/tokens.dart';

/// How close (in RGB channel distance, 0..1 per channel summed) a colour may sit
/// to harvest gold before it is pulled away. Gold is the ONE reward signal
/// (`DECISIONS.md`), so a mustard-yellow cover must not light the tree in a hue
/// a user would read as "harvested".
const double _goldGuardDistance = 0.28;

/// Extract the dominant vivid colour from [rgba], a row-major RGBA byte buffer
/// of [width] x [height] pixels (4 bytes per pixel).
///
/// The rules, each one tested:
///  - SKIP fully transparent pixels: padding around a non-square cover carries
///    no colour and would drag every result toward whatever the pad is.
///  - WEIGHT by saturation. A cover is mostly near-grey box art with a few vivid
///    accents, and the accent is what a person would call "its colour". A plain
///    average returns mud; weighting by saturation returns the accent.
///  - BUCKET into a coarse hue/lightness grid and take the heaviest bucket,
///    rather than averaging, so two opposite vivid colours do not average into
///    grey between them.
///  - GUARD gold: if the winner sits within [_goldGuardDistance] of
///    `palette.accent`, rotate it away so it cannot impersonate the harvest cue.
///
/// Returns null when the image has no usable colour at all (fully transparent,
/// or uniformly grey), so the caller can simply skip the bloom rather than cast
/// a grey one.
Color? dominantColor(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) return null;

  // Downsample: at most ~48x48 samples is plenty for one representative colour,
  // and it keeps this cheap on the big covers IGDB serves.
  final stepX = (width / 48).ceil().clamp(1, width);
  final stepY = (height / 48).ceil().clamp(1, height);

  // Coarse buckets: 12 hue sectors x 3 lightness bands. Fine enough to separate
  // teal from lime, coarse enough that near-identical accents pool together.
  const hueSectors = 12;
  const lightBands = 3;
  final weight = List<double>.filled(hueSectors * lightBands, 0);
  final sumR = List<double>.filled(hueSectors * lightBands, 0);
  final sumG = List<double>.filled(hueSectors * lightBands, 0);
  final sumB = List<double>.filled(hueSectors * lightBands, 0);
  var any = false;

  for (var y = 0; y < height; y += stepY) {
    for (var x = 0; x < width; x += stepX) {
      final i = (y * width + x) * 4;
      final a = rgba[i + 3];
      if (a < 8) continue; // transparent padding
      final r = rgba[i] / 255.0;
      final g = rgba[i + 1] / 255.0;
      final b = rgba[i + 2] / 255.0;
      final hsl = _toHsl(r, g, b);
      final hue = hsl[0], sat = hsl[1], light = hsl[2];
      // Weight = saturation squared, so vivid accents dominate near-grey box art
      // hard rather than gently. A near-grey pixel contributes almost nothing.
      final w = sat * sat;
      if (w <= 0) continue;
      any = true;
      final hs = ((hue / 360.0) * hueSectors).floor().clamp(0, hueSectors - 1);
      final lb = (light * lightBands).floor().clamp(0, lightBands - 1);
      final bucket = lb * hueSectors + hs;
      weight[bucket] += w;
      sumR[bucket] += r * w;
      sumG[bucket] += g * w;
      sumB[bucket] += b * w;
    }
  }
  if (!any) return null;

  var best = 0;
  for (var k = 1; k < weight.length; k++) {
    if (weight[k] > weight[best]) best = k;
  }
  if (weight[best] <= 0) return null;

  var r = sumR[best] / weight[best];
  var g = sumG[best] / weight[best];
  var b = sumB[best] / weight[best];

  // Guard gold. If the winner is close to the accent, rotate its hue by 40deg so
  // it stays vivid and clearly the game's own colour, but is no longer gold.
  final gold = Tokens.palette.accent;
  final dist = (r - gold.r).abs() + (g - gold.g).abs() + (b - gold.b).abs();
  if (dist < _goldGuardDistance) {
    final hsl = _toHsl(r, g, b);
    final rgb = _fromHsl((hsl[0] + 40) % 360, hsl[1], hsl[2]);
    r = rgb[0];
    g = rgb[1];
    b = rgb[2];
  }

  return Color.from(alpha: 1, red: r, green: g, blue: b);
}

/// RGB (each 0..1) to [hue 0..360, saturation 0..1, lightness 0..1].
List<double> _toHsl(double r, double g, double b) {
  final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final l = (maxC + minC) / 2;
  final d = maxC - minC;
  if (d == 0) return [0, 0, l];
  final s = d / (1 - (2 * l - 1).abs());
  double h;
  if (maxC == r) {
    h = ((g - b) / d) % 6;
  } else if (maxC == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  h *= 60;
  if (h < 0) h += 360;
  return [h, s, l];
}

/// [hue 0..360, sat 0..1, light 0..1] back to RGB (each 0..1).
List<double> _fromHsl(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final hp = h / 60;
  final x = c * (1 - (hp % 2 - 1).abs());
  double r = 0, g = 0, b = 0;
  if (hp < 1) {
    r = c; g = x;
  } else if (hp < 2) {
    r = x; g = c;
  } else if (hp < 3) {
    g = c; b = x;
  } else if (hp < 4) {
    g = x; b = c;
  } else if (hp < 5) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  final m = l - c / 2;
  return [r + m, g + m, b + m];
}
