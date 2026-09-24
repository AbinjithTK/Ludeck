# Ludeck — Design

> **Correction, 2026-09-24. Ripeness is gone.** This document still refers to ripe
> fruit in thirteen places and every one of them is out of date. Completion is now the
> only status the tree shows: a fruit is harvested or it is not. There is no `isRipe`
> getter, no `ripe` layout field, and no ripeness in the database. Where this document
> and `DECISIONS.md` disagree about status, `DECISIONS.md` wins. The sections on
> composition, motion, palette and typography are unaffected and still binding.

This document is binding. Where it disagrees with a later conversation, this wins.
Where it disagrees with `..\shipaton-gaming\BUILD.md` on the data model, BUILD.md wins:
the enums and the two-axis model are frozen there and are not re-litigated here.

---

## 1. The problem, stated positively

Someone mentions a game. You see a clip on TikTok. A friend says "you'd love this".
Three weeks later you remember none of it.

That is the problem Ludeck solves: **games you genuinely wanted to play, captured the
moment they land on your radar, so they do not slip away.**

It is not a backlog app. A backlog is a debt, and every competitor in this space
frames it that way — one rival ships the statuses "waiting, playing, completed,
abandoned", another calls itself a bucket list. Debt language makes the app a place
you avoid opening, which is exactly wrong for something whose value depends on you
opening it.

**Ludeck is a tree you grow.** Games arrive as fruit. Finishing one is a harvest.
Nothing on the tree is an accusation.

### The emotion we are designing for

Calm pride. Not urgency, not guilt, not completionism. A person opening Ludeck should
feel the way you feel looking at a plant you kept alive.

This single decision governs everything below. Any feature that makes a user feel
behind is wrong here even if it would increase engagement.

---

## 2. The metaphor, and its rules

A metaphor that is not consistent is worse than no metaphor. These rules are not
flavour text; they decide what the UI is allowed to do.

| Metaphor | Means | Rule it imposes |
|---|---|---|
| **Seed** | Someone recommended it. Not owned. | A seed can sit unplanted forever without reproach |
| **Fruit on a branch** | Owned, not yet played | Fruit does not rot. Nothing decays over time |
| **Ripe fruit** | Owned, unplayed, short enough to finish soon | Ripeness is computed, never assigned by the user |
| **Harvested** | Finished | Harvest is the celebration moment. The one place delight is spent |
| **Pressed** | Set aside, stopped playing | Kept, not discarded. A pressed flower, not compost |
| **Branch** | A platform you own games on | Branch thickness follows how many games sit on it |

**What the metaphor must never do:** wither, rot, nag, empty, or shrink. There is no
neglect state. A tree with two hundred unpicked fruit is a healthy tree, not a
failure — that is the entire point.

### Vocabulary is presentation, not persistence

The database keeps the frozen enums from BUILD.md. The tree words are a display
layer on top. This matters because a metaphor is a product decision that may change,
and a schema migration is expensive.

```
Ownership.SPOTTED   -> "Seed"
Ownership.OWNED     -> on the tree
Ownership.RELEASED  -> "Given away"

Progress.UNTOUCHED  -> "Ripe"        (or "Growing" when long)
Progress.INSTALLED  -> "Within reach"
Progress.PLAYING    -> "In hand"
Progress.FINISHED   -> "Harvested"
Progress.ABANDONED  -> "Pressed"
```

The banned words from BUILD.md stay banned in code: `backlog`, `completed`,
`beaten`, `dropped`, `on_hold`, `want_to_play`. `scripts\check.ps1` enforces it.

---

## 3. The main screen is the tree

A glance at the main screen answers one question: **what could I play?**

Layout, bottom to top:

- **Roots** carry the count. "41 games, 9 harvested." Quiet, small, factual.
- **Branches** are platforms. One branch per platform you actually own games on, so
  a PC-only player sees one branch and no empty scaffolding.
- **Fruit** are games, positioned on their platform's branch. Ripe fruit sits toward
  the branch tips where the light is, which is how the eye finds it without a legend.
- **Seeds** rest at the base, in soil. Unplanted recommendations, waiting.

Above it, one line of text and nothing else: **"Three are ripe."**

### Rendering: CustomPainter, not 3D

**Decision: a single `CustomPainter` on a `Canvas`, with 2.5D depth cues. Not
three.js, not `flutter_scene`, not a WebView.**

