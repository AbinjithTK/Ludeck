// The orchard's meadow: one continuous night landscape under every tree.
//
// Before this, each page painted its own sky and its own hill, so a swipe
// slid a whole hill away and brought a new one in, with a seam where two
// pages met. Now the land is one function of WORLD x (page index x width +
// position on the page) and is painted in three layers:
//
//   [MeadowBackPainter]   behind the pages: sky, parallax stars, the rolling
//                         ridge, back grass. Repaints from the page scroll.
//   per page              the tree's halo, its props and the tree itself,
//                         moving with the page (they belong to one tree).
//   [MeadowFrontPainter]  above the pages: a row of short front grass, so
//                         the trunk's foot stands IN the grass, not on it.
//
// The ridge crests exactly under each trunk (the soil line) and dips between
// trees, so trees stand on knolls of one rolling meadow and the ground never
// ends. The sky and stars are static apart from a slight parallax.
//
// What moves at rest (DECISIONS.md, reversed 2026-09-27 at Abin's request:
// "the grass and flowers should wiggle, make the scenes live"): the grass,
// the flowers, the fireflies and the lantern flame, driven by one
// [MeadowClock]. Bounded so it stays atmosphere, not a show: a slow wave of
// wind rolls across the meadow, blades bend a few degrees, and a swipe makes
// the grass trail behind the ground like real grass does, then settle. The
// sky, the tree, the covers, text and controls never move at rest. Nothing
// moves at all under the OS reduce-motion setting.

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../tokens.dart';
import 'rive_tree.dart' show kTreeArtW, treeFrame;
import 'tree_style.dart';

/// Time and wind for everything alive in the meadow. One per orchard.
class MeadowClock extends ChangeNotifier {
  /// Off under flutter_test: a clock that never stops would keep every
  /// `pumpAndSettle` on the home screen from ever settling. A test that wants
  /// the clock drives [advance] itself.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Seconds since the orchard opened.
  double t = 0;

  /// How far the grass is blown by the swipe, in radians of lean. Positive
  /// leans right. Follows the scroll's velocity through a short low-pass, so
  /// it rises with the swipe and settles in ~0.4s when the ground stops.
  double wind = 0;

  double? _lastScroll;

  // ---- touch: the meadow answers a finger ---------------------------------
  /// The finger, in WORLD coordinates (x + page scroll, screen y), or null.
  Offset? touch;

  /// How pressed the finger is, 0..1: rises fast on down, eases off after up,
  /// so grass parted by a finger springs back rather than snapping.
  double touchK = 0;
  bool _down = false;

  /// Taps on the meadow: flowers near one bounce, and each throws up a puff
  /// of petals. (world x, y, time).
  final List<(double, double, double)> pokes = [];

  /// Petals in the air: start (world), launch velocity, birth time, shade.
  final List<({Offset at, Offset v, double born, int shade})> petals = [];

  void pointerDown(Offset world) {
    touch = world;
    _down = true;
  }

  void pointerMove(Offset world) => touch = world;

  void pointerUp() => _down = false;

  /// A tap at [world]: a puff of [n] petals, and a bounce for flowers there.
  void poke(Offset world, {int n = 7}) {
    pokes.add((world.dx, world.dy, t));
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 1.6;
      final s = 110 + _rnd.nextDouble() * 120;
      petals.add((
        at: world + Offset((_rnd.nextDouble() - 0.5) * 16, -4),
        v: Offset(math.cos(a) * s, math.sin(a) * s),
        born: t,
        shade: _rnd.nextInt(3),
      ));
    }
    if (petals.length > 60) petals.removeRange(0, petals.length - 60);
  }

  final math.Random _rnd = math.Random(3);

  /// Seconds a petal lives, and the gravity pulling it down (px/s^2).
  static const double petalLife = 1.6, petalGravity = 240;

  /// Where petal [p] is now, and how visible (0 = gone).
  (Offset, double) petalAt(({Offset at, Offset v, double born, int shade}) p) {
    final a = t - p.born;
    final drag = math.exp(-1.6 * a); // air slows the throw
    final travel = p.v * ((1 - drag) / 1.6);
    final flutter = Offset(math.sin(a * 7 + p.born * 13) * 6, 0);
    final fall = Offset(0, 0.5 * petalGravity * 0.35 * a * a);
    final fade = (1 - a / petalLife).clamp(0.0, 1.0);
    return (p.at + travel + fall + flutter, fade);
  }

  /// Extra bounce for a flower at world ([x], [y]) from recent pokes, radians.
  double pokeNod(double x, double y) {
    var nod = 0.0;
    for (final (px, py, pt) in pokes) {
      final d = math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
      if (d > kPokeReach) continue;
      final a = t - pt;
      nod += 0.5 * (1 - d / kPokeReach) * math.exp(-4 * a) * math.sin(16 * a);
    }
    return nod;
  }

  /// Move time on by [dt] seconds with the pages at [scroll] px.
  void advance(double dt, double scroll) {
    if (dt <= 0) return;
    t += dt;
    final last = _lastScroll ?? scroll;
    _lastScroll = scroll;
    final v = (scroll - last) / dt; // px/s; the ground moves the other way
    final target = (v / kWindPerLean).clamp(-kWindMax, kWindMax);
    wind += (target - wind) * (1 - math.exp(-dt / kWindLag));
    touchK += ((_down ? 1.0 : 0.0) - touchK) *
        (1 - math.exp(-dt / (_down ? 0.05 : 0.30)));
    if (!_down && touchK < 0.01) touch = null;
    pokes.removeWhere((p) => t - p.$3 > 1.5);
    petals.removeWhere((p) => t - p.born > petalLife);
    notifyListeners();
  }
}

