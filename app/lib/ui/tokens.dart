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

  /// The gamified surface: gradients, glow and translucent panels.
  ///
  /// ### Why this exists, since `_Palette` says "six colours, not seven"
  ///
  /// `docs/DECISIONS.md` freezes the palette at six and says adding to it "is a
  /// design decision, not a convenience". This is that decision, made
  /// deliberately and written down rather than smuggled in as a literal at a
  /// call site -- which is what `check.ps1` rule 1 exists to prevent.
  ///
  /// The reason is that the six colours are all FLAT FILLS, and the screen being
  /// built is a depth illusion: a night sky you travel up through. A gradient
  /// cannot be expressed as one of six flat colours, and faking one by stacking
  /// `surface` over `bg` produces banding rather than depth. So these are not
  /// six more content colours -- nothing here ever colours text, a status, or a
  /// control. They colour the SPACE BEHIND the content, and every foreground
  /// value on top of them still resolves through `_Palette`.
  ///
  /// Two things it deliberately does NOT take from the Tolan reference:
  ///
  /// The lime-green call-to-action. `DECISIONS.md` records that "the palette has
  /// no green", and gold is already the app's own accent and its harvest signal.
  /// Borrowing Tolan's green would make the app look like Tolan rather than like
  /// Ludeck wearing Tolan's depth, and it would put a second meaning on a colour
  /// that already means harvested.
  ///
  /// The padlocked "next" card. A lock marks what the user has NOT done, which
  /// `DECISIONS.md` forbids outright ("may only reward what already happened").
  /// Nothing here provides a locked or greyed state, so that shape is not
  /// reachable by accident.
  static const cosmos = _Cosmos();

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

/// The night sky the gamified screens sit in. Background only -- never content.
///
/// Two gradients rather than one, because the two screens are at different
/// altitudes and a single gradient cannot be both. `hero` is the profile/header
/// area, where the horizon is close and warm; `deep` is the map you travel up
/// through, where there is no horizon at all. Sharing one would either put a
/// warm glow at the top of the map (which reads as dawn, not space) or drain the
/// warmth out of the header (which reads as a dead screen).
class _Cosmos {
  const _Cosmos();

  /// Top-to-bottom stops for the header: deep indigo down to a warm horizon.
  ///
  /// Four stops, not two. A two-stop indigo-to-warm ramp passes through a muddy
  /// grey-mauve in the middle, because the shortest path between those two hues
  /// crosses desaturated ground. The intermediate violets keep the ramp saturated
  /// the whole way down.
  final List<Color> hero = const [
    Color(0xFF1B2A6B),
    Color(0xFF3B2F75),
    Color(0xFF5B4A82),
    Color(0xFF7C6580),
  ];

  /// Top-to-bottom stops for the map. Near-black at the top so a cover card and
  /// a glow both have somewhere to be bright against.
  final List<Color> deep = const [
    Color(0xFF0B0A1C),
    Color(0xFF16112E),
    Color(0xFF241A3D),
  ];

  /// A translucent panel over the gradient -- the "soft light" card.
  ///
  /// Deliberately alpha rather than opaque: an opaque card over a gradient shows
  /// a visible seam where its flat fill meets the ramp, and the card has to sit
  /// at several heights on a scrolling screen. Letting the sky through is what
  /// makes it read as glass rather than as a rectangle.
  final Color panel = const Color(0x2EFFFFFF);

  /// The hairline that gives a translucent panel an edge. Without it the panel
  /// dissolves into a bright region of the gradient and stops reading as a card.
  final Color panelEdge = const Color(0x3DFFFFFF);

  /// A darker panel, for a card that must hold small text.
  ///
  /// `panel` over the light end of `hero` leaves too little contrast under
  /// caption-sized text; this one sits over the gradient rather than in it.
  final Color panelDeep = const Color(0x8A120F26);

  /// The bloom around an orb or an active node. Used at low alpha in a radial
  /// gradient, never as a fill.
  final Color glow = const Color(0x66A99BFF);

  /// A star on the backdrop. One colour at varying alpha and size -- real
  /// starfields vary in brightness, not in hue.
  final Color star = const Color(0xFFFFFFFF);

  /// The path a roadmap travels along, where it has been walked.
  final Color trail = const Color(0x59FFFFFF);

  /// The same path where it has NOT been walked.
  ///
  /// Dimmer, and that is the one distinction this group draws between done and
  /// not-done. It is a line on a map, not a lock or a badge: it says where the
  /// path continues, which `DECISIONS.md` permits, rather than marking a game as
  /// overdue, which it forbids.
  final Color trailDim = const Color(0x24FFFFFF);
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

  /// The bigger, softer corner the gamified panels use.
  ///
  /// A second radius rather than widening `card`: `card` is a dense list row at
  /// 10, and a 20 there would make the collection look inflated. These are large
  /// standalone panels, where 10 reads as sharp-edged against a gradient.
  final double panel = 20;

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

  /// The profile orb on the header. Large on purpose: it is the one thing on
  /// that screen that is meant to be looked at rather than read.
  final double orb = 148;

  /// A game's cover card sitting on a roadmap node.
  ///
  /// Cover art is portrait (IGDB's own ratio is 3:4), so this is the WIDTH and
  /// the height follows from `coverRatio`. Storing one number and a ratio rather
  /// than two numbers means a card can never be set to a shape that crops the
  /// art.
  final double nodeCard = 64;

  /// Height divided by width for cover art. IGDB serves 3:4.
  final double coverRatio = 4 / 3;

  /// The pill progress bar's track height.
  final double progressTrack = 10;
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
