import 'package:flutter/animation.dart';

/// NO NEW VALUES.
///
/// If you need a value that is not here, change THIS FILE and say why in the
/// commit. Do not add a one-off colour, size or duration at a call site.
///
/// Ported verbatim from the Kotlin app's Tokens.kt so the two implementations
/// cannot drift apart while both exist.
class Tokens {
  Tokens._();

  /// Six colours. Not seven.
  static const palette = _Palette();

  /// Four type sizes. A fifth means the hierarchy is unclear, not that a size
  /// is missing.
  static const type = _Type();

  /// One spacing scale. Never a bare number at a call site.
  static const space = _Space();

  static const radius = _Radius();
  static const size = _Size();
  static const motion = _Motion();
}

class _Palette {
  const _Palette();
  final Color bg = const Color(0xFF0E0F11);
  final Color surface = const Color(0xFF181A1D);
  final Color text = const Color(0xFFF2F3F5);
  final Color textDim = const Color(0xFF8B9099);
  final Color accent = const Color(0xFFE8B84B);
  final Color danger = const Color(0xFFD4553F);
}

class _Type {
  const _Type();
  final double display = 28;
  final double title = 20;
  final double body = 15;
  final double caption = 13;

  /// Tracking is size-specific. Large text reads too loose as it grows, so it
  /// tightens; body sits near zero. One fixed value would be wrong somewhere.
  final double trackingDisplay = -0.02 * 28;
  final double trackingTitle = -0.01 * 20;
  final double trackingBody = 0;

  /// Leading tracks size inversely: tight on headings, looser on body.
  final double leadingDisplay = 1.05;
  final double leadingTitle = 1.2;
  final double leadingBody = 1.45;
}

class _Space {
  const _Space();
  final double xxs = 4;
  final double xs = 8;
  final double sm = 12;
  final double md = 16;
  final double lg = 24;
  final double xl = 32;
}

class _Radius {
  const _Radius();
  final double card = 10;
  final double pill = 999;
}

class _Size {
  const _Size();

  /// Minimum cover width in the list grid; the column count follows from it.
  final double coverMin = 120;

  /// A round floating control's diameter. Added because the add button's size
  /// was a bare 52 at its call site AND the chrome metrics need the same
  /// number to reserve space for it; two copies would drift and the scrim
  /// would stop matching the button it covers.
  final double control = 52;

  /// A fruit's diameter on the canvas at zoom 1.
  final double fruit = 44;

  /// Trunk width at the base, at zoom 1.
  final double trunk = 22;
}

/// Motion values from Apple's Designing Fluid Interfaces, not invented.
///
/// Response is how fast a spring reaches its target. Damping is how much it
/// overshoots: 1.0 never overshoots and is the default, because overshoot on
/// something that merely appeared feels wrong. Bounce is reserved for motion
/// the user's own gesture put momentum into.
class _Motion {
  const _Motion();

  /// Press feedback. Fires on pointer-down, so it must be near-invisible.
  final Duration press = const Duration(milliseconds: 100);

  /// Switching tree and list. Seen often, so it stays under perception.
  final Duration swap = const Duration(milliseconds: 200);

  /// A fruit growing onto a branch when a game is captured.
  final Duration grow = const Duration(milliseconds: 260);

  /// The harvest celebration. The only place the delight budget is spent.
  final Duration harvest = const Duration(milliseconds: 520);

  /// Critically damped. No overshoot. The default for everything.
  final double dampingDefault = 1.0;

  /// Slight overshoot, only after a flick or a drag release.
  final double dampingMomentum = 0.8;

  /// Apple ships response 0.3 to 0.4 for UI. Converted to a Flutter stiffness
  /// via k = m * (2 pi / response)^2, with mass 1.
  final double stiffnessDefault = 246; // response ~0.40s
  final double stiffnessSnappy = 438; // response ~0.30s

  /// Apple's scroll deceleration constant, for projecting where a flick lands.
  final double deceleration = 0.998;

  /// How far a press scales down. Deliberately barely visible.
  final double pressScale = 0.97;

  /// Zoom bounds on the tree canvas.
  final double zoomMin = 0.6;
  final double zoomMax = 3.0;

  /// Rubber-band constant. Higher resists less.
  final double rubberBand = 0.55;

  /// The strong ease-out. Platform curves are too weak to read as deliberate.
  /// Never ease-in on UI: it delays the moment the user is watching.
  final Curve easeOut = const Cubic(0.23, 1, 0.32, 1);

  /// Something already on screen moving to a new place.
  final Curve easeInOut = const Cubic(0.77, 0, 0.175, 1);
}
