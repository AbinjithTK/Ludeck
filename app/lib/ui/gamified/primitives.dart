// The gamified surface's building blocks.
//
// Five widgets that the map, the header, onboarding and the sign-in screen all
// draw from, so those four screens cannot drift into four different looks. Every
// colour here resolves through `Tokens.cosmos` or `Tokens.palette` -- there is no
// literal in this file, which is `check.ps1` rule 1 and also the reason the look
// can be retuned in one place.
//
// What is deliberately NOT here: any notion of a locked, expired, overdue or
// greyed-out state. `docs/DECISIONS.md` forbids marking what the user has not
// done, and a primitive that offers a `locked` flag is how that arrives later
// without anyone deciding to add it.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Which sky a screen sits in.
enum Sky {
  /// The header: a close, warm horizon.
  hero,

  /// The map: open space, no horizon.
  deep,
}

/// The gradient sky, with a fixed starfield over it.
///
/// The stars are generated from a FIXED seed, not from `Random()`. A field that
/// re-randomises every build would shimmer on every rebuild -- and a rebuild
/// happens on every scroll frame, which would turn a calm backdrop into visual
/// noise. Same seed, same sky, every frame.
class CosmosBackdrop extends StatelessWidget {
  const CosmosBackdrop({
    super.key,
    required this.child,
    this.sky = Sky.deep,
    this.stars = 60,
  });

  final Widget child;
  final Sky sky;

  /// How many stars to scatter. Zero is legal and gives a clean gradient.
  final int stars;

  @override
  Widget build(BuildContext context) {
    final colors = sky == Sky.hero ? Tokens.cosmos.hero : Tokens.cosmos.deep;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: CustomPaint(
        painter: stars > 0 ? _StarfieldPainter(count: stars) : null,
        child: child,
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({required this.count});

  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    // Seeded, so the field is identical on every repaint. See the class doc.
    final random = math.Random(20260925);
    final paint = Paint();

    for (var i = 0; i < count; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      // Brightness and radius vary together: a big dim star reads as a smudge,
      // and a tiny bright one disappears at this scale.
      final t = random.nextDouble();
      paint.color = Tokens.cosmos.star.withValues(alpha: 0.12 + t * 0.5);
      canvas.drawCircle(Offset(dx, dy), 0.6 + t * 1.2, paint);
    }
  }

  // The field is a pure function of count and size, so it only repaints when
  // count changes. Returning true would redraw the same pixels every frame.
  @override
  bool shouldRepaint(_StarfieldPainter old) => old.count != count;
}

/// A glowing sphere. The profile avatar, and a node on the map.
///
/// The glow is painted OUTSIDE the sphere as a radial gradient rather than as a
/// `BoxShadow`, because a shadow is clipped to a blur around the box and cannot
/// bloom past it -- and the bloom is the whole effect. [image] is optional so
/// the same primitive serves a profile planet and a bare node.
class GlowOrb extends StatelessWidget {
  const GlowOrb({
    super.key,
    required this.diameter,
    this.image,
    this.child,
    this.glow = 1.0,
  });

  final double diameter;

  /// Painted inside the sphere, cover-fitted. A cover URL's image, usually.
  final ImageProvider? image;

  /// Drawn over the sphere -- an initial, an icon, a count.
  final Widget? child;

  /// Bloom strength, 0 to 1. Zero still draws the sphere, with no halo.
  final double glow;