/// How far a finger parts the grass (px), how far a tap reaches a flower.
const double kTouchReach = 64, kPokeReach = 34;

/// How much a finger at [touch] (strength [k]) bends a blade whose middle is
/// at ([x], [y]): away from the finger, most when closest, nothing past
/// [kTouchReach]. Pure, so a test can pin the direction and the bound.
double touchLean(double x, double y, Offset? touch, double k) {
  if (touch == null || k < 0.005) return 0;
  final dx = x - touch.dx, dy = y - touch.dy;
  final d = math.sqrt(dx * dx + dy * dy);
  if (d > kTouchReach) return 0;
  final f = 1 - d / kTouchReach;
  return (dx >= 0 ? 1 : -1) * 0.9 * k * f * f;
}

/// Scroll speed (px/s) that bends the grass by one radian, the most it
/// bends, and how quickly it follows (seconds, low-pass time constant).
const double kWindPerLean = 5200, kWindMax = 0.32, kWindLag = 0.12;

/// The resting sway: blades bend by this much (radians) as the wave passes,
/// the wave's speed across the meadow, and how long one gust takes.
const double kSwayLean = 0.075, kSwaySpeed = 1.5, kGustPeriod = 17;

/// Extra lean for a blade at world x [xw] at time [t], with [wind].
/// Pure, so a test can pin that it is bounded and that it is 0 when still.
double swayAt(double xw, double t, double wind, double salt) {
  if (t == 0 && wind == 0) return 0;
  final gust = 0.55 + 0.45 * math.sin(2 * math.pi * t / kGustPeriod + xw * 0.0015);
  return kSwayLean * gust * math.sin(xw * 0.016 - t * kSwaySpeed + salt * 1.3) +
      wind;
}

/// Where the blossom's light is centred, in artboard units, and its reach.
const Offset kHaloCentre = Offset(190, 400);
const double kHaloRadius = 260;

/// The trunk's x in artboard units (TREE_X in rive/tree/build_tree.py).
const double kTreeBaseX = 180;

/// How far the meadow dips between two trees, as a fraction of page width.
const double kRidgeDip = 0.045;

/// Stars drift at this fraction of the page scroll: far away, barely moving.
const double kStarParallax = 0.08;

/// The ridge's height at world x [xw] for pages [pageW] wide whose trees'
/// soil line is [groundY]. Crest (== [groundY]) at every page centre, lowest
/// at the seams between pages, with the depth of each dip varied slowly so
/// the meadow does not read as a sine wave.
double ridgeY(double xw, double pageW, double groundY) {
  if (pageW <= 0) return groundY;
  final u = xw / pageW - 0.5;
  final depth = kRidgeDip * pageW *
      (1 + 0.35 * math.sin(2 * math.pi * xw / (2.3 * pageW)));
  return groundY + depth * (1 - math.cos(2 * math.pi * u)) / 2;
}

/// A stable pseudo-random value in [0, 1) for integer [k] and [salt]: the
/// same blade is the same shape every frame and every launch.
double _hash(int k, int salt) {
  var h = (k * 374761393 + salt * 668265263) & 0x7fffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
  return (h ^ (h >> 16)) / 0x7fffffff;
}

/// How lush the meadow is at world x [xw], 0..1: two slow waves and a finer
/// one, so there are thick patches, thin patches and the odd bare spot
/// instead of an even comb (2026-09-28: "the grass feels very organised in a
/// line"). Pure, so a test can pin that it really varies.
double lushAt(double xw, int salt) {
  final a = math.sin(xw * 0.0105 + salt * 0.7);
  final b = math.sin(xw * 0.031 + salt * 1.9 + 1.3);
  final c = math.sin(xw * 0.083 + salt * 3.1);
  return (0.5 + 0.30 * a + 0.14 * b + 0.06 * c).clamp(0.0, 1.0);
}

