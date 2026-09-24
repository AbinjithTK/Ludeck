# BUILD.md — binding build document

**This file is the contract.** If something is not in here, it does not get built.
If this file and any other instruction disagree, this file wins. Read it fully
before writing code.

Target: Google Play, Android only. Submission deadline 2026-09-30 23:45 PDT,
app must be **fully published** by then, so the real ship date is **2026-09-24**.

---

## 0. GO / NO-GO GATES — answer these before any code

Both are blocking. If either fails, the plan changes, not the dates.

| Gate | Why it blocks | Status |
|---|---|---|
| **G1. Google Play Console account is established (not brand new)** | A new personal developer account must run a closed test with 12 testers for 14 continuous days before production release. That makes shipping by 2026-09-24 impossible. An established or organisation account is exempt. | **PASSED 2026-09-22 — organisation account, exempt** |
| **G2. Layers has an Android SDK** | The Growth Loop category requires the Layers SDK installed and verifiable before judging. No Android SDK means drop that category. | **PASSED 2026-09-22** — `install_growth_measurement` supports 10 platforms and names "Android package name" as an accepted product identity; tracking links write UTM into the Play Store install referrer so they survive the install |

Both gates are clear. Growth Loop (Layers) is reachable and remains the highest-value
category available: 1 credible rival across 1,080 projects, first prize $15,000.

**Sequencing note that follows from the Layers docs:** a store-destination tracking
link is refused until a Play Store URL is on file (`configure_growth_measurement`
sets it), so the loop produces no measurable signal until the app is published.
Judging opens 2026-10-01. Publishing early is therefore worth more than one more
feature, because criterion 4 asks what the signal actually showed.

If G1 fails: the only remaining store is the Samsung Galaxy Store, which needs
commercial-seller onboarding of one to three weeks, so there is no store at all
and the entry becomes ineligible. Confirm G1 first, before anything else.

---

## 1. FROZEN DECISIONS

These cannot be changed after the first Play Console record exists. Fill every
blank in this section before scaffolding.

| Thing | Value | Notes |
|---|---|---|
| Product name | **Ludeck** | *ludus* (play) + *deck*: a collection you also draw one from. Coined, so ownable |
| Package id | **`com.ludeck.android`** | FROZEN 2026-09-22. Permanent. Cannot be renamed, ever |
| RevenueCat entitlement id | `pro` | One entitlement only |
| Play product id — annual | `pro_annual` | |
| Play product id — monthly | `pro_monthly` | |
| Play product id — lifetime | `pro_lifetime` | |
| Single "is pro" resolution point | `data/billing/Entitlements.kt` | Nowhere else may ask |
| On-device database | `ludeck.db` | |

Pricing, decided from RevenueCat's own category data (gaming LTV per payer is
$11.22, the lowest of any category, so do not price against productivity apps):

| Plan | Price | Trial |
|---|---|---|
| Annual (default, badged) | $19.99 | **30 days** |
| Monthly (deliberately unattractive) | $2.99 | none |
| Lifetime | $39.99 | none |

The 30-day trial is not a preference. Trials of 17 to 32 days convert at 42.5%
against 25.5% for four days or fewer. QuestLog ships a 7-day trial; this is a
real edge over it.

---

## 2. TECH STACK, AND WHY

| Layer | Choice | Reason |
|---|---|---|
| App | **Kotlin + Jetpack Compose** | Windows host, single platform, largest agent training corpus, fastest path to visual polish per hour |
| Local store | **Room** | Offline-first, standard, no surprises |
| DI | **Koin** | Less ceremony than Hilt, no kapt/ksp build cost |
| HTTP | **Retrofit + OkHttp** | Most documented; interceptor is where the rate limiter lives |
| Images | **Coil** | Compose-native |
| Backend | **Supabase** (Postgres + Auth + Edge Functions) | One product covers the IGDB proxy, the shared list, and later the coin ledger |
| Public web list | **Next.js on Vercel**, one route | The share target; needs no install, which is the whole point |
| Payments | **RevenueCat Android SDK** + Play Billing | Required by the hackathon; wraps Play Billing |
| Push | **OneSignal Android SDK** | Required by the OneSignal category |
| Growth | **Layers SDK** | Gated on G2 |

