// Painting the procedural tree: bark, foliage, ground.
//
// `docs/DESIGN.md` §3 fixes rendering as `CustomPainter` and `CONSTRAINTS.md`
// ranks 3D last with reasons, so nothing here is a mesh, a camera or a
// projection. Depth is done with three cues that cost nothing: things behind are
// PAINTED FIRST, set back in colour, and drawn smaller.
//
// WHAT MADE THE OLD TREE LOOK LIKE A DIAGRAM
//
// It stroked each stem as a line. A stroked line is flat by definition -- one
// colour across its whole width -- so no matter how good the geometry is, the
// result is a ribbon, and grey ribbons on a dark background read as a wireframe.
// Two changes fix that, and they are the whole reason this file exists:
//
//   1. A stem is FILLED as a tapered outline, not stroked. The polygon comes
//      from the engine's per-sample half-widths, so the wood is thick at the
//      root and fine at the tip the way the geometry always said it was.
//   2. Each stem is painted THREE TIMES -- body, a lit ribbon toward the light,
//      a shaded ribbon away from it -- which is what turns a flat ribbon into a
//      cylinder. The offsets follow the stem's own normals, so the shading bends
//      with the limb instead of sliding off it.
//
// There is no idle motion anywhere in this file. `DESIGN.md` §7 rejects leaf
// sway outright: seen every launch, no nameable purpose, and slow oscillation
// near 0.2 Hz is a listed vestibular trigger.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'procedural_tree.dart';

/// Where the light comes from, as a unit vector in canvas space.
///
/// Up and to the left. Fixed rather than configurable because a consistent light
/// direction is most of what makes separate painted objects look like one solid
/// scene, and a light that moved per screen would undo that.
const Offset kLightDirection = Offset(-0.62, -0.78);

/// One leaf in the canopy.
///
/// Was a blurred circle ("blob"). At device scale a cloud of blurred circles
/// read as green SMOKE rather than foliage -- Abin's "boring" verdict and the
/// Stage-1 render both showed it. A leaf now carries an ANGLE and a small HUE
/// SHIFT, both from the deterministic seed, so the mass is built from hundreds
/// of small shapes at varied tilts and tints. That is what reads as leaves: the
/// silhouette is still the thing the eye takes in, but it is now a ragged leafy
/// edge instead of a soft puff, and the tint variation stops it looking like one
/// flat fill.
///
/// The name is kept as `FoliageBlob` so no call site outside this file changes;
/// what changed is what it draws.
class FoliageBlob {
  const FoliageBlob({
    required this.centre,
    required this.radius,
    required this.depth,
    required this.lit,
    this.angle = 0,
    this.hueShift = 0,
  });

  final Offset centre;
  final double radius;

  /// 0 nearest the viewer, 1 furthest. Decides paint order and colour.
  final double depth;

  /// True for the leaves that catch the light, drawn last and smaller.
  final bool lit;

  /// The leaf's tilt in radians, from the seed. A canopy of identically-angled
  /// leaves reads as a pattern, not as growth.
  final double angle;

  /// A small per-leaf lightness nudge, -1..1, from the seed. Applied to the
  /// base foliage colour so the mass has internal variation rather than being
  /// one flat green, which is most of what separated "leaves" from "smoke".
  final double hueShift;
}

