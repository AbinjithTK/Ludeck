# Ludeck: Design

This document describes the design as built. Where it disagrees with
`DECISIONS.md`, `DECISIONS.md` wins, because that file is the running record of
decisions and this one is the explanation of them. Where either disagrees with
the code, the code wins and the doc is the thing that needs fixing.

The data model is frozen in `app/lib/data/enums.dart`. Two orthogonal axes,
ownership and progress, and they are not re-litigated here.

## 1. The problem, stated positively

Someone mentions a game. You see a clip on TikTok. A friend says "you'd love
this". Three weeks later you remember none of it.

That is the problem Ludeck solves: **games you genuinely wanted to play,
captured the moment they land on your radar, so they do not slip away.**

It is not a backlog app. A backlog is a debt, and every competitor in this space
frames it that way. One rival ships the statuses "waiting, playing, completed,
abandoned", another calls itself a bucket list. Debt language makes the app a
place you avoid opening, which is exactly wrong for something whose value
depends on you opening it.

**Ludeck is a tree you grow.** Games arrive as fruit. Finishing one is a
harvest. Nothing on the tree is an accusation.

### The emotion we are designing for

Calm pride. Not urgency, not guilt, not completionism. A person opening Ludeck
should feel the way you feel looking at a plant you kept alive.

This single decision governs everything below. Any feature that makes a user
feel behind is wrong here even if it would increase engagement.

## 2. The metaphor, and its rules

A metaphor that is not consistent is worse than no metaphor. These rules are not
flavour text; they decide what the UI is allowed to do.

| Metaphor | Means | Rule it imposes |
|---|---|---|
| **Bud** | Someone recommended it. Not owned. | A bud can sit unopened forever without reproach |
| **Growing** | Owned, not yet finished | Fruit does not rot. Nothing decays over time |
| **Harvested** | Finished | Harvest is the celebration moment. The one place delight is spent |
| **Pressed** | Set aside, stopped playing | Kept, not discarded. A pressed flower, not compost |
| **Branch** | A named group the user made | Branch thickness follows how many games sit on it |

**There is exactly one status the tree shows: harvested or not.** Ripeness was
removed on 2026-09-24. It had been a computed "short enough to finish soon"
state rendered as a colour, and it failed for a reason worth recording: a colour
asks the user to learn what the colour means, and it can only ever hint. The
question ripeness was trying to answer now belongs to `choosePick`, which
answers it in a sentence that states its own reason. See §14.

**What the metaphor must never do:** wither, rot, nag, empty, or shrink. There
is no neglect state. A tree with two hundred unpicked fruit is a healthy tree,
not a failure, and that is the entire point.

### Vocabulary is presentation, not persistence

The database keeps the enum `name`. The tree words are a display layer on top.
This matters because a metaphor is a product decision that may change, and a
schema migration is expensive. Both labels live on the enum itself:

| Enum value | Plain label | Tree word |
|---|---|---|
| `Ownership.spotted` | Spotted | Bud |
| `Ownership.owned` | Owned | On the tree |
| `Ownership.released` | Let go | Given away |
| `Progress.untouched` | Not started | Growing |
| `Progress.installed` | Installed | Within reach |
| `Progress.playing` | Playing | In hand |
| `Progress.finished` | Finished | Harvested |
| `Progress.abandoned` | Set aside | Pressed |

The banned words stay banned in code: `backlog`, `completed`, `beaten`,
`dropped`, `on_hold`, `want_to_play`. `scripts\check.ps1` enforces that, and it
also enforces that ripeness stays gone, in both its identifier and its
display-string form.

## 3. The main screen is the tree

A glance at the main screen answers one question: **what could I play?**

The scene is full bleed. Chrome floats at the screen edges over it rather than
sitting in a reserved strip, because a header strip made the tree read as a
diagram inside a panel instead of a place.

Layout, bottom to top:

- **The ground** is where the trunk stands. It carries nothing. Until
  2026-09-26 it held a strip of recommendations resting in soil; that strip is
  gone, because a seed does not become an apple on a tree that already exists,
  and because on a real collection it put more than half the games in a cramped
  bar under a sparse tree. See `DECISIONS.md`.
