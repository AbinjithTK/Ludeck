# Decisions and invariants

Everything here is settled. If a change would break one of these, the change is
wrong, not the rule. Where a rule has a reason, the reason is written down, because a
rule without a reason gets argued away later.

## Identity

| Thing | Value | Note |
|---|---|---|
| Product name | Ludeck | From *ludus* (play) and *deck* (a collection you hold) |
| Android package / applicationId | `com.ludeck.android` | Permanent once the Play record exists. Cannot be changed afterwards. |
| On-device database file | `ludeck.db` | User-visible in the app's data directory |
| RevenueCat entitlement | `pro` | One entitlement, not several |
| RevenueCat products | `pro_annual`, `pro_monthly`, `pro_lifetime` | Must exist in Play Console before the first submission |

Dead names, rejected: Hoard, Bramble, Magpie, Ludex. Zero references to any of them
may remain in the source. This was verified once by search; keep it true.

If iOS ever happens, use a bundle id without the `.android` suffix. Do not reuse
`com.ludeck.android` on another platform.

## Pricing

| Product | Price | Trial |
|---|---|---|
| Annual (default) | 19.99 USD | 30 days |
| Monthly | 2.99 USD | none |
| Lifetime | 39.99 USD | none |

**Never gate collection size, and never gate sharing.** Paywall the insight layer
only. Two competitors already gate size (QuestLog at 15 games, Cibby at 10); the
free tier being genuinely unlimited is a positioning decision, not an oversight.
Gating sharing would also break the growth loop, which is the thing most likely to
win a category.

## The status vocabulary is frozen

These enums are the only status vocabulary in the product. They are two independent
axes, never one chain.

```
Ownership  { spotted, owned, released }
Progress   { untouched, installed, playing, finished, abandoned }
Form       { digital, physical }
Acquired   { bought, subscription, gift, bundle, free }
Platform   { pc, playstation, xbox, switch_, steamDeck, quest, android, ios }
```

`Platform` is a property of a `Copy`, not of a `Game`. Its declaration order is the
order branches are laid out, lowest first. Note that `switch_` carries a trailing
underscore because `switch` is a Dart keyword; the persisted `name` is therefore
`switch_` and must not be "corrected".

Banned in code, in any casing or separator style: `want_to_play`, `wantToPlay`,
`backlog`, `completed`, `beaten`, `dropped`, `on_hold`. They are banned because each
one smuggles a single-chain model back in, and the two-axis model is the product's
main structural differentiator.

Every enum carries two labels: `label` (plain words) and `tree` (the metaphor).
Persistence uses `name`, never the label, so the metaphor can be reworded at any time
without a database migration.

## Structural invariants

**Two orthogonal axes, never one chain.** Selling a game must not destroy the record
that you finished it. A rival (Barklog) uses the single chain "waiting, playing,
completed, abandoned" and therefore cannot represent this at all.

**Ownership is a set of `Copy` rows, not a field on the game.** A game owned on two
platforms hangs on the tree twice. A test asserts this. If you find yourself adding a
`platform` field to `Game`, stop.

**`igdbId` is the only identity.** Never match, deduplicate or join on title. Titles
collide, get re-released, and differ by region.

**`timeToBeatSeconds` is in seconds.** IGDB's `game_time_to_beats` returns seconds,
not minutes and not hours. Divide by 3600 exactly once, at the display edge. Dart
has `secondsPerHour` in `app/lib/data/models.dart`; use it rather than a literal.

**Completion is the only status the tree shows.** A fruit is either harvested or it is
not, and harvested means `progress == finished`. Nothing else changes how a fruit looks.

This replaced ripeness on 2026-09-24. Ripeness was a computed third state, owned and
untouched and 15 hours or less, and it is **gone**: there is no `isRipe` getter, no
`ripe` field on the layout, and no ripeness column. Two things drove the removal. It was
a second status axis competing with progress for the same pixel, and it is not one of
the five verbs the Gaming criterion asks for, which are save, organize, complete, rate
and share.

The question ripeness was trying to answer, what should I play tonight, is answered
properly by `choosePick` in `lib/domain/pick.dart` instead: an explicit, reasoned
suggestion that can state why, rather than a colour the user has to learn.