/// Grass over the visible world range, grown the way grass grows: in CLUMPS
/// (blades fanning out from one root, the middle ones tallest), clumps
/// scattered at uneven spacing and at a range of depths down the hill face
/// ([depthBand] px below the ridge), thicker where [lushAt] is high and bare
/// here and there, blades curving more near the tip, and the odd seed head.
/// Nearer (lower) clumps are larger and lighter. Batched into one path per
/// shade, so a frame costs a handful of draw calls, not one per blade.
void _paintGrass(Canvas canvas, Size size,
    {required double scroll,
    required double groundY,
    required double spacing,
    required double minH,
    required double maxH,
    required double sink,
    required int salt,
    required List<Color> shades,
    double depthBand = 0,
    double nearScale = 0.3,
    Color? moon,
    Color? seed,
    double time = 0,
    double wind = 0,
    Offset? touch,
    double touchK = 0,
    double? period}) {
  final pw = period ?? size.width;
  final paths = List.generate(shades.length, (_) => Path());
  final moonPath = Path(), seedPath = Path(), stemPath = Path();
  final first = ((scroll - maxH * 2) / spacing).floor();
  final last = ((scroll + size.width + maxH * 2) / spacing).ceil();
  for (var k = first; k <= last; k++) {
    final r1 = _hash(k, salt), r2 = _hash(k, salt + 1), r3 = _hash(k, salt + 2);
    final cx = k * spacing + (r2 - 0.5) * spacing * 1.2;
    final lush = lushAt(cx, salt);
    // Bare patches: thin ground loses clumps, never all of them.
    if (lush < 0.32 && r3 > lush * 2.2) continue;
    final dFrac = depthBand > 0 ? math.pow(r1, 1.5).toDouble() : 0.0;
    final near = 1 + nearScale * dFrac;
    final rootY = ridgeY(cx, pw, groundY) + sink + dFrac * depthBand;
    final clumpH = (minH + (maxH - minH) * (0.35 + 0.65 * lush) * (0.6 + 0.4 * r3)) * near;
    final n = 3 + (lush * 6 * (0.6 + 0.4 * r1)).round();
    final spread = (3 + 5 * lush) * near;
    // Farther clumps take the darker shades, nearer the lighter.
    final shadeBase = (dFrac * 0.55 + r2 * 0.45) * shades.length;
    for (var j = 0; j < n; j++) {
      final h1 = _hash(k * 17 + j, salt + 5), h2 = _hash(k * 17 + j, salt + 6);
      final u = n == 1 ? 0.0 : j / (n - 1) * 2 - 1; // -1..1 across the clump
      final x0 = cx + u * spread * 0.5 + (h1 - 0.5) * 2;
      final xr = x0 - scroll;
      if (xr < -maxH * 2 || xr > size.width + maxH * 2) continue;
      final h = clumpH * (1 - 0.38 * u.abs()) * (0.7 + 0.45 * h2);
      // Blades fan outward from the root; the wind and a finger add to it.
      final lean = u * 0.42 + (h1 - 0.5) * 0.30 +
          swayAt(x0, time, wind, h2) +
          touchLean(x0, rootY - h / 2, touch, touchK);
      final w = (1.3 + h2 * 1.5) * near;
      // A cubic that bends most near the tip, the way a blade droops.
      final c1 = Offset(xr + math.sin(lean * 0.35) * h * 0.35, rootY - h * 0.38);
      final c2 = Offset(xr + math.sin(lean * 0.8) * h * 0.72, rootY - h * 0.78);
      final tip = Offset(xr + math.sin(lean * 1.25) * h, rootY - math.cos(lean * 1.25) * h);
      final p = paths[(shadeBase + (h1 - 0.5)).floor().clamp(0, shades.length - 1)];
      p
        ..moveTo(xr - w / 2, rootY)
        ..cubicTo(c1.dx - w * 0.35, c1.dy, c2.dx - w * 0.15, c2.dy, tip.dx, tip.dy)
        ..cubicTo(c2.dx + w * 0.25, c2.dy, c1.dx + w * 0.45, c1.dy, xr + w / 2, rootY)
        ..close();
      // Moonlight on a tall blade: a soft filled sliver down its lit (left,
      // toward the moon) edge over the top third, tapering into the tip. A
      // fill, not a stroke, so it is light ON the blade, not a line round it.
      if (moon != null && h > maxH * 0.6) {
        final a = Offset.lerp(c1, c2, 0.75)!;
        moonPath
          ..moveTo(a.dx - w * 0.3, a.dy)
          ..quadraticBezierTo(c2.dx - w * 0.2, c2.dy, tip.dx, tip.dy)
          ..quadraticBezierTo(c2.dx + w * 0.05, c2.dy, a.dx + w * 0.05, a.dy)
          ..close();
      }
      // A seed head on the odd tall stem in a lush clump: a hair-thin filled
      // stem, and a grain (a slim filled oval along the stem) at its end.
      if (seed != null && j == n ~/ 2 && lush > 0.55 && r3 > 0.72) {
        final sh = h * 1.35;
        final ang = lean * 1.1;
        final st = Offset(xr + math.sin(ang) * sh, rootY - math.cos(ang) * sh);
        final mid = Offset(xr + math.sin(lean * 0.6) * sh * 0.6, rootY - sh * 0.62);
        final sw = 0.55 * near;
        stemPath
          ..moveTo(xr - sw, rootY - h * 0.2)
          ..quadraticBezierTo(mid.dx - sw * 0.6, mid.dy, st.dx, st.dy)
          ..quadraticBezierTo(mid.dx + sw * 0.6, mid.dy, xr + sw, rootY - h * 0.2)
          ..close();
        final gw = 2.4 * near, gh = 6.5 * near;
        final m = Matrix4.identity()
          ..translateByDouble(st.dx, st.dy, 0, 1)
          ..rotateZ(ang);
        seedPath.addPath(
            Path()..addOval(Rect.fromCenter(center: Offset(0, -gh * 0.3), width: gw, height: gh)),
            Offset.zero,
            matrix4: m.storage);
        // The grain's moonlit side.
        moonPath.addPath(
            Path()
              ..addOval(Rect.fromCenter(
                  center: Offset(-gw * 0.18, -gh * 0.45), width: gw * 0.5, height: gh * 0.6)),
            Offset.zero,
            matrix4: m.storage);
      }
    }
  }
  for (var i = 0; i < shades.length; i++) {
    canvas.drawPath(paths[i], Paint()..color = shades[i]);
  }
  if (seed != null) {
    canvas.drawPath(stemPath, Paint()..color = shades.last);
    canvas.drawPath(seedPath, Paint()..color = seed);
  }
  if (moon != null) {
    canvas.drawPath(moonPath, Paint()..color = moon);
  }
}

