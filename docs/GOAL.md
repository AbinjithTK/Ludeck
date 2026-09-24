# Goal: finish Ludeck to a submission-ready, Tolan-grade polish

This is the one document a looped agent reads in full, every cycle, before doing
anything. It exists because the loop may be running on a weaker model than the one
that wrote this file. Every section below is written so a mechanical check can
verify it -- a number, a file, a test -- not so a taste call is required to
apply it. Where taste genuinely cannot be avoided, that is marked, and the fallback
is "log it, do not decide it."

Read `docs/PROGRESS.md` after this file. `GOAL.md` says what "done" means.
`PROGRESS.md` says what is already done and what to do next. Never duplicate
state between them: if you learn something new about scope, it goes in
`GOAL.md`; if you learn something new about what happened, it goes in
`PROGRESS.md`.

## 1. What "done" means

Not "every idea we discussed." Done means: every item in Section 2 below is
checked off in `PROGRESS.md`, `flutter analyze` is clean, `flutter test` is
green, `scripts\check.ps1` is green, and every screen listed in Section 4 has
passed its critique pass with zero unresolved findings above severity
"minor." When all of that is true, stop the loop yourself: create the stop
file named in your nudge message and say so in `PROGRESS.md`. Do not keep
looping past done looking for more to do.

If you cannot tell whether something is done, it is not done. Say so in
`PROGRESS.md` rather than guessing either direction.

## 2. Scope: the features that must exist

This is the real remainder, not a re-listing of already-shipped work. Cross-check
against `docs/TASKS.md` phase letters -- they are the authoritative task
breakdown; this section is the acceptance bar for each phase, not a
duplicate task list.

### Phase C -- state layer (NOT STARTED)

- A `provider`-based store class over `LudeckRepository`. `main.dart`
  currently calls the repository directly and holds `load`, `setProgress`,
  `setOwnership` itself -- move that logic into the store.
- Acceptance: a widget test asserts items are `null` before `load()`
  completes, and that a repository error surfaces as a readable state, not
  an uncaught exception in the widget tree.

### Phase D -- entitlement (DONE)

`EntitlementService`, `FakeEntitlementSource`, and the paywall screen exist
and are tested. No further work unless critique (Section 4) finds a defect.

### Phase E -- the five Gaming-criterion screens (PARTIALLY STARTED)

Only the paywall exists. Still missing, each is its own acceptance bar:

- **E1, rate on harvest**: a rating sheet appears once, at the moment a
  `Progress` transitions to `finished`. Skippable with no re-prompt.
  Acceptance: a test drives that transition and asserts the sheet opens
  exactly once, and that skipping it does not open it again on the next
  transition.
- **E2, list view**: branch-grouped, collapsible sections; each row shows
  title, platform badge, rating if present. This is the accessible
  alternative to the tree -- every semantics label uses the plain `label`
  field from `DECISIONS.md`'s enum table, never the `tree` metaphor word.
  Acceptance: a screen-reader-oriented widget test reads every row's
  `Semantics` label and asserts none contains a metaphor word ("grow",
  "wither", "ripe", "harvest" as a verb applied to the row itself).
- **E3, branches**: create, rename, reorder, delete. Delete states in the
  confirmation dialog, in plain words, that games are kept. Acceptance: a
  test deletes a branch with games on it and asserts those games still
  resolve to `unplacedGameIds` afterward, and a widget test asserts the
  confirmation text contains the retention promise.
- **E4, search and add**: screen against `CatalogService` (build this
  behind an interface now; see Phase F for why the real HTTP source stays
  inert). Debounced input, explicit empty state, explicit error state --
  neither may be a blank screen.
- **E5, share**: superseded by Phase F below (share-to-library subsumes the
  narrower "share card" originally scoped here). Do not build a separate
  share screen; F6's confirm sheet is this feature.

### Phase F -- share anything to the library (IN PROGRESS)

Steps F1 (source storage) and F2 (resolver core) are committed and tested.
F3 through F8 remain:

- **F3, SSRF-hardened fetcher**: https only; block private, loopback,
  link-local and cloud-metadata ranges; re-check the resolved address
  AFTER DNS resolution, not before (rebinding attack); cap redirects; cap
  response body size; hard timeout; the function returns only extracted
  fields, never raw fetched bytes. Acceptance: a test table with one entry
  per blocked range asserts each is refused, not merely "usually avoided."
