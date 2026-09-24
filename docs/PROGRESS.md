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
  - [ ] F6 confirm sheet -- **IN PROGRESS, UNCOMMITTED.** As of this seed
        the following are untracked working files from an interrupted
        turn, not yet committed and not yet fully passing:
        `app/lib/services/share_intake.dart`, `app/lib/ui/intake/`,
        `app/test/intake_sheet_test.dart`,
        `app/test/share_to_library_test.dart`. The interrupted session's
        last state: 7 of 8 end-to-end tests passing, one remaining failure
        was a Rive-native-library load race in the Windows test
        environment (not present on real devices) -- the fix attempted was
        pumping outside `tester.runAsync` so `FlutterError.onError` could
        catch the async throw. **Read these files and re-run
        `flutter test` before writing anything new** -- do not assume this
        is unstarted.
  - [ ] F7 Android share target -- **IN PROGRESS, UNCOMMITTED.**
        `app/android/app/src/main/AndroidManifest.xml` and
        `app/android/app/src/main/kotlin/com/ludeck/ludeck/MainActivity.kt`
        are modified but uncommitted as of this seed. Diff against git HEAD
        to see exactly what changed before continuing.
  - [ ] F8 verification -- not started (depends on F3-F7)
- [ ] Backend polish: transaction/cascade audit -- not started as a
      systematic pass (individual tables have been tested ad hoc, e.g. the
      `sources` table's `ON DELETE CASCADE` from Phase F1, but no full
      audit across every table has been done)

## Next (highest priority first)

1. **Finish Phase F6/F7 before starting anything else.** There is real
   uncommitted work in flight (see checklist above). Read the files, re-run
   `flutter test`, resolve the one known failing test, commit. Do not start
   F3-F5 while F6/F7 are half-done and uncommitted -- that is how work gets
   lost.
2. Phase F3 (SSRF-hardened fetcher) -- needed before F4/F5 can call any real
   network endpoint. Can be built and tested entirely offline against fixture
   URLs; no external blocker.
3. Phase C (state layer) -- currently the largest gap between "features
   exist" and "app is coherently structured." Not urgent for demo purposes
   but blocks doing E1-E4 cleanly, since those screens need a mutable store
   to write against rather than reaching into the repository directly the
   way `main.dart` does now.
4. Phase E1 (rate on harvest) -- smallest of the missing E-screens, good
   next screen-building item once Phase C exists to wire it against.
5. Phase F4/F5 (extractors) -- F4's YouTube tier is blocked on a human
   (API key); Twitch and Steam tiers are not blocked and can proceed.
   F5 has no blocker.
6. Phase E2-E4 -- in roughly that order (list view is most self-contained;
   search-and-add depends on `CatalogService` existing, which does not yet).

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
