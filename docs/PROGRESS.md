# Progress

Append one dated entry per loop cycle, newest at the top. Never delete an
entry. If something you recorded turns out to be wrong, add a new entry that
says so -- do not edit history.

Format per entry: what you did, what critique found (Section 4 of
`GOAL.md`), what's still open, then update the checklist and the Next
section below to match.

---

## 2026-09-25 -- Cover art for collection rows

Rows were text-only even when a game HAD a cover: `Game.coverUrl` already
flowed from IGDB through the DB into the model, but `_GameRow` never rendered
it. Two gaps closed, not one:

1. **Rendering.** Added `_Cover`, a 32x32 rounded thumbnail on the row's
   leading edge (before `_StatusMark`). Real `Image.network` when
   `coverUrl` is set, a placeholder tile (a game-controller glyph) otherwise,
   `errorBuilder` falling back to the same placeholder rather than Flutter's
   broken-image icon on a dead link.
2. **Sourcing.** The bundled 609-title catalogue (`assets/catalog/games.json`)
   ships with **no** cover art by design (its own note says so), and the
   fixture rows have none either -- so most rows had nothing to render even
   after (1). Added `CoverArtReader` (`lib/services/cover_art.dart`): looks a
   title up against Wikipedia's `page/summary` REST endpoint, unauthenticated,
   same "reading needs no credentials" fact `link_metadata.dart` already
   leans on for page titles. Not IGDB-quality and said so in the code: an
   ambiguous title (a disambiguation page) or an obscure one returns no image,
   silently, by design -- never a guess.

Wiring: `CoverArtCache` (`lib/services/cover_art_cache.dart`) is the
in-memory, per-session, at-most-once-per-game dedup layer a rebuilding row
calls into from `build()` -- fire-and-forget, so the list never blocks on the
network for a paint it can complete without an image. A resolved cover is
written back via the new `Repository.setCoverUrl` (a targeted update, same
pattern as `setRating` -- touches nothing else on the row) and
`LudeckStore.applyCoverUrl` patches the in-memory item directly rather than
going through `_write`'s full re-read, which would turn "the list is
scrolling" into a database read per frame. `applyCoverUrl` **awaits** the
repository write before patching memory (an earlier draft fired it
unawaited, which a fast reload racing behind it could have read stale and
then overwritten the patch on the next render -- caught before it shipped,
not after).