/// Generate the canopy for [tree].
///
/// Pure and deterministic: seeded from `tree.seed`, which is itself derived from
/// the collection, so the same collection grows the same canopy every launch. A
/// canopy that reshuffled per frame would be a screensaver, and one that
/// reshuffled per launch would not be the user's tree.
///
/// Exposed as a top-level function rather than hidden in the painter so it can be
/// unit-tested on the VM with no canvas.
List<FoliageBlob> foliageFor(ProceduralTree tree) {
  final out = <FoliageBlob>[];
  var state = (tree.seed & 0x7fffffff) | 1;
  double rnd() {
    state = (state * 1664525 + 1013904223) & 0xffffffff;
    return state / 0x100000000;
  }

  final unit = tree.canvas.width;

  void clumpAt(TreeStem stem, double depth, double scale) {
    // Along the outer half of the stem: leaves grow toward the light, not out of
    // the shoulder where the limb leaves the trunk.
    //
    // Seven samples, and at each one a SPRAY of small leaves rather than two big
    // blobs. The blob version read as smoke; a spray of tilted leaf shapes reads
    // as foliage because its silhouette is ragged and its interior varies. Each
    // leaf takes an angle and a hue shift from the seed, so no two are identical
    // and the mass is not one flat fill.
    const steps = 7;
    const leavesPerSample = 6;
    for (var k = 0; k < steps; k++) {
      final u = 0.46 + 0.54 * (k / (steps - 1));
      final at = stem.sample(u);
      // Bigger toward the tip, so the mass gathers at the ends of the wood the
      // way a real canopy does, instead of sleeving the whole branch evenly.
      final grow = 0.62 + 0.38 * ((u - 0.46) / 0.54);
      // The size a single leaf is scaled from. Smaller than the old blob radius
      // because many leaves now fill the space one blob used to.
      final leafR = unit * 0.030 * scale * grow;
      // The radius the spray is scattered within, which is what actually sets
      // the silhouette's size -- kept close to the old blob radius so the canopy
      // is the same overall size, just built from leaves.
      final spread = unit * 0.058 * scale * grow;

      for (var j = 0; j < leavesPerSample; j++) {
        final ang = rnd() * 6.283;
        final dist = spread * (0.2 + 0.8 * rnd());
        final centre = at.point +
            Offset(math.cos(ang) * dist, math.sin(ang) * dist - spread * 0.20);
        out.add(FoliageBlob(
          centre: centre,
          radius: leafR * (0.7 + rnd() * 0.6),
          depth: depth,
          lit: false,
          // Leaves fan outward from the sample point, plus jitter, so they point
          // away from the branch the way real leaves do.
          angle: ang + (rnd() - 0.5) * 1.4,
          hueShift: (rnd() - 0.5) * 2,
        ));
      }
      // A few lit leaves offset toward the light. This is the only thing that
      // gives the mass a top and a bottom.
      if (k.isOdd) {
        for (var j = 0; j < 3; j++) {
          final ang = rnd() * 6.283;
          out.add(FoliageBlob(
            centre: at.point +
                kLightDirection * (spread * 0.55) +
                Offset(math.cos(ang) * leafR, math.sin(ang) * leafR),
            radius: leafR * (0.6 + rnd() * 0.4),
            depth: depth,
            lit: true,
            angle: ang + (rnd() - 0.5) * 1.4,
            hueShift: (rnd() - 0.5) * 2,
          ));
        }
      }
    }
  }

  // Crown first: it is the canopy that exists regardless of how the user has
  // organised anything, so it must never be conditional on having limbs.
  for (var i = 0; i < tree.crown.length; i++) {
    clumpAt(tree.crown[i], i.isEven ? 0.20 : 0.55, 1.0);
  }
  for (final limb in tree.limbs) {
    // A loaded limb carries slightly less leaf: the covers hanging on it are the
    // thing to look at, and dense foliage behind cover art just muddies it.
    final scale = limb.fruit.isEmpty ? 1.0 : 0.78;
    clumpAt(limb.stem, limb.depth, scale);
  }

  // Far blobs first so nearer mass paints over them.
  out.sort((a, b) => b.depth.compareTo(a.depth));
  return out;
}

