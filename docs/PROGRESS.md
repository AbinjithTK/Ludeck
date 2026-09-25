# Progress

Append one dated entry per loop cycle, newest at the top. Never delete an
entry. If something you recorded turns out to be wrong, add a new entry that
says so -- do not edit history.

Format per entry: what you did, what critique found (Section 4 of
`GOAL.md`), what's still open, then update the checklist and the Next
section below to match.

---

## BLOCKED

(empty -- nothing blocked as of this seed. A stuck loop writes here.)

## Needs human judgment

(empty as of this seed. Log subjective design calls here rather than
deciding them.)

## Checklist (mirrors GOAL.md Section 2)

- [x] Phase A -- business logic, pure Dart
- [x] Phase B -- repository (createBranch, renameBranch, deleteBranch,
      reorderBranches, place, unplace, unplacedGameIds all exist)
- [ ] Phase C -- state layer. NOT STARTED. `main.dart` still holds `load`,
      `setProgress`, `setOwnership` directly; no `provider` dependency in
      `pubspec.yaml`; no `LudeckStore` class anywhere in `lib/`.
- [x] Phase D -- entitlement (`entitlement_service.dart`, paywall screen,
      both tested)
- [ ] Phase E -- Gaming-criterion screens
  - [ ] E1 rate on harvest -- not started
  - [ ] E2 list view -- not started
  - [ ] E3 branches screen -- not started (repository methods exist per
        Phase B; no screen)
  - [ ] E4 search and add -- not started; `CatalogService` does not exist
        yet (`services/catalog_service.dart` was referenced in an earlier
        plan but is not present in `lib/services/` as of this seed --
        confirm before assuming it exists)
  - [x] E5 superseded by Phase F, per GOAL.md -- do not build separately
- [ ] Phase F -- share anything to the library
  - [x] F1 source storage (commit `c3fb771`)
  - [x] F2 resolver core (commit `3c4509e`)
  - [ ] F3 SSRF-hardened fetcher -- not started
  - [ ] F4 exact and keyed extractors -- not started
  - [ ] F5 oEmbed / Open Graph extractors -- not started
  - [x] F6 confirm sheet -- **DONE, commit `7ef3ec1`.** `share_intake.dart`,
        `ui/intake/confirm_sheet.dart`, `intake_sheet_test.dart` and
        `share_to_library_test.dart` are all committed and green (8/8).
        The tree visualisation was swapped for `ui/collection/collection_view.dart`
        (plain Flutter, no Rive) at the user's request so behaviour is visible
        and testable; `tree_scene.dart` is parked, not deleted.
        The "Rive load race" the seed blamed for the one failing test was
        WRONG. The real cause was a sqflite lock deadlock: `pumpWidget` ran
        outside `tester.runAsync`, so `initState`'s load started real I/O
        under fake time, never completed, and held the database lock. See
        docs/CONSTRAINTS.md "The hanging flutter test". `check.ps1` rule 8
        now guards the shape.
  - [x] F7 Android share target -- **DONE, commit `7ef3ec1`.** Manifest
        `text/plain` intent filter plus `MainActivity.kt` handling both cold
        start and `onNewIntent`. Warm share is covered by the lifecycle-resume
        test, not a widget rebuild.
  - [ ] F8 verification -- not started (depends on F3-F7)
- [ ] Backend polish: transaction/cascade audit -- not started as a
      systematic pass (individual tables have been tested ad hoc, e.g. the
      `sources` table's `ON DELETE CASCADE` from Phase F1, but no full
      audit across every table has been done)

## Next (highest priority first)

1. **Phase F3 (SSRF-hardened fetcher)** -- needed before F4/F5 can call any real
   network endpoint. Can be built and tested entirely offline against fixture
   URLs; no external blocker.
2. Phase C (state layer) -- currently the largest gap between "features
   exist" and "app is coherently structured." Not urgent for demo purposes
   but blocks doing E1-E4 cleanly, since those screens need a mutable store
   to write against rather than reaching into the repository directly the
   way `main.dart` does now.