class MeadowBackPainter extends CustomPainter {
  MeadowBackPainter({
    required this.scroll,
    required this.groundFromBottom,
    this.halos = const [],
    this.period,
  }) : super(repaint: scroll);

  /// The ridge's wavelength in px: one crest per tree. Defaults to the
  /// painted width (the home screen: one tree per page). A portrait holding
  /// several trees in one picture passes its slot width, so a crest sits
  /// under every trunk instead of only under the picture's centre.
  final double? period;

  /// The pages' scroll offset in pixels (0 = first tree centred).
  final ValueListenable<double> scroll;

  /// Page i's tree glow: its blossom colour and camera zoom, or null (the
  /// patch). Painted here, world-locked, not on the page: a glow is wider than
  /// a page, and on the page it was cut into a hard vertical edge mid-swipe.
  final List<(Color, double)?> halos;

  /// The soil line's distance from the bottom edge (same for every page).
  final double groundFromBottom;

  static final List<(Offset, double, double)> _stars = () {
    final rnd = math.Random(7); // fixed: the same sky every launch
    return List.generate(70, (_) {
      final p = Offset(rnd.nextDouble(), math.pow(rnd.nextDouble(), 1.4) * 0.7);
      return (p, 0.4 + rnd.nextDouble() * 0.8, 0.10 + rnd.nextDouble() * 0.40);
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final s = scroll.value;
    final groundY = size.height - groundFromBottom;
    final c = Tokens.cosmos;

    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: c.night,
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromLTRB(0, 0, size.width, groundY)));

    // Stars over a band 1.6 screens wide, wrapped, drifting slowly.
    final span = size.width * 1.6;
    final star = Paint();
    for (final (p, r, a) in _stars) {
      final x = (p.dx * span - s * kStarParallax) % span;
      if (x > size.width + 2) continue;
      star.color = c.star.withValues(alpha: a);
      canvas.drawCircle(Offset(x, p.dy * groundY), r, star);
    }

    for (var i = 0; i < halos.length; i++) {
      final h = halos[i];
      final left = i * size.width - s;
      if (h == null || left > size.width * 1.5 || left < -size.width * 1.5) {
        continue;
      }
      final frame = treeFrame(size, groundY, h.$2).shift(Offset(left, 0));
      HaloPainter(tree: frame, colour: h.$1).paint(canvas, size);
    }

    // The ridge, sampled across the screen.
    final pw = period ?? size.width;
    final ridge = Path()..moveTo(-1, ridgeY(s - 1, pw, groundY));
    for (var x = 0.0; x <= size.width + 6; x += 6) {
      ridge.lineTo(x, ridgeY(s + x, pw, groundY));
    }
    final land = Path.from(ridge)
      ..lineTo(size.width + 6, size.height + 1)
      ..lineTo(-1, size.height + 1)
      ..close();
    canvas.drawPath(
        land,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.hillTop, c.hillDeep],
          ).createShader(
              Rect.fromLTRB(0, groundY - kRidgeDip * pw, size.width, size.height)));
    // Moonlight on the crest: a soft band, not a drawn line. The 1pt rim
    // stroke that was here made the whole meadow read as one ruled line.
    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
          ..color = c.hillRim.withValues(alpha: c.hillRim.a * 0.9));
    // The hill face darkens away from the light in uneven swells, so the
    // ground is a surface with some body and not a flat fill.
    canvas.save();
    canvas.clipPath(land);
    for (var k = ((s - size.width) / 160).floor(); k <= ((s + 2 * size.width) / 160).ceil(); k++) {
      final x = k * 160 + (_hash(k, 71) - 0.5) * 90 - s;
      // Well below the crest and faint: nearer the ridge, a 0.55 hollow sat
      // at a trunk's foot and read as a hole under the tree (2026-09-28).
      final y = ridgeY(x + s, pw, groundY) + 44 + _hash(k, 72) * 30;
      final r = 60 + _hash(k, 73) * 70;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: r * 2.4, height: r * 0.7),
          Paint()
            ..shader = RadialGradient(colors: [
              c.hillDeep.withValues(alpha: 0.3),
              c.hillDeep.withValues(alpha: 0),
            ]).createShader(Rect.fromCenter(center: Offset(x, y), width: r * 2.4, height: r * 0.7)));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MeadowBackPainter old) =>
      old.scroll != scroll ||
      old.groundFromBottom != groundFromBottom ||
      old.period != period ||
      !listEquals(old.halos, halos);
}

