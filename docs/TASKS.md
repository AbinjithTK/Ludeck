# Task list: code, one step at a time

Companion to `BUILD-PLAN.md`. That document says what to build and why. This one is
the work order. Every step is small enough to do without making a decision.

## How to work through this

Do the steps in number order. Do not skip ahead, because later steps import things
earlier steps create.

After **every** step, run both of these from `F:\Abin\Ludeck\app`:

```
flutter analyze
flutter test
```

`flutter analyze` must say "No issues found!". `flutter test` must say all tests
passed. If either fails, fix it before starting the next step. Do not continue with a
red build, because the next step will build on top of the breakage and then two things
are wrong instead of one.

## Rules that apply to every step

These come from `DECISIONS.md`. Breaking one breaks the product, not just the build.

1. **No colour literal anywhere except `lib/ui/tokens.dart`.** No `Color(0xFF...)`, no
   `Colors.red`. Use `Tokens.colour.*`. The palette is exactly six colours.
2. **Ownership and progress are two separate axes.** Never write a function that sets
   both from one argument. Selling a game must never change its progress.
3. **Never match a game on its title.** `igdbId` is the only identity.
4. **`timeToBeatSeconds` is seconds.** Only `Game.hours` divides it. Never divide by
   3600 anywhere else.
5. **Persist enum `name`, never `label` or `tree`.** `switch_` keeps its trailing
   underscore. Do not "fix" it.
6. **Metaphor words are display only.** Nothing in the database says harvest or seed.
   There is no ripeness anywhere, in the database or in the code.
7. **No em dashes, no arrows, no horizontal rules** in any user-visible text.
8. `shelved` replaces delete. Never delete a collection row.

## Phase A: business logic, pure Dart

These files import nothing from Flutter. That is what makes them cheap to test, and it
is why they come first: everything later depends on them and nothing depends on the UI.

Create the folder `lib/domain/`.

### Step A1: extend `Entry.copyWith`

**File:** `lib/data/models.dart`

`Entry.copyWith` currently accepts only `ownership` and `progress`. A rating cannot be
written without this, so it is the first change.

Add three optional named parameters: `rating`, `note`, `shelved`. Keep the existing two.

The tricky part, and the reason this is its own step: `rating` is `int?`, so passing
`null` is ambiguous between "leave it alone" and "clear it". Use a sentinel.

```dart
/// Sentinel meaning "this argument was not supplied", so that passing an
/// explicit null can mean "clear this value" instead of "leave it alone".
const Object _unset = Object();

Entry copyWith({
  Ownership? ownership,
  Progress? progress,
  Object? rating = _unset,
  Object? note = _unset,
  bool? shelved,
}) =>
    Entry(
      igdbId: igdbId,
      ownership: ownership ?? this.ownership,
      progress: progress ?? this.progress,
      rating: rating == _unset ? this.rating : rating as int?,
      note: note == _unset ? this.note : note as String?,
      lastPlayedAt: lastPlayedAt,
      recommendedBy: recommendedBy,
      shelved: shelved ?? this.shelved,
    );
```

**Verify:** analyze clean, tests pass. No behaviour changed yet.

### Step A2: the pick

**File:** `lib/domain/pick.dart` (new)

This answers the question the product exists to answer: what should I play tonight.

```dart
/// A suggestion, with the reason it was chosen. The reason is the product.
class Pick {
  const Pick({required this.item, required this.reason});
  final TreeItem item;
  final String reason;
}

/// Choose one game to play tonight.
///
/// [hoursFree] is how long the player has. [devices] is what is within reach
/// right now; an empty set means no filter.
Pick? choosePick(
  List<TreeItem> items, {
  double? hoursFree,
  Set<Platform> devices = const {},
});
```

Rules, in order. Apply them as filters, then score.