- **Buds** are recommendations, hanging on the wood. Smaller than fruit, with a
  green calyx, so "not yours yet" reads without a label while the cover art stays
  identifiable. A bud can be filed onto a named branch like anything else.
- **Branches** are the user's own named groups. See §13.
- **Fruit** are games, positioned on their branch. Order within a branch is
  deterministic, with harvested fruit sorted last, so the arrangement does not
  shuffle between launches.

**Grafting** is the social act, and it is separate from the bud. You take a
cutting from someone else's tree and it grows on yours while staying their
variety -- which is exactly "a friend recommended this, it is mine now, and I
remember where it came from". `Entry.recommendedBy` is where that provenance
already lived.

### The status line is two lines and counts only what exists

The headline counts what is on the tree: "41 on the tree." At zero it says
"Nothing growing yet.", and with buds but nothing owned, "All buds, for now."
It can only go up, which is the whole difference between this and a backlog.

The second line omits any part that is zero rather than printing the zero, so it
reads "9 harvested · 2 seeds" and never "0 harvested", because a zero there
reads as a reproach and an omission does not. The active filter, when there is
one, appends to the same line.

### Rendering: Rive artboards in parallax layers

The original decision here was a single `CustomPainter` with 2.5D depth cues,
chosen over three.js and `flutter_scene`. The reasoning against those still
holds and is worth keeping:

- three.js does not exist in Flutter. Reaching it means a `WebView`, which costs
  a platform view, breaks gesture arenas, and adds a visible seam between the
  web surface and the Flutter chrome.
- `flutter_scene` is experimental and Impeller-only, which is a poor bet for a
  v1.
- A real 3D scene in a collection app usually reads as a tech demo.

**What actually shipped is the Rive path described in §12**, which replaced the
painter's drawing while keeping its arithmetic. Depth comes from scale, opacity
and parallax across five authored layers. The painter survives as the fallback
for unharvested fruit and as the fallback when a Rive layer fails to load.

Gesture behaviour:

- **Horizontal drag to orbit** shifts the layers against each other. Not true 3D
  rotation; the illusion is sufficient and it cannot break. Past one unit of
  rotation the response is damped rather than clamped, so the gesture never
  feels like it hit a wall, and release hands the real velocity to a spring.
- **Pinch to zoom** is 1:1 with the gesture, rubber-banded at both bounds.
- **Vertical drag to pan** is bounded by the tree's own extent, rubber-banded.

### The list is a first-class equal, not a fallback

Some people want a list, and a list is faster for finding one known thing. One
tap switches. **The list is not a degraded mode:** it carries the same filters,
the same hold-to-change, and the same information.

Accessibility makes this non-negotiable rather than nice. A canvas is invisible
to a screen reader, so the list view is the accessible path, it must be
complete, and every fruit needs a semantics label regardless.

## 4. Capture is the wedge

The judged criterion is whether a user can save a game the moment they discover
it. Two rivals now attack this via the share sheet. Ludeck must be at least as
fast.

**Path one, the share sheet.** You are in TikTok, Instagram or a browser. Share
to Ludeck. Ludeck reads the text and URL, resolves the game against IGDB, and
plants a **seed**: no screen, no form, one system toast. You never leave what
you were watching.

**Path two, Steam import.** One paste of a vanity URL grows the whole tree at
once, with real playtime and last-played dates already attached. This is the
moment that sells the app: an empty screen becomes a tree in one action.

**Path three, search.** Type, tap, planted.

A seed captured with low confidence is still planted. It sits in soil with a
quiet "is this right?" affordance. **Never block capture on certainty.** The
cost of a wrong seed is one tap to fix, the cost of a refused capture is a lost
game.

## 5. Platforms are a property, not the organising axis

Platforms supported by name: **PC, PlayStation 5, Xbox, Nintendo Switch, Steam
Deck, Meta Quest, Android, iOS**.