/// The back grass and the ridge's rim, on their own layer: they sway with
/// [clock] every frame, and the sky, stars and halos under them do not need
/// repainting for that.
class MeadowGrassPainter extends CustomPainter {
  MeadowGrassPainter(
      {required this.scroll, required this.groundFromBottom, this.clock, this.period})
      : super(repaint: Listenable.merge([scroll, clock]));

  final ValueListenable<double> scroll;
  final double groundFromBottom;
  final MeadowClock? clock;

  /// See [MeadowBackPainter.period].
  final double? period;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scroll.value;
    final groundY = size.height - groundFromBottom;
    final o = Tokens.orchard;
    // Back grass: clumps along the crest, the tallest in the meadow.
    _paintGrass(canvas, size,
        scroll: s,
        groundY: groundY,
        spacing: 8.5,
        minH: 8,
        maxH: 27,
        sink: 2,
        depthBand: 6,
        nearScale: 0.15,
        salt: 11,
        shades: [o.grassBack, Color.lerp(o.grassBack, o.grassFront, 0.5)!, o.grassFront],
        moon: o.grassMoon,
        seed: o.grassSeed,
        time: clock?.t ?? 0,
        wind: clock?.wind ?? 0,
        touch: clock?.touch,
        touchK: clock?.touchK ?? 0,
        period: period);
  }

  @override
  bool shouldRepaint(MeadowGrassPainter old) =>
      old.scroll != scroll ||
      old.clock != clock ||
      old.period != period ||
      old.groundFromBottom != groundFromBottom;
}

/// Short grass in FRONT of the trees, so each trunk's foot stands in it.
class MeadowFrontPainter extends CustomPainter {
  MeadowFrontPainter(
      {required this.scroll, required this.groundFromBottom, this.clock, this.period})
      : super(repaint: Listenable.merge([scroll, clock]));

  final ValueListenable<double> scroll;
  final MeadowClock? clock;

  /// See [MeadowBackPainter.period].
  final double? period;

  /// The soil line's distance from the bottom edge (same for every page).
  final double groundFromBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Tokens.orchard;
    final groundY = size.height - groundFromBottom;
    _paintGrass(canvas, size,
        scroll: scroll.value,
        groundY: groundY,
        spacing: 13,
        // Front grass is a low fringe the trunk's foot stands IN, not a
        // hedge: its blades were as tall as the flowers (maxH 15), so a tall
        // blade drew OVER a flower that is meant to be the nearest thing on
        // the meadow (2026-09-28, Abin: "some grass is on top of the flowers
        // that is really in front"). Shorter blades, sunk a little deeper,
        // keep the foot-in-grass reading while staying below the flowers.
        minH: 4,
        maxH: 9,
        sink: 5,
        depthBand: 22,
        nearScale: 0.45,
        salt: 29,
        shades: [o.grassBack, Color.lerp(o.grassBack, Tokens.cosmos.hillTop, 0.5)!],
        time: clock?.t ?? 0,
        wind: clock?.wind ?? 0,
        touch: clock?.touch,
        touchK: clock?.touchK ?? 0,
        period: period);
    // Petals thrown up by a tap on the meadow, drifting down as they fade.
    final c = clock;
    if (c == null || c.petals.isEmpty) return;
    final s = scroll.value;
    for (final p in c.petals) {
      final (at, fade) = c.petalAt(p);
      if (fade <= 0) continue;
      final a = c.t - p.born;
      canvas.save();
      canvas.translate(at.dx - s, at.dy);
      canvas.rotate(a * 5 + p.born * 11);
      canvas.drawOval(
          const Rect.fromLTWH(-3.2, -1.8, 6.4, 3.6),
          Paint()
            ..color = o.petals[p.shade % o.petals.length]
                .withValues(alpha: 0.9 * fade));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(MeadowFrontPainter old) =>
      old.scroll != scroll ||
      old.clock != clock ||
      old.period != period ||
      old.groundFromBottom != groundFromBottom;
}

/// One tree's light on the sky behind it, in its blossom's colour.
class HaloPainter extends CustomPainter {
  HaloPainter({required this.tree, required this.colour});
  final Rect tree;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final s = tree.width / kTreeArtW;
    final centre = tree.topLeft + kHaloCentre * s;
    final r = kHaloRadius * s;
    final a = Tokens.orchard.haloAlpha;
    canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            colour.withValues(alpha: a),
            colour.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: centre, radius: r)));
  }

  @override
  bool shouldRepaint(HaloPainter old) =>
      old.tree != tree || old.colour != colour;
}