3. Phase E1 (rate on harvest) -- smallest of the missing E-screens, good
   next screen-building item once Phase C exists to wire it against.
4. Phase F4/F5 (extractors) -- F4's YouTube tier is blocked on a human
   (API key); Twitch and Steam tiers are not blocked and can proceed.
   F5 has no blocker.
5. Phase E2-E4 -- in roughly that order (list view is most self-contained;
   search-and-add uses `services/catalog_service.dart`, which DOES exist:
   `CatalogSource` with `FixtureCatalog`. The seed note below saying it is
   absent was wrong).

## Cycle log

### 2026-09-24 22:44 -- seed (not a loop cycle; written by the setup turn)

Wrote `docs/GOAL.md`, this file, and `docs/LOOP.md` in response to the user
asking how to set up the dashboard goal-loop for full feature + backend +
design completion. Confirmed actual repo state before seeding this
checklist (did not assume TASKS.md's checkbox state matched reality):
read `lib/` file tree directly, ran `git status`, checked `pubspec.yaml`
for the `provider` dependency, grep'd for `LudeckStore` and `Screen` class
definitions. Findings that corrected assumptions:

- No `provider` in `pubspec.yaml`, no `LudeckStore` class anywhere --
  Phase C is genuinely not started, not "probably mostly done."
- `services/catalog_service.dart` does not exist in `lib/services/` --
  only `entitlement_service.dart`, `share_intake.dart`, and
  `share_resolver.dart` are there. An earlier plan referenced building
  `CatalogService`; confirm this before Phase E4 assumes a starting point.
- Git status shows real uncommitted work matching the interrupted
  session's Phase F6/F7 progress -- this is live, not stale, and the loop's
  first cycle should pick it up rather than starting fresh.
- A stray unrelated modification, `.kiro/settings/cli.json`, is also
  showing as modified in git status. Not part of this project's scope --
  leave it alone unless it blocks a commit.

### 2026-09-25 08:55 -- cycle 3

Finished Phase F6/F7 and fixed the fault that had wedged three test runs.

Root cause, and it was NOT what two earlier sessions believed. Rive was
blamed twice; it was innocent. `share_to_library_test.dart` mounted
`TreeScreen` outside `tester.runAsync`, so `initState`'s load began real
sqflite I/O inside the FakeAsync zone. That query can never complete under
fake time and it HELD THE DATABASE LOCK, so every later real-async call
waited on a lock nothing would release. sqflite's ten-second message
("use the transaction object") is its canned text for any long-held lock,
not evidence of transaction misuse -- `repository.dart` never nests a
Database call inside a transaction. And because the wait ran in real time
while the framework timeout runs on the fake clock, the run HUNG instead of
failing. The orphaned `flutter_tester.exe` then kept a handle on
`build\native_assets\windows\sqlite3.dll`, which made the NEXT run die with
an unrelated-looking errno 183.

Fix: wrap `pumpWidget` in `tester.runAsync`. That file went from hanging
indefinitely to 8/8 in 5 seconds.

Also per the user's instruction, the tree visualisation is parked: the home
screen renders `ui/collection/collection_view.dart`, a plain Flutter grouped
list showing title, year, hours, platforms, progress, ownership, seed and
rating, keeping `onSelect`/`onHold` intact. `tree_scene.dart` and its two
arithmetic tests are kept for when the tree returns.

Verified: 213 tests green in 7s (was 163), `flutter analyze` clean,
`check.ps1` 12/12.

New guard: `check.ps1` rule 8 fails any `pumpWidget` not inside `runAsync`
in a test importing `data/repository.dart`. Negative-tested with a probe.

Corrections to this file's own seed: `catalog_service.dart` DOES exist, and
the "Rive load race" diagnosis was wrong. Both fixed above.

No design critique this cycle -- no screenshot was taken, because the
emulator died with the previous session and the work was a test-harness
deadlock rather than a UI change. `CollectionView` has NOT been seen
rendered on a device yet. That is the next cycle's first job.

Still open: F3-F5, Phase C, Phase E1-E4, the systematic cascade audit.