Reasoning, because this will be questioned later:

- three.js does not exist in Flutter. Reaching it means a `WebView`, which costs a
  platform view, breaks gesture arenas, and adds a visible seam between the web
  surface and the Flutter chrome.
- `flutter_scene` is experimental and Impeller-only, which is a poor bet for a v1.
- A canvas gives full control of hit testing, is one widget to test, and renders a
  few hundred nodes at 60fps without a scene graph.
- Depth is achieved with **scale, blur, shadow and parallax**, which reads as
  deliberate craft. A real 3D scene in a collection app usually reads as a tech demo.

Zoom and rotate are still real, and both are gesture-driven:

- **Pinch to zoom** — 1:1 with the gesture, rubber-banded at both bounds.
- **Horizontal drag to orbit** — rotates the tree around its trunk by shifting
  branch parallax offsets. Not true 3D rotation; the illusion is sufficient and it
  cannot break.
- **Vertical drag to pan** — bounded by the tree's own extent, rubber-banded.

### The list is a first-class equal, not a fallback

Some people want a list, and a list is faster for finding one known thing. One tap
switches. **The list is not a degraded mode:** it carries the same filters, the same
hold-to-change, and the same information.

Accessibility makes this non-negotiable rather than nice: a canvas is invisible to a
screen reader. The list view is the accessible path, so it must be complete, and
every fruit needs a semantics label regardless.

---

## 4. Capture is the wedge

The judged criterion is whether a user can save a game the moment they discover it.
Two rivals now attack this via the share sheet. Ludeck must be at least as fast.

**Path one, the share sheet.** You are in TikTok, Instagram or a browser. Share to
Ludeck. Ludeck reads the text and URL, resolves the game against IGDB, and plants a
**seed** — no screen, no form, one system toast. You never leave what you were
watching.

**Path two, Steam import.** One paste of a vanity URL grows the whole tree at once,
with real playtime and last-played dates already attached. This is the moment that
sells the app: an empty screen becomes a tree in one action.

**Path three, search.** Type, tap, planted.

A seed captured with low confidence is still planted. It sits in soil with a quiet
"is this right?" affordance. **Never block capture on certainty** — the cost of a
wrong seed is one tap to fix, the cost of a refused capture is a lost game.

---

## 5. Devices are branches

Platforms to support by name: **PC, PlayStation 5, Xbox, Nintendo Switch, Android,
iOS, Meta Quest, Steam Deck**.

This is already modelled: `Copy` rows carry `platform`, one row per copy, so owning a
game on two platforms is two copies and selling one does not erase the other. The
tree makes that visible in a way a list cannot — the same game can hang on two
branches, and that reads correctly rather than as a duplicate.

Filtering to a branch is a tap on the branch itself. **No filter menu**: the control
is the thing it affects, which is the strongest form of mapping.

---

## 6. Social: visiting, not competing

Hypelist's lesson, taken with its numbers: 20,000 monthly installs and $0 monthly
revenue. Social curation earns attention, not money. So social here is cheap to build
and is not where monetisation lives.

**Your tree has a public address.** `ludeck.app/@you` renders your tree as a web page,
zoomable, no app install required. This is the shareable artifact, and it is also the
Layers growth-loop surface — one piece of work serving both.

What ships:

- **Visit a friend's tree.** Read-only. See their branches, their harvests.
- **Plant from a friend's tree.** One tap moves a fruit you saw into your soil as a
  seed, crediting them. This is the loop: a visit produces a capture.
- **Recommend directly.** Send a game to someone's soil. It arrives as a seed with
  your name on it, which is exactly the "someone recommended it" case in §1.

What is explicitly **not** built: follower counts, leaderboards, streaks, activity
feeds, comments. Every one of them converts calm pride into competition, and §1 says
no.

---

## 7. Motion

The `animate` gate applied honestly. Two things in the request were rejected.

| Interaction | Frequency tier | Purpose | Decision |
|---|---|---|---|
| Tree at rest on app open | Many times a day | none nameable | **No animation.** The tree is already grown. Renders at final state instantly |
| Fruit appears on capture | Occasional | state indication | Animate. Grows along the branch, 260ms |
| Harvest | Rare | delight | The delight budget. This is the one celebration |
| Pinch / orbit / pan | Continuous | direct manipulation | Gesture-driven, 1:1, no duration at all |
| Press a fruit | Tens a day | feedback | Scale 0.97 on pointer-**down**, 100ms |
| Switch tree/list | Occasional | spatial consistency | Cross-fade plus slight scale, 200ms |