1. Drop anything `shelved`.
2. Drop anything not `Ownership.owned`. You cannot play what you do not have.
3. Drop `Progress.finished` and `Progress.abandoned`.
4. If `devices` is not empty, keep only items with a copy on one of those devices.
5. Prefer `Progress.playing` over `Progress.installed` over `Progress.untouched`.
   Something already in hand is the easiest thing to continue.
6. If `hoursFree` is given, drop anything whose `game.hours` is known and greater
   than `hoursFree`. Items with unknown hours are **kept**, not dropped, because
   unknown is not the same as too long.
7. Among the remainder, prefer the shortest known length. Unknown sorts last.

Return `null` when nothing survives. That is a real state and the UI must handle it.

The reason string must name the actual cause, for example
`Already in hand, about 9 hours left` or `Short enough for tonight`. Never write a
reason that is not true of the item chosen.

**File:** `test/domain/pick_test.dart` (new). Cover at least: nothing owned returns
null, a playing game beats an untouched one, a device filter excludes, unknown hours
survive an `hoursFree` filter, and the shortest known game wins a tie.

**Verify:** analyze clean, tests pass.

### Step A3: the season rollup

**File:** `lib/domain/season.dart` (new)

Seasons, not streaks. This was an explicit rejection of `tolan/home/07`'s streak pill.
A season that went badly is still a season, and nothing here may scold.

```dart
class Season {
  const Season({
    required this.harvested,
    required this.pressed,
    required this.stillGrowing,
    required this.seeds,
  });
  final int harvested;      // progress finished
  final int pressed;        // progress abandoned
  final int stillGrowing;   // owned, not finished, not abandoned
  final int seeds;          // ownership spotted
}

Season summarise(List<TreeItem> items);
```

Count from the whole collection, skipping `shelved`. No dates in v1: a season is the
current state of the tree, not a time window. Do not add a streak, a percentage
complete, or anything that can go down and make the user feel worse.

**File:** `test/domain/season_test.dart` (new).

**Verify:** analyze clean, tests pass.

### Step A4: the rating rollup

**File:** `lib/domain/ratings.dart` (new)

```dart
class RatingSummary {
  const RatingSummary({required this.count, required this.average, required this.distribution});
  final int count;              // how many harvested games carry a rating
  final double? average;        // null when count is 0
  final Map<int, int> distribution;  // rating value to how many
}

RatingSummary summariseRatings(List<TreeItem> items);
```

Only count items that are `isHarvested` **and** have a non-null rating. A rating on an
unfinished game should not exist, but if one does, ignore it rather than crash.

Ratings are 1 to 5 inclusive. Ignore anything outside that range instead of throwing,
because a bad row in the database must not take the screen down.

**File:** `test/domain/ratings_test.dart` (new). Include a case with zero ratings, which
must give `average == null` and not divide by zero.

**Verify:** analyze clean, tests pass.

### Step A5: the entitlement rules

**File:** `lib/domain/entitlement.dart` (new)

Pure logic for what a free user can do. No SDK import. This exists separately from the
service so the rules can be tested with no store connection.

```dart
enum Capability {
  reasonedPick,      // the pick with time, device and mood filters
  seasonSummary,     // the season rollup screen
  spendAnalysis,     // what was spent per platform
  timeToClear,       // projection across the collection
}

/// True when a free user may use this. Everything not listed is free.
bool isFree(Capability c) => false;

bool allows(Capability c, {required bool isPro}) => isPro || isFree(c);
```

Write it so the **default is free**. Only the four capabilities above are paid.
Specifically, and this is a rule not a preference: collection size is never limited,
and sharing is never limited. QuestLog gates at 15 games and Cibby at 10, and both are
worse products for it.

A plain `choosePick` with no filters is **free**. Only the filtered, reasoned version
is paid. The core question the app exists to answer must be answerable without paying.

**File:** `test/domain/entitlement_test.dart` (new). Assert explicitly that adding an
unlimited number of games and sharing are not gated, so a future edit that gates them
fails a test.

**Verify:** analyze clean, tests pass.

## Phase B: repository

