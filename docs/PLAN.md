# Plan and status

Last updated Thursday 24 September 2026, 14:37 IST (09:07 UTC).

## The clock, stated accurately

| Date | What it is |
|---|---|
| Wednesday 30 September 2026, 23:45 PDT | **Hard deadline.** The app must be fully published, not merely uploaded. |
| 1 October 2026, 06:45 UTC | The same instant in UTC |
| Now | About **6 days and 22 hours** remain |
| Today, 24 September | **Working ship date.** Self-imposed, not the deadline. |

The working date sits six days early on purpose. "Fully published" means Google Play
review has to finish, and the first review on a new developer account is the slowest
one that account will ever get. Submitting on the 30th is the same as not submitting.

An earlier note in this project said "about 10 hours remaining". That was hours left in
the working day, not hours left before the deadline. If today slips to tomorrow, the
submission is not lost. If it slips to the 29th, it is.

## Status, honestly

### Flutter app, `app/`

Analyzer clean. **42 of 42 tests pass.** Android debug APK builds at 139.8 MB. The
Windows target builds and the app runs.

Built and working:

- **Persistence.** `lib/data/db/database.dart` and `lib/data/repository.dart`.
  Hand-written SQL on `sqflite`, because code generation does not work on this
  toolchain; see `docs/CONSTRAINTS.md` for the chain that causes it. Five tables:
  `games`, `entries`, `copies`, `branches`, `placements`. Foreign keys are enabled per
  connection. Runs on Android and on Windows. 22 tests cover the invariants, including
  the one the whole model exists for: selling a game does not erase that you finished
  it.
- `lib/ui/tokens.dart` : six colours, four type sizes with per-size tracking and
  leading, Apple spring values converted to Flutter stiffness.
- `lib/data/enums.dart` : the frozen vocabulary with two labels each.
- `lib/data/models.dart` : Game, Copy, Entry, TreeItem, plus `fixtureTree()` with 10
  real IGDB ids.
- `lib/ui/tree/tree_layout.dart` : pure geometry with no Flutter widget imports, which
  is what makes it unit-testable. Includes `projectMomentum` and `rubberBand`.
- `lib/ui/tree/tree_view.dart` : one finger orbits and pans, two fingers pinch about
  the focal point, release projects momentum and hands velocity to a
  `SpringSimulation`, bounds rubber-band, press fires on pointer-down, tapping a
  branch filters.
- `test/tree_layout_test.dart` : 20 tests that assert design rules rather than pixels.
- The Rive pipeline works end to end. `rive/fruit/scene.rml` verifies with 0 errors,
  builds a 401-byte `.riv`, and `rive . --screenshot --advance=1` renders a PNG that
  can actually be looked at. That was the first real visual verification loop in the
  project.

### The tree does not read as a tree

This is the honest verdict and it has not changed. The Rive fruit genuinely look good:
they have volume, a highlight and a halo. Six structural defects remain:

1. The trunk renders as a hairline sliver. Its path is near-degenerate, about 3px wide
   at the top against 11px at the base.
2. Branches read as scratches. They are drawn in `surface`, which is nearly the
   background colour.
3. The fruit are oversized relative to the branches.
4. Fruit on the low branches collide.
5. Only the middle third of the canvas is used.
6. The soil reads as a UI panel rather than as ground.

`docs/DESIGN.md` section 11 sets the rule for this situation: if the canvas is not
convincing when step 4 ends, ship the list and make the tree v1.1. **That checkpoint
has fired.**

### Kotlin fallback, `fallback-kotlin/`

BUILD SUCCESSFUL, 10,336 KB APK. `check.ps1` passes all six rules. The Gradle wrapper
is generated so the project is self-contained. Renamed from Hoard to Ludeck with zero
remaining references, verified by search rather than assumed.

It has the motion layer, the decision-first shelf with all six states, the Tonight
card with 1:1 drag and momentum commit, and a long-press status sheet. It has no tree.

