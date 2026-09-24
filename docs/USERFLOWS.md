# User flows

Every flow that ships in v1, specified to the point where it can be built without
guessing. Each one names its reference, its states including the dead ones, and what
already exists in code.

Read `docs/FEATURES.md` first for scope, and `docs/DECISIONS.md` for the rules that
constrain these flows.

## The spine

There is one sentence the whole product has to answer, and every flow either serves it
or gets cut:

**A game arrives, it hangs on your tree, and one of them is the one to play tonight.**

Capture puts it there. The branch says where. Tonight picks one. Harvest closes it.
Sharing shows it to someone. That is the product.

## Flow 0: First run

The one chance to set the framing, and the framing is the product's whole
differentiation: this is not a backlog you owe.

Reference: `tolan/onboarding/01-character-intro-caption.png` for the opener, a bold hero
on a saturated backdrop with one caption line and no other chrome.
`tolan/onboarding/02-meet-your-tolan-traits.png` for the reveal: a serif name, chips, a
descriptive line and a floating call to action.

1. A single screen with a bare sapling and one line of copy. No sign-in, no permissions,
   no carousel.
2. Name the tree. Pre-fill something usable so the field is never a blocker. Hypelist
   pre-fills its name field in `hypelist/share/06-new-list-sharing-settings.png`; do the
   same.
3. Land on the tree with three starter branches already made, named in plain words, and
   say they can be renamed. Do not make branch creation the first task.

States: there is no signed-out state because there is no account in v1. Sharing is what
introduces an account, and it does so at the moment of sharing, not before.

Copy rule: no "bucket list", no "backlog", no "catch up". `docs/DECISIONS.md` has the
banned vocabulary.

## Flow 1: Capture

Reference: `tolan/home/08-plus-action-menu.png`. A plus at a screen edge expands into a
short stack of pills and morphs into a close icon. Three pills, nothing more.

### 1a. Share-sheet intent, the wedge

1. Someone is on a store page, a video, or a review, and shares into Ludeck.
2. Ludeck is invoked without its own UI in front, resolves the text or URL against IGDB
   through the proxy, and shows one confirmation sheet with the match.
3. One tap accepts. The sheet closes and returns the user to where they were.

States, all of which have to be handled because this is the entry point a judge will
try:

- Exactly one confident match. Show it, accept on one tap.
- Several plausible matches. Show up to three and let one be picked.
- No match. Offer the shared text as a manual title, pre-filled, so the capture still
  succeeds. Never dead-end.
- Already in the collection. Say so, name the branch it is on, and offer to jump to it
  rather than duplicating. `igdbId` is the only identity per `docs/DECISIONS.md`.
- Offline. Queue it locally and resolve later. The capture must never be lost because
  the network was down.

### 1b. Search

1. Search field, results scoped to games in v1.
2. A result row uses the compact metadata anatomy from
   `hypelist/discover/11-more-like-this.png`: cover, title, a platform-aware one-line
   description, and a save affordance on the row itself.
3. Saving does not open a detail screen. It captures and stays in the results so several
   games can be added in a row.

Respect the IGDB limits in `docs/CONSTRAINTS.md`: 4 requests a second, 8 concurrent, and
the proxy is mandatory because there is no CORS. Debounce the field.

### 1c. Manual add

Title, platform, form, and how it was acquired. This is the only path for PSN, Xbox and
Nintendo. It must be reachable in two taps from the tree and must not feel like the
punishment option.

### Where a capture lands

Unplaced, and visibly so. Reference:
`hypelist/list/07-new-badges-uncategorized.png`, which uses a "NEW" ribbon and an
uncategorised group.

On the tree this is a small holding area rather than a fruit on a branch. In the list it
is an "Unplaced" section pinned at the top. The count appears on the tree screen as a
badge, using the pattern in `tolan/home/04-daily-card-with-token-badge.png`, which puts
a count bubble on the chevron.

This is the one nag the product is allowed, and it is allowed because it refers to
something the user just did rather than something they failed to do.

## Flow 2: Place it on a branch

**v1 does the cheap version. v1.1 does the good version.** Both are written here so the
cheap one is built as a deliberate stepping stone rather than as a thing to throw away.

### v1: assign

Tap an unplaced game, pick a branch from a list, done. One sheet, no gesture.

### v1.1: place

Reference: `tolan/world/01-object-placement-ring.png` and
`tolan/world/02-object-placed-handles.png`.

1. Unplaced games sit in a tray along the bottom edge with count badges.
2. Drag one toward the tree. Eligible branches highlight as the finger approaches.
3. Release on a branch and the fruit takes, with the spring values from
   `docs/DECISIONS.md` and the velocity handed off from the drag.
4. A placed fruit can be selected and moved, with confirm, delete and move arranged
   around it.

This replaces the current interaction, where tapping a branch filters. Filtering is not
wrong, but it is not ownable, and placement is the thing no rival has.

## Flow 3: What to play tonight

The question the product exists to answer, and the thing Couch Quest also claims. The
difference is that Couch Quest offers three picks by time, energy and mood, and Ludeck
offers one, with a reason.

1. A card floats over the tree, not a separate screen. Reference:
   `tolan/home/02-world-with-floating-card.png`, a card over the live scene with page
   dots.
2. It names one game and why it was picked, in one line. Ripe means owned, untouched, and
   fifteen hours or less to beat, computed and never stored per `docs/DECISIONS.md`.
3. Drag it aside to get another. The drag tracks 1:1, and the commit decision uses the
   momentum projection of where the finger was going, not where it stopped.