**Never use `ConflictAlgorithm.replace` on `games`.** `INSERT OR REPLACE` in SQLite
deletes the conflicting row and inserts a new one rather than updating it. `entries`,
`copies` and `placements` all declare `REFERENCES games(igdb_id) ON DELETE CASCADE`, and
`PRAGMA foreign_keys = ON` is set per connection, so that delete cascades.

This was live for the whole of the first build. Re-importing a game you already owned
destroyed its progress, its rating, its note, who recommended it, every platform you
owned it on, and every branch it hung from. `seedIfEmpty` hid it, because nothing else
ever imported twice.

Use `ON CONFLICT(igdb_id) DO UPDATE SET` for catalogue columns, which updates in place
and triggers no delete. `entries` and `copies` use `DO NOTHING`, because only the user
changes those. Nine tests in `test/repository_hardening_test.dart` cover this and they
are the reason it cannot come back quietly.

**A shared tree must never carry `recommendedBy` or `note`.** Both are free text and
`recommendedBy` routinely holds a real person's first name, because the whole premise is
that a seed remembers who suggested it. The share card and the public tree page are
world readable, so publishing either field leaks a third party's name to the internet
without that person's consent. The share layer takes title, cover, status and rating,
and nothing else. This is a privacy rule, not a design preference.

**A released game is excluded from every season bucket, on purpose.** Ownership and
progress stay independent so a sale never erases a completion record, and that record
is `Entry.progress == finished` forever, exactly where it always was. But
`domain/season.dart`'s snapshot answers "what does my collection look like right now",
and counting a game you no longer own inflates that answer with something no longer on
the shelf. The two facts do not contradict: the record survives in the data, the season
just is not where you read it back from.

**No colour literal outside the token file.** Every colour resolves through
`app/lib/ui/tokens.dart`. The palette is exactly six colours. Adding a seventh is a
design decision, not a convenience, and it is why the Rive fruit has no green leaf.

**`Tokens.canopy` is that decision, taken on 2026-09-25 for the tree itself.**
Bark and foliage colours were added deliberately, and the earlier reasoning was
right for a 24px fruit glyph and wrong for the tree. Rendered in the six flat
colours the tree read as a grey diagram: `textDim` grey is the app's DIM TEXT
colour, so a tree painted in it looks like disabled UI rather than like wood. The
user's verdict was "the tree is very bad", and that was the cause.

The group is fenced the same way `Tokens.cosmos` is. Nothing in it may colour
text, a status, a control or a count -- it colours bark and leaf and nothing else,
every foreground value painted on top still resolves through `_Palette`, and gold
keeps its single meaning of harvested. It inherits two rules rather than
renegotiating them: foliage never browns, thins or sheds (the metaphor may not
wither), and nothing in it animates at rest (§Motion rejects idle leaf sway).

**The tree is COLOURFUL, and it is a SKIN, decided 2026-09-26.** Abin reversed
the muted-tree call: his words were the tree is "very boring" and he wants it
"colourful" and "gaming themed". The muted hues (`skins.midnight`) were chosen so
foliage would not fight the indigo sky, and they produced a tree the colour of a
disabled UI surface. So `Tokens.canopy` is no longer a fixed group; it resolves
through `Tokens.activeSkin`, one of several `TreeSkin`s, each carrying its own
bark, foliage, ground, glow AND sky (a saturated foliage set needs a sky chosen
for it). The skins still obey every fence above -- material and light only, gold
untouched.

The active skin is **`biolume`**, a bioluminescent night garden: glowing teal
foliage, warm bark, deep aquatic navy sky. It was chosen from four real
device-size renders at empty / 8 / 13 games, not from description. `twilight`
(sunset orchard) lost cover-card contrast against its bright sky, and covers are
the point of the tree; `neon` (synthwave) made the bark vanish into the dark and
its hot-pink foliage competed with harvest gold for "look here", which this file
reserves for gold alone. Both remain in `tokens.dart` for a one-line revert.
Colour is on its own axis: the render at 13 games confirmed it does NOT fix the
composition defect (covers crowd the middle band, lower trunk bare) -- that is
the foliage/light stage and the 3D stage, deliberately separate.