`Copy` rows carry `platform`, one row per copy, so owning a game on two
platforms is two copies and selling one does not erase the other.

This section originally made platforms the branches. **§13 supersedes that.**
Platform remains a real property of a copy, shown on the fruit and available as
a filter, because "can I actually play this tonight" depends on it. It is no
longer what the tree is organised by.

## 6. Social: visiting, not competing

Hypelist's lesson, taken with its numbers: 20,000 monthly installs and $0
monthly revenue. Social curation earns attention, not money. So social here is
cheap to build and is not where monetisation lives.

**Your tree has a public address.** `ludeck.app/@you` renders your tree as a web
page, zoomable, no app install required. This is the shareable artifact, and it
is also the Layers growth-loop surface, so one piece of work serves both.

What ships:

- **Visit a friend's tree.** Read-only. See their branches, their harvests.
- **Plant from a friend's tree.** One tap moves a fruit you saw into your soil
  as a seed, crediting them. This is the loop: a visit produces a capture.
- **Recommend directly.** Send a game to someone's soil. It arrives as a seed
  with your name on it, which is exactly the "someone recommended it" case in
  §1.

What is explicitly **not** built: follower counts, leaderboards, streaks,
activity feeds, comments. Every one of them converts calm pride into
competition, and §1 says no.

**One privacy rule, binding on the share layer when it is built.**
`recommendedBy` routinely holds a real person's first name, because the premise
is that a seed remembers who suggested it. A public tree page must never carry
it. The share payload is title, cover, status and rating, and nothing else.

## 7. Motion

The `animate` gate applied honestly. Two things in the original request were
rejected.

| Interaction | Frequency tier | Purpose | Decision |
|---|---|---|---|
| Tree at rest on app open | Many times a day | none nameable | **No animation.** The tree is already grown. Renders at final state instantly |
| Fruit appears on capture | Occasional | state indication | Animate. Grows along the branch, 260ms |
| Harvest | Rare | delight | The delight budget. This is the one celebration |
| Pinch, orbit, pan | Continuous | direct manipulation | Gesture-driven, 1:1, no duration at all |
| Press a fruit | Tens a day | feedback | Scale 0.97 on pointer-**down**, 100ms |
| Switch tree and list | Occasional | spatial consistency | Cross-fade plus slight scale, 200ms |

**Rejected from the request:**

- **An idle animation on the tree**, leaves swaying, ambient drift. It fails the
  gate outright: seen every launch, no nameable purpose, and a slow looping
  oscillation near 0.2Hz is specifically listed as a vestibular trigger. A tree
  that moves when you are trying to read it is decoration charged to the user.
- **Growth animation replayed on every open.** Charming once, an obstacle by the
  fourth launch. It plays when something is actually added, and never otherwise.

### Ingredients

- **Springs for everything a finger touches.** Critically damped, `damping 1.0`,
  `response 0.4`. Bounce only after a flick released with momentum,
  `damping 0.8`.
- **Momentum projection** on a flicked orbit: `current + (v/1000)·d/(1−d)`,
  `d = 0.998`. Land where the gesture was going, not where the finger stopped.
- **Rubber-banding** at zoom and pan bounds: `(over·dim·0.55)/(dim + 0.55·|over|)`.
- **Easing for the non-gesture cases:** `cubic-bezier(0.23, 1, 0.32, 1)`. Never
  `ease-in` on entry.
- **Reduced motion** is a first-class branch, not a stripped one. Growth becomes
  a cross-fade, harvest becomes a still badge, orbit and parallax are disabled,
  zoom stays because it is comprehension rather than decoration.
- **Haptics** on three events only: seed planted, harvest, and a snap at a zoom
  bound. Fired on the same frame as the visual. More than three trains people to
  ignore all of them.

## 8. Screens

1. **Tree**, the main screen. Ground, branches, fruit, seeds. Two lines of
   status.
2. **List**, the same data, sortable and filterable, fully accessible.
3. **Game**, opens from a fruit. Cover, hours to finish, the platforms you own
   it on, status, your note. Hold a fruit to change status without coming here at
   all.