4. Accepting sets progress to `playing`.

Already built, in Kotlin: `fallback-kotlin\app\src\main\java\com\ludeck\android\ui\shelf\TonightCard.kt`
has the 1:1 drag, the projection and the velocity handoff. Port the behaviour to Flutter.

Dead states:

- Nothing ripe. Offer the shortest owned game instead and say that is what it is doing.
- Nothing owned. Point at capture. Do not show an empty card.
- One game only. Show it without the drag affordance, because there is nothing to drag
  to.

## Flow 4: Status, and harvest

Two independent controls in one sheet, never a single chain. Long press a fruit or a row.

Already built, in Kotlin: `fallback-kotlin\app\src\main\java\com\ludeck\android\ui\shelf\StatusSheet.kt`.

- Ownership: `spotted`, `owned`, `released`.
- Progress: `untouched`, `installed`, `playing`, `finished`, `abandoned`.

Setting ownership to `released` must not touch progress. That is the invariant the whole
model exists for, and it is the thing to test first.

Setting progress to `finished` is a harvest:

1. A short celebration. Reference: `tolan/home/10-reward-confetti-moment.png`, with the
   scene dimmed and blurred behind the moment.
2. It is skippable on tap and it never blocks.
3. The fruit stays on the tree in a harvested state. It is not removed. In the list the
   row stays in place with a struck-through title, from
   `hypelist/list/05-checked-off-strikethrough.png`.

`abandoned` gets no celebration and no penalty. It is recorded plainly. The metaphor may
never shame per `docs/DECISIONS.md`.

## Flow 5: The list

The accessible path, and the proof that the data layer works.

1. Sections are the branches, collapsible, named by the user. Reference:
   `hypelist/list/03-status-sections-playing-shelved.png`.
2. "Unplaced" is pinned above them.
3. A row is a cover thumbnail, the title, a platform line, and an overflow, from
   `hypelist/list/02-first-item-playing-section.png`. No rating; ratings are cut.
4. Multi-select for moving several games to a branch at once, from
   `hypelist/list/04-selection-checkboxes.png`.

Accessibility is the point of this screen, so it is not optional here: every row has a
label naming the game, its ownership and its progress, in that order. Every control has
a touch target of at least 48 logical pixels. The screen works with the canvas never
rendered.

Dead states:

- Empty collection. Reference `hypelist/list/01-empty-state-game-bucket-list.png` for
  the composition and the drawn arrow pointing at the add button. Take the layout, not
  the words, because "bucket list" is the framing this product rejects.
- A branch with nothing on it. Say it is ready rather than that it is empty.
- Cover art missing. The IGDB proxy is written but not deployed per `docs/PLAN.md`, so
  this is the **current** state, not an edge case. A missing cover must look deliberate:
  the title set in the tile, not a grey box and not a broken image glyph.

## Flow 6: Share the tree

The growth loop. Free, always, for everyone.

1. Share from the tree screen.
2. Consent first. Reference: `hypelist/share/01-make-public-to-share.png`. A Private and
   Public control with the consequence of each in plain language, then "Save and share".
   **Default private.** The user opts in, every time, for each tree.
3. On going public, generate the share card. Reference:
   `hypelist/share/03-share-story-card.png`: the tree, one sample game, light branding.
4. Destinations: copy link first, then the system share sheet. Confirmation without
   dismissing, from `hypelist/share/05-link-copied-toast.png`.
5. A QR code if it is cheap, from `hypelist/share/04-share-qr-code.png`. Good for showing
   someone a tree in person.

The link resolves to a public web page rendering the tree. That page is the Layers
surface and the tracking link target per `docs/SUBMISSION.md`, and it is the artifact no
rival has per `docs/COMPETITION.md`.

An account is created at this moment and not before, because this is the first moment it
buys the user anything.

Dead states:

- A tree with nothing on it. Do not allow sharing. Say what it needs first.
- Going private again. The link stops working and the sheet says so before it happens.
- No network. The card still renders locally so it can be saved, and the link is queued.

## Flow 7: The paywall

Eligibility for every category depends on this existing and being reachable.

1. Reached from the insight screen, never from a wall in front of normal use.
2. Annual with a thirty day trial is the default choice, monthly and lifetime beside it.
   Prices are in `docs/DECISIONS.md`.
3. Restore purchases is always visible.

Behind it: total hours to beat across the collection, finished against abandoned, the
season summary, the ripeness breakdown, per-platform splits.

Not behind it, ever: collection size, branches, capture, the tree, the list, sharing.
Two competitors cap collection size, at fifteen games and at ten. Not capping it is the
position.

## What this leaves to build

This is the **code** order, sequenced by what depends on what. It is not the same as the
list in `docs/PLAN.md`, and the difference is deliberate: that list is sequenced by
external latency, because creating the Play Console record, the three in-app products
and the RevenueCat dashboard entries all involve waiting on somebody else. Start those
first and let them run while the code below is written. Neither list overrides the other;
they run in parallel.

1. Persistence. Everything.
2. Capture, manual and search first, share-sheet intent second. Flow 1.
3. The list with branch sections. Flow 5.
4. The status sheet, ported from Kotlin. Flow 4.
5. RevenueCat, the single resolution point, and the paywall. Flow 7.
6. Share with consent and a card. Flow 6.
7. The Tonight card, ported from Kotlin. Flow 3.
8. Float the header over the canvas and fix the trunk. Flow 2 and the tree screen.

Items 1 through 5 are what makes it a publishable, eligible app. Items 6 through 8 are
what makes it worth judging. `docs/PLAN.md` holds the clock.
