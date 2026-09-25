# Ludeck — handoff

Written 2026-09-25 for a fresh agent with no memory of this project. Read this
file first, then `docs/DECISIONS.md` (the frozen rules) and
`docs/CONSTRAINTS.md` (the traps that have already cost days).

Everything here was verified against the repo on the date above. Where something
is an inference rather than a check, it says so.

---

## 1. What Ludeck is, in one paragraph

A game collection app built on one metaphor: **your games are fruit on a tree
you grow.** You add games (by link, share-sheet, or search), they hang on the
tree, you set how far you got and whether you own them, and finishing a game
("harvesting") is the only thing the app ever celebrates. You group games onto
**branches you name yourself**. You can publish a read-only public page of your
tree and visit someone else's, planting a game you saw there as a seed of your
own.

**Two orthogonal axes, never one chain.** `Progress` (how far you got) and
`Ownership` (whether you have it) are independent — selling a game does not erase
that you finished it. Competitors use a single chain; this is the product's main
structural differentiator. See `docs/COMPETITION.md`.

### The frozen rules — do not renegotiate these without the user

From `docs/DECISIONS.md`, all load-bearing:

- **The metaphor may never wither, rot, nag, empty or shrink.** A full tree is a
  healthy tree. This forbids overdue badges, decay timers, "you haven't played
  this in 90 days", empty-state guilt.
- **Gamification may only reward what already happened, never mark what has
  not.** Seasons, not streaks. No locked or greyed "next" states.
- **No colour literal outside `app/lib/ui/tokens.dart`.** Mechanically enforced
  by `scripts/check.ps1` rule 1. The palette is six content colours; two fenced
  groups (`Tokens.cosmos` for background, `Tokens.canopy` for bark and leaf) are
  documented exceptions that may never colour text, status, controls or counts.
- **`shelved` replaces delete.** Nothing the user recorded is destroyed by a
  normal action.
- **The share payload is title, cover, status, rating — and nothing else.**
  `Entry.recommendedBy` holds a real person's name and must never leave the
  device. `check.ps1` has a rule for this.
- **No follower counts, leaderboards, streaks, activity feeds or comments.**
- **Rendering is `CustomPainter`, not 3D** — `docs/DESIGN.md` §3. **This is the
  decision the user is currently reversing; see §6.**

---

## 2. How to run and verify

```powershell
cd F:\Abin\Ludeck\app
flutter analyze                 # must be clean
flutter test                    # 507 tests, must be green
cd F:\Abin\Ludeck
powershell -File scripts\check.ps1   # 14 rules, must all pass
```

`scripts\check.ps1` is the real gate. It runs 12 project-specific rules plus
analyze and the full test suite. **If you add a guard rule, negative-test it**
by injecting the exact violation and confirming it fails — an inert rule is
worse than none, and placing a rule inside the `try` block that runs
`flutter analyze` silently skips it.

### Seeing the tree without a device (4 seconds)

```powershell
cd F:\Abin\Ludeck\app
$env:LUDECK_CAPTURE = "C:\temp\tree"
flutter test test\procedural_tree_view_test.dart
```

Writes `tree-empty.png`, `tree-no-branches.png`, `tree-loaded.png` rendered
against the app's real night-sky gradient. **Use this before calling any visual
work done.** It caught six defects that 23 green geometry tests did not.

### Device

Android emulator `Pixel_8`, 1080x2400, WHPX accelerator. `adb` is **not on PATH**:
use `$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe`.

```powershell
flutter build apk --debug --target-platform android-x64   # ~90MB; the fat APK won't fit
& $adb uninstall com.ludeck.ludeck                        # /data is 91% full — MUST uninstall first
& $adb install <apk>
& $adb shell monkey -p com.ludeck.ludeck -c android.intent.category.LAUNCHER 1
```

`install -r` fails with `INSUFFICIENT_STORAGE` unless you uninstall first, and
**it fails silently if you pipe its output away** — that cost two wasted capture
rounds. `monkey` brings an already-running app to the front rather than
restarting it, so `am force-stop` first or you will screenshot stale code.

