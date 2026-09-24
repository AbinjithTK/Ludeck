# Features

Derived from the 51 staged screens in `uireferences/` and scoped against the clock in
`docs/PLAN.md`. Every feature here names the reference that specifies it, so nobody has
to re-derive the design. Every feature also says whether it ships now, waits, or is cut.

This document is written from `uireferences/manifest.json`, which records the anatomy
and the intent of each screen. Where a decision needs the pixels rather than the
description, it says so.

## What the two references jointly establish

Hypelist's model is a **list** that contains **items**, with **status sections** inside
the list, and the list is the unit of sharing. Tolan's model is a **world** you place
**objects** into, with a real placement and manipulation kit, and the world doubles as
your avatar.

Ludeck is the intersection, and the mapping is exact:

| Hypelist | Tolan | Ludeck |
|---|---|---|
| A list | The world | Your tree |
| An item | A placed object | A fruit |
| A status section | A region of the world | A branch, named by you |
| Making a list public | The world as your avatar | A shareable tree page |
| Bookmark to save | Inventory tray | Captured but not yet placed |

This is why both references were the right pick. Neither alone gives the product; the
overlap does. It also means the two-axis model from `docs/DECISIONS.md` has a home:
ownership lives on the `Copy`, progress lives on the `Entry`, and a branch is neither,
which is what lets a sold game keep its completion record and still hang on the tree.

## Ships in v1

Ordered by what a published, eligible, coherent app cannot go without.

### 1. Persistence

Nothing below works without it. The tree currently runs on `fixtureTree()` and does not
survive a restart.

Drift or Isar. Schema follows `docs/DECISIONS.md`: `Game`, `Copy` (a set, not a field),
`Entry`, plus `Branch` and `Placement` for user-named branches. Database file
`ludeck.db`.

### 2. Capture

The judged tie-break, and two rivals attack it directly.

Reference: `tolan/home/08-plus-action-menu.png`. A plus button expands into a short
stack of pill buttons and morphs into a close icon. Three entry points, in order of
value:

- **Android share-sheet intent.** Someone shares a store page or a video into Ludeck
  and it resolves to a game. This is the wedge and it is what `docs/DESIGN.md` section
  4 calls the wedge.
- **Search.** Resolves against IGDB through the proxy. Reference:
  `hypelist/discover/04-search-results-tabs.png` for scoping results into games, people
  and trees. In v1 only the games tab exists.
- **Manual add.** Always available, and the only path for PSN, Xbox and Nintendo, which
  have no API at all per `docs/CONSTRAINTS.md`.

A captured game lands **unplaced**. Reference:
`hypelist/list/07-new-badges-uncategorized.png`, which puts a "NEW" ribbon on freshly
added rows and groups them as uncategorised. That state is the bridge to placement.

### 3. The list view

`docs/DESIGN.md` section 3 requires it, and it is the accessible path because a canvas
is invisible to a screen reader. It also proves the data layer with zero canvas risk.

Row anatomy from `hypelist/list/02-first-item-playing-section.png`: cover thumbnail,
title, expand chevron, a platform line, rating, overflow.

Sections from `hypelist/list/03-status-sections-playing-shelved.png`: collapsible and
named by the user. This is the single most important list reference because the sections
are the branches.

Completion from `hypelist/list/05-checked-off-strikethrough.png`: a finished item stays
in place with a struck-through title. It is not removed. That is the same principle as
the two-axis model, expressed in the list.

A sectioned and flat toggle, from `hypelist/list/06-flat-list-completed-marks.png`, if
it is free. Cut it if it is not.

### 4. Status change

Ownership and progress are separate controls, never one chain. The Kotlin app already
has this as a long-press sheet in
`fallback-kotlin/app/src/main/java/com/ludeck/android/ui/shelf/StatusSheet.kt`; the
Flutter app has nothing. Port the behaviour, not the code.

Changing progress to `finished` is a harvest and gets a celebration beat. Reference:
`tolan/home/10-reward-confetti-moment.png`, with the scene dimmed and blurred behind
the moment. Keep it short and make it skippable.

### 5. The tree screen, recomposed

The tree exists and orbits, pans and pinches correctly. What it does not do is read as
a tree, and six structural defects are listed in `docs/PLAN.md`.

The composition fix comes from `tolan/home/01-world-character-collapsed-ui.png`: the
scene owns the middle and every control sits at a screen edge. Ludeck currently reserves
a fixed strip about 130px tall at the top, which is why it reads as a diagram in a box.
Float that strip over the canvas.

`tolan/home/02-world-with-floating-card.png` floats a card with page dots over the
scene, which is how the Tonight pick and the newest capture surface without leaving the
tree. The Kotlin `TonightCard.kt` already has the drag, the momentum projection and the
velocity handoff; port that behaviour.

### 6. Share the tree

The growth loop, the Layers surface, and the thing zero of ten gaming rivals have per
`docs/COMPETITION.md`. Seven references specify it completely.

- Consent first: `hypelist/share/01-make-public-to-share.png`. A Private and Public
  segmented control with the consequence of each written in plain language, then "Save
  and share". Default private.
- The artifact: `hypelist/share/03-share-story-card.png`. A generated card carrying the
  tree, a sample game and light branding, with destinations beneath.
- Copy link, and the confirmation from
  `hypelist/share/05-link-copied-toast.png`, which drops a toast in without dismissing
  the sheet.

**Sharing is never paywalled and collection size is never capped.** Both rules are in
`docs/DECISIONS.md`. Gating either would break the loop that is most likely to win a
category.