### Step B1: write a rating

**File:** `lib/data/repository.dart`

```dart
Future<void> setRating(int igdbId, int? rating);
```

Update only the `rating` column on `entries`. Do not touch ownership or progress in the
same statement. Passing null clears it.

Guard the range: accept null, or 1 to 5. Anything else throws `ArgumentError`, because
a silent clamp hides a bug at the call site.

### Step B2: delete and reorder branches

**File:** `lib/data/repository.dart`

```dart
Future<void> deleteBranch(int id);
Future<void> reorderBranches(List<int> idsInOrder);
```

`deleteBranch` removes the branch row and its `placements` rows. It must **not** delete
any game, any entry, or any copy. A branch is a container. Emptying the container does
not destroy what was in it, and the games simply become unplaced.

`reorderBranches` writes `sortOrder` as the index in the supplied list, in one
transaction so a failure halfway does not leave two branches claiming the same
position.

### Step B3: tests

**File:** `test/repository_test.dart` (extend the existing file)

Add at least these, and make the first one load bearing:

1. Rating a finished game, then selling it, leaves both the rating and
   `Progress.finished` intact. This is the same invariant the existing sale test
   protects, extended to cover the new column.
2. `setRating` with 0 or 6 throws.
3. `setRating(null)` clears an existing rating.
4. `deleteBranch` removes placements but the games still load.
5. `reorderBranches` gives every branch a distinct `sortOrder`.

**Verify:** analyze clean, tests pass.

## Phase C: state

### Step C1: add the dependency

```
cd F:\Abin\Ludeck\app
flutter pub add provider
```

Chosen because there is no code generation on this toolchain. See `CONSTRAINTS.md` for
the exact reason: `meta 1.17.0` caps `analyzer`, which caps `build_runner`, which calls
`dart compile`, which Dart 3.10.8 refuses. That rules out `freezed` and
`riverpod_generator`. `provider` needs no generation and gives `context.select`, which
stops the whole canvas rebuilding when one fruit changes.

### Step C2: the store

**File:** `lib/state/ludeck_store.dart` (new)

```dart
class LudeckStore extends ChangeNotifier {
  LudeckStore(this._repo);
  final Repository _repo;

  List<TreeItem>? get items;     // null means the first read has not finished
  bool get isLoading;
  Object? get error;

  Future<void> load();
  Future<void> setProgress(int igdbId, Progress p);
  Future<void> setOwnership(int igdbId, Ownership o);
  Future<void> setRating(int igdbId, int? rating);
  Future<void> shelve(int igdbId);
}
```

Three rules for this class:

1. `items` is nullable and null means **the first read has not happened yet**. That is
   not the same as an empty collection, and the UI must show different things for the
   two. This is already how `main.dart` behaves and it must not regress.
2. Every mutation does three things in order: call the repository, re-read, then
   `notifyListeners`. Never mutate the in-memory list directly and hope it matches the
   database.
3. No SQL in this file. No RevenueCat in this file.

**File:** `test/state/ludeck_store_test.dart` (new). Use `Repository.openInMemory()`.
Assert that `items` is null before `load()` and non-null after, and that a failed
mutation surfaces on `error` instead of throwing into the widget tree.

### Step C3: wire it into the app

**File:** `lib/main.dart`

Wrap the app in `ChangeNotifierProvider`. Move `_load`, `_setProgress` and
`_setOwnership` out of `_TreeScreenState` and delete them from there. The screen reads
from the store and calls the store.

Keep the status sheet showing **both** axes under their own headings. That was added
deliberately, because showing only progress hid the thing the whole model exists for.

**Verify:** analyze clean, tests pass, then `flutter run -d windows` and confirm the
tree still renders and a status change still persists across a restart.

## Phase D: entitlement

### Step D1: the service, with a fake

**File:** `lib/services/entitlement_service.dart` (new)

This is the only file in the app allowed to import the RevenueCat package, ever. It is
built now with a local fake so every screen that depends on it can be finished before
the store account exists.