**Rejected, with reasons.** Kotlin Multiplatform: its only payoff was the
JetBrains category, which needs an iOS build this machine cannot produce.
Flutter and React Native: cross-platform tax with no second platform to spend it
on, and harder to make beautiful in ten hours. Stripe anything: no Stripe account
available in India, which already removed the Funnel Vision category.

---

## 3. SCOPE

### In (v1, this build)

1. Search and add a game, including **mobile games**
2. Manual platform tagging per owned copy, multi-select
3. Status on each game, from the fixed enum in section 4
4. Collection grid with cover art
5. Search and filter by platform and status
6. **Steam import** — paste vanity URL, pull owned games with playtime and last-played
7. "What to play" wheel with a time filter
8. Mark finished, rate, export a share card image
9. Public read-only web list (the share target)
10. RevenueCat paywall on the insight layer only
11. One OneSignal campaign
12. Layers SDK plus a written growth loop

### Out (app two, or never)

Coins and any paid mechanic. Creator portal. OBS overlay. Polls and roulette
voting. Following, friends, activity feed, taste matching, public profiles.
Quit-point and achievement analysis. Android installed-game detection. Physical
box scanning. Console library sync. Gaming Wrapped. Pile-of-shame value counter.

### Never (each would fail review or lose the entry)

- Any paid outcome decided by chance
- Coins or credits that expire
- `QUERY_ALL_PACKAGES` in the manifest
- Probing URL schemes to inventory installed apps
- Storing or re-hosting a video clip
- Metacritic data, or HowLongToBeat scraping
- The influencer's name, handle or likeness in the app, the listing, the URL or the copy
- Gating collection size or anything social behind the paywall

---

## 4. DATA MODEL — exact spellings, used verbatim everywhere

Two orthogonal axes. A single chain cannot express "I finished it and then sold
it," which is a normal collector state.

```kotlin
enum class Ownership { SPOTTED, OWNED, RELEASED }
enum class Progress  { UNTOUCHED, INSTALLED, PLAYING, FINISHED, ABANDONED }
enum class Form      { DIGITAL, PHYSICAL }
enum class Acquired  { BOUGHT, SUBSCRIPTION, GIFT, BUNDLE, FREE }
```

Do not invent `want_to_play`, `wantToPlay`, `backlog`, `completed`, `beaten` or
`dropped`. The five Progress values above are the only ones.

`SPOTTED` exists because the judged tie-break criterion is saving a game at
**discovery**, which happens before ownership. `ABANDONED` exists because
abandoning is not finishing.

Ownership is a **set of copies**, not a field, because people own the same game
on more than one platform:

```kotlin
data class Game(         // one row per IGDB id, never duplicated
  val igdbId: Long,      // THE ONLY identity. Never match on title
  val title: String,
  val coverUrl: String?,
  val releaseYear: Int?,
  val timeToBeatSeconds: Int?,   // SECONDS. See section 6
)

data class Copy(
  val igdbId: Long,
  val platform: String,  // free text from a fixed list, e.g. "Steam", "PS5", "iOS"
  val form: Form,
  val acquired: Acquired,
  val pricePaidMinor: Int?,
)

data class Entry(        // the user's relationship to a game
  val igdbId: Long,
  val ownership: Ownership,
  val progress: Progress,
  val rating: Int?,      // 1..10 or null
  val note: String?,
  val lastPlayedAt: Long?,   // from Steam rtime_last_played when available
  val shelved: Boolean,      // display flag; never delete a row
)
```

`shelved` replaces delete. Deleting a collection row is not a feature.