Package id is **`com.ludeck.ludeck`**.

---

## 3. Current state

48 commits. 507 tests green. `check.ps1` 14/14. Analyzer clean. Everything is
committed on `main`; the working tree is clean.

### Built and verified

| Area | State |
|---|---|
| Data layer | sqflite, hand-written SQL, `Repository` + `LudeckStore`. Migrations, integrity audit, conflict rules all tested |
| Add a game | Link paste, share-sheet intake, catalogue search, confirm sheet |
| Status | Progress + Ownership as two independent axes, in a bottom sheet |
| Harvest | Rating sheet on finish, skippable, re-openable |
| Branches | Create, rename, reorder, delete (`branch_screen.dart`) |
| Filing | "Where does it hang" section in the status sheet (accessible, non-drag) |
| The tree | **One** procedural engine + renderer — see §5 |
| Profile | Tree-as-avatar, season summary, level |
| Publish | Consent screen, privacy copy, share card |
| Visiting | Read-only public tree, Plant-from-a-friend, reactions, follows |
| Onboarding | 4 pages, shown once, skippable, re-openable |
| Social backend | `SocialBackend` contract + in-memory fake + Supabase implementation + RLS schema |
| Paywall | Entitlement service, paywall screen |

### Not wired, and the user needs to know

1. **`resolveSocialBackend()` is called with no arguments** in
   `app/lib/main.dart` and nothing reads a `String.fromEnvironment`. So it can
   only ever return `FakeSocialBackend(configured: false)`, and
   `SupabaseSocialBackend` is **unreachable in the shipped app**. Creating the
   Supabase project will not switch it on by itself. The app honestly says
   "Sharing isn't set up yet on this build. Nothing left this device."
2. **No real authentication.** No sign-in, no chosen handle; the handle is
   hardcoded `@you`, which the visitor header renders as "@you's tree".
3. **The Supabase project does not exist.** Migration is at
   `fallback-kotlin/supabase/migrations/0001_community.sql`; commands are in
   `docs/DEPLOY-COMMUNITY.md`. `supabase login` needs the user's own browser —
   an agent cannot do it.
4. **`rive` is a dead dependency.** Nothing in `app/lib` imports it since
   `tree_scene.dart` was deleted. `app/assets/tree.riv` and
   `app/assets/fruit.riv` are dead assets, and `app/rive/` is a dead authoring
   directory. Removing them is free and de-risks the upgrade in §6.

---

## 4. Codebase map

```
app/lib/
  main.dart (36k)          App root, TreeScreen (home), status sheet, filing,
                           _StartupGate (onboarding routing)
  data/
    db/database.dart       Schema + migrations
    models.dart            TreeItem, Game, Entry, Branch (a record type)
    repository.dart (24k)  All SQL. openInMemory() for tests
    enums.dart             Progress, Ownership + their display vocabulary
  domain/                  Pure functions, all tested: level, season, ratings,
                           resolve (link -> game), title_match, video_title, pick
  services/
    catalog_service.dart   FixtureCatalog / layered / http. Resolved via
                           resolveCatalog() — check.ps1 enforces the app uses it
    cover_art*.dart        Cover lookup + a per-session cache
    share_*.dart           Share-sheet intake and resolution
    social/                SocialBackend contract, fake, Supabase impl
  state/ludeck_store.dart  The one ChangeNotifier. items, branches, placements
  ui/
    tokens.dart (15k)      EVERY colour, size, type, spacing, motion value
    tree/
      procedural_tree.dart (32k)      The engine. Pure Dart, no widgets
      tree_painter.dart (14k)         CustomPainter: bark, foliage, ground
      procedural_tree_view.dart (9k)  The widget. Canvas + cover widgets
    map/game_node.dart     One game as a cover card. Shared by tree and list
    collection/collection_view.dart   The list-shaped alternative to the tree
    shell/                 tree_header, add_menu
    gamified/primitives.dart          CosmosBackdrop, SoftCard, etc.
    branches/, publish/, visit/, profile/, onboarding/, paywall/, add/,
    intake/, harvest/                 One screen each
docs/                      16 documents. DECISIONS + CONSTRAINTS are mandatory
scripts/check.ps1          The 14-rule gate
```