### 7. RevenueCat and the paywall

Hard eligibility requirement for all five categories. Entitlement `pro`, products
`pro_annual`, `pro_monthly` and `pro_lifetime`, resolved at a single point so no screen
queries the SDK directly.

What is behind it is the **insight layer only**: total hours to beat across the
collection, what you actually finish against what you abandon, the season summary, the
ripeness breakdown, per-platform splits. Everything that makes the app work is free.

### 8. Rating a harvest

Asked for by name in the Gaming criterion. `Entry.rating` already exists in
`models.dart` as `int?` and is currently unused, so this is UI and a repository method,
not a schema change.

The rule that keeps this from becoming a third axis: **a rating belongs to the harvest,
not to the game.** It is only ever asked for at the moment a game becomes `finished`,
it is never required, and it has no effect on anything else. It does not change
ripeness. It does not change placement. It does not change what the tree looks like.
Nothing in the app is ordered or filtered by it in v1.

The flow is one step. When a game is marked finished, the harvest confirmation offers
a rating inline. Skipping is a normal outcome and is not chased or reminded about.

Stored as a small integer. Read back in the list view and on the share card, where a
harvested game can carry what the player thought of it, which is the part that makes
a shared tree worth looking at.

## v1.1, designed but not built

### Placement on a branch

This is the most ownable interaction in the whole reference set and the hardest to fake.

`tolan/world/01-object-placement-ring.png` is a placement ring projected onto the
ground, a rotate handle on the ring edge, Done at top right, and an inventory tray of
owned items along the bottom with count badges. `tolan/world/02-object-placed-handles.png`
adds the manipulation kit: confirm, delete, rotate and a four-way move puck arranged
around the selected object in world space.

Translated: a captured game sits in a tray at the bottom, you drag it to a branch, and
it takes. It replaces the current interaction, where tapping a branch merely filters.

It is v1.1 only because it needs the pixels to get right and the clock does not allow
that before submission. It is the first thing to build after shipping.

### Whole-tree overview

`tolan/home/06-orbit-planet-navigation.png` zooms all the way out until the world
becomes a small object with orbit rings and an add affordance in orbit. The model for a
whole-tree overview, and later for more than one tree.

### Visiting someone else's tree

`hypelist/list/09-public-list-artwork-cover.png` is the read-only visitor view, where
rows offer save instead of checkboxes and the bottom bar switches to commenting.
`docs/DESIGN.md` section 6 frames this as visiting, not competing.

### Collaborative branches

`hypelist/share/02-invite-collaborator.png`: user search, suggested people with Invite
buttons that flip to an invited state, and a footnote that invitees can add or edit.

### Game detail with community

`hypelist/discover/09-item-community-thoughts.png` has Info and Community tabs, sort and
filter chips, threaded reactions and a floating add action, with a save pill and rating
pinned over the key art.

`hypelist/discover/10-item-also-added-in.png` shows every other list containing this
game, scoped by Everyone, Following and Your Lists. The manifest flags it as a
differentiator worth copying and it is right, but it needs other people's trees to
exist first.

### Profile

`tolan/world/04-profile-planet-progress.png` renders the profile as the world itself.
`hypelist/profile/01-profile-lists-menu.png` gives the shelf and the long-press menu.
For Ludeck the tree goes where the avatar is, which is the same artifact as the share
card.

### Season summary

`docs/DECISIONS.md` allows seasons and forbids streaks. A season ends and a new one
starts; nothing is lost by missing a day. The summary is part of the paid insight layer.

## Cut, with reasons

**Cosmetic customisation.** `tolan/customize/` is four well-made screens for species,
bark, foliage and season. The palette is six colours and `docs/DECISIONS.md` makes
adding a seventh a design decision, not a convenience. Cut for v1 and probably for v1.1.

**Anything 3D.** Every Tolan reference is a real 3D scene. `docs/DESIGN.md` section 3
fixes rendering as `CustomPainter` and `docs/CONSTRAINTS.md` ranks 3D last with the
reasons. Take the composition, leave the rendering.

**AI features.** `hypelist/discover/02-explore-trending-games.png` has an "Ask AI" pill
and Barklog's whole pitch is an AI naming a game from a clip. Not in six days, and not
as a differentiator when a rival already owns that ground.

**Ratings.** Reversed on 2026-09-24. This entry used to say a rating is a third axis
and not what the product is about. The design reasoning was right and the strategic
call was wrong: the Gaming criterion asks, word for word, for players to "save,
organize, complete, rate, and share" their games. Cutting a named judged verb to
protect a two-axis model we can protect another way was a bad trade. See
`BUILD-PLAN.md` and section 8 below.

**Charts and trending.** `hypelist/discover/05` and `06` need a population. Ludeck will
not have one at launch.

## References deliberately rejected

`tolan/home/07-voice-mode-streak-pill.png` shows a streak pill reading "2 days of
friendship" with a flame token. **Rejected.** `docs/DECISIONS.md` forbids streaks
because a streak punishes a missed day, and the metaphor may never nag. Seasons do the
same job without the punishment. This is the clearest case in the set of a good pattern
that is wrong for this product.

`hypelist/list/01-empty-state-game-bucket-list.png` is a best-in-class empty state, but
note that the Hypelist framing is a **bucket list**, which is the backlog framing
Ludeck exists to reject. Take the composition, the drawn arrow pointing at the add
button, and the private chip. Do not take the words.