---

## 5. DESIGN PHASE

### Tokens — one file, `ui/theme/Tokens.kt`, and nothing hardcodes a value

```
Colour       max 6 values total: bg, surface, text, textDim, accent, danger
Type scale   4 sizes only: 28 / 20 / 15 / 13
Spacing      4 / 8 / 12 / 16 / 24 / 32 only
Radius       2 values only
Elevation    1 rule only
Motion       140ms enter, 100ms exit, one easing
```

Header comment must read: "No new values. If you need a value that is not here,
change this file and say why in the commit."

The generated look comes from adding decoration. The token cap is how the agent
is prevented from adding it.

### Screens — six, and no more

1. **Shelf** (home) — the grid. This is the hero screen
2. **Search / add**
3. **Game detail** — copies, status, rating, note
4. **Steam import**
5. **Wheel**
6. **Paywall**

### States every screen must implement

Empty, first-run, loading, error, offline, partial. The cold-start empty shelf is
this category's specific failure mode: an empty collection reads as a broken app
to whoever opens it at judging. It gets real copy and a single obvious action.

### Seed fixture — 30 real games

Real IGDB ids and real cover art. Must deliberately include: one very long title,
one with no cover art, one 200-hour RPG next to a 2-hour indie, and two games
owned on two platforms each. Placeholder data hides every layout bug and looks
poor on camera.

---

## 6. EXTERNAL API CONTRACTS

Every constraint here has been verified. Violating one produces a silent bug, not
an obvious one.

### IGDB (primary metadata)

- Auth: Twitch OAuth2 **client credentials**. Token lasts ~60 days and an app may
  hold at most **25 active tokens** — cache it, never mint per request
- **Rate limit: 4 requests/second, 8 concurrent.** Enforced in one OkHttp
  interceptor, and there is a test that proves it
- **No CORS.** A direct client call leaks the token and fails. All IGDB traffic
  goes through the Supabase Edge Function proxy. There is exactly one call site
- `game_time_to_beats` returns **SECONDS**, not hours. Fields: `hastily`,
  `normally`, `completely`, `count`. Divide by 3600 exactly once, in the mapper
- Commercial use requires a free partnership via partner@igdb.com, and a
  **user-facing IGDB attribution in a static location** (not a changelog)
- Mobile coverage is IGDB's weakest area. Expect gaps in the mobile long tail

### Steam (the import wedge)

- `IPlayerService/GetOwnedGames` with `include_appinfo=1&include_played_free_games=1`
- Needs a free Web API key and the user's **game details set to Public**. A
  private profile returns empty, which must be handled as its own error state
  with a real instruction, not a blank list
- Returns `appid`, `name`, `playtime_forever`, `playtime_2weeks`,
  `rtime_last_played`
- `rtime_last_played` is what powers the OneSignal campaign and the ABANDONED
  state without asking the user anything
- ~100,000 calls/day per key

### Apple iTunes Search API (mobile-game gap filler only)

- No key required. `entity=software`
- **~20 calls/minute, IP-based.** Use only when IGDB returns nothing

### Does not exist — do not attempt

No official API for PlayStation, Xbox, Epic, GOG, EA, Ubisoft, Battle.net or
Nintendo libraries. No Google Play metadata API. No source for Game Pass, PS
Plus, Apple Arcade, Netflix Games or Play Pass availability.

---

## 7. THE PLAN

Capacity is measured, not assumed: Sunday 3.5, Monday 3.0, Tuesday 7.0,
Wednesday 10.0, Thursday 13.5 pomodoros. Thursday is the strongest day and is
therefore submission day, not a build day.

### Day 0 — Sunday 20th (3.5) — decisions only, zero code

1. Answer G1 and G2
2. Fill in every blank in section 1
3. Create the Play Console app record and the three IAP products (they are
   reviewed with the first submission, so they must exist early)