/// A tree's props on the meadow. [front] paints what stands before the trunk
/// (flowers, mushrooms, stones, fireflies); otherwise what stands behind it
/// (fence, lantern). Every prop sits on [ridgeY], so it follows the knoll.
class DecorPainter extends CustomPainter {
  DecorPainter({
    required this.tree,
    required this.decor,
    required this.front,
    required this.groundY,
    required this.pageIndex,
    this.clock,
  }) : super(repaint: clock);

  final Rect tree;
  final Set<TreeDecor> decor;
  final bool front;
  final double groundY;
  final int pageIndex;

  /// Flowers nod, fireflies drift and pulse, the lantern flickers. Null or
  /// stopped: everything is drawn at rest.
  final MeadowClock? clock;
  double get _t => clock?.t ?? 0;
  double get _wind => clock?.wind ?? 0;

  /// A flower at page-local ([x], [y]) bends away from a finger brushing
  /// past and bounces when tapped. The clock's touch is in world x.
  double _pageW = 0; // set at the start of each paint
  double _touchNod(double x, double y) {
    final c = clock;
    if (c == null) return 0;
    final xw = pageIndex * _pageW + x;
    return touchLean(xw, y, c.touch, c.touchK) + c.pokeNod(xw, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (decor.isEmpty) return;
    final s = tree.width / kTreeArtW;
    final trunk = tree.left + kTreeBaseX * s;
    final world0 = pageIndex * size.width;
    _pageW = size.width;
    double ground(double x) => ridgeY(world0 + x, size.width, groundY);

    if (!front) {
      if (decor.contains(TreeDecor.fence)) _fence(canvas, trunk, s, ground);
      if (decor.contains(TreeDecor.lantern)) _lantern(canvas, trunk, s, ground);
      return;
    }
    if (decor.contains(TreeDecor.stones)) _stones(canvas, trunk, s, ground);
    if (decor.contains(TreeDecor.mushrooms)) _mushrooms(canvas, trunk, s, ground);
    if (decor.contains(TreeDecor.flowers)) _flowers(canvas, trunk, s, ground);
    if (decor.contains(TreeDecor.fireflies)) _fireflies(canvas, s);
  }

  void _fence(Canvas c, double trunk, double s, double Function(double) g) {
    final paint = Paint()..color = Tokens.orchard.fence;
    const n = 6;
    final x0 = trunk + 64 * s, step = 17 * s, h = 30 * s, w = 4.2 * s;
    final tops = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = x0 + i * step;
      final y = g(x) + 2;
      final ph = h * (1 - 0.06 * (i % 2));
      c.drawPath(
          Path()
            ..moveTo(x - w / 2, y)
            ..lineTo(x - w / 2, y - ph + w / 2)
            ..lineTo(x, y - ph)
            ..lineTo(x + w / 2, y - ph + w / 2)
            ..lineTo(x + w / 2, y)
            ..close(),
          paint);
      tops.add(Offset(x, y));
    }
    final rail = Paint()
      ..color = Tokens.orchard.fence
      ..strokeWidth = 2.6 * s
      ..strokeCap = StrokeCap.round;
    for (final f in const [0.38, 0.72]) {
      for (var i = 0; i < n - 1; i++) {
        c.drawLine(tops[i] - Offset(0, h * f), tops[i + 1] - Offset(0, h * f), rail);
      }
    }
  }