**Rejected from the request:**

- **An idle animation on the tree** — leaves swaying, ambient drift. It fails the
  gate outright: seen every launch, no nameable purpose, and a slow looping
  oscillation near 0.2Hz is specifically listed as a vestibular trigger. A tree that
  moves when you are trying to read it is decoration charged to the user.
- **Growth animation replayed on every open.** Charming once, an obstacle by the
  fourth launch. It plays when something is actually added, and never otherwise.

### Ingredients

- **Springs for everything a finger touches.** Critically damped, `damping 1.0`,
  `response 0.4`. Bounce only after a flick released with momentum, `damping 0.8`.
- **Momentum projection** on a flicked orbit: `current + (v/1000)·d/(1−d)`, `d = 0.998`.
  Land where the gesture was going, not where the finger stopped.
- **Rubber-banding** at zoom and pan bounds: `(over·dim·0.55)/(dim + 0.55·|over|)`.
- **Easing for the non-gesture cases:** `cubic-bezier(0.23, 1, 0.32, 1)`. Never
  `ease-in` on entry.
- **Reduced motion** is a first-class branch, not a stripped one. Growth becomes a
  cross-fade, harvest becomes a still badge, orbit and parallax are disabled, zoom
  stays because it is comprehension rather than decoration.
- **Haptics** on three events only: seed planted, harvest, and a snap at a zoom
  bound. Fired on the same frame as the visual. More than three trains people to
  ignore all of them.

---

## 8. Screens

1. **Tree** — the main screen. Roots, branches, fruit, seeds. One line of status.
2. **List** — the same data, sortable and filterable, fully accessible.
3. **Game** — opens from a fruit. Cover, hours to finish, the platforms you own it
   on, status, your note. Hold a fruit to change status without coming here at all.
4. **Plant** — search and Steam import. The only screen with a text field.
5. **Soil** — seeds awaiting a decision, with who recommended each.
6. **Visit** — a friend's tree, read-only, with plant-from-here.
7. **Paywall** — appears only on reaching for the insight layer. Never gates
   collection size and never gates sharing.

---

## 9. What is paid

Free forever: unlimited games, the tree, Steam import, sharing, visiting.

Paid (`pro`, annual $19.99 with a 30-day trial, monthly $2.99, lifetime $39.99):

- **Harvest history** — what you finished, when, how long it took.
- **Ripeness tuning** — set what "short enough" means for your week.
- **Multiple trees** — separate a shared family tree from your own.
- **The insight layer** — where your money actually went, what you never touched.

Rivals gate at 15 and 10 games. Gating collection size on a collection app punishes
the exact behaviour the product needs. We gate the *reflection*, not the *recording*.

---

## 10. Cut, and why

- **3D engine.** §3. Not shippable at the required quality.
- **PSN / Xbox / Nintendo auto-import.** No public API exists. Manual per-platform
  ownership only, and the branch UI makes that feel intentional rather than missing.
- **AI game identification from video.** A rival does this. It needs a vision model
  on the capture path and would make the wedge slower and less certain.
- **Follower graph, streaks, leaderboards.** §6.
- **Light theme.** Cover art reads better on dark. One well-tuned theme beats two
  half-tuned ones.

---

## 11. Build order

Numbered because time is short and the order is the plan.

1. Tokens and motion layer, ported from the Kotlin app's `Tokens.kt` and `Motion.kt`.
   Same six colours, same Apple spring values.
2. Data layer. The frozen enums, `Game` / `Copy` / `Entry`, Drift or Isar for local
   storage.
3. **List view first.** It is the accessible path and it proves the data layer
   without any canvas risk. If everything else slips, this still ships.
4. Tree canvas, static. No gestures. Just correct layout of branches and fruit.
5. Gestures: pinch, orbit, pan, with rubber-banding and momentum.
6. Hold-to-change status, growth on capture, harvest.
7. Steam import.
8. Paywall, then Layers, then the public web tree.