- **F4, exact and keyed extractors**: Twitch clip -> `game_id` ->
  `igdb_id` (zero fuzzy matching); Steam appid -> IGDB `external_games`;
  YouTube Data API v3 behind a key (fixture-tested until the user creates
  the key -- this is a human-only blocker, do not attempt to obtain a key
  yourself).
- **F5, oEmbed and Open Graph extractors**: TikTok, X, Instagram, Vimeo,
  Reddit via oEmbed; a generic Open Graph / JSON-LD reader for everything
  else (blogs, news sites, forum posts). One extractor for the OG/JSON-LD
  tier, not one per site.
- **F6, confirm sheet**: multi-select, high-confidence matches pre-ticked,
  low-confidence listed but unticked, optional one-tap "recommended by"
  field. NEVER writes to the library silently -- this is a hard rule, not
  a preference; a test must assert that calling the resolver alone, without
  a confirm action, writes zero rows. Files already exist as of the
  interrupted turn: `lib/services/share_intake.dart`,
  `lib/ui/intake/`, `test/intake_sheet_test.dart`,
  `test/share_to_library_test.dart` -- read these before writing new code,
  they are mid-flight, not a clean slate.
- **F7, Android share target**: `text/plain` intent filter; cold start
  (`ACTION_SEND` on a fresh launch) and warm start (`onNewIntent`, since
  `launchMode="singleTop"` is already set) both route to the resolver.
  `AndroidManifest.xml` and `MainActivity.kt` are already modified for
  this as of the interrupted turn -- diff them against git HEAD before
  assuming they are untouched.
- **F8, verification**: `flutter analyze`, full suite, `check.ps1`, then a
  REAL share from the emulator's Chrome (not a unit test standing in for
  it) with a screenshot of the confirm sheet.

**Privacy invariant, enforced by `scripts\check.ps1` rule 10 already**: no
file matching `share*` or `export*` may reference `recommended_by`,
`recommendedBy`, `.channel`, or call `sourcesFor(`. If you touch those
filenames, run the checker before committing, not after.

**AI seam, deliberately not built yet**: an `Interpreter` abstract class
with a `NullInterpreter` implementation is the intended shape for a future
LLM fallback on vague prose with no title. Do not build an LLM-backed
implementation in this loop. The decision to skip AI was made deliberately
(see `docs/DECISIONS.md` and the interrupted-session conversation record) --
do not re-open it. If you find yourself wanting a model to disambiguate
something the deterministic ladder cannot, add it as a logged limitation
in `PROGRESS.md`, not as new code.

### Backend polish (cuts across all phases)

- Every repository write method must be audited for transaction safety and
  correct `ON DELETE CASCADE` behavior. Acceptance: for every table with a
  foreign key, a test deletes the parent and asserts the child row's fate
  matches the declared `ON DELETE` clause (`CASCADE` rows vanish,
  `RESTRICT` rows block the delete, no orphans either way).
- Schema migrations: `database.dart`'s `_onUpgrade` must handle every
  version transition from 1 to current with a real migration, tested
  against an on-disk database at the OLD version, not only the create
  path. This burned real time once already (`_onUpgrade` threw
  unconditionally after the F1 schema bump) -- do not reintroduce it.

## 3. What is explicitly OUT of scope for this loop

Do not build these even if a cycle's context makes them look tempting:

- iOS. This machine cannot build it (see `docs/CONSTRAINTS.md`).
- The public tree page (a hosted, shareable URL for a tree). Needs backend
  infrastructure that does not exist. Stays in `docs/BUILD-PLAN.md` as a
  post-submission item.
- Any LLM-backed feature. See the AI seam note above.
- Renaming, restructuring, or "cleaning up" files outside the phase you are
  actively working. A loop that reorganizes working code between features
  is spending its budget on risk with no acceptance criterion behind it.
- Anything requiring a human-only blocker you do not have: RevenueCat keys,
  the Supabase/IGDB proxy deploy, a YouTube API key, `layers setup`. Log
  these as blocked in `PROGRESS.md` and build everything around them
  (fixture sources, inert HTTP clients) instead of stopping.

## 4. Design standard: what "polished like Tolan" means, in checkable terms

"Like Tolan" is a reference from earlier UI research, not something to intuit
freshly each cycle. It means specific, nameable properties Tolan's screens have
and a default Flutter/Material screen does not. Below is what that cashes out
to as rules a model without design taste can still verify against a
screenshot. `docs/DESIGN.md` Section 7 ("Motion") and the design tokens in
`app/lib/ui/tokens.dart` are the source of truth for the actual numbers used
in this codebase -- read both before critiquing; do not invent new tokens.