4. **Plant**, search and Steam import. The only screen with a text field.
5. **Soil**, seeds awaiting a decision, with who recommended each.
6. **Visit**, a friend's tree, read-only, with plant-from-here.
7. **Paywall**, appears only on reaching for the insight layer. Never gates
   collection size and never gates sharing.

## 9. What is paid

Free forever: unlimited games, the tree, branches, Steam import, sharing,
visiting, and an unfiltered answer to "what should I play".

The paid set is defined in exactly one place, `app/lib/domain/entitlement.dart`,
as four named capabilities. Everything not named there is free by default, which
is deliberate: paid status is something a capability has to be explicitly given,
not something the absence of a rule falls back to.

| Capability | What it is |
|---|---|
| `reasonedPick` | The pick filtered by time available, device, or mood. The unfiltered pick is free |
| `seasonSummary` | The season rollup: harvested, pressed, still growing, seeds |
| `spendAnalysis` | What was spent, broken down per platform |
| `timeToClear` | A projection of how long the remaining collection would take to clear |

Pricing: `pro`, annual $19.99 with a 30-day trial, monthly $2.99, lifetime
$39.99.

Rivals gate at 15 and 10 games. Gating collection size on a collection app
punishes the exact behaviour the product needs, so there is no `Capability`
value for collection size and none for sharing. Two tests assert that no
capability name can even plausibly mean either. We gate the *reflection*, not
the *recording*.

The paywall copy states the free promise outright, and a test fails if the words
"limit", "up to", "maximum" or "unlimited games" ever appear on that screen.
Competitors cap collections, so users assume the worst unless told otherwise.

## 10. Cut, and why

- **3D engine.** §3. Not shippable at the required quality.
- **Ripeness.** §2. A computed status carried by colour, replaced by a pick that
  states its reason.
- **PSN, Xbox and Nintendo auto-import.** No public API exists. Manual
  per-platform ownership only, and the branch UI makes that feel intentional
  rather than missing.
- **AI game identification from video.** A rival does this. It needs a vision
  model on the capture path and would make the wedge slower and less certain.
- **Follower graph, streaks, leaderboards.** §6.
- **Light theme.** Cover art reads better on dark. One well-tuned theme beats two
  half-tuned ones.

## 11. Build order

Numbered because time is short and the order is the plan.

1. Tokens and motion layer. Same six colours, same Apple spring values as the
   earlier Kotlin prototype.
2. Data layer. The frozen enums, `Game`, `Copy`, `Entry`, on **sqflite with
   hand-written SQL**. Not Drift, not Isar, and not by preference: code
   generation is unavailable on this toolchain, because Flutter pins `meta` to
   1.17.0, which caps the analyzer, which caps `build_runner`, which the Dart
   SDK then refuses to run. Hand-written SQL has no such dependency.
3. **List view first.** It is the accessible path and it proves the data layer
   without any canvas risk. If everything else slips, this still ships.
4. Tree scene, static. No gestures. Just correct layout of branches and fruit.
5. Gestures: orbit, pinch, pan, with rubber-banding and momentum.
6. Hold-to-change status, growth on capture, harvest.
7. Steam import.
8. Paywall, then Layers, then the public web tree.

Step 3 is the checkpoint. **If the scene is not convincing by the time step 4
ends, ship the list and call the tree a v1.1 feature.** A polished list beats a
janky tree, and the metaphor survives in the language either way.

## 12. Rive, as built

An earlier version of this document said a Rive artboard needs a human in the
Rive editor, so an agent could not author one. That was wrong. Rive ships an
official CLI that writes **Rive Markup Language**, and it runs on Windows.

**What shipped.** Two files. `assets/tree.riv` carries five artboards, and
`assets/fruit.riv` carries one.

| Artboard | Parallax multiplier | Note |
|---|---|---|
| `TreeGround` | 0.10 | Barely moves. A floor that slides destroys the illusion faster than anything else |
| `TreeBack` | -0.85 | Counter-moves against the finger, which is what far things do |
| `TreeMid` | -0.35 | Mid branches and the leader |
| `TreeTrunk` | 0.00 | The pivot. Never translates, and squeezes 6% horizontally at full rotation, because a cylinder turning away gets narrower |
| `TreeFront` | 1.00 | Follows the finger |