`git init` was run in the original location but **no commit was ever made**. In this
consolidated tree there is no repository yet at all.

### What does not exist in either codebase

- **RevenueCat.** Hard eligibility requirement for all five categories.
- The list view, which `docs/DESIGN.md` section 3 requires and which is the accessible
  path, because a canvas is invisible to a screen reader.
- Capture by share-sheet intent, which is the judged tie-break and which two rivals
  now attack directly.
- Steam import.
- OneSignal.
- The Layers SDK.
- Store assets: icon, screenshots, video.
- The Devpost writeup.
- The Supabase IGDB proxy is written but not deployed, so cover art renders as empty
  surfaces.

## What to do, in order

The order is by what protects the submission, not by what is interesting. Items 1, 2 and
3 involve waiting on Google and on the RevenueCat dashboard, so they are first because
of external latency, not because of code dependency. Start them, then write code while
they sit. `docs/USERFLOWS.md` holds the code order, which is sequenced by what depends on
what; the two lists run in parallel and neither overrides the other.

The design for items 6, 8 and 11 is already settled by the 51 staged reference screens.
Read `docs/UI-REFERENCES.md` for the index, `docs/FEATURES.md` for what is in scope and
what is cut, and `docs/USERFLOWS.md` for the flows specified screen by screen. There is
no design work left blocking the list view or the share flow, only build work.

1. **RevenueCat integration.** Nothing else counts if this is absent. Entitlement
   `pro`, three products, a single resolution point so no screen queries the SDK
   directly. The Kotlin app's intended point was
   `data/billing/Entitlements.kt`; the Flutter equivalent needs the same shape.
2. **Create the three Play IAP products.** They are reviewed with the first
   submission, so they must exist hours before it, not during it.
3. **Create the Play Console app record** with `com.ludeck.android`. The package id
   becomes permanent at this moment, so read `docs/DECISIONS.md` once more first.
4. **Commit everything.** There is no repository in this tree yet. One command.
5. **Persistence** in Flutter, Drift or Isar.
6. **The list view.** Before any more canvas work. It is the accessible path and it
   proves the data layer with zero canvas risk. Take the Hypelist patterns in
   `docs/COMPETITION.md`.
7. **`layers setup`.** `npm install -g @layers/cli` then `layers setup`; the browser
   sign-in is the user's step. Free, progresses the best-odds category, and an
   `install_growth_measurement` call with `action: spec` settles the Flutter support
   question definitively.
8. **Capture by share-sheet intent.** The judged tie-break.
9. **Store assets and submission.** Icon at 1024x1024, screenshots with the 2:1 cap
   verified first, a 90-second video from a real phone, a Devpost writeup targeting
   about 6,000 characters. Update `intel/me.json` and re-run `intel/benchmark_me.py`.
10. **Extend `check.ps1` to cover `.dart`.** The colour-literal rule and the enum rule
    are currently unenforced in the Flutter code, which is the code that ships.
11. **Tree structure fixes, if time allows.** A solid tapering trunk, branches in a
    lighter colour with real thickness, smaller fruit, better vertical distribution,
    fixed low-branch collisions, soil that does not read as a panel. Also float the
    header over the canvas instead of reserving a strip for it, per the Tolan reference.

Deferred, deliberately: the Supabase IGDB proxy deploy, running `fetch-fixture.mjs`,
RML keying for `ripeness` as a float, the Branch and Placement data model for
user-named branches, the public web tree, OneSignal.

## The decision still outstanding

Whether Ludeck ships as Kotlin or as Flutter.

- Kotlin builds now, has a designed shelf, and has no tree.
- Flutter has the better fruit, a tree that needs rework, and nothing else built.

Both have zero RevenueCat, so item 1 above has to be done either way and does not
break the tie. `docs/DECISIONS.md` records Flutter as the chosen stack and that
decision is not reopened; this line exists only because the fallback is real and the
clock is short.