Run the `design-critique` skill against every screen you build or touch, using
this checklist as the standard it critiques against:

1. **No default Material chrome left visible.** No default `AppBar` drop
   shadow with unstyled title text, no default `SnackBar`, no unthemed
   `FloatingActionButton`. Every visible surface uses a color from
   `Tokens.palette`, never a literal hex or a Material default.
2. **Spacing is systematic, not eyeballed.** Every padding/margin value
   traces to a value in `tokens.dart`'s spacing scale. A screenshot showing
   two visually-similar gaps that are NOT the same token is a finding.
3. **One accent color per screen means exactly one thing.** This was a
   real, fixed defect earlier in this project (gold meaning both "harvested"
   and "primary action" on the same screen). Before marking a screen done,
   name what the accent color means on THAT screen and confirm nothing else
   on it is also that color for a different reason.
4. **Status is never color-only.** Every state that matters (harvested vs.
   not, error vs. success, selected vs. not) must be distinguishable by
   shape, icon, or text as well as color. This is an accessibility rule,
   not a style preference -- deuteranopia was the specific failure mode
   found earlier. Acceptance: name the non-color cue for every colored
   status indicator on the screen, or flag it as a finding.
5. **Motion has a stated reason.** Cite the specific interaction in
   `DESIGN.md` Section 7 that governs this transition. "It felt static so I
   added an animation" is not sufficient; find or add the design rule
   first, then implement it.
6. **Empty and error states are designed, not default.** No screen may show
   a blank white/black rectangle or an unstyled `Text('Error: $e')`. Every
   loading, empty, and error state gets the same visual treatment pass as
   the happy path.
7. **Contrast is measured, not assumed.** Any text-on-background pairing
   that is not already an established token combination gets a contrast
   ratio computed (not eyeballed) and must clear 4.5:1 for body text, 3:1
   for large text (WCAG AA). Record the ratio in the critique note.
8. **The screen is judged at real phone proportions.** A desktop-window
   screenshot is not sufficient evidence -- this project already learned
   that lesson once (the tree's vertical composition looked fine at
   1600x900 and used only half the screen at 1179x2556). Screenshot from
   the emulator or a device, never the Windows desktop build, before
   calling a screen's layout done.
9. **Before critiquing, confirm you are seeing the real render path**, not
   a fallback. If a screen has a graceful degradation path (Rive falling
   back to painted primitives is the existing example), check the live
   widget tree first (`dart` MCP `get_widget_tree`) to confirm which path
   rendered. Critiquing the fallback and reporting it as the real thing is
   a wasted cycle.

**Where taste is genuinely required** (is this spacing "premium" enough, does
this shade of gold feel right) -- do not decide it. Log it as a specific,
described finding in `PROGRESS.md` under a "Needs human judgment" heading and
move to the next item. A loop that spends cycles relitigating a subjective
call it cannot resolve is a stuck loop, not a productive one.

## 5. Standing rules that override anything a cycle "figures out fresh"

These are already decided. Do not re-derive them, do not re-open them:

- Never gate collection size or sharing behind the paywall (see
  `DECISIONS.md`).
- `igdbId` is the only identity; never match on title.
- The status vocabulary is frozen -- two independent axes
  (`Ownership`/`Progress`), never a single chain. See the banned-word list
  in `DECISIONS.md`.
- Every enum's `tree` (metaphor) label is presentation-only. Any
  accessibility-facing text (`Semantics` labels, list-view rows) uses
  `label`, never `tree`.
- `timeToBeatSeconds` is seconds; divide by `secondsPerHour` exactly once,
  at the display edge.
- No `git push` to `main` -- ever, from this loop. If work is ready to
  ship, say so in `PROGRESS.md` and stop; a human runs the push.
- Commit after each completed, tested item. Do not batch several items
  into one commit -- a stuck later item should not block committing the
  earlier ones.
- `scripts\check.ps1` must stay green. If you add a rule that turns out to
  be too blunt (a real false positive, not a real violation), fix the
  rule -- do not `check:ignore` around a rule that is actually correct.

## 6. If you get stuck

Two failed attempts at the same acceptance criterion, in a row: stop
attempting variations of the same fix. Write the two attempts and why each
failed at the top of `PROGRESS.md` under a "BLOCKED" heading, and create the
stop file. Do not attempt a third variation unattended -- that is the
threshold this project has already used successfully elsewhere (never
silently retry the same approach more than a couple of times).