**A real regression, caught by the existing test suite, not introduced
silently.** Adding the 32px cover as a new fixed-width leading child of the
row's `Row` overflowed by 27px at 2x text scale (`collection_layout_test.dart:
the header survives a wrapped headline at large text scale`) -- not from the
cover itself, but because `_RatingOrStatus`'s trailing status `Text` had
never had a width bound and the row had zero slack even before this change.
Fixed at the actual fault, not by shrinking the new element to hide it:
`_RatingOrStatus`'s status text now sits in a `ConstrainedBox(maxWidth: 84)`
with `maxLines: 1` and ellipsis, which bounds it regardless of what else the
row gains later. 435 tests green after the fix (was 412; +23: 6 reader, 4
cache, 5 store, 2 repository, 5 row/widget, with one pre-existing count
shifted by the fix).

**Verified on the device**, not only in tests, because the whole point is
visual. Installed over the same emulator database from stage 4/5 (real
continuity, not a fresh install): Hades, Astro Bot and Blue Prince already
had IGDB covers from earlier sessions and rendered them; Tunic had none and
resolved one live from Wikipedia within seconds of cold start. Celeste and
Outer Wilds stayed on the placeholder -- checked directly rather than
assumed: `en.wikipedia.org/api/rest_v1/page/summary/Celeste` is a genuine
disambiguation page ("Celeste may refer to:"), so the silent no-guess
behaviour is correct, not a bug. This is the one real limitation and it is
open, not hidden: a common one-word title collides with something else on
Wikipedia and gets no cover until the IGDB proxy is deployed.

Not touched: `AddScreen`'s `_ResultRow` (the search-results list, a
different screen) is also text-only. Out of scope for "add cover art to the
catalogue so rows aren't text-only," which is the collection view; flagged
here rather than silently expanded into.

## BLOCKED

(empty -- nothing blocked as of this seed. A stuck loop writes here.)

## Needs human judgment

(empty as of this seed. Log subjective design calls here rather than
deciding them.)

## Checklist (mirrors GOAL.md Section 2)

- [x] Phase A -- business logic, pure Dart
- [x] Phase B -- repository (createBranch, renameBranch, deleteBranch,
      reorderBranches, place, unplace, unplacedGameIds all exist)
- [x] Phase C -- state layer. **DONE 2026-09-25.** `provider ^6.1.5+1` added,
      `lib/state/ludeck_store.dart` owns the collection, the skipped count, the
      loading flag and the error. `TreeScreen` no longer takes a `Repository` at
      all -- a screen holding both a repo and a store would be two sources of
      truth -- so the store is provided above `MaterialApp` and the screen reads
      it with `context.watch`. 15 tests in `test/state/ludeck_store_test.dart`.
- [x] Phase D -- entitlement (`entitlement_service.dart`, paywall screen,
      both tested)
- [ ] Phase E -- Gaming-criterion screens
  - [x] E1 rate on harvest -- **DONE 2026-09-25.**
        `lib/ui/harvest/rating_sheet.dart`, fired on the TRANSITION into
        finished from the status sheet, plus a user-initiated row in that sheet
        for harvested games so a skip does not make rating unreachable.
        21 tests across `test/rating_sheet_test.dart` (pure sheet, no DB) and
        `test/rating_test.dart` (through the real screen and database).
  - [x] E2 list view -- **DONE 2026-09-25.** `collection_view.dart` now groups by
        the user's branches when any exist (unplaced last, empty branches still
        shown), falls back to status grouping when none do, and every section is
        collapsible. Rows and headings carry full Semantics. 17 tests in
        `test/branch_sections_test.dart`.
  - [x] E3 branches screen -- **DONE 2026-09-25, commit `cc8639a`.** Create,
        rename, reorder, delete. Reorder carries a non-drag path (Move up / Move
        down in each row's menu) because drag is the least accessible
        interaction there is; delete states the game count and that they are
        kept. 16 tests.
  - [x] E4 search and add -- **DONE 2026-09-25, commit `4dee3d3`.** Five states
        with empty and failed kept distinct, 300ms debounce, in-flight guard
        against out-of-order responses. `HttpCatalog` is written and tested
        against recorded IGDB shapes; `resolveCatalog()` returns the fixture
        while `catalogBaseUrl` is empty, so that constant is the whole swap.
        36 tests.
  - [x] E5 superseded by Phase F, per GOAL.md -- do not build separately
- [ ] Phase F -- share anything to the library
  - [x] F1 source storage (commit `c3fb771`)
  - [x] F2 resolver core (commit `3c4509e`)
  - [x] F3 SSRF-hardened fetcher -- **DONE 2026-09-25.**
        `fallback-kotlin/supabase/functions/igdb/url_guard.ts` (pure policy, 17
        tests run under node) and `safe_fetch.ts` (the impure shell). `check.ps1`
        rule 11 refuses a fetch outside the guard and refuses the follow-redirect
        mode anywhere in that directory. ONE RESIDUAL GAP is documented in
        `safe_fetch.ts` rather than hidden: it still connects by hostname after
        checking the resolved addresses, because Deno's fetch cannot pin an IP, so
        the last DNS-rebinding millisecond needs an egress firewall in production.
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
- [x] Backend polish: transaction/cascade audit -- **DONE 2026-09-25.**
      `test/integrity_audit_test.dart`, 17 tests. Foreign-key enforcement
      asserted on three open paths including a REOPEN (the setting is
      per-connection, not stored in the file); every one of the five declared
      relations checked for presence AND `CASCADE` by reading the engine rather
      than the DDL text; an orphan-creation test per relation; a delete test per
      parent; atomicity of the multi-row writes; and a realistic workload that
      re-runs `PRAGMA foreign_key_check` after every step.
      Negative-tested by flipping the pragma to OFF: five tests go red.

## Next (highest priority first)

1. **Phase F4/F5 (extractors)** -- stage 8, NOT started. Now unblocked: the SSRF
   guard and `safeFetchPage` exist for the Open Graph tier. Twitch clip to
   `game_id` to `igdb_id` and Steam appid via `external_games` are already written
   in `HttpCatalog.byExternalId` and fixture-tested, so F4's exact tier is mostly
   done; what remains is the oEmbed tier, the generic Open Graph and JSON-LD
   reader, and the YouTube tier behind a key only Abin can create.
2. Final verification -- stage 10, not started. Stage 9's backend audit IS done.
3. Not a code item, but the real critical path: the proxy deploy
   (`docs/DEPLOY-PROXY.md` steps 3 to 6), a YouTube Data API key, and RevenueCat
   all need account access only Abin has. Every client-side seam for them is
   written, tested and inert.

## Design items deferred from stage 1 (open, not bugs)

From the phone-proportions critique. Neither is a layout fault, so both were
deliberately left out of the layout stage rather than folded in as scope creep:

- **"2 seeds" names something hard to find.** The subline promises two seeds and
  the Seeds group is ordered LAST, so on first open both are below the fold. The
  header makes a claim the first screenful does not keep.
- **Group ordering is by activity, not by what the user came to see.** "In hand"
  first is defensible; whether harvested and seeds belong above the fold is a
  judgment call worth making deliberately once the branch grouping of Phase E2
  lands, since that changes the sectioning anyway.

## Design items seen during stage 3

Observed on the device while verifying rate-on-harvest.

- **CLOSED in stage 4. A rating REPLACED the status word on a row's right edge.**
  So Hades read "Finished" while a rated Hollow Knight read stars, and the
  right-hand column carried two different kinds of information depending on the
  row. Status is now always present and the pips sit beneath it.
- **CLOSED in stage 4. A rating survived a game leaving `finished`** and would
  then show stars where its progress word belongs. The rating still survives the
  transition, deliberately -- it is a true record of a past harvest and deleting it
  silently would be worse -- but it is no longer SHOWN or announced on a game that
  is not harvested.
- **OPEN. The status sheet for a harvested game is taller than the screen.** It
  carries three sections, and the rating row sits below the fold with no
  affordance suggesting there is more to scroll to. Tolerable, but it is the kind
  of thing that makes a feature look missing.

## Cycle log

### 2026-09-25 12:45 -- a real catalogue, and links that resolve

Abin sent a device screenshot: "Nothing recognised -- that link could not be
matched to a game yet", and said search could not find GTA V either. One root
cause sat under both complaints.

**The app had no game data.** `resolveCatalog()` returned the ten-row fixture, so
the shipped app's search box was decorative and a link had nothing to be matched
against. Everything built in stages 6 to 8 was real code wired to an empty shelf.

**The worst bug of the day, and only the device found it.** `main.dart` line 118
read `_catalog = widget.catalog ?? FixtureCatalog()`. It never called
`resolveCatalog()` at all. So the factory could be fixed, tested, and asserted
against -- `expect(resolveCatalog(), isA<BundledCatalog>())` passed -- while the
running app ignored it entirely. **A factory the app bypasses is not a seam; it is
dead code with a test attached, and no amount of green proves otherwise.** 412
tests were passing at the moment the device said "Nothing matched".

That is now checker rule 12: main.dart may name `resolveCatalog` and may not
construct a catalogue source directly. Negative-tested -- and the FIRST version of
the rule was inert, because the anchor I inserted it at matched the
`Pass 'flutter analyze clean'` line rather than that rule's start, wedging my rule
inside the analyze block's `try`. A failing analyze raises a terminating error
there, so the rule silently never ran. Moved out of the try and re-negative-tested.

**What now ships.** `assets/catalog/games.json`, 609 hand-authored well-known
games with years and approximate main-story hours, loaded by `BundledCatalog`.
Ids are NEGATIVE and derived from a hash of the title: negative so they can never
collide with a real positive catalogue id, and title-derived rather than
position-derived because position would mean inserting one game shifts every id
after it and silently repoints rows the user already saved. `LayeredCatalog` puts
the live proxy in front when configured and keeps the bundle as the offline
fallback, deduplicating on a numeral-folded title so one game cannot appear twice
with two different ids.

**Why "gta v" found nothing even with GTA V present.** A substring search cannot
reach `Grand Theft Auto V` from that query -- it is an ACRONYM. `title_match.dart`
now builds several keys per title: the full name, the subtitle after a colon
(nobody asks whether you have played "The Legend of Zelda"), acronyms with and
without the leading article, and roman-numeral/digit variants both ways. Tiers are
exact > acronym > prefix > contains, and a shorter title wins an equal tier so
"Hades" beats "Hades II" for the query "hades".

**Links needed no credentials, which contradicts what this file said before.**
Tiers 2 and 3 carried a comment claiming they needed the deployed proxy. False:
reading a page's TITLE needs nothing, only looking a game UP needs IGDB. oEmbed
answers unauthenticated on YouTube, TikTok, Vimeo, X and Reddit -- a YouTube Data
API key is for statistics and captions, not for a title -- and every other page is
read through Open Graph, JSON-LD or `<title>`. So the YouTube key is no longer on
the critical path for this feature.

`video_title.dart` turns a noisy title into candidates by taking every contiguous
window of words. That is deliberately crude: the obvious alternative, deleting the
words that look like noise, destroys real titles, because any honest noise list
contains "of", "the", "final" and "last" -- strip those and *Call of Duty*, *Final
Fantasy* and *The Last of Us* stop existing. Noise is used only to REJECT an
all-noise candidate, never to edit one. A link-derived match is accepted only at
exact or acronym tier, and an ambiguous one-word hit ("Journey", "Control",
"Inside") additionally needs gaming context, read from the page title itself.

**A duplicate guard that had to become a write skip.** The add screen matched
`igdbId` only, which was fine when one catalogue existed. With two sources the same
game arrives under two ids, so it now matches on title too AND skips the write --
upserting a different id would create the second row rather than update the first,
so "already there" has to mean "do nothing", not just a different snackbar.

**Suite flakiness, and an attempted fix that made it worse.** Different tests
failed on each full-suite run while all passed in isolation -- the signature of
timing, since a real bug fails the same test every time. Cause: 40 ms fixed waits
for real database writes, fine when written and used up as the suite passed four
hundred tests. I first made `tapAndSettle` wait for the tapped label to DISAPPEAR,
which looked like a real signal and was the opposite: the confirm sheet pops before
its write and reload finish, so the predicate went true in 20 ms and the following
read ran against a half-written collection. That turned an intermittent failure
into a reliable one. Reverted; the harnesses now poll, use a real predicate where
one exists (the created branch's row appearing), and otherwise wait eight rounds of
20 ms. Three consecutive full runs green.

**Verified on the device**, which is the only reason two of these were found:
searching "gta v" returns Grand Theft Auto V first (Grand Theft Auto VI second,
because a roman-numeral suffix reduces to its first letter so both yield "gtav" --
the digit variants still separate them and the shorter title ranks first), and
sharing `en.wikipedia.org/wiki/Elden_Ring` over live network resolved to Elden Ring
labelled "From the page details".

412 tests green three times, analyzer clean, `check.ps1` 14/14.

Still open: the bundled catalogue is finite and hand-authored, so anything outside
609 titles still needs the proxy. Add-by-hand remains the escape hatch.

### 2026-09-25 11:32 -- stage 9, the backend integrity audit

Systematic pass over foreign keys, cascades and transactions:
`test/integrity_audit_test.dart`, 17 tests.

**The finding that justifies the whole stage.** SQLite defaults foreign keys OFF
and the setting is PER CONNECTION, not stored in the file. `database.dart` did set
`PRAGMA foreign_keys = ON` in `onConfigure`, and that was correct -- but NOTHING
verified it. Every `ON DELETE CASCADE` in the schema was one deleted line away
from becoming decoration, and the failure would have been completely silent:
writes keep succeeding and orphan rows accumulate. Enforcement is now asserted on
three open paths including a REOPEN, since a first-open-only test would miss
exactly the case where a second connection forgets.

Negative-tested by flipping the pragma to OFF: five tests go red, including two
orphan-creation tests. Before this file existed, flipping it would have broken
nothing visible.

**Three audit findings, all acted on:**

`deleteBranch` deletes placements by hand AND the schema cascades them, which
means it would keep working with enforcement off -- masking a broken pragma. The
redundancy is kept deliberately (it is a hedge against a future connection that
forgets `onConfigure`) and the comment already said so; what was missing was a
test that checks the CASCADE independently of it, which now exists.

**Nothing in the app ever deleted a `games` row**, because `shelved` replaces
delete by design. So all four cascades pointing at `games` were latent and had
never been exercised once. Added `Repository.purgeGame`, an honest hard delete
reachable only from code, which deletes ONLY the games row and relies on the
cascades -- so the test exercises the real mechanism rather than a hand-rolled
imitation. It is explicitly not the delete the UI offers.

Enforcement being per-connection also means a database written by a build from
BEFORE `onConfigure` existed can already hold orphans, and turning the pragma on
later does not retroactively clean them. `Repository.foreignKeyViolations()` wraps
`PRAGMA foreign_key_check` so that is checkable; the workload test re-runs it after
every mutation.

Also added `tableNames()` and `foreignKeysOf()`, which read the ENGINE rather than
the DDL string. That distinction matters: a cascade clause written in `_ddl` but
missing from `_migrations` would apply on a fresh install and not on an upgraded
one, and only an engine read sees the difference. The `sources` table arrived in
the v2 migration, so it is the one most exposed to that, and it has its own
assertion on the migrated path.

A table-set assertion fails if a new table appears with no entry in the audit's
relation list, so the next schema addition has to make a delete-behaviour decision
rather than discover one months later.

Verified: 343 tests green (was 326), analyzer clean, `check.ps1` 13/13.

Scope note, stated rather than glossed: `openLudeckDatabase()` -- the real app
entry point -- needs `path_provider` platform channels a unit test does not have,
so it is covered only through `openLudeckDatabaseAt`, which it delegates to. That
split already existed for the migration tests and is why it exists.

**STILL NOT DONE: stage 8 (extractors, F4 and F5).** The plan status has now
reported it complete once without it being started. What actually remains is the
oEmbed tier, the generic Open Graph / JSON-LD reader over `safeFetchPage`, and the
YouTube tier behind an API key only Abin can create; F4's exact tier (Twitch clip
and Steam appid) is already written and fixture-tested in
`HttpCatalog.byExternalId`.

### 2026-09-25 11:20 -- stages 5, 6 and 7, and a correction to the plan status

**The orchestrator's plan status was wrong three times and had to be corrected
rather than followed.** It reported stage 5 complete when the code was written but
uncommitted and its device verification had been cancelled; then stage 6 complete
when it had never been started; then stage 7 complete when it had never been
started. Each turn began by checking `git status` against the claim, which is the
only reason the holes were caught. Nothing was skipped to keep up with the status
board.

Commits, in order: `cc8639a` Phase E3 (branches screen), `4dee3d3` Phase E4
(search and add), and this one for Phase F3.

**Phase E3, branches screen.** Create, rename, reorder, delete, over the store
methods added in stage 4. Two decisions worth the words:

Reorder has a NON-DRAG path. Drag and drop needs a sustained press, a steady hand
and sight of the destination; the handle stays for people who want it, and every
row's menu also carries Move up and Move down, offered only where they mean
something. Delete states what happens to the games before the button, with the
count and the correct singular, because a user who suspects deleting a branch
destroys their games will never delete one and will be stuck with a list they
cannot tidy.

Found a real bug before writing the screen: `createBranch` defaults `sortOrder` to
0, so a branch created after any reorder would jump to the FRONT of a list the user
had just arranged. Fixed in the store by computing the next order; there is a test
that reorders, creates, and asserts the new branch is last.

A genuine bug the tests caught: `showDialog(...).whenComplete(controller.dispose)`
throws "A TextEditingController was used after being disposed", because the route's
exit animation still rebuilds the field after the future resolves. The controller
has to be owned by a StatefulWidget whose dispose runs once the route is gone.

**Phase E4, search and add.** `lib/ui/add/add_screen.dart` plus
`lib/services/http_catalog.dart`.

The screen has FIVE states and the distinction that matters is empty versus
failed: "nothing matched" says the game is not in the catalogue, "could not
search" says nobody asked, and rendering both as an empty list makes the first a
lie. A malformed reply offers no retry, because retrying a broken response breaks
again and a button that cannot help is worse than no button. Debounced at 300ms
with an in-flight query guard, so a slow earlier response cannot overwrite a newer
one.

The HTTP source is WRITTEN, not stubbed, and tested against recorded IGDB response
shapes: the `time_to_beat` object form, the scheme-less cover URL, rows with no id
skipped rather than fatal, and a quote in the query escaped so it cannot terminate
the Apicalypse string. `resolveCatalog()` returns the fixture while
`catalogBaseUrl` is empty, so filling that constant in is the entire swap.

**Phase F3, the SSRF guard.** Deno is not installed on this machine, and shipping
security-critical range arithmetic with no executed test was not an acceptable
trade. So the policy is PURE TypeScript with no Deno APIs, tested under node with
`--experimental-strip-types`, and the impure shell that does DNS and sockets is
kept thin around it.

What is tested: every blocked IPv4 range refused AND a public address just outside
each one allowed (an off-by-one prefix fails one or the other); the IPv6 ranges;
and the three IPv4-in-IPv6 embeddings that are real bypasses -- IPv4-mapped, NAT64
and 6to4 -- none of which sits in `fc00::/7` or `fe80::/10`, so checking the IPv6
prefix alone would miss all three. Also asserted as a load-bearing fact rather
than assumed: WHATWG `URL` normalises `2130706433`, `0177.0.0.1`, `127.1` and
`0x7f.0.0.1` all to `127.0.0.1`, which is the only reason a strict dotted-quad
parser is safe here.

Negative-tested by deleting the `169.254.0.0/16` entry: FIVE tests went red,
including the 6to4 case and the post-DNS rebinding test. 17/17 green after revert.

New `check.ps1` rule 11 refuses a `fetch(` outside `safe_fetch.ts` and refuses the
follow-redirect mode anywhere in the proxy directory, and requires
`safe_fetch.ts` to apply BOTH halves of the guard. Negative-tested with a rogue
module. Like rule 3 before it, it fired on my own comment containing the literal
it forbids, and the comment was reworded rather than the rule loosened.

**The residual gap, stated rather than hidden:** after checking the resolved
addresses, the fetcher still connects by HOSTNAME, because Deno's fetch cannot be
told to connect to a pinned IP while presenting the right SNI. The last DNS
rebinding millisecond is therefore not closed in code and wants an egress firewall
in production. Everything else is: every literal address, every blocked name,
every redirect hop re-vetted, body capped before it is read, timeout, port 443
only so port scanning is not a capability.

Verified: 326 tests green in the app (twice), analyzer clean, `check.ps1` 13/13,
17/17 in the proxy guard suite.

A test-flakiness root cause worth keeping: `collection_layout_test` passed alone
and failed consistently in the FULL suite. Under concurrency its fixed 20ms wait
was too short for the seeded load, so the store's items were still null, the screen
rendered its deliberate blank branch, and every `getRect` failed on a finder that
matched nothing -- which reads as a layout bug and is a timing one. Replaced with a
bounded poll for the widget the test actually needs.

**NOT done in this turn: stage 8 (extractors, F4 and F5).** The guard and fetcher
it depends on now exist, so it is unblocked.

### 2026-09-25 10:28 -- stage 4 of the "remaining features" plan (Phase E2)

Branch sections and the accessible path.

**The decision worth arguing about: branch grouping has a fallback, and it is not
a shortcut.** Nothing seeds a branch, so a new install has none, and grouping by
branch then produces a single unnamed heap of the entire collection -- strictly
less information than the status grouping it replaced. So `CollectionView` groups
by branch when branches exist and by status when they do not. Branches earn the
sectioning once the user has made some. A test asserts both paths.

Grouping details, each a deliberate call: branches appear in the user's own order
(reordering them reorders the sections, tested); an EMPTY branch is still shown,
because the user made it deliberately and hiding it would look like a deletion;
unplaced games get a section, last, because that is where a freshly shared game
waits to be filed rather than the headline of the collection; and a placement
pointing at a shelved game is skipped so a heading's count always equals the rows
under it.

Collapse state is view state and lives in the widget, not the store. Collapsing a
section is not a fact about the collection. Section keys are stable ids rather
than labels, so a reload -- or renaming a branch -- cannot silently reopen a
collapsed section; there is a test for that.

Accessibility, which is the real point of this phase since a canvas is invisible
to a screen reader:

- A row announces one sentence carrying everything it conveys, including what is
  only visual: `"Hades, Finished, about 23 hours, on PC, rated 4 out of 5"`. Built
  from the plain labels, never the metaphor word -- "Ripe" read aloud without the
  picture means nothing.
- `excludeSemantics: true` on the row, because otherwise the inner Text widgets
  are announced again after the label, so the title and status are read twice and
  the metadata arrives as "2017 . 26 h . PC", which does not parse aloud.
- Headings are a header AND a button AND carry `hasExpandedState` / `isExpanded`.
  The chevron communicates state to sighted users only.
- "1 game" not "1 games".

**Both stage 3 design findings are now closed**, since this stage revisited the
row anyway. The rating no longer REPLACES the status word: status is always
present and the pips sit beneath it, so the right-hand column carries one kind of
information on every row. And a rating is only shown on a harvested game, which
fixes stars appearing on a game merely "Playing" after a harvest was undone. The
rating itself still survives that transition, deliberately: it is a true record of
a past harvest and deleting it silently would be worse.

A real bug this stage introduced and fixed: adding branches+placements to the
store's read made EVERY write three queries instead of one, and `_applyIntake` was
doing two full write-and-reload cycles per game (upsert, then addSource). That
pushed the share test's fixed 20ms wait past the second write, and it failed
looking exactly like a feature that does not record sources. Fixed at the cause
with `store.addShared`, one write and one reload -- which is also the honest unit
of work, since a shared game and its provenance are one event, and the old path
briefly left the collection holding a game with no source. The share test's delay
went to 40ms as well, because any fixed delay there is fragile.

Verified: 274 tests green (was 250), analyzer clean, `check.ps1` 12/12, and the
suite run THREE times to confirm the race was gone rather than merely retimed.

**Verified on the device in both modes.** The status fallback first, then -- since
there is no branch-creating UI until stage 5 -- three branches were written
straight into the emulator's database (two populated, one empty on purpose).
Confirmed: branch order honoured, the empty branch shown with count 0, "Not on a
branch 6" last, counts matching rows, and a real tap collapsing one section while
its siblings stayed open. Empty logcat.

NOTE for stage 5: the emulator's fixture now HAS three branches, deliberately left
in place so the branches screen has something real to rename, reorder and delete.
This is the one device-state change not made through the UI.

A Kiro Crew policy blocked one command as a false positive: the git-publish floor
matched `adb push` combined with a `${...}-journal` brace expansion. No git
operation was involved. Its stated objection is that shell expansion makes the
push target unverifiable, so the command was reissued with fully literal paths,
which removes the expansion rather than working around the check.

### 2026-09-25 10:09 -- stage 3 of the "remaining features" plan (Phase E1)

Rate on harvest. `lib/ui/harvest/rating_sheet.dart`, fired from the status
sheet's progress callback via `_setProgressAndMaybeRate`.

The trigger is the TRANSITION into finished, not the finished state. So
re-selecting "finished" on an already-finished game asks nothing, and a game that
already carries a rating is not asked again. A test covers each, and the
transition guard was negative-tested: removing `!wasFinished` turns the
"re-selecting finished asks nothing" test red, which matters because that test
asserts `findsNothing` and would otherwise pass vacuously if the tap silently
failed.

**One addition beyond the brief, and it closes a real hole.** The brief says the
sheet appears once and skipping is a normal outcome. Taken literally that makes a
skipped rating permanently unreachable, and "rate" is one of the judged Gaming
criteria, so the feature would have had no surface at all for anyone who
dismissed it once. The status sheet now carries a "What did you think" row, shown
ONLY for harvested games and only when the user opens that sheet themselves. No
badge, no count, nothing appears unprompted, so it is not a nag.

Design decision worth recording: `RatingChoice` exists instead of a bare `int?`
because there are three outcomes, not two. A null return from the sheet means
SKIP (write nothing); a `RatingChoice` carrying a null rating means CLEAR (write
null). The first draft encoded clear as `0`, which the repository throws on since
ratings are 1 to 5, and which made skip and remove indistinguishable at the call
site.

Verified: 250 tests green (was 235), `flutter analyze` clean, `check.ps1` 12/12.

`check.ps1` rule 8 fired and was right to. Six of the new tests pump a bare
`MaterialApp` with no database, but they sat in a file that imports
`data/repository.dart`, which the rule matches at file level. Fixed structurally
rather than with an exemption: the pure-sheet tests moved to
`test/rating_sheet_test.dart`, which imports no repository at all.

**Verified on the device across the whole flow:** harvested Hollow Knight, saw
the sheet appear on the transition, tapped 4 stars, watched it persist and render
as four filled pips against one outline on the row, then reopened the status
sheet, found the rating row pre-filled at 4 with "Remove rating" offered, removed
it, and set progress back so the fixture matches the stage 1 baseline exactly.
Empty logcat throughout.

Two async-test traps cost time and are worth knowing:

- A tap that triggers a database write needs the tap in ONE `runAsync` and the
  wait in a SEPARATE one. Pumping the fake clock inside `runAsync` does not give
  a real sqflite future time to resolve, so the continuation never runs and the
  sheet that should follow the write never appears. Five tests failed this way
  and the symptom looked like a broken feature.
- `find.text('Harvested')` matches BOTH the sheet option and the list's group
  heading behind it, and `tap` refuses an ambiguous finder. Sheet finders must be
  scoped with `find.descendant(of: find.byType(BottomSheet), ...)`.
- Once a game is harvested the status sheet is taller than the screen, so a
  control below the fold is found by the finder but the tap MISSES it, reported
  only as a warning. `tester.ensureVisible` first.

### 2026-09-25 09:54 -- stage 2 of the "remaining features" plan (Phase C)

Built the state layer. `provider ^6.1.5+1`, `lib/state/ludeck_store.dart`, and
`main.dart`'s `_load` / `_setProgress` / `_setOwnership` deleted rather than
wrapped.

One decision beyond the brief, and it is the one worth arguing about: **`TreeScreen`
no longer takes a `Repository`.** The brief said move the three methods into the
store, which would have left the screen holding a repo it still used for the share
intake writes -- two sources of truth for the same rows, and nothing stopping a
future edit from reaching past the store. So `repo` came off the constructor
entirely, the store is provided above `MaterialApp`, and the screen reads it with
`context.watch`. Cost: both widget-test harnesses now wrap in
`ChangeNotifierProvider`. That churn is the point -- a test that could construct
the screen with a bare repo was documenting the wrong architecture.

The store's contract, all three rules from TASKS.md Phase C honoured:
`items` stays nullable (null = first read not finished, NOT an empty collection);
every mutation writes, re-reads, then notifies, so the screen can never show a
value the database does not have; no SQL and no entitlement SDK in the file.

Two things added that the brief did not ask for and that the code needed:

- **`_LoadFailure`.** The brief said errors must surface on `error` rather than
  throwing into the widget tree, which the store does. But if the FIRST read
  fails, `items` is null and the old code painted a blank screen -- indistinguishable
  from an empty collection, so the user would be told their library is empty when
  it merely failed to load. That is a worse lie than an error page. Later failures
  deliberately do NOT come here: the collection is already on screen and replacing
  it over one failed write would throw away readable data.
- **Dispose guard.** A write can complete after the screen is gone (a share
  applied across a lifecycle change is the real case) and notifying a disposed
  `ChangeNotifier` throws. There is a test for it.

Also: `_drainShare` moved from `initState` to a post-frame callback, because it
now needs the provider, which is not reachable from `initState`.

Verified: 235 tests green (was 220), `flutter analyze` clean, `check.ps1` 12/12.

**Verified on the device, not just in tests**, because the one failure mode the
tests could not catch is a provider read from a popped sheet's context throwing
"deactivated widget's ancestor". Long-pressed Hollow Knight via `adb input swipe`,
tapped Harvested, and watched the row move groups, the mark fill, and the subline
go "1 harvested" to "2 harvested", with an empty logcat. Then reverted it through
the same UI so the fixture matches the stage 1 baseline.

Two wrong assumptions I made writing the tests, both caught by the analyzer:
`Ownership.sold` does not exist (it is `released`) and `SourceKind.link` does not
exist (it is `web`).

No new design critique: this stage changed no pixels, and the device screenshot is
byte-for-byte the same layout as stage 1's. The two deferred design items below
are still open.

### 2026-09-25 09:43 -- stage 1 of the "remaining features" plan

Fixed the two live layout defects the emulator screenshot exposed, and the fix is
not the one the stage brief assumed.

The brief said "give the scrollable a top inset". It already had one; the inset
was WRONG, not missing. `CollectionView` computed
`padding.top + space.md + display * leadingDisplay + space.lg`, budgeting for one
line of display type against a header that is two lines plus an optional notice.
Correcting the sum by measuring both lines with a TextPainter was still 20px
short, because the header can WRAP -- its height depends on font, text scale and
width, so no number computed away from the layout is reliable.

So the guess is gone rather than corrected. The header is now an ordinary layout
sibling above the content (`Column` + `Expanded`), which makes a top overlap
inexpressible. `ChromeMetrics` shrank to just `bottom`, where the value really is
fixed (a 52px control, a known gap). The skipped-games notice now flows after the
subline instead of sitting at a hardcoded `md + xl + lg` offset that could land on
a wrapped headline.

Bottom band: padding only governs where the list comes to rest, so a `_Scrim`
sized from the same `ChromeMetrics.bottom` fades rows out under the add control
while dragging. `IgnorePointer` on it is load bearing.

Regression I introduced and caught on the device: moving the header into a
`Column` CENTRED it, because Column centres on the cross axis and the block
shrink-wrapped to its text width. Fixed with `CrossAxisAlignment.stretch` and
locked with a test on the header's left edge.

New: `test/collection_layout_test.dart`, 7 tests -- viewport below header, header
survives 2x text scale, no row overlaps at rest, last row clears the control,
scrim matches the padded band, header left-aligned, scrim passes pointers
through. Negative-tested by zeroing `bottomInset`: two assertions went red, green
again after revert. Also added `Tokens.size.control`, removing the bare 52 that
was duplicated between `add_menu.dart` and the chrome.

Verified: 220 tests green (was 213), `flutter analyze` clean, `check.ps1` 12/12,
and confirmed on emulator-5554 with two screenshots (before and after the
alignment fix) rather than asserted from code.

Design critique against GOAL.md Section 4: the header/list relationship now
passes. Two items from the earlier phone-proportions critique remain OPEN and are
NOT layout bugs, so they were deliberately not folded into this stage: "2 seeds"
names something hard to find, and the seeds group sits last so the two seeds are
below the fold on first open. Logged under Next.

Traps recorded in CONSTRAINTS.md: flutter_test's default font renders every glyph
as a full em square (text wraps in tests where it does not on a device -- treat it
as a free large-text-scale case, not a reason to loosen the test); `Column`
centres its children; PowerShell 5 `Set-Content -Encoding UTF8` writes a BOM,
which a negative-test probe left in `main.dart` before it was stripped.

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