  @override
  Widget build(BuildContext context) {
    // The halo needs room to bloom into, so the widget is larger than its
    // sphere. Sized from the diameter rather than a fixed pad, so a small node
    // and a large planet get proportional halos.
    final bloom = diameter * 0.45;
    final extent = diameter + bloom * 2;

    return SizedBox(
      width: extent,
      height: extent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (glow > 0)
            // IgnorePointer, because the halo is decoration that extends well
            // past the sphere; without it the orb would swallow taps in the
            // empty space around itself.
            IgnorePointer(
              child: Container(
                width: extent,
                height: extent,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Tokens.cosmos.glow
                          .withValues(alpha: 0.55 * glow.clamp(0, 1)),
                      Tokens.cosmos.glow.withValues(alpha: 0),
                    ],
                    // The sphere occupies the inner portion, so the ramp starts
                    // at its edge -- a ramp from the centre would wash the
                    // sphere itself out.
                    stops: const [0.42, 1],
                  ),
                ),
              ),
            ),
          Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Tokens.cosmos.panelDeep,
              image: image == null
                  ? null
                  : DecorationImage(image: image!, fit: BoxFit.cover),
              border: Border.all(color: Tokens.cosmos.panelEdge),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A translucent panel over the sky -- the Tolan "soft light" card.
///
/// [onTap] is optional: the same shape is used for a tappable activity card and
/// for a static block of copy in onboarding. When it is null no `InkWell` is
/// built at all, so a static card cannot show a stray ripple.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.deep = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Use the darker fill. Needed wherever the card holds caption-sized text: the
  /// lighter fill over the bright end of the hero gradient leaves too little
  /// contrast under small type.
  final bool deep;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Tokens.radius.panel);
    final body = Padding(
      padding: padding ?? EdgeInsets.all(Tokens.space.md),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: deep ? Tokens.cosmos.panelDeep : Tokens.cosmos.panel,
        border: Border.all(color: Tokens.cosmos.panelEdge),
      ),
      child: onTap == null
          ? body
          : Material(
              color: Tokens.palette.bg.withValues(alpha: 0),
              borderRadius: radius,
              child: InkWell(borderRadius: radius, onTap: onTap, child: body),
            ),
    );
  }
}

/// A pill progress bar.
///
/// [value] is 0 to 1 and is CLAMPED rather than asserted, because it is computed
/// from collection counts upstream and a divide-by-zero on an empty collection
/// would otherwise paint a NaN-width box and throw in the render phase.
///
/// It reports progress and nothing else: there is no "goal", no remaining count
/// and no deadline, because a bar that shows what is missing is the shape
/// `DECISIONS.md` rules out.
class PillProgress extends StatelessWidget {
  const PillProgress({super.key, required this.value, this.label});

  final double value;

  /// Optional text inside the leading cap -- a level number, usually.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final fraction = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    final height = Tokens.size.progressTrack;

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.radius.pill),
      child: Stack(
        children: [
          Container(height: height, color: Tokens.cosmos.trailDim),
          // FractionallySizedBox rather than a computed width: the bar's own
          // width is decided by its parent, so a measured number here would be
          // wrong at any other screen size.
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: Tokens.palette.accent,
                borderRadius: BorderRadius.circular(Tokens.radius.pill),
              ),
            ),
          ),
        ],
      ),
    );

    if (label == null) return bar;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: Tokens.space.xs, vertical: Tokens.space.xxs),
          decoration: BoxDecoration(
            color: Tokens.cosmos.panelDeep,
            borderRadius: BorderRadius.circular(Tokens.radius.pill),
            border: Border.all(color: Tokens.palette.accent),
          ),
          child: Text(
            label!,
            style: TextStyle(
              fontSize: Tokens.type.caption,
              color: Tokens.palette.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: Tokens.space.xs),
        Expanded(child: bar),
      ],
    );
  }
}

/// A small labelled count -- "3 harvested", "2 seeds".
///
/// The icon is required and the label is short on purpose: this is the shape
/// Tolan uses along the bottom of its profile, and it only works when each chip
/// carries one fact. A chip with two numbers in it is a table, and should be one.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;

  /// The number, rendered larger than the label because it is what is scanned.
  final String value;

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // One sentence, so a screen reader says "3 harvested" rather than reading
      // an icon, a digit and a word as three separate things.
      label: '$value $label',
      excludeSemantics: true,
      child: SoftCard(
        deep: true,
        padding: EdgeInsets.symmetric(
            horizontal: Tokens.space.sm, vertical: Tokens.space.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Tokens.palette.accent),
            SizedBox(width: Tokens.space.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: Tokens.type.body,
                    color: Tokens.palette.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: Tokens.type.caption,
                    color: Tokens.palette.textDim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