Those five numbers are the depth effect. The most-parallaxed layer travels 46
artboard units at full rotation: below about 30 the effect is invisible, above
about 60 the layers visibly come apart. All of it is pure arithmetic in
`parallaxOffsetFor` and `trunkSqueezeFor`, so the relationships are tested
without a device.

**The artboards carry no state machine inputs.** Each has an idle state machine
and nothing driven from Dart. The original plan here specified a `fruit` artboard
taking `ripeness` as a float, plus `seed`, `branch` and `trunk` artboards with
their own inputs. None of that was built, and the `ripeness` input is dead with
the concept. Status is expressed in Flutter, on top of the art.

**Fruit are split across the two techniques, on purpose.** A harvested fruit is
the authored `Fruit` artboard, gold, with the volume and highlight that make a
circle read as a sphere. Everything else is painted by `_PaintedFruit`. The
artboard has one hardcoded gold and colour carries status, so tinting it would
trade meaning for polish. Making the good-looking fruit the harvested one means
the thing the app is pointing at is the thing that looks best.

Two implementation facts that cost real time and are easy to lose:

- **One `FileLoader` per layer.** A single loader shared across five concurrent
  `RiveWidgetBuilder`s fails, with every layer reporting `RiveFailed`. The asset
  is 2.5 KB, so five loads cost nothing worth counting.
- **`rive .` with `--verify` or `inspect` reads the RML source and does not write
  the `.riv` binary.** Only `--screenshot`, or a real build, regenerates it. After
  restructuring RML into new artboards, verifying the source and then copying the
  stale binary shipped the old file and produced "Artboard not found" at runtime.
  Regenerate, then byte-check the artifact for the new artboard names.

**Layout stays data-driven.** An artboard is a fixed composition, so a tree with
a variable branch count needs the geometry in `tree_layout.dart` either way. Rive
replaced the *drawing*, not the *arithmetic*, and the layout tests kept passing
across the swap, which is what made it safe to attempt under time pressure. Hit
testing also stays in Flutter, because the accessible path, the long-press and
the filter all already work against the layout.

## 13. Branches are the user's own, not the platform's

**This supersedes §5.** Platform branches were a fact about the library. Named
branches are a statement about the person, and that is what makes a tree worth
visiting.

A branch is a user-created object with a name, a position on the trunk, and a
set of games. "Comfort games". "Will finish in 2027". "Co-op with Dev". "Bought
in a sale, never opened, no regrets."

### Data model

```
Branch     id, name, sortOrder, createdAt
Placement  igdbId, branchId          (many-to-many: a game may hang on several)
```

### Rules

- **A new user gets branches, not an empty tree.** On first import, Ludeck
  creates branches from the platforms it found, and says so: "I sorted these by
  platform to start you off. Rename anything." Auto-organisation that announces
  itself and is trivially overridable respects agency; a blank canvas is a chore.
- **A game with no branch hangs on the trunk**, not nowhere. There is no orphan
  state.
- **A branch may be empty.** It is a plan, not a failure. It renders as a bare
  limb.
- **Deleting a branch never deletes games.** They fall back to the trunk. The
  confirmation says exactly that, so the action is not frightening, and the
  delete runs in a transaction so a half-finished write cannot lose either the
  branch or the games.
- **Branch order is the user's**, dragged on the trunk. Not alphabetical, not by
  size.
- **Names are validated, not clamped.** Blank, whitespace-only, and names past
  120 characters are refused outright. A clamp writes something the user did not
  choose.

## 14. Gamification that does not become shame

Gamification usually works by manufacturing debt: streaks you can break, bars
you have not filled, badges you have not earned. Every one of those contradicts
§1.

**The rule: the tree may only reward what already happened. It may never mark
what has not.**

What ships:

