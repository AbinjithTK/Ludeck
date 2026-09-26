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

  /// The tree's own material: bark and foliage.
  ///
  /// ### This is the palette decision, made deliberately
  ///
  /// `docs/DECISIONS.md` says a colour outside the six "is a design decision,
  /// not a convenience, and it is why the Rive fruit has no green leaf", and
  /// §"Fruit" records the leaf being dropped because "in grey it read as a
  /// pebble, and the palette has no green". That reasoning was right for a
  /// 24px fruit glyph and wrong for the tree itself, which is the single
  /// largest object in the app and the whole metaphor. Rendered in the six
  /// flat colours it read as a grey diagram of a tree -- the user's words were
  /// "the tree is very bad" -- and the reason is structural: `textDim` grey is
  /// the app's DIM TEXT colour, so a tree painted in it looks like disabled UI
  /// rather than like wood.
  ///
  /// So this group is the seventh-colour decision taken on purpose, and the
  /// same discipline as `_Cosmos` applies to it: nothing here ever colours
  /// text, a status, a control or a count. It colours BARK AND LEAF, and
  /// nothing else in the app may reach for it. Every foreground value painted
  /// on top still resolves through `_Palette`, and harvest is still
  /// `palette.accent` -- gold keeps its one meaning.
  ///
  /// Two rules it inherits rather than renegotiates:
  ///
  ///  - Foliage NEVER browns, thins or sheds. `DECISIONS.md`: "the metaphor may
  ///    never wither, rot, nag, empty or shrink". There is deliberately no
  ///    autumn or dead value here, so that state is not reachable by accident.
  ///  - Nothing here animates at rest. `DESIGN.md` §7 rejects idle leaf sway
  ///    outright as a vestibular trigger seen every launch.
  /// The tree's material and light, resolved through the ACTIVE skin.
  ///
  /// Every call site reads `Tokens.canopy.barkMid` and so on unchanged. What
  /// changed on 2026-09-26 is that the values behind it are one of several
  /// `TreeSkin`s rather than a fixed group, so a colour direction is chosen by
  /// pointing `activeSkin` at a different skin -- no call site edits, and the
  /// colour-literal rule stays satisfied because every skin lives in this file.
  static TreeSkin get canopy => activeSkin;

  /// The candidate looks. `skins.midnight` is what shipped before this change.
  static const skins = _Skins();

  /// The skin the app renders with. Chosen on 2026-09-26 from four real
  /// device-size renders (`skin-*` captures): `biolume`, the bioluminescent
  /// night garden. It keeps the dark sky that gives cover art its contrast and
  /// keeps gold as the one reward colour, while the glowing teal foliage answers
  /// Abin's "boring / not colourful" verdict. `twilight` lost cover contrast
  /// against its bright sky; `neon` made the bark vanish and its pink foliage
  /// competed with harvest gold. The render harness still swaps this per
  /// capture; the other three remain for a one-line revert.
  static TreeSkin activeSkin = skins.biolume;

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

  /// Mask stops for an edge fade. NOT palette colours -- only their ALPHA is
  /// used, by a `BlendMode.dstIn` ShaderMask, so the RGB is irrelevant and
  /// nothing on screen is ever tinted by them.
  ///
  /// They live here because `check.ps1` rule 1 bans a colour literal outside this
  /// file, and the rule is mechanical for a good reason: an exception for "it is
  /// only a mask" is exactly how a seventh palette colour arrives. Keeping them
  /// here costs nothing and keeps the guard honest.
  final Color maskOpaque = const Color(0xFF000000);
  final Color maskClear = const Color(0x00000000);
}