4. Write `ui/theme/Tokens.kt`
5. Write the 8-shot video list: one screen per shot, each naming the exact state
   it must be in. Anything not in a shot does not get built

### Day 1 — Monday 21st (3.0) — the spine

1. Scaffold the Android project, Compose, Room, Koin
2. Encode section 4 verbatim as Kotlin enums and entities
3. Supabase project, and the IGDB Edge Function proxy with the rate limiter
4. Load the 30-game fixture into Room and render the raw grid, unstyled

### Day 2 — Tuesday 22nd (7.0) — the loop

1. Search and add against the proxy
2. Game detail: copies, platform multi-select, status, rating, note
3. Filter by platform and status
4. Steam import screen, including the private-profile error state
5. Style the Shelf to the chosen mockup

### Day 3 — Wednesday 23rd (10.0) — the entry

1. Wheel with the time filter
2. Finish, rate, share-card export
3. RevenueCat paywall, all three products, 30-day trial
4. OneSignal SDK and one campaign built on `rtime_last_played`
5. Layers SDK, if G2 passed
6. Public web list, one Next.js route
7. All six empty and error states

### Day 4 — Thursday 24th (13.5) — ship

1. Icon 1024x1024
2. Screenshots at **1179x2556, no device frames** (a submission requirement)
3. Record and cut the 90-second video, under two minutes, uploaded public to
   YouTube or Vimeo
4. Upload to Play, submit for review
5. Devpost submission, all six category answers (section 8)

---

## 8. SUBMISSION CHECKLIST

Global requirements, all mandatory: app fully published on a supported store;
**first public release must fall inside the submission window**; RevenueCat SDK
powering at least one purchase; demo video under two minutes, public on YouTube
or Vimeo; 1024x1024 icon; at least one 1179x2556 screenshot without a frame;
accessible from the United States; free trial or a judge promo code.

| Category | Extra requirement | Priority |
|---|---|---|
| **Growth Loop (Layers)** | SDK verifiable, plus the loop, signal and learning | **BUILD FOR IT.** 1 credible rival in 1,017 projects, stable across four crawls. Gated on G2 |
| **Gaming (Lewis)** | Describe how it serves that audience | **BUILD FOR IT.** 4 credible rivals, zero new entrants in three crawls, and Steam import is unbuilt by all of them |
| OneSignal | SDK integrated, at least one campaign deployed, App ID supplied | Enter. 23 credible rivals for $25k, so crowded, but the campaign is cheap to deploy |
| Design | Which design elements and animations to look at | Enter only. Playwall is the benchmark and a three-day Compose build will not beat it |
| Grand Prize | Post-launch growth with numbers | Enter only. Shortlisted on revenue during the window, which you will not have |
| ~~HAMM~~ | Monetisation strategy and results | **Moved to app two.** Criterion 2 rewards a diverse mix beyond standard models; with coins cut, this app has one subscription |
| ~~#BuildInPublic~~ | Links to posts tagged #Shipaton | **Moved to app two.** Four days of posting cannot compete with two months, even though audience size does not matter |

Judging note: the **first** criterion in every category is the tie-breaker. For
Lewis that is "Can users quickly save games when they discover them and organise
their backlog," which is why Steam import and fast capture outrank everything
else in this build.

---

## 9. MECHANICAL GUARD

`scripts/check.ps1` must fail the build on any of these. This is the part that
makes the constraints real rather than advisory.

1. A colour literal (`#`, `Color(0x`) anywhere outside `ui/theme/Tokens.kt`
2. `QUERY_ALL_PACKAGES` anywhere in any manifest
3. A status string that is not a member of the section 4 enums
4. An `api.igdb.com` reference outside the Edge Function
5. `timeToBeat` divided by anything other than 3600
6. A Supabase service-role or RevenueCat secret key string in the app source

Two real tests, because these cannot be eyeballed:

- the IGDB client cannot exceed 4 requests per second
- a Room migration never drops a user row