/// Outline a stem as a filled, tapered shape.
///
/// [widthScale] narrows the ribbon and [shift] slides it along the stem's own
/// normals, which is how the lit and shaded passes are produced from the same
/// geometry -- so the shading follows a curving limb instead of sitting on it
/// like a decal.
Path stemPath(TreeStem stem, {double widthScale = 1.0, double shift = 0.0}) {
  final n = stem.spine.length;
  final normals = <Offset>[];
  for (var i = 0; i < n; i++) {
    final a = stem.spine[i == 0 ? 0 : i - 1];
    final b = stem.spine[i == n - 1 ? n - 1 : i + 1];
    final d = b - a;
    final mag = d.distance == 0 ? 1.0 : d.distance;
    normals.add(Offset(-d.dy / mag, d.dx / mag));
  }

  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < n; i++) {
    final w = stem.halfWidth[i] * widthScale;
    final base = stem.spine[i] + normals[i] * (stem.halfWidth[i] * shift);
    left.add(base + normals[i] * w);
    right.add(base - normals[i] * w);
  }

  final path = Path()..moveTo(left.first.dx, left.first.dy);
  // Quadratics through the midpoints rather than straight segments: at 16-26
  // samples a polyline edge is visibly faceted on the trunk, and bark facets
  // read as a low-poly asset rather than as wood.
  for (var i = 1; i < n; i++) {
    final mid = (left[i - 1] + left[i]) / 2;
    path.quadraticBezierTo(left[i - 1].dx, left[i - 1].dy, mid.dx, mid.dy);
  }
  path.lineTo(left.last.dx, left.last.dy);
  path.lineTo(right.last.dx, right.last.dy);
  for (var i = n - 2; i >= 0; i--) {
    final mid = (right[i + 1] + right[i]) / 2;
    path.quadraticBezierTo(right[i + 1].dx, right[i + 1].dy, mid.dx, mid.dy);
  }
  // Explicitly back to the first right-hand point before closing.
  //
  // Without this line, `close()` draws a chord from the last MIDPOINT (half a
  // segment up the stem) straight across to `left.first`, chamfering the base.
  // On the trunk that rendered as a visible wedge at ground level -- the trunk
  // appeared to get NARROWER where it met the soil, which is the opposite of
  // what the geometry says and the opposite of how a tree meets the ground.
  path.lineTo(right.first.dx, right.first.dy);
  path.close();
  return path;
}

/// The tree itself. Fruit and seeds are NOT painted here -- they are real
/// widgets above this canvas, because a game is identified by its cover art and
/// a painted circle cannot show one.
class ProceduralTreePainter extends CustomPainter {
  ProceduralTreePainter({
    required this.tree,
    required this.foliage,
    this.groundVisible = true,
    this.bloomTints = const {},
  }) : skinName = Tokens.canopy.name;

  final ProceduralTree tree;
  final List<FoliageBlob> foliage;

  /// The active skin at construction, so a colour-direction swap repaints.
  final String skinName;

  /// igdbId -> the dominant colour of that game's cover, for the bloom a fruit
  /// casts onto the wood and foliage around it. Empty until covers resolve and
  /// their colours are extracted; a fruit not in the map casts no bloom, so the
  /// tree simply lights up gradually as art loads rather than flashing.
  final Map<int, Color> bloomTints;

  /// False for a small portrait, where a ground plane crops awkwardly and the
  /// tree reads better floating.
  final bool groundVisible;

  @override
  void paint(Canvas canvas, Size size) {
    if (groundVisible) _paintGround(canvas, size);

    // Back to front. A far limb painted before the trunk has its shoulder
    // covered by the trunk, which is exactly what "behind" means.
    final far = tree.limbs.where((l) => l.depth >= 0.5).toList();
    final near = tree.limbs.where((l) => l.depth < 0.5).toList();

    _paintFoliage(canvas, minDepth: 0.5);
    for (final limb in far) {
      _paintStem(canvas, limb.stem, opacity: limb.opacity);
    }
    _paintStem(canvas, tree.trunk, opacity: 1.0);
    for (final twig in tree.crown) {
      _paintStem(canvas, twig, opacity: 0.94);
    }
    for (final limb in near) {
      _paintStem(canvas, limb.stem, opacity: limb.opacity);
    }
    // Contact shadow where each limb leaves the trunk. A limb painted over the
    // trunk with no shadow reads as a stick laid ON the trunk; a soft dark patch
    // at the join is what makes it read as GROWING FROM it. One lamp, so the
    // shadow sits on the shaded side of the join. Cheap: one blurred circle per
    // limb, drawn after the wood so it sits in the crease.
    for (final limb in tree.limbs) {
      final base = limb.stem.base;
      final r = limb.stem.baseHalfWidth;
      canvas.drawCircle(
        base - kLightDirection * (r * 0.6),
        r * 1.8,
        Paint()
          ..color = Tokens.canopy.barkShade.withValues(alpha: 0.55 * limb.opacity)
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, r * 1.1),
      );
    }
    _paintFoliage(canvas, maxDepth: 0.5);