/// Bark and leaf. The tree's material, never content.
///
/// ### Why these hues and not "brown" and "green"
///
/// The tree stands in `_Cosmos.deep` -- a near-black indigo sky. A naturalistic
/// daylight brown goes muddy-orange against indigo, and a saturated leaf green
/// fights it outright, because indigo and pure green are close to opposite in
/// hue and neither yields. Both families are therefore pulled TOWARD the sky:
/// the bark is a violet-leaning brown and the foliage a deep blue-green. That is
/// also physically right for the scene -- this tree is lit by a cool night sky,
/// not by afternoon sun, so every hue carries some of that light.
///
/// Three bark values rather than one, because a stem is a CYLINDER. A single
/// fill makes it a flat ribbon no matter how well the outline is shaped; the
/// unlit-to-lit ramp across its width is what makes it round, and it is the
/// cheapest depth cue in the file.
/// A complete look for the tree: bark, foliage, ground, and the sky it stands
/// against.
///
/// ### Why this is a swappable type and not a fixed group
///
/// It used to be a single `const _Canopy()`. On 2026-09-26 Abin reversed the
/// muted-tree decision -- his words were the tree is "very boring" and he wants
/// it "colourful" and "gaming themed". The muted hues below (`midnight`) were
/// chosen so foliage would not fight the indigo sky; that was a defensible call
/// and it produced a tree the colour of a disabled UI surface. Rather than
/// argue three colour directions in prose, they are three real `TreeSkin`
/// values rendered at device size and judged from pixels.
///
/// A skin therefore carries its OWN sky, because a saturated foliage set that
/// reads well needs a sky chosen for it: the same bark against two different
/// skies is two different pictures, and judging a colourful tree against the
/// muted `_Cosmos.deep` would judge the wrong one.
///
/// Everything a skin inherits from the old `_Canopy` still holds: nothing here
/// colours text, a status, a control or a count; harvest stays `palette.accent`
/// gold with its single meaning; foliage never browns or sheds; nothing
/// animates at rest. A skin is a material and a light, not a new content
/// palette.
class TreeSkin {
  const TreeSkin({
    required this.name,
    required this.barkShade,
    required this.barkMid,
    required this.barkLit,
    required this.foliageNear,
    required this.foliageFar,
    required this.foliageLit,
    required this.ground,
    required this.groundLit,
    required this.sky,
    required this.glow,
  });

  /// A stable id for captures, tests and the recorded decision.
  final String name;

  /// The shaded side of a stem, away from the light.
  final Color barkShade;

  /// The body of the bark.
  final Color barkMid;

  /// The lit side, catching the sky.
  final Color barkLit;

  /// Leaf mass at the front of the canopy.
  final Color foliageNear;

  /// Leaf mass set back, and the mass behind the trunk. Darker, for aerial
  /// perspective rather than plain opacity.
  final Color foliageFar;

  /// The highlight on the crown where the light hits it hardest.
  final Color foliageLit;

  /// The mound the tree stands on.
  final Color ground;

  /// The lit lip of that mound, which stops the ground reading as a hole.
  final Color groundLit;

  /// The sky this skin stands against, top-to-bottom. A skin is judged against
  /// its own sky, never against a shared default.
  final List<Color> sky;

  /// An ambient bloom colour the crown catches, low alpha. This is what makes a
  /// "lit" tree read as lit rather than as flatly brighter. Never a fill.
  final Color glow;
}

/// The three candidate looks, all defined here so `check.ps1` rule 1 stays
/// mechanical: a colour lives in this file or it does not ship.
class _Skins {
  const _Skins();

  /// WHAT SHIPS TODAY. The muted night tree. Kept as the safe fallback and the
  /// regression baseline, so a skin swap can be reverted to exactly this.
  final TreeSkin midnight = const TreeSkin(
    name: 'midnight',
    barkShade: Color(0xFF241B2A),
    barkMid: Color(0xFF3E2F3A),
    barkLit: Color(0xFF6B5668),
    foliageNear: Color(0xFF2E5A4E),
    foliageFar: Color(0xFF1B3A3C),
    foliageLit: Color(0xFF4A7F63),
    ground: Color(0xFF191426),
    groundLit: Color(0xFF2A2140),
    sky: [Color(0xFF0B0A1C), Color(0xFF16112E), Color(0xFF241A3D)],
    glow: Color(0x00000000),
  );