---

## 5. The tree, in detail — this is the active work

Two commits: `3986cac` (engine) and `223f713` (renderer). Read both messages;
they record what looked wrong and why.

### The engine — `app/lib/ui/tree/procedural_tree.dart`

Pure Dart plus `Offset`/`Size`. No widgets, so every rule is unit-testable on
the VM with no device and no canvas.

- **Keyed on the user's own `Branch` records**, nothing else. It previously keyed
  on the *platform* a game was owned on, which is why two different trees existed
  in the app at once.
- **Deterministic.** An explicit seeded LCG (`_Lcg`) plus an FNV-1a seed over the
  branch identities and the **sorted** game ids. The same collection always grows
  the same tree. No `Random()`, no clock.
- **`TreeStem` is a polyline**, not a start/tip pair — a list of spine samples
  each with its own half-width. A straight segment cannot bend, and a tree whose
  limbs do not bend reads as a diagram of a tree.
- **Growth is coupled to structure:** `structure = min(1, branches / 6)`. Trunk
  apex moves `0.30 → 0.10` of canvas height; the crown recedes upward and
  shortens. An unorganised collection is a short bushy sapling; organising grows
  it taller. **This caps at 6 branches — see §7 Stage 3.**
- **Thickness follows load** (da Vinci's rule): a parent's cross-section equals
  the sum of its children's, derived from `sqrt(share)`.
  `trunkStructuralHalfWidth` is the width limbs derive from — *not*
  `trunk.baseHalfWidth`, which includes the root flare (a buttress carries no
  branches).
- **The crown always exists.** Short twigs at the top, present regardless of how
  anything is organised, with a near-vertical **leader** so the canopy closes over
  the trunk. Without it the commonest state — games owned, no branch made yet —
  was a bare pole with fruit threaded up it like a kebab.
- **Games on no branch hang in the crown**, matching what publishing does ("On
  the trunk").
- **`_separateFruit` resolves crowding.** Deterministic, leashed pairwise
  relaxation in y-compressed space, because a cover is a portrait card and a
  circular measure would leave vertical stacks. Fruit may touch; they may not
  hide each other.
- **No rotation parameter exists in the file.** The user judged the rotating tree
  worse than a still one, and a rotated limb puts every title at an angle.

### The painter — `app/lib/ui/tree/tree_painter.dart`

- A stem is **filled as a tapered outline**, never stroked. A stroked line is one
  colour across its width, so it can only ever be a flat ribbon.
- Each stem is painted **three times** — body, lit ribbon, shade ribbon — offset
  along the stem's own normals and **blurred**. The blur is the whole difference
  between a cylinder and a folded plank.
- `stemPath` closes through `right.first` explicitly. Without that line,
  `close()` draws a chord across the base and the trunk appears to *narrow* where
  it meets the ground.
- Foliage is a cloud of blurred circles (`foliageFor`, deterministic from
  `tree.seed`), blurred by **0.09** of each radius. At 0.22 it rendered as green
  smoke: a circle blurred by a fifth of itself has no edge, and a mass with no
  edge has no silhouette.
- `kLightDirection` is fixed (up and left). A consistent light direction is most
  of what makes separately painted objects look like one scene.

### The view — `app/lib/ui/tree/procedural_tree_view.dart`

**The one structural decision: wood is painted, games are widgets.** Each fruit
is a real `GameNode` — the same widget the list rows use — so cover art, the
initials placeholder, the harvest glow, the arrival animation and the spoken
label are shared, not reimplemented. A painted circle cannot show a cover, be
focused by a screen reader, or host a network image.

Used by **both** home (`main.dart`, interactive) and the profile portrait
(`profile_screen.dart`, handlers null so it cannot be half-interactive).

### Deleted, deliberately — do not resurrect

`tree_layout.dart`, `tree_scene.dart` (Rive, 5 parallax artboards, platform
limbs), `tree_anchors.dart`, `branching_tree_view.dart`, and their three test
files. They were three competing renderers of the same data.

### Known open defects

1. **A loaded tree of 12+ covers is visually dense** — the canopy disappears
   behind the art. Composition, not collision.
2. **On home the lower third of the trunk is bare** while covers crowd the top.
3. Unfixed critique items: the publish screen's primary button **jumps ~100px**
   when you switch Private→Public (the explanation grows from one line to three);
   the selected segment fills a **muddy brown** that reads as disabled; a
   **measured hard seam** on home (bottom 4%) and the share card (bottom 17%)
   where the backdrop stops — brightness drops 34.6→14.9 of 255 in one 10px step.
4. `--` used where an em dash belongs, onboarding pages 1 and 4.

---

## 6. The 3D decision: flutter_scene + Impeller

The user has decided to move the tree to `flutter_scene`. This **reverses**
`docs/DESIGN.md` §3 ("rendering is CustomPainter") and `docs/FEATURES.md`
("Anything 3D — cut"). That reversal is the user's call and is recorded here;
update both documents when the spike passes.

### Verified requirements

Checked against pub.dev on 2026-09-25:

- `flutter_scene` **0.23.0** requires **Flutter 3.47 stable or newer**.
- **This project is on Flutter 3.38.9 / Dart 3.10.8** (Jan 2026). That is a
  **nine-minor-version jump** and the single biggest risk in this plan.
- Flutter GPU is **off by default** and must be enabled per platform. Android:
  add to `android/app/src/main/AndroidManifest.xml` inside `<application>`:
  `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />`
  While developing: `flutter run --enable-flutter-gpu`.
- Impeller is the default renderer on every native platform as of 3.47, so
  nothing to do for Impeller itself.
- **Windows/Linux need 3.47.1** to ship a release build (3.47.0 compiles the
  environment switches out). Relevant because the test suite runs on Windows.
- The package is **pre-1.0 and "minor releases can carry breaking changes."**
- It **ships agent skills**: `dart run flutter_scene:skills` installs guidance on
  idiomatic usage, traps, a run-settle-capture verification loop, look presets
  and procedural content. **Install these before writing any Scene code** — they
  exist precisely so an agent does not guess.

### Why it genuinely fits, beyond "3D looks nicer"

Four features map directly onto problems this project already has:

1. **`TubeGeometry` sweeps a profile along a path.** That *is* a branch. The
   engine already produces exactly the input it wants: a spine polyline plus a
   per-sample radius. The port is mostly adding a z axis.
2. **"Interactive Flutter widgets embedded on 3D surfaces, with pointer
   raycasting into the scene."** This is the critical one. Covers stay real
   `GameNode` widgets, so cover art, tap, and the harvest glow all survive. The
   naive fear — that going 3D means giving up cover art and tappability — is
   unfounded.
3. **"Screen-reader accessibility, exposing scene content through Flutter
   semantics."** The a11y work and `accessibility_semantics_test.dart` survive in
   principle. **Verify this in the spike**; it is the thing most likely to be
   thinner than the README implies.
4. **"Synchronous frame capture as `ui.Image`."** The 4-second capture loop in
   §2 keeps working, which is how visual work gets judged here.

Also: skeletal/blended animation and a declarative node API make **branch growth
animation** a first-class thing rather than a hand-rolled tween.

### Design for the 3D tree

**Keep `procedural_tree.dart` as the source of truth.** It is pure, deterministic
and data-derived — exactly what should feed a mesh builder. Do not start over.

```
LudeckStore (branches, placements, items)
        |
        v
procedural_tree.dart          <- keep. Change Offset -> Vector3, add depth
  TreeStem { spine: List<Vector3>, halfWidth: List<double> }
        |
        +--> tree_mesh.dart    <- NEW. TubeGeometry per stem, radius per sample
        |                          Leaf clusters as BillboardGeometry or
        |                          instanced quads
        |
        +--> tree_scene_view.dart  <- NEW. SceneView + PerspectiveCamera.
                                      Covers as embedded Flutter widgets,
                                      positioned by projecting each fruit's
                                      anchor into screen space
```

**Branch growth animation.** Do not animate the mesh vertices. Give each stem a
`growth` scalar in 0..1 and rebuild its `TubeGeometry` from a truncated path
(`path.take(growth * length)`). A tree has well under 100 stems and normally only
*one* is animating — the branch that was just created — so rebuilding that single
tube per frame is cheap. If profiling disagrees, move to a custom `.fmat`
material that clips by an arc-length vertex attribute; that is the efficient form
but needs a shader, so do not start there.

**Camera.** `PerspectiveCamera`, pulling back as the tree grows so a big
collection still fits the frame. **Keep the no-rotation rule** until the user
explicitly revisits it — they have rejected a rotating tree twice. A constrained
look-around is a separate proposal, not an assumption.

**Determinism must survive.** The seeded LCG stays. A 3D tree that reshuffles per
launch is a screensaver, not the user's tree.

### The gate — do this before committing the plan to 3D

Do it on a **branch**, not on `main`. Each step is a stop-or-go:

1. **Remove `rive` first.** It is already unused (§3.4). Drop the dependency, the
   two `.riv` assets and `app/rive/`. Confirm 507 tests still green. This deletes
   a native plugin from the upgrade surface for free.
2. `flutter upgrade` to 3.47.1. Then **`flutter analyze` + all 507 tests**.
   Expect breakage; fix it before going further.
3. **Rebuild the APK, install, launch.** Confirm the app still works end to end
   on the emulator.
4. Re-check the two known host traps: the JDK pin
   (`flutter config --jdk-dir=<Temurin 17>`) and the sqflite Windows native
   asset used by the test suite.
5. `flutter pub add flutter_scene`, `dart run flutter_scene:init`,
   `dart run flutter_scene:skills`. Render the **README cube** on the emulator
   with Flutter GPU enabled.
6. Render **one `TubeGeometry` branch** from a real `TreeStem`.
7. Embed **one `GameNode`** on a 3D surface and confirm it is tappable **and
   announced by a screen reader**.

Only after step 7 should the tree be ported. If step 2 or 3 fails badly, the
honest fallback is: stay on `CustomPainter`, and spend the same effort on
recursive branch forking (§7 Stage 3), which delivers most of the visual gain
with none of the upgrade risk.

### A possible bonus, worth checking

Flutter 3.38.9 pins `meta 1.17.0`, which caps `analyzer`, which caps
`build_runner`, which is why **code generation is currently impossible** in this
project (no Drift, freezed, json_serializable or riverpod_generator — see
`docs/CONSTRAINTS.md`). Upgrading to 3.47 may lift that cap. Check it while you
are there; it would be a significant quality-of-life win.

---

## 7. Stages yet to build

Stages 1 and 2 of the approved plan are **done and committed**. What follows is
stages 3–8 as approved, with Stage 3 revised for the decisions above. Each stage
must end green: `flutter analyze` clean, full suite passing, `check.ps1` 14/14.

### Stage 3 — Growth, forking, and a way for the user to tune it

Revised. The user cannot currently change how the tree looks without an agent,
and that is the real bottleneck.

- **Recursive forking.** Limbs are single sticks; real branches fork, then fork
  again. This is the highest-impact visual change available and is pure maths.
  Depth should follow the collection's size, and thickness must keep obeying da
  Vinci's rule at every fork.
- **Uncap growth.** `structure = min(1, branches / 6)` stops responding past six
  branches. Decide what a 20-branch, 200-game tree looks like — a bigger tree, a
  zoomed-out camera, or (worth proposing) a **forest of several trees**, which is
  how Forest solves the same problem.
- **A Tree Lab.** A hidden dev screen with a live slider for every shape
  parameter and a "copy these values" action, so the user tunes the tree with
  their thumb and hands back numbers to bake in. Roughly 15 parameters; they are
  tabulated in the chat history and each is commented in the source.
- Acceptance: forking is visible in all three captures; a 20-branch tree looks
  different from a 6-branch one; the user can change the look without editing
  Dart.

### Stage 4 — The home screen as a place

- Tolan's layout: chrome to the edges so the tree owns the middle, a collapsible
  card stack, a "new games to place" count.
  (`uireferences/tolan/world/01-object-placement-ring` is flagged in the
  project's own manifest as the most important reference in the set.)
- **Fix the two open composition defects**: density at 12+ covers, and the bare
  lower trunk.
- All six states designed, including empty and first-run — a judge opens the app
  with no data.
- Move progress off the flat bar into the tree itself and a level chip.

### Stage 5 — Placement and organising

- Tolan world-edit mode: a placement ring on the chosen limb, Done, and a bottom
  inventory tray of unplaced games.
- Create, rename, reorder and delete branches **from the tree**; drag a game
  between limbs. The status-sheet filing path stays as the accessible route — add
  direct manipulation **on top of it, not instead of it**.
- Hypelist's collapsible status sections as the list-shaped counterpart
  (`hypelist/list/03-status-sections` maps 1:1 onto named branches).

### Stage 6 — Micro-interactions and the celebration beat

- Arrival (grow along the branch from `TreeFruit.anchor`, which exists for
  exactly this), press-and-hold lift, tap-for-status, level-up growth, and a
  harvest moment modelled on Tolan's reward screen.
- **Branch growth animation** — the thing the 3D move is for.
- Honour reduced-motion. **No idle animation at rest**: `docs/DESIGN.md` §7
  rejects ambient leaf sway outright (seen every launch, no nameable purpose,
  and slow oscillation near 0.2 Hz is a listed vestibular trigger).
- Capture as video; a still frame proves neither duration nor easing.

### Stage 7 — Tree customisation

- Tolan's customise layout: live preview above, tab strip and swatch grid below.
- Species, bark, foliage, season — persisted and fed back into the generator.
- **Never paywalled.** Sharing and identity are not paid features here.
- Note `docs/FEATURES.md` lists cosmetic customisation as cut for v1; the user
  reinstated it in the approved plan.

### Stage 8 — Real authentication and a live backend

- Wire the Supabase URL and anon key through so `SupabaseSocialBackend` is
  reachable at all (§3.1). This is a real bug, not a config step.
- Real sign-in, profile sync, and a **handle the user chooses** instead of `@you`.
- Hand the user the exact `supabase` CLI commands; `supabase login` needs their
  browser.

### Stage 9 — Verification and outstanding fixes

- Full suite, `check.ps1`, six states captured, video of each animation, and a
  design critique run against **real pixels** (the `design-critique` skill).
- Clear the open critique items in §5: the button jump, the muddy selected
  segment, the measured background seam, the `--` em dashes.

### Explicitly out of scope unless the user asks

- **Hypelist's discovery surface** (search tabs, "also added in", recommendation
  rows, social feed) — a large independent body of work.
- **Deploying Supabase** — needs the user's own browser.
- **AI features** — `docs/FEATURES.md` cuts them, and a rival already owns that
  ground.

---

## 8. Traps that will bite you

The full list is `docs/CONSTRAINTS.md`. These are the ones that have cost the
most time, and they are all still live.

### Testing

- **A widget test that mounts a screen doing real sqflite I/O outside
  `tester.runAsync` HANGS, it does not fail.** `testWidgets` runs in a FakeAsync
  zone; the query cannot complete under the fake clock *and* it holds the
  database lock, so every later real-async call waits forever. `check.ps1` rule 8
  fails any `pumpWidget` in a test file importing `data/repository.dart` that is
  not wrapped — **including ones that never touch the DB.** Wrap them; do not
  weaken the rule.
- **Always run `flutter test` through `Start-Process -PassThru` +
  `WaitForExit(ms)`.** A wedged run and a slow run look identical from outside —
  the shell call just blocks, streaming nothing. Diagnose wedged-vs-busy by
  reading process CPU twice a minute apart: identical = wedged, climbing = busy.
- **An orphaned `flutter_tester.exe` holds a handle on
  `build/native_assets/windows/sqlite3.dll`**, so the next run dies with errno
  183 and `Remove-Item` silently fails. Kill the orphan, delete
  `build/native_assets`, re-run.
- **`toImage()` is real async** and hangs under the fake clock. Wrap in
  `tester.runAsync`.
- **`flutter_test` pumps a ~800x600 surface by default, wider than a phone.** A
  phone-only layout bug passes green there. Set
  `tester.view.physicalSize = Size(412, 760)`.
- **The default test font renders every glyph as a full em square**, so text is
  much wider than on a device and wraps where the app does not. Treat a
  test-only overflow as a free large-text case, not a reason to loosen the test.
- **`check.ps1` runs `analyze` immediately before `test`**, which shifts timing
  enough to expose flaky tests that pass standalone. A fixed-ms wait for a real
  DB write is the usual culprit — replace it with a bounded poll for the widget
  or data to exist.

### Host / PowerShell

- **`$KIROCREW_SCRATCH` for all scratch work**, not `/tmp`.
- **PowerShell 5 has no here-doc and no ternary.** `git commit -F <file>` instead.
- **`Set-Content -Encoding UTF8` and `>` both write a BOM**, which kiro-cli's
  Rust JSON parser and Dart reject. `>` also corrupts binary output. Check the
  first three bytes after any scripted rewrite.
- **`sc` is an alias for `Set-Content`**, not the service tool. Use `sc.exe`.
- **`Set-Location` does not change .NET's working directory** — always pass
  absolute paths to `[System.IO.File]` APIs.
- **`**` is not recursive in PowerShell globs.** Use `Get-ChildItem -Recurse`.

### Android / emulator

- **Flutter must use Temurin 17**, not Android Studio's bundled JDK 25 (Gradle
  does not support it): `flutter config --jdk-dir=<Temurin 17 path>`.
- Emulator `/data` is **91% full**. Uninstall before installing, and build
  `--target-platform android-x64` (~90MB) rather than the fat APK (~167MB).
- **An `adb uiautomator dump` is NOT a valid Flutter accessibility audit.**
  Attaching the dump is what makes Flutter build its semantics tree, so a freshly
  pushed route reads back nearly empty. This produced a completely wrong
  "catastrophic a11y gap" finding. The authoritative check is a **widget test
  reading the semantics tree** (`find.bySemanticsLabel`). Separately, an
  `IconButton`'s `tooltip` does **not** reach the semantics tree — use
  `Icon(semanticLabel:)`.

### Working method

- **Green invariant tests can still describe an ugly result.** Render or plot the
  actual thing and look at it — especially the empty/first-run case. On this
  project 23 green tests passed while an ASCII plot caught two real defects, and
  a PNG capture later caught six more.
- **After a mechanical rename, read the touched blocks.** A scripted replace once
  produced valid code with two identical `if` conditions, the second unreachable,
  silently rendering fruit the wrong colour. Prefer the file-editing tool over
  scripted string replace for multi-line edits.
- **A factory the app bypasses is dead code with a test attached.** Verify the
  app's own wiring calls it (`check.ps1` has a rule for `resolveCatalog()`; the
  bug in §3.1 is the same class of error, uncaught).
- **When a build/test approach fails twice on the same mechanism, stop varying it
  and diagnose the root cause with a real probe.** Three pump-timing variations
  cost an hour once; reading the actual exception solved it in one step.
- **Stash before a big visual experiment** (`git stash push -u`) rather than
  deleting the working version, so a "this is worse" verdict costs nothing.
- The user's visual judgement has been right every time it disagreed with the
  tests. Treat "it looks weird" as a real bug report and go render it.

### Reference images

`uireferences/tolan/` and `uireferences/hypelist/` are named `*.png` but are
**WebP-encoded**, and the image-read tool rejects them. Do not keep retrying —
work from `uireferences/manifest.json`, whose `why` field describes each screen's
anatomy in enough detail to design from.

---

## 9. Where to start

1. Run the three commands in §2 and confirm 507 / 14 / clean. Never trust a
   status board over `git log` and a real run.
2. Read `docs/DECISIONS.md` and `docs/CONSTRAINTS.md` in full.
3. Run the capture loop in §2 and look at the three PNGs, so you know what the
   tree currently looks like rather than what this document says.
4. If continuing the 3D move: start at §6's gate, step 1, on a branch.
5. If not: Stage 3's recursive forking is the highest-value work available.