- **The tree grows with the collection.** The trunk gets taller as games are
  added. Growth is a record of participation, and adding a game you never play
  still grows it, which is honest, and which is what stops the metaphor becoming
  a chore.
- **A pick that states its reason.** This is what replaced ripeness.
  `choosePick` returns one game and the reason it was chosen, and the reason is
  the product: "Already in hand, about 12 hours left." or "Short enough for
  tonight, about 6 hours." A sentence needs no legend, can be argued with, and
  can say something a colour cannot. Continuation beats length, so a short game
  you have not touched never jumps ahead of a shorter one you are already
  mid-way through. An unknown length survives a time filter, because IGDB having
  no length on file is not the same fact as the game being too long.
- **Harvest is the celebration.** Finishing a game is the one moment the app
  spends its delight budget: the fruit detaches, the branch springs, a haptic
  lands on the same frame.
- **Seasons, not streaks.** `Season` counts harvested, pressed, still growing and
  seeds. No rate, no percentage, no comparison to a prior period, each of those
  absences guarded by its own test so adding one has to consciously break a test.
  A count cannot reset to zero and read as failure. A released game sits outside
  every bucket, because ownership and progress are independent precisely so a
  sale never erases a completion record, and a season asks what is on the shelf
  now rather than what was ever finished.

Explicitly rejected: streaks, daily goals, completion percentages, XP, levels,
badges, a withering tree, a tree that shrinks, notifications that count what you
have not played.

**The one negative signal allowed** is set-aside fruit rendered in `danger`, and
only because the user chose it themselves. The app never assigns it.

## 15. Edge cases and dead states

Every state below must render something a person can act on. A blank screen is a
bug.

### Collection size

| State | Behaviour |
|---|---|
| Zero games, first run | A sapling with no fruit, one line: "Nothing planted yet." One action: import or search. Never an empty rectangle |
| Seeds but nothing owned | "Seeds only, for now." Soil full, tree bare. A bare tree is not an error |
| One game | One branch, one fruit. Do not scale the tree down to fill space; a sapling is correct and honest |
| 500+ games | Fruit cluster into a single node per branch past a density threshold, labelled with a count. Zooming in un-clusters. Layout stays O(n) |
| 5000 games | Hard cap on rendered fruit per frame; the list view becomes the default entry point and says why |
| One game on eight platforms | Eight fruit, one per copy. This is the truth, and a test asserts it |

### Data quality

| State | Behaviour |
|---|---|
| No cover art | Fruit renders as solid colour with the title beneath. Never a broken-image glyph |
| No known length | Shown as "length unknown", never guessed. It still survives a time filter and simply loses every length-based tiebreak |
| Title longer than the tile | Two lines then ellipsis. Full title in the sheet |
| Blank title | Refused on write, not stored empty |
| Branch name longer than the trunk | Truncate on the tree, full name in the branch sheet. Reject nothing on display |
| Duplicate branch name | Allowed. Two branches may share a name; the id is identity, not the name |
| Game already on the tree, captured again | Reuse the existing row and flash its fruit. Never create a duplicate, never error, and **never destroy the existing entry**: see below |
| A row that will not parse | Skip it, count it, and say so. One unreadable row out of a thousand must not blank the screen. The count is shown as a line the user can tap for an explanation that states nothing was deleted |
| Rating outside 1 to 5 in the file | Reads as unrated. A nine-star game is a worse outcome than no stars |
| Rating outside 1 to 5 on write | Refused. A clamp writes a number the user never chose |

**The re-import rule, stated as an invariant because breaking it lost user
data.** `entries`, `copies` and `placements` all declare
`REFERENCES games(igdb_id) ON DELETE CASCADE`, with foreign keys on. In SQLite
`INSERT OR REPLACE` deletes the row and inserts a new one, so replacing a `games`
row destroyed the user's status, rating, note, every platform they owned it on,
and every branch it hung from. Upsert with `ON CONFLICT DO UPDATE`, which updates
in place and cascades nothing. `scripts\check.ps1` rule 7 catches the shape, and
nine tests cover the behaviour. A replacing conflict on a leaf table such as
`placements` is safe and often correct.