  /// A · BIOLUMINESCENT NIGHT GARDEN. Still a night tree, but the foliage
  /// glows: teal-cyan leaves lit from within, warm amber bark, against a deep
  /// aquatic navy. The gaming read is "magical night biome" -- Ori, Gris,
  /// Hollow Knight's brighter zones. Closest to what ships, so the lowest-risk
  /// step up in colour, and the glow does real work rather than just raising
  /// saturation.
  final TreeSkin biolume = const TreeSkin(
    name: 'biolume',
    barkShade: Color(0xFF2A1E33),
    barkMid: Color(0xFF5A3E52),
    barkLit: Color(0xFF9C7A6E),
    foliageNear: Color(0xFF1FB89A),
    foliageFar: Color(0xFF15707E),
    foliageLit: Color(0xFF6BF0C8),
    ground: Color(0xFF0F1A2E),
    groundLit: Color(0xFF1E3A5C),
    sky: [Color(0xFF04121F), Color(0xFF0A2438), Color(0xFF123A4A)],
    glow: Color(0x8047F0C8),
  );

  /// B · VIVID TWILIGHT ORCHARD. A real tree at golden hour on an alien world:
  /// warm sienna bark, saturated green-to-lime foliage, a magenta-to-orange
  /// sunset sky. The most naturalistic and the most broadly appealing -- reads
  /// as a lush fantasy world (Fortnite, Sky, Genshin) rather than a UI element.
  /// The risk is that a sunset sky is bright, so a cover card has less contrast
  /// against it than against near-black.
  final TreeSkin twilight = const TreeSkin(
    name: 'twilight',
    barkShade: Color(0xFF3A2118),
    barkMid: Color(0xFF6E4A2E),
    barkLit: Color(0xFFB98A54),
    foliageNear: Color(0xFF4FA83E),
    foliageFar: Color(0xFF2E6B3A),
    foliageLit: Color(0xFFBFE84B),
    ground: Color(0xFF2E1A2A),
    groundLit: Color(0xFF5C2E48),
    sky: [Color(0xFF2B1140), Color(0xFF7A2A5A), Color(0xFFC85A3C)],
    glow: Color(0x80F0A24B),
  );

  /// C · ARCADE NEON. The tree as a synthwave object: near-black bark with an
  /// electric magenta rim, hot-pink-to-cyan foliage, a grid-purple sky. The
  /// most overtly "gaming" and the most divisive -- unmistakably a game screen
  /// (Tron, Hades' neon, retrowave), but it pushes furthest from a tree and the
  /// pink foliage risks competing with harvest gold for "look here".
  final TreeSkin neon = const TreeSkin(
    name: 'neon',
    barkShade: Color(0xFF1A0F26),
    barkMid: Color(0xFF3D1F52),
    barkLit: Color(0xFFE84BC8),
    foliageNear: Color(0xFFFF4FB0),
    foliageFar: Color(0xFF7A2E9C),
    foliageLit: Color(0xFF4FE8FF),
    ground: Color(0xFF160B24),
    groundLit: Color(0xFF6B1FA8),
    sky: [Color(0xFF0A0620), Color(0xFF1F0F3D), Color(0xFF3D1F6B)],
    glow: Color(0x80FF4FE8),
  );
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

  /// The floating navigation pill's height.
  ///
  /// 56 carries an icon and its word in two lines and still clears the 48dp
  /// minimum touch target, which a bar of four destinations has to: with four
  /// Expanded children on a 412pt phone each one is about 95pt wide, so height is
  /// the only dimension that can fail the target. A shorter pill would mean
  /// dropping the labels, and `NavPill` documents why the labels are not
  /// optional.
  final double navPill = 56;

  /// A fruit's diameter on the canvas at zoom 1.
  ///
  /// 56, raised from 44 after looking at a device capture. A fruit is a real
  /// cover card, and at 44 on a 412pt phone the art was too small to tell one
  /// game from another -- which defeats the entire reason the tree hangs covers
  /// instead of painted circles. The height follows from `coverRatio`, so this
  /// number can never crop the art.
  final double fruit = 56;

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