Step 3 is the checkpoint. **If the canvas is not convincing by the time step 4 ends,
ship the list and call the tree a v1.1 feature.** A polished list beats a janky tree,
and the metaphor survives in the language either way.

---

## 12. Rive — corrected, and the integration plan

An earlier version of this document said a Rive artboard needs a human in the Rive
editor, so an agent could not author one. **That was wrong.** Rive ships an official
CLI that writes **Rive Markup Language**, explicitly built for coding agents, and it
runs on Windows. The Flutter runtime (`rive`, 1,947 likes, 434k downloads) is mature.

So Rive is a real path to the polish the canvas lacks. What it changes and what it
does not:

**What Rive is good at here**
- The *fruit*: a ripening state machine, a harvest animation with real squash and
  settle, a seed sprouting. Authored once, driven by inputs from Dart.
- The *trunk and branch art*: hand-shaped bezier work that a painter cannot match.
- File size and performance: vector, tiny, 60fps, no image assets.

**What Rive does NOT solve**
- **Layout is still data-driven.** An artboard is a fixed composition. A tree with a
  variable branch count needs nested artboards instantiated per branch, positioned by
  Dart. The geometry in `tree_layout.dart` stays either way; Rive replaces the
  *drawing*, not the *arithmetic*.
- **Hit testing stays in Flutter.** Rive can report a hit, but the accessible path,
  the long-press and the filter all already work against the layout, so they should
  keep working against the layout.

**Therefore the integration is a swap, not a rewrite:** keep `TreeLayout` exactly as
it is, keep the gesture layer, and replace `_TreePainter`'s primitives with Rive
artboard instances positioned at the same coordinates. The 20 layout tests keep
passing throughout, which is what makes the swap safe to attempt under time pressure.

**One artboard per concept, with these state machine inputs:**

| Artboard | Inputs from Dart |
|---|---|
| `fruit` | `ripeness` 0–1, `harvested` bool, `pressed` bool, `setAside` bool |
| `seed` | `sprouting` bool |
| `branch` | `load` 0–1 (drives thickness), `dimmed` bool |
| `trunk` | `height` 0–1 (grows as the collection grows) |

`ripeness` as a **float, not a bool**, is the important one: it lets a game visibly
approach ripeness rather than snapping, which is the difference between a status icon
and something that feels alive.

---

## 13. Branches are the user's own, not the platform's

**This supersedes §5.** Platform branches were a fact about the library. Named
branches are a statement about the person, and that is what makes a tree worth
visiting.

A branch is a user-created object with a name, a position on the trunk, and a set of
games. "Comfort games". "Will finish in 2027". "Co-op with Dev". "Bought in a sale,
never opened, no regrets."

### Data model change

```
Branch   id, name, sortOrder, createdAt
Placement  igdbId, branchId          (many-to-many: a game may hang on several)
```

`Copy.platform` does **not** go away — it still records which device a game is on,
because that is the question "can I actually play this tonight" depends on. It stops
being the *organising* axis and becomes a property shown on the fruit and available
as a filter.

### Rules

- **A new user gets branches, not an empty tree.** On first import, Ludeck creates
  branches from the platforms it found, and says so: "I sorted these by platform to
  start you off. Rename anything." Auto-organisation that announces itself and is
  trivially overridable respects agency; a blank canvas is a chore.
- **A game with no branch hangs on the trunk**, not nowhere. There is no orphan state.
- **A branch may be empty.** It is a plan, not a failure. It renders as a bare limb.
- **Deleting a branch never deletes games.** They fall back to the trunk. The
  confirmation says exactly that, so the action is not frightening.
- **Branch order is the user's**, dragged on the trunk. Not alphabetical, not by size.

---

## 14. Gamification that does not become shame

Gamification usually works by manufacturing debt: streaks you can break, bars you
have not filled, badges you have not earned. Every one of those contradicts §1.

**The rule: the tree may only reward what already happened. It may never mark what
has not.**

What ships:

- **The tree grows with the collection.** The trunk gets taller as games are added.
  Growth is a record of participation, and adding a game you never play still grows
  it — which is honest, and which is what stops the metaphor becoming a chore.
- **Ripening is visible and gradual.** A game approaches ripeness as its length, your
  available time and how long you have owned it line up. `ripeness` is a float.
- **Harvest is the celebration.** Finishing a game is the one moment the app spends
  its delight budget: the fruit detaches, the branch springs, a haptic lands on the
  same frame.