```dart
abstract class EntitlementSource {
  Stream<bool> get isPro;
  Future<void> restore();
  Future<bool> purchase(String productId);
}

/// Local, no network. Used until the RevenueCat keys exist, and in every test.
class FakeEntitlementSource implements EntitlementSource { ... }

class EntitlementService {
  EntitlementService(this._source);
  bool get isPro;
  bool allows(Capability c);   // delegates to domain/entitlement.dart
}
```

Do not put pricing strings in this file. Do not let any screen call the source
directly. When the real RevenueCat keys arrive, one new class implements
`EntitlementSource` and nothing else in the app changes. That is the entire point.

### Step D2: the paywall

**File:** `lib/ui/paywall/paywall_screen.dart` (new)

Three products, from `DECISIONS.md` and not to be re-decided: `pro_annual` at 19.99
with a 30 day trial, preselected. `pro_monthly` at 2.99. `pro_lifetime` at 39.99.

The trial matters beyond pricing: Devpost requires either a free trial or a promo code
so judges can reach the premium features, and a trial is less work than issuing codes.

Say plainly what is paid, which is the insight layer. Do not imply the collection is
limited, because it is not, and a paywall that lies about it is worse than no paywall.
Restore must be reachable without a purchase.

**Verify:** analyze clean, tests pass.

## Phase E: the screens that satisfy the Gaming criterion

The criterion asks for save, organize, complete, rate and share. Complete already
works. These steps add the rest.

### Step E1: rate on harvest

**File:** `lib/ui/harvest/rating_sheet.dart` (new)

Shown once, at the moment a game becomes `finished`. Never shown at any other time,
because a rating belongs to the harvest and not to the game.

Five taps, skippable. Skipping is a normal outcome. Do not nag, do not badge, do not
count how many are unrated.

### Step E2: the list view

**File:** `lib/ui/list/list_screen.dart` (new)

This is the accessible path. A canvas is invisible to a screen reader, so without this
the app is unusable for some people and fails an accessibility review. It also proves
the whole data layer with none of the canvas risk.

Sections are the user's own branches, collapsible. Each row shows the title, the
platform, and the rating when there is one. Specified screen by screen in
`USERFLOWS.md` Flow 5 and `UI-REFERENCES.md`.

Every row needs a `Semantics` label that reads correctly out loud. Use the plain
`label`, not the metaphor `tree` word, because "Ripe" makes no sense read aloud
without the picture.

### Step E3: branches

**File:** `lib/ui/branches/branch_screen.dart` (new)

Create, rename, reorder, delete. Deleting asks first and says plainly that the games
are kept. This is **organize** in the criterion.

### Step E4: search and add

**File:** `lib/ui/add/add_screen.dart` (new). This is **save** in the criterion.

Blocked on the IGDB proxy being deployed. Until it is, wire it to `fixtureTree()` as
the source so the screen can be built and tested, and swap the source afterwards. Do
not fake the network layer itself, only its data.

### Step E5: share

Covered in `BUILD-PLAN.md`. The share card and the public tree page. This is the one
genuinely unoccupied position found across 1,286 projects, and it is also the Growth
Loop category's measurable surface.

## Phase F: share anything to the library

Share a link OR plain text to Ludeck from any app and the game lands in the
collection with its source attached. Approved 2026-09-24, deliberately WITHOUT
an AI tier: the deterministic ladder plus a corroboration heuristic covers the
realistic cases, and `Interpreter` is the seam where a model drops in later if
testing shows it is actually needed.

Resolver input is TEXT, not a URL. Pulling links out of that text is the first
pass, not the interface. A share can name several games at once.

### Step F1: source storage `DONE 2026-09-24`

Schema v2. `sources` table, one-to-many from `games`, `ON DELETE CASCADE`.
`url` nullable because shared prose has no link, and SQLite treats NULLs as
distinct in a UNIQUE constraint, so two text recommendations for one game are
correctly two rows while re-sharing one link stays idempotent.