  void _lantern(Canvas c, double trunk, double s, double Function(double) g) {
    final x = trunk - 92 * s, y = g(x) + 2;
    final frame = Paint()..color = Tokens.orchard.lanternFrame;
    final light = Tokens.orchard.lanternLight;
    final postH = 66 * s;
    c.drawRect(Rect.fromLTRB(x - 1.6 * s, y - postH, x + 1.6 * s, y), frame);
    // Arm, hook and the lamp hanging from it.
    final armEnd = Offset(x + 16 * s, y - postH + 4 * s);
    c.drawLine(Offset(x, y - postH + 4 * s), armEnd,
        Paint()
          ..color = Tokens.orchard.lanternFrame
          ..strokeWidth = 2.2 * s);
    final lamp = Rect.fromCenter(
        center: armEnd + Offset(0, 13 * s), width: 11 * s, height: 14 * s);
    // Glow first, so the frame draws over its bright core. A candle's
    // flicker: two incommensurate waves, never more than 12% dimmer.
    final t = _t;
    final flame = t == 0 ? 1.0 : 0.94 + 0.06 * math.sin(t * 7.3) * math.sin(t * 3.1 + 1);
    for (final (r, a) in [(46.0, 0.14 * flame), (20.0, 0.22 * flame)]) {
      c.drawCircle(
          lamp.center,
          r * s,
          Paint()
            ..shader = RadialGradient(colors: [
              light.withValues(alpha: a),
              light.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: lamp.center, radius: r * s)));
    }
    // Light pooled on the grass below it.
    final pool = Rect.fromCenter(
        center: Offset(lamp.center.dx, g(lamp.center.dx) + 3),
        width: 70 * s,
        height: 12 * s);
    c.drawOval(
        pool,
        Paint()
          ..shader = RadialGradient(colors: [
            light.withValues(alpha: 0.10),
            light.withValues(alpha: 0),
          ]).createShader(pool));
    c.drawLine(armEnd, lamp.topCenter, Paint()
      ..color = Tokens.orchard.lanternFrame
      ..strokeWidth = 1.2 * s);
    c.drawRRect(RRect.fromRectAndRadius(lamp, Radius.circular(2.5 * s)),
        Paint()..color = light.withValues(alpha: 0.92));
    c.drawRRect(
        RRect.fromRectAndRadius(lamp, Radius.circular(2.5 * s)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * s
          ..color = Tokens.orchard.lanternFrame);
    c.drawRect(
        Rect.fromCenter(
            center: lamp.topCenter, width: 14 * s, height: 3 * s),
        frame);
  }

  void _stones(Canvas c, double trunk, double s, double Function(double) g) {
    for (final (dx, w, h) in [(36.0, 16.0, 9.0), (50.0, 11.0, 7.0), (-58.0, 13.0, 7.5)]) {
      final x = trunk + dx * s, y = g(x) + 4;
      final r = Rect.fromCenter(
          center: Offset(x, y - h * s / 2), width: w * s, height: h * s);
      c.drawOval(r, Paint()..color = Tokens.orchard.stone);
      c.drawOval(
          Rect.fromLTWH(r.left + r.width * 0.2, r.top + 0.5, r.width * 0.5,
              r.height * 0.38),
          Paint()..color = Tokens.orchard.stoneLit);
    }
  }

  void _mushrooms(Canvas c, double trunk, double s, double Function(double) g) {
    final t = Tokens.orchard;
    for (final (dx, k) in [(-24.0, 1.0), (-34.0, 0.72), (22.0, 0.6)]) {
      final x = trunk + dx * s, y = g(x) + 3;
      final sc = s * k;
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(x - 2.2 * sc, y - 9 * sc, x + 2.2 * sc, y),
              Radius.circular(1.5 * sc)),
          Paint()..color = t.mushroomStem);
      final cap = Rect.fromCenter(
          center: Offset(x, y - 9 * sc), width: 15 * sc, height: 11 * sc);
      c.drawArc(cap, math.pi, math.pi, true, Paint()..color = t.mushroomCap);
      final spot = Paint()..color = t.mushroomSpot;
      c.drawCircle(Offset(x - 3 * sc, y - 12 * sc), 1.3 * sc, spot);
      c.drawCircle(Offset(x + 2.5 * sc, y - 11 * sc), 1.0 * sc, spot);
    }
  }

  void _flowers(Canvas c, double trunk, double s, double Function(double) g) {
    final t = Tokens.orchard;
    final stem = Paint()
      ..color = t.stem
      ..strokeWidth = 1.2 * s
      ..strokeCap = StrokeCap.round;
    // In drifts, not a row: a few clusters at uneven spacing, each flower at
    // its own depth down the hill face, nearer ones a little larger.
    const spots = [-152.0, -143.0, -134.0, -101.0, -93.0, -58.0, 27.0, 36.0, 71.0, 80.0, 90.0, 131.0, 141.0];
    for (var i = 0; i < spots.length; i++) {
      final depth = _hash(i, 6);
      final sc = s * (0.85 + 0.35 * depth);
      final x = trunk + spots[i] * s, y = g(x) + 3 + depth * 16 * s;
      final h = (8 + 7 * _hash(i, 3)) * sc;
      // A nod: each flower on its own slow phase, plus the swipe's wind.
      final nod = 0.10 * math.sin(_t * 1.7 + i * 1.9) * (_t == 0 ? 0 : 1) + _wind +
          _touchNod(x, y - h / 2);
      final head = Offset(
          x + (_hash(i, 4) - 0.5) * 4 * s + math.sin(nod) * h,
          y - h * math.cos(nod));
      c.drawLine(Offset(x, y), head, stem);
      final petal = Paint()..color = t.petals[i % t.petals.length];
      final r = (2.0 + _hash(i, 5)) * sc;
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * math.pi / 5 + i;
        c.drawCircle(head + Offset(math.cos(a), math.sin(a)) * r, r * 0.75, petal);
      }
      c.drawCircle(head, r * 0.55, Paint()..color = t.mushroomSpot);
    }
  }

  void _fireflies(Canvas c, double s) {
    final f = Tokens.orchard.firefly;
    // Artboard units: around and under the canopy, never over the fruit.
    const at = [
      Offset(44, 470), Offset(372, 440), Offset(30, 590), Offset(388, 575),
      Offset(120, 640), Offset(262, 628), Offset(70, 380), Offset(350, 330),
      Offset(210, 648),
    ];
    for (var i = 0; i < at.length; i++) {
      final t = _t;
      // A slow wandering loop a few points wide, and a glow that breathes.
      final drift = t == 0
          ? Offset.zero
          : Offset(math.sin(t * 0.55 + i * 2.1) * 5, math.cos(t * 0.41 + i * 1.7) * 4);
      final pulse = t == 0 ? 1.0 : 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 1.25 + i * 2.7));
      var p = tree.topLeft + (at[i] + drift) * s;
      // They shy away from a finger, and drift back when it lifts.
      final ck = clock;
      if (ck != null && ck.touch != null && ck.touchK > 0.01) {
        final f = Offset(ck.touch!.dx - pageIndex * _pageW, ck.touch!.dy);
        final away = p - f;
        final d = away.distance;
        if (d < 90 && d > 0.1) p += away / d * (1 - d / 90) * 34 * ck.touchK;
      }
      final r = (7 + 4 * _hash(i, 9)) * s;
      c.drawCircle(
          p,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              f.withValues(alpha: 0.30 * pulse),
              f.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: p, radius: r)));
      c.drawCircle(p, 1.3 * s, Paint()..color = f.withValues(alpha: 0.9 * pulse));
    }
  }

  @override
  bool shouldRepaint(DecorPainter old) =>
      old.tree != tree ||
      old.front != front ||
      old.clock != clock ||
      old.groundY != groundY ||
      old.pageIndex != pageIndex ||
      !setEquals(old.decor, decor);
}