    // Each fruit casts a BLOOM of its cover's dominant colour onto the wood and
    // foliage beneath it. This is the tree taking its colour from the user's own
    // games. Painted after the scene and before the stalks/fruit, with a plus
    // blend so it LIGHTS the surface rather than covering it -- a coloured glow,
    // not a coloured disc. Falls off with radius, and a set-back fruit blooms
    // fainter (aerial perspective, same cue the foliage uses).
    _paintBlooms(canvas);

    // Stalks last, so a fruit is always joined to wood no matter which layer its
    // limb ended up in.
    _paintStalks(canvas);
  }

  void _paintGround(Canvas canvas, Size size) {
    final y = tree.soilY;
    // Shallow and soft.
    //
    // The first version was a 0.16-height oval in a near-black fill with a hard
    // 2px lit arc on top. Rendered, that is not a mound -- it is a black hole
    // with a chalk line on it, taking a fifth of the screen. What actually reads
    // as ground is a LOW, BLURRED band only a little darker than the sky, so the
    // eye takes it as a surface receding rather than as an object.
    final mound = Rect.fromCenter(
      center: Offset(size.width / 2, y + size.height * 0.030),
      width: size.width * 1.35,
      height: size.height * 0.075,
    );
    canvas.drawOval(
      mound,
      Paint()
        ..color = Tokens.canopy.ground.withValues(alpha: 0.85)
        ..maskFilter =
            ui.MaskFilter.blur(BlurStyle.normal, size.height * 0.012),
    );
    // A soft lit lip rather than a stroked arc: same job, no chalk line.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, y),
        width: size.width * 0.72,
        height: size.height * 0.022,
      ),
      Paint()
        ..color = Tokens.canopy.groundLit.withValues(alpha: 0.55)
        ..maskFilter =
            ui.MaskFilter.blur(BlurStyle.normal, size.height * 0.010),
    );
  }

  void _paintFoliage(Canvas canvas, {double minDepth = 0.0, double maxDepth = 1.1}) {
    // An ambient bloom on the NEAR canopy before the leaf mass, so a lit skin
    // reads as glowing from within rather than as flatly brighter foliage. Only
    // on the near pass (a bloom behind the trunk would be invisible) and only
    // where the skin actually carries glow alpha, so `midnight` is unchanged.
    if (minDepth < 0.5 && Tokens.canopy.glow.a > 0) {
      for (final b in foliage) {
        if (b.depth >= 0.5 || !b.lit) continue;
        canvas.drawCircle(
          b.centre,
          b.radius * 2.0,
          Paint()
            ..color = Tokens.canopy.glow.withValues(alpha: Tokens.canopy.glow.a * 0.55)
            ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, b.radius * 1.4),
        );
      }
    }

    // A SOFT MASS BASE under the leaves, per depth band, so the sky does not
    // show through the gaps between individual leaf shapes. This is the old
    // blurred-blob idea kept only as a backing wash: it carries the silhouette's
    // solidity while the leaves on top carry the texture. Without it a spray of
    // separate leaves reads as confetti; with it, as a canopy.
    for (final b in foliage) {
      if (b.depth < minDepth || b.depth >= maxDepth || b.lit) continue;
      final base = b.depth >= 0.5 ? Tokens.canopy.foliageFar : Tokens.canopy.foliageNear;
      canvas.drawCircle(
        b.centre,
        b.radius * 1.5,
        Paint()
          ..color = base.withValues(alpha: (0.42 - b.depth * 0.14).clamp(0.0, 1.0))
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, b.radius * 0.9),
      );
    }

    // The leaves themselves, each a tilted shape with its own tint.
    for (final b in foliage) {
      if (b.depth < minDepth || b.depth >= maxDepth) continue;
      final base = b.lit
          ? Tokens.canopy.foliageLit
          : (b.depth >= 0.5 ? Tokens.canopy.foliageFar : Tokens.canopy.foliageNear);
      // Per-leaf lightness variation, so the mass is not one flat fill. A small
      // range: too much and it reads as noise rather than as leaves in light.
      final tinted = _shiftLightness(base, b.hueShift * 0.12);
      // Aerial perspective: further leaves lose contrast. The lit ones stay
      // brighter (they are the highlight) and the near ones are near-opaque.
      final alpha = b.lit ? 0.62 : (0.96 - b.depth * 0.32).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = tinted.withValues(alpha: alpha)
        // A whisper of blur softens the leaf edge without dissolving it, so the
        // silhouette survives while a hard vector edge does not read as organic.
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, math.max(0.4, b.radius * 0.12));
      canvas.drawPath(_leafPath(b.centre, b.radius, b.angle), paint);
    }
  }

  /// A single leaf: a rounded almond, its long axis along [angle].
  ///
  /// Two quadratics from tip to tip through offset control points. Cheap, and at
  /// canopy scale it reads as a leaf where a circle read as a bubble.
  Path _leafPath(Offset c, double r, double angle) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    final perp = Offset(-dir.dy, dir.dx);
    final tip = c + dir * r;
    final tail = c - dir * r;
    final bulge = perp * (r * 0.5);
    return Path()
      ..moveTo(tail.dx, tail.dy)
      ..quadraticBezierTo((c + bulge).dx, (c + bulge).dy, tip.dx, tip.dy)
      ..quadraticBezierTo((c - bulge).dx, (c - bulge).dy, tail.dx, tail.dy)
      ..close();
  }

  /// Nudge a colour's lightness by [delta]. Pure channel scaling -- no
  /// colour-space import needed, and it keeps hue so a green leaf stays green.
  Color _shiftLightness(Color base, double delta) {
    if (delta == 0) return base;
    double ch(double v) => (v + delta).clamp(0.0, 1.0);
    return Color.from(
      alpha: base.a,
      red: ch(base.r),
      green: ch(base.g),
      blue: ch(base.b),
    );
  }

  void _paintStem(Canvas canvas, TreeStem stem, {required double opacity}) {
    final w = stem.baseHalfWidth;

    // Body.
    canvas.drawPath(
      stemPath(stem),
      Paint()..color = Tokens.canopy.barkMid.withValues(alpha: opacity),
    );

    // Shaded and lit sides, BLURRED.
    //
    // The blur is the whole difference between a cylinder and a folded plank.
    // Unblurred, these two ribbons meet the body along hard edges and the trunk
    // renders as creased paper with a stripe down it -- which is exactly how the
    // first render of this file looked. Blurring by a fraction of the stem's own
    // width turns the same two paths into a soft terminator, and a soft
    // terminator is what the eye reads as round.
    canvas.drawPath(
      stemPath(stem, widthScale: 0.58, shift: _shadeShift(stem)),
      Paint()
        ..color = Tokens.canopy.barkShade.withValues(alpha: opacity * 0.9)
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, math.max(1.0, w * 0.5)),
    );
    canvas.drawPath(
      stemPath(stem, widthScale: 0.30, shift: -_shadeShift(stem) * 1.05),
      Paint()
        ..color = Tokens.canopy.barkLit.withValues(alpha: opacity * 0.95)
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, math.max(1.0, w * 0.42)),
    );
  }

  /// Which way to push the shaded ribbon, from the stem's own direction against
  /// the light. A limb leaning left is lit on its other face from one leaning
  /// right, and this one sign is what keeps both consistent with a single lamp.
  double _shadeShift(TreeStem stem) {
    final d = stem.tip - stem.base;
    final mag = d.distance == 0 ? 1.0 : d.distance;
    final normal = Offset(-d.dy / mag, d.dx / mag);
    final facing = normal.dx * kLightDirection.dx + normal.dy * kLightDirection.dy;
    return facing >= 0 ? -0.42 : 0.42;
  }
  /// Cast each fruit's cover colour as a soft radial bloom on the scene.
  void _paintBlooms(Canvas canvas) {
    if (bloomTints.isEmpty) return;
    for (final f in tree.allFruit) {
      // A bud is not the user's game yet, so it does not light the tree.
      if (f.bud) continue;
      final colour = bloomTints[f.item.game.igdbId];
      if (colour == null) continue;
      // A bloom the size of a fruit or so, brightest at the fruit and gone by
      // its edge. Kept modest: a big bright bloom washes the tree into one
      // colour and merges neighbours, where a tight one reads as THIS game
      // tinting its own patch of wood. Set-back fruit bloom fainter.
      final radius = f.radius * 2.1;
      final peak = (0.26 - f.depth * 0.10).clamp(0.0, 1.0);
      final shader = RadialGradient(
        colors: [
          colour.withValues(alpha: peak),
          colour.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: f.centre, radius: radius));
      canvas.drawCircle(
        f.centre,
        radius,
        Paint()
          ..shader = shader
          // Plus lightens the surface toward the colour instead of painting a
          // flat disc over it, so it reads as light cast, not as a sticker.
          ..blendMode = BlendMode.plus,
      );
    }
  }



  void _paintStalks(Canvas canvas) {
    final paint = Paint()
      ..color = Tokens.canopy.barkShade
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final f in tree.allFruit) {
      paint.strokeWidth = math.max(1.2, f.radius * 0.10);
      canvas.drawLine(f.anchor, f.centre - Offset(0, f.radius * 0.55), paint);
    }

    // A CALYX behind each bud: the little leafy cup a real bud sits in.
    //
    // Size alone was not enough to read "not yours yet". A smaller cover card
    // among larger ones looks like a card further away, because scale is already
    // the depth cue -- so the difference needs a second channel, and a shape the
    // eye knows is young growth is better than a badge to decode. Drawn BEFORE
    // the cover widget paints over it, so it shows as a collar around the top of
    // the card rather than sitting on the art.
    final calyx = Paint()
      ..color = Tokens.canopy.foliageLit
      ..style = PaintingStyle.fill;
    for (final f in tree.allFruit) {
      if (!f.bud) continue;
      // 1.30 radii above centre, NOT 0.62.
      //
      // A cover is a PORTRAIT card: its height is 2.67 radii, so its top edge is
      // 1.33 radii above the centre. At 0.62 the calyx was painted fully inside
      // the card and the widget covered it completely -- it rendered, it was
      // correct, and it was invisible, which a capture caught and no test would
      // have. It has to sit on the card's shoulder to be seen at all.
      final top = f.centre - Offset(0, f.radius * 1.30);
      final r = f.radius * 0.78;
      // Three short lobes, centre one upright. A single circle read as a dot.
      for (final lean in const [-0.72, 0.0, 0.72]) {
        canvas.save();
        canvas.translate(top.dx, top.dy);
        canvas.rotate(lean);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, -r * 0.40),
            width: r * 0.58,
            height: r * 1.05,
          ),
          calyx,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(ProceduralTreePainter old) =>
      old.tree.seed != tree.seed ||
      old.tree.canvas != tree.canvas ||
      old.tree.fruitCount != tree.fruitCount ||
      old.skinName != skinName ||
      old.bloomTints.length != bloomTints.length ||
      old.groundVisible != groundVisible;
}