`_onUpgrade` used to throw outright, so the version bump needed a real stepwise
migration keyed by the version it produces. `openLudeckDatabaseAt` exists so
tests run the shipping migration rather than a copy. `kMigrationVersions` exists
so a test catches the version bump with no migration behind it.

`MatchMethod` is stored per source, strongest first: exact, metadata, text,
manual. It decides how far to trust a row and shows which resolver tier is
earning its place once real shares arrive.

The privacy invariant is enforced in `scripts\check.ps1` rule 10 rather than a
test, because the share layer does not exist yet and the rule must fire when
that code is written, not when someone remembers to test it.

### Step F2: resolver core, pure Dart, no network

Text in, a set of distinct candidate games out, each with a `MatchMethod` and a
confidence. URL extraction and canonicalisation first, then prose.

The corroboration heuristic lives here and matters more than it looks: *Control*,
*Journey*, *Inside*, *Limbo* and *Firewatch* are ordinary English words. A title
match in prose only counts when gaming context sits near it (a gaming link in
the same text, or play/played/playing/beat/finished/co-op). Without this the
library fills with games from messages that were about nothing of the kind, and
the user stops trusting it.

Declare `abstract class Interpreter` with a `NullInterpreter` default.

### Step F3: SSRF-hardened fetcher

Step F5 fetches arbitrary user-supplied URLs server-side, which is a hole if
built naively. https only; block private, loopback, link-local and metadata
ranges; re-check the address AFTER DNS resolution to stop rebinding; cap
redirects and body size; hard timeout; return extracted fields only, never the
fetched body. One test per blocked range.

### Step F4: exact and keyed extractors

Twitch clip to `game_id` to `igdb_id` — verified against the Helix reference:
Get Clips returns `game_id`, and Get Games both accepts and returns `igdb_id`,
so this needs no matching at all. Twitch VODs return no game field, so they fall
through to text. Steam store URL to appid via IGDB `external_games`.

YouTube Data API v3 behind a key Abin must create (free, 10k units/day,
`videos.list` costs 1). Fixture-tested until it exists.

### Step F5: oEmbed and Open Graph extractors

TikTok, X, Instagram, Vimeo, Reddit via oEmbed. Then a generic Open Graph and
JSON-LD reader, which is what actually makes this universal: blogs, news, forums,
store pages, anything serving meta tags.

Two findings to re-verify at deploy time. Meta reportedly dropped the token and
App Review requirement for its oEmbed endpoints on 2026-06-15, but Meta's own
docs still show the old text, so confirm with one live call. X oEmbed at
`publish.x.com` answers unauthenticated and returns markup containing the post
text; the v2 read API is paid and the old syndication JSON is gone.

Instagram keeps a permanent manual fallback regardless: Meta's doc says the
endpoint is for embedding, and reading a caption to identify a game stretches
that.

### Step F6: confirm sheet

Multi-select, high-confidence matches pre-ticked and low-confidence ones listed
but unticked. One tap still adds everything, so the feature stays fast, but
NOTHING enters the library unseen. Offers the optional `recommendedBy` field,
which is what that column was always for.

Saving the source is separate from identifying the game: a platform that cannot
be read costs one extra tap, never the feature.

### Step F7: Android share target

`ACTION_SEND` with `text/plain`, which covers a bare link, a link wrapped in
prose, and pure prose in one filter. Cold start and warm start both route to the
resolver. No clipboard watching: Android restricts it and it is not a trade
worth making on a user's behalf.

### Step F8: verification

`flutter analyze`, full suite, `check.ps1`, emulator run, runtime errors read,
screenshots of the resolve-and-add flow.

## What is not in this list

The store record, the in-app products, the RevenueCat dashboard, `layers setup`, the
video and the Devpost writeup are all in `BUILD-PLAN.md` and need a person with
account access. They are the critical path. This list is what can be built while those
are in flight.