/// Where a tree meets the meadow: a soft contact shadow at the trunk's foot,
/// so the tree stands ON the ground instead of floating over it. On the empty
/// patch ([patch]) it is a mound of turned earth waiting for a seed instead.
/// Feathered radial fills only: no hard edge anywhere, so it blends with the
/// ridge and the grass painted over and under it.
class GroundContactPainter extends CustomPainter {
  GroundContactPainter({
    required this.tree,
    required this.groundY,
    required this.pageIndex,
    this.patch = false,
    this.period,
  });

  final Rect tree;
  final double groundY;
  final int pageIndex;
  final bool patch;

  /// See [MeadowBackPainter.period].
  final double? period;

  @override
  void paint(Canvas canvas, Size size) {
    final s = tree.width / kTreeArtW;
    final x = tree.left + kTreeBaseX * s;
    final y = ridgeY(pageIndex * size.width + x, period ?? size.width, groundY) + 2;
    final c = Tokens.cosmos;
    void soft(double w, double h, Color colour, double alpha, {double dy = 0}) {
      canvas.save();
      canvas.translate(x, y + dy);
      canvas.scale(1, h / w);
      final r = w / 2;
      canvas.drawCircle(
          Offset.zero,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              colour.withValues(alpha: alpha),
              colour.withValues(alpha: alpha * 0.45),
              colour.withValues(alpha: 0),
            ], stops: const [0, 0.55, 1])
                .createShader(Rect.fromCircle(center: Offset.zero, radius: r)));
      canvas.restore();
    }

    if (patch) {
      // Turned earth: a low dark mound with a faint lit top.
      soft(130 * s, 22 * s, c.hillDeep, 0.9);
      soft(84 * s, 10 * s, c.hillRim, 0.10, dy: -3 * s);
      return;
    }
    soft(150 * s, 20 * s, c.hillDeep, 0.75); // the canopy's shade
    soft(54 * s, 9 * s, c.hillDeep, 0.9); // the trunk's own foot
  }

  @override
  bool shouldRepaint(GroundContactPainter old) =>
      old.tree != tree ||
      old.groundY != groundY ||
      old.pageIndex != pageIndex ||
      old.period != period ||
      old.patch != patch;
}
