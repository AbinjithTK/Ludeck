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

/// Grass blades over the visible world range, batched into a few paths by
/// shade so a frame costs a handful of draw calls, not one per blade.
void _paintGrass(Canvas canvas, Size size,
    {required double scroll,
    required double groundY,
    required double spacing,
    required double minH,
    required double maxH,
    required double sink,
    required int salt,
    required List<Color> shades,
    Color? rim,
    double time = 0,
    double wind = 0,
    Offset? touch,
    double touchK = 0}) {
  final paths = List.generate(shades.length, (_) => Path());
  final rimPath = Path();
  final first = ((scroll - maxH) / spacing).floor();
  final last = ((scroll + size.width + maxH) / spacing).ceil();
  for (var k = first; k <= last; k++) {
    final r1 = _hash(k, salt), r2 = _hash(k, salt + 1), r3 = _hash(k, salt + 2);
    final xw = k * spacing + (r2 - 0.5) * spacing * 0.8;
    final x = xw - scroll;
    final base = ridgeY(xw, size.width, groundY) + sink;
    var h = minH + (maxH - minH) * r1 * r1;
    if (r3 > 0.93) h *= 1.5; // the odd tall stem
    final lean = (r2 - 0.5) * 0.9 +
        swayAt(xw, time, wind, r3) +
        touchLean(xw, base - h / 2, touch, touchK);
    final w = 1.6 + r3 * 1.4;
    final tip = Offset(x + math.sin(lean) * h, base - math.cos(lean) * h);
    final bend = Offset(x + math.sin(lean) * h * 0.35, base - h * 0.55);
    final p = paths[(r3 * shades.length).floor().clamp(0, shades.length - 1)];
    p
      ..moveTo(x - w / 2, base)
      ..quadraticBezierTo(bend.dx - w * 0.2, bend.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(bend.dx + w * 0.4, bend.dy, x + w / 2, base)
      ..close();
    if (rim != null && h > maxH * 0.8) {
      rimPath
        ..moveTo(bend.dx, bend.dy)
        ..quadraticBezierTo(
            (bend.dx + tip.dx) / 2, (bend.dy + tip.dy) / 2 - 1, tip.dx, tip.dy);
    }
  }
  for (var i = 0; i < shades.length; i++) {
    canvas.drawPath(paths[i], Paint()..color = shades[i]);
  }
  if (rim != null) {
    canvas.drawPath(
        rimPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = rim);
  }
}

class MeadowBackPainter extends CustomPainter {
  MeadowBackPainter({
    required this.scroll,
    required this.groundFromBottom,
    this.halos = const [],
  }) : super(repaint: scroll);

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
    final ridge = Path()..moveTo(-1, ridgeY(s - 1, size.width, groundY));
    for (var x = 0.0; x <= size.width + 6; x += 6) {
      ridge.lineTo(x, ridgeY(s + x, size.width, groundY));
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
              Rect.fromLTRB(0, groundY - kRidgeDip * size.width, size.width, size.height)));
  }

  @override
  bool shouldRepaint(MeadowBackPainter old) =>
      old.scroll != scroll ||
      old.groundFromBottom != groundFromBottom ||
      !listEquals(old.halos, halos);
}

/// The back grass and the ridge's rim, on their own layer: they sway with
/// [clock] every frame, and the sky, stars and halos under them do not need
/// repainting for that.
class MeadowGrassPainter extends CustomPainter {
  MeadowGrassPainter(
      {required this.scroll, required this.groundFromBottom, this.clock})
      : super(repaint: Listenable.merge([scroll, clock]));

  final ValueListenable<double> scroll;
  final double groundFromBottom;
  final MeadowClock? clock;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scroll.value;
    final groundY = size.height - groundFromBottom;
    final c = Tokens.cosmos, o = Tokens.orchard;
    // Back grass: dense, tall, standing just behind the ridge line.
    _paintGrass(canvas, size,
        scroll: s,
        groundY: groundY,
        spacing: 2.6,
        minH: 7,
        maxH: 24,
        sink: 1.5,
        salt: 11,
        shades: [o.grassBack, Color.lerp(o.grassBack, o.grassFront, 0.5)!, o.grassFront],
        rim: o.grassRim,
        time: clock?.t ?? 0,
        wind: clock?.wind ?? 0,
        touch: clock?.touch,
        touchK: clock?.touchK ?? 0);

    final ridge = Path()..moveTo(-1, ridgeY(s - 1, size.width, groundY));
    for (var x = 0.0; x <= size.width + 6; x += 6) {
      ridge.lineTo(x, ridgeY(s + x, size.width, groundY));
    }
    canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = c.hillRim.withValues(alpha: c.hillRim.a * 0.6));
  }

  @override
  bool shouldRepaint(MeadowGrassPainter old) =>
      old.scroll != scroll ||
      old.clock != clock ||
      old.groundFromBottom != groundFromBottom;
}

/// Short grass in FRONT of the trees, so each trunk's foot stands in it.
class MeadowFrontPainter extends CustomPainter {
  MeadowFrontPainter(
      {required this.scroll, required this.groundFromBottom, this.clock})
      : super(repaint: Listenable.merge([scroll, clock]));

  final ValueListenable<double> scroll;
  final MeadowClock? clock;

  /// The soil line's distance from the bottom edge (same for every page).
  final double groundFromBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Tokens.orchard;
    final groundY = size.height - groundFromBottom;
    _paintGrass(canvas, size,
        scroll: scroll.value,
        groundY: groundY,
        spacing: 3.6,
        minH: 4,
        maxH: 13,
        sink: 6,
        salt: 29,
        shades: [o.grassBack, Color.lerp(o.grassBack, Tokens.cosmos.hillTop, 0.5)!],
        time: clock?.t ?? 0,
        wind: clock?.wind ?? 0,
        touch: clock?.touch,
        touchK: clock?.touchK ?? 0);
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
    const spots = [-148.0, -121.0, -104.0, -70.0, -47.0, 30.0, 58.0, 84.0, 118.0, 139.0];
    for (var i = 0; i < spots.length; i++) {
      final x = trunk + spots[i] * s, y = g(x) + 4;
      final h = (9 + 6 * _hash(i, 3)) * s;
      // A nod: each flower on its own slow phase, plus the swipe's wind.
      final nod = 0.10 * math.sin(_t * 1.7 + i * 1.9) * (_t == 0 ? 0 : 1) + _wind +
          _touchNod(x, y - h / 2);
      final head = Offset(
          x + (_hash(i, 4) - 0.5) * 4 * s + math.sin(nod) * h,
          y - h * math.cos(nod));
      c.drawLine(Offset(x, y), head, stem);
      final petal = Paint()..color = t.petals[i % t.petals.length];
      final r = (2.0 + _hash(i, 5)) * s;
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