- **Seasons, not streaks.** A harvest is stamped with the month. "Four harvested this
  autumn" is a fact about the past. A streak is a threat about the future.

Explicitly rejected: streaks, daily goals, completion percentages, XP, levels,
badges, a withering tree, a tree that shrinks, notifications that count what you have
not played.

**The one negative signal allowed** is set-aside fruit rendered in `danger`, and only
because the user chose it themselves. The app never assigns it.

---

## 15. Edge cases and dead states

Every state below must render something a person can act on. A blank screen is a bug.

### Collection size

| State | Behaviour |
|---|---|
| Zero games, first run | A sapling with no fruit, one line: "Plant your first game." One action: import or search. Never an empty rectangle |
| One game | One branch, one fruit. Do not scale the tree down to fill space; a sapling is correct and honest |
| 500+ games | Fruit cluster into a single node per branch past a density threshold, labelled with a count. Zooming in un-clusters. Layout stays O(n) |
| 5000 games | Hard cap on rendered fruit per frame; the list view becomes the default entry point and says why |
| All games are seeds, none owned | Soil full, tree bare. "Nothing planted yet" — a bare tree is not an error |
| One game on eight platforms | Eight fruit, one per copy. This is the truth, and a test asserts it |

### Data quality

| State | Behaviour |
|---|---|
| No cover art | Fruit renders as solid colour with the title beneath. Never a broken-image glyph |
| No known length | Cannot be ripe. Shown as "length unknown", never guessed, because the reason line is the whole value |
| Title longer than the tile | Two lines then ellipsis. Full title in the sheet |
| Branch name longer than the trunk | Truncate on the tree, full name in the branch sheet. Reject nothing |
| Duplicate branch name | Allowed. Two branches may share a name; the id is identity, not the name |
| Game already on the tree, captured again | Silently reuse the existing entry and flash its fruit. Never create a duplicate, never error |

### Import and network

| State | Behaviour |
|---|---|
| Steam profile private | Name the exact setting to change, in one sentence. Never a blank list |
| Steam returns zero games | "That profile has no games we can see" plus the privacy hint. Distinguish from a failure |
| Import partially fails | Plant what succeeded, say how many did not, offer retry for the remainder. Never all-or-nothing |
| Offline | Full tree from local storage, one quiet line. Capture still works and queues |
| IGDB rate limited | Queue and retry with backoff. Capture returns immediately regardless: the seed is planted, the metadata fills in |
| Capture with low confidence | Plant it anyway, with a quiet "is this right?" affordance. **Never block capture on certainty** |

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
| Screen reader | The canvas is invisible to it. **The list view is the accessible path** and must be complete. Every fruit carries a semantics label regardless |
| `disableAnimations` | Growth becomes a cross-fade, harvest a still badge, orbit and parallax off. Zoom stays: it is comprehension, not decoration |
| Large system text | Spacing scales with text. The status line wraps rather than truncating |
| Reduced transparency | Any translucent sheet becomes near-solid |
| High contrast | Fruit gain a defined border; the ripe halo is replaced by a ring |
| Tiny screen | Tree gets fewer visible depth planes; list is one tap away |
| Tablet / desktop | Tree and list side by side rather than a stretched phone layout |

### Destructive and reversible

| Action | Behaviour |
|---|---|
| Delete a branch | Games fall to the trunk. Confirmation states that plainly |
| Un-harvest | Ordinary status change. No confirmation; a slip must be cheap |
| Remove a game | Sets `shelved`, never deletes. Recoverable |
| Sign out | Local tree survives. Never wipe on sign-out |

---

## 16. Other UI elements

- **The status line is the only chrome at rest.** One sentence, counting what is
  playable, never what is outstanding.
- **A bottom sheet, never a screen,** for status, branch assignment and details. The
  tree stays visible behind it, so context is never lost.
- **A translucent toolbar** that content scrolls under, not an opaque strip.
- **Scroll edge fade** where the tree meets the status line, not a 1px divider.
- **No tab bar until there are three destinations.** Tree, list and profile is three,
  so it arrives with the profile, not before.
- **Long-press everywhere is the same gesture:** hold a thing to change what it is.
  Fruit, branch, seed.
- **Empty states are illustrations, not apologies.** A sapling is a picture of a
  beginning.