### Import and network

| State | Behaviour |
|---|---|
| Steam profile private | Name the exact setting to change, in one sentence. Never a blank list |
| Steam returns zero games | "That profile has no games we can see" plus the privacy hint. Distinguish from a failure |
| Import partially fails | Plant what succeeded, say how many did not, offer retry for the remainder. Never all-or-nothing |
| Offline | Full tree from local storage, one quiet line. Capture still works and queues |
| IGDB rate limited | Queue and retry with backoff. Capture returns immediately regardless: the seed is planted, the metadata fills in |
| Capture with low confidence | Plant it anyway, with a quiet "is this right?" affordance. **Never block capture on certainty** |
| Catalogue not connected | Say so in plain words rather than opening a search box that cannot return anything. This is the current real state |

### Social

| State | Behaviour |
|---|---|
| Friend's tree is empty | "Nothing planted yet." Not an error, and not a judgement |
| Friend revoked sharing | "This tree is private now." Keep anything already planted from it |
| Friend's link is dead | A plain 404 page with an app install link. It is a public web page; treat it like one |
| Recommendation to someone with no account | The link works without an app. The seed waits |

### Accessibility and system settings

| Signal | Behaviour |
|---|---|
| Screen reader | The scene is invisible to it. **The list view is the accessible path** and must be complete. Every fruit carries a semantics label regardless |
| Colour vision deficiency | **Harvest status must never be carried by colour alone.** A harvested fruit wears a ring in addition to being gold. Under deuteranopia the gold and the greys sit at similar lightness, so without a second cue the single most important status in the app is unreadable. The ring ships unconditionally, not as a high-contrast variant |
| `disableAnimations` | Growth becomes a cross-fade, harvest a still badge, orbit and parallax off. Zoom stays: it is comprehension, not decoration |
| Large system text | Spacing scales with text. The status line wraps rather than truncating, and any screen with stacked content scrolls rather than overflowing |
| Reduced transparency | Any translucent sheet becomes near-solid |
| High contrast | All fruit gain a defined border |
| Tiny screen | Fewer visible depth planes; list is one tap away |
| Tablet and desktop | Tree and list side by side rather than a stretched phone layout |

### Destructive and reversible

| Action | Behaviour |
|---|---|
| Delete a branch | Games fall to the trunk, in a transaction. Confirmation states that plainly |
| Un-harvest | Ordinary status change. No confirmation; a slip must be cheap |
| Remove a game | Sets `shelved`, never deletes. **`unshelve` must exist**, or "shelved replaces delete" is a delete with a gentler name |
| Sign out | Local tree survives. Never wipe on sign-out |
| Cancel a purchase | Not an error. Say nothing at all. Backing out is the most common outcome of showing a paywall, and commenting on it reads as nagging. A genuine failure is different and leads with "Nothing has been charged" |

## 16. Other UI elements

- **Gold means exactly one thing: harvested.** It is the palette's one loud
  colour and it was briefly doing two jobs, marking a finished game and also the
  primary action, with nothing to tell them apart. The add button uses the
  brightest neutral instead, which measures about 17:1 against the background and
  loses no prominence.
- **The status line is the only chrome at rest.** Two lines, counting what
  exists, never what is outstanding.
- **A bottom sheet, never a screen,** for status, branch assignment and details.
  The tree stays visible behind it, so context is never lost.
- **A translucent toolbar** that content scrolls under, not an opaque strip.
- **Scroll edge fade** where the tree meets the status line, not a 1px divider.
- **No tab bar until there are three destinations.** Tree, list and profile is
  three, so it arrives with the profile, not before.
- **Long-press everywhere is the same gesture:** hold a thing to change what it
  is. Fruit, branch, seed.
- **Empty states are illustrations, not apologies.** A sapling is a picture of a
  beginning.
- **A button that must stay clickable never carries `aria-expanded`**, which is
  a web lesson from the sibling project and applies to any semantics work here:
  it can replace the invoke action with expand-collapse and make the control
  unreachable to a screen reader. State a toggle's state as a pressed state
  instead.