**The tree WILL rotate, decided 2026-09-26.** The old rule ("no rotation, the
user rejected a rotating tree twice") is superseded by Abin's own request for a
rotatable tree. The two prior rejections were of a FAKE parallax orbit (five Rive
layers sliding), not of a true perspective camera, and that path is now buildable
(the Stage-1 flutter_scene gate cleared). The real objection that still stands --
"a rotated limb puts every game title at an angle" -- is answered by billboarding:
covers become `WidgetComponent`s that always face the camera while the wood turns,
so titles stay upright. This is built in the 3D stage, not on the painter.

**SUPERSEDED 2026-09-26: the tree is retired for a node roadmap.** After the 3D
tree rendered (bark meshes, orbit, billboarded covers, all working behind a flag),
Abin judged both the 2D painted tree and the 3D scene wrong for the product and
asked for a Noom/Mimo-style **editable roadmap of connected nodes** instead: each
game a node on a winding path, joined by rounded elbow connectors, with a draw-line
creation animation and an editable, reorderable order. `flutter_scene`, the 3D
scene, `tree_mesh`, `tree_painter` and `procedural_tree` were all deleted; the
renderer is now `ui/roadmap/`. The no-rotation objection is moot — a roadmap
scrolls, it does not orbit. The billboarding lesson still stands as history. The
`docs/HANDOFF.md`, `DESIGN.md` and `PROGRESS.md` tree sections predate this pivot.

**`shelved` replaces delete.** Nothing the user has recorded is ever destroyed by a
normal action.

**The metaphor may never wither, rot, nag, empty or shrink.** A full tree is a
healthy tree. This forbids a whole class of otherwise ordinary features: overdue
badges, decay timers, "you haven't played this in 90 days" nudges, empty-state guilt.

*Amended 2026-09-28 (Abin):* an orchard tree's size follows the games it holds, so
it eases smaller when the user moves a game off it. The rule above is about time and
neglect, and it still holds absolutely: nothing but the user's own move ever makes a
tree smaller, and a shake never removes a game. The search screen's discovery tree
still only grows (`onlyGrow`), because a new result set is a browse, not a loss.

**Gamification may only reward what already happened, never mark what has not.**
Seasons, not streaks. A streak punishes a missed day; a season simply ends and a new
one starts.

## Motion

Springs come from measured Apple values, converted for Flutter with

```
k = m * (2*pi/response)^2      with mass = 1
```

which gives stiffness 246 for a 0.40 s response and 438 for a 0.30 s response.
Damping is set for critical or near-critical behaviour, never bouncy overshoot on
functional UI.

Press feedback fires on **pointer-down**, not on tap-up. A press that waits for
release feels broken even when the timing is identical.

Drag tracks the finger 1:1. Release hands the real velocity to the spring, and the
committed or cancelled decision uses a momentum projection of where the finger was
going, not where it stopped.

Reduced motion is honoured by reading `ANIMATOR_DURATION_SCALE`. When it is zero,
animations resolve instantly rather than being skipped in a way that loses state.

**The meadow moves at rest, decided 2026-09-27.** Abin reversed "nothing animates
at rest": his words were "the grass and flowers should animate perfectly, wiggle
or something, make the scenes live". It is fenced so it stays atmosphere: only the
meadow's grass, the flowers, fireflies and lantern move (one `MeadowClock` in
`meadow.dart`); blades bend at most `kSwayLean` (0.075 rad) in a slow travelling
wave, and a swipe blows them the way the ground trails, bounded by `kWindMax`,
settling in ~0.4s. The sky, the tree, covers, text and controls never move at
rest, and under reduce motion nothing moves at all.

**A game's state on the tree is a shape, never a colour to learn.** `fruit_look.dart`
bakes it into the card image: a bud (recommended, not owned) is drained of colour,
playing carries a play mark, harvested a gold rim and check (gold keeps its one
meaning), everything else is the plain cover. A game with no cover is a lettered
card.

## Rive

The fruit artboard is 240x240. The body Shape sits at (120, 140) with diameter 112,
so radius 56. To place it at centre `(cx, cy)` with radius `r`:

```
scale = r / 56
left  = cx - 120 * scale
top   = cy - 140 * scale
side  = 240 * scale
```

Draw order in RML is front-to-back: the first declared element paints on top. This is
the reverse of HTML and is the single easiest thing to get wrong.

There is no Artboard `Fill`, so the artboard composites over whatever is behind it.

The stem is `textDim`. In `surface` it was invisible. The leaf was dropped: in grey it
read as a pebble, and the palette has no green.

Import the runtime prefixed, because `rive_native` exports its own `Animation` and
`PaintingStyle` which collide with Flutter's:

```dart
import 'package:rive/rive.dart' as rv;
```

Create **one** `FileLoader` for the whole tree, not one per fruit.

```dart
rv.FileLoader.fromAsset('assets/fruit.riv', riveFactory: rv.Factory.rive)
rv.RiveWidgetBuilder(
  fileLoader: loader,
  builder: (context, state) => switch (state) {
    rv.RiveLoaded() => rv.RiveWidget(controller: state.controller, fit: rv.Fit.contain),
    _ => const SizedBox.shrink(),
  },
)
```

Load states are `RiveLoading`, `RiveLoaded` (has `.controller`) and `RiveFailed`.

Never guess a Rive type or property name. Use `rive schema <Type>` and
`rive docs <topic>`; Rive's own `AGENTS.md` says the same.

Rive renders **harvested fruit only**, because the artboard has one hardcoded gold and
colour carries status. That is now the right way round rather than a gap: gold is the
best-looking fruit and harvested is the achievement, so the good art marks the thing
worth marking. Everything unharvested uses `_PaintedFruit`, whose radial highlight is
positioned to match the artboard so the two read as the same object.

This used to say gold meant ripe and called it a known gap needing a `ripeness` float
input. Ripeness no longer exists, so that gap is closed by deletion rather than by work.

## Process decisions

**Flutter is the shipping stack.** This was chosen on 23 September at 22:24, after
the risk was argued twice and acknowledged. It is not reopened.

**The Kotlin app is not deleted.** It builds, it passes its own guard script, and it
is the fallback if Flutter runs out of time. It lives in `fallback-kotlin/`.

**User-named branches supersede platform-derived branches.** Arbitrary, unlimited
categorisation, so the tree has a different shape per person. This replaced an
earlier design where branches were fixed platforms.

## The shell, the social area, and the seed lifecycle

Decided 2026-09-26 from three sets of options shown side by side. Each is
isolated to its own stage, so any one can be reversed without touching the others.

**Navigation is a floating pill plus two corner chips, not a tab bar.** A bottom
tab bar costs 56dp permanently on the one screen whose entire purpose is the
tree, and Tolan-style corner-only chrome hides Friends so thoroughly a new user
would not find it. The pill is translucent over the sky and fades while the tree
is being dragged. THE FADE MAY NOT HIDE NAVIGATION -- if it cannot be made to
read while faded, it does not fade.

Before this, the only exits from home were the profile orb and a 17dp glyph, and
`VisitScreen` -- the whole social surface -- sat four taps deep behind "See what
a visitor sees" on the user's own share card. So you could only ever visit your
OWN tree, which is why Follow had no screen where following meant anything.

**The social area is a friends list with handle search.** Find by handle, follow,
tap to open their tree, graft from a visit. Not an "orchard" of friends' trees as
a walkable landscape: that is a second world with its own lighting and camera,
and it is not what makes Follow reachable. No counts, no feed -- the freeze above
still holds, and all three options were drawn to respect it.

**Wishlist games become BUDS on the tree; the soil strip becomes an inbox.**
A seed does not become an apple on a tree that already exists -- it grows its own
tree. The real mechanism for "a friend recommended this, it is mine now, and I
remember it came from them" is GRAFTING, and `Entry.recommendedBy` already stores
that provenance. So seed/graft keeps its meaning as the social act, and the
wishlist gets the lifecycle it actually has: bud, blossom, fruit, harvested.

The strip is not deleted outright. It shrinks to "just arrived, not placed yet"
and empties as games are filed, because a new arrival needs somewhere to land
before it is placed and organising should stay a deliberate act. Its empty state
must read as FINISHED, not as broken.

This is presentation, not persistence: `DESIGN.md` §3 already states the tree
words are a presentation layer, so there is **no schema migration** in any of it.

It also fixes two rendering defects for free. The user's own screenshot had 7
seeds against 4 on the tree, so more than half the collection sat in a cramped
strip while the tree above it was sparse -- and Stage 2 of the render work left
the lower third of the trunk bare while covers crowded the top. Moving the bulk
of the collection onto the wood is the same change as fixing both.

## Copy rules

No em dashes. No arrows. No horizontal rules. No "delve", "leverage", "seamless",
"unlock", "elevate", "game-changer", or any sentence of the shape "it's not just X,
it's Y". Plain words. Short sentences. This applies to UI strings, store listing,
the Devpost writeup and commit messages.
