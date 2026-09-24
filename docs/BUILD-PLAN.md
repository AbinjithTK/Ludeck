# Build plan: full app, backend and business logic

Written 2026-09-24. Everything here is checked against the live Devpost record for
`revenuecat-shipaton-2026`, fetched 2026-09-24T10:29Z, not against memory.

This document supersedes the ordering in `PLAN.md`. Read `DECISIONS.md` first for the
frozen vocabulary, because several invariants below depend on it.

## The clock, exactly

| Fact | Value |
|---|---|
| Submissions close | 2026-10-01 06:45 UTC |
| First public release must fall between | 2026-08-01 and 2026-09-30 |
| Winners announced | 2026-10-21 16:00 UTC |
| Time left at time of writing | 6 days 20 hours |

The release deadline is a day earlier than the submission deadline. The app has to be
live on a store by **30 September**, not the 1st.

## Three corrections to our own documents

These were found by reading the judging criteria rather than trusting the notes.

### 1. Ratings were cut, and the judges ask for them by name

The Gaming criterion reads, word for word:

> Build a gaming bucket list where players can easily save, organize, complete, rate,
> and share the games they want to play.

`FEATURES.md` lists ratings as cut, on the grounds that they are a third axis.
That reasoning was sound as product design and wrong as strategy: rating is one of
five named verbs in the category we are most invested in. `Entry.rating` already
exists in `models.dart` as `int?` and is unused.

**Ratings are back in v1.** They stay off the tree. A rating is a property of the
harvest, not a status, so it is only ever asked for after a game is finished, and it
never affects ripeness or placement. That keeps the two-axis invariant intact while
satisfying the criterion.

### 2. The word "bucket list" is not the enemy we assumed

`UI-REFERENCES.md` says to take Hypelist's empty state composition but not its
wording, because "Game Bucket List" is the framing Ludeck rejects. That conflates two
different things. A backlog is a list of debts. A bucket list is a list of desires.
Ludeck rejects the first and is a good version of the second.

The writeup should use the judge's own words for what the app is, and then show that
the tree is a better container for a bucket list than a checklist is. Fighting the
phrase loses a criterion for nothing.

### 3. The video limit is 2 minutes, and the screenshot size is exact

- Video: **no more than 2 minutes** of essential footage, on YouTube or Vimeo,
  publicly visible. Judges are not required to watch past two minutes. Our notes said
  90 seconds, which is safely inside this, so aim for 90 to 110 seconds.
- Screenshot: **exactly 1179 by 2556 pixels, with no device frame.** At least one.
  This is a Devpost requirement and is separate from whatever Google Play asks for.
  Our earlier note about Play capping phone screenshots at 2:1 was never verified and
  does not apply to this asset.

## The one risk that can end the submission

Google requires **closed testing with at least 12 testers for 14 continuous days**
before granting production access, for personal developer accounts created after
13 November 2023. Fourteen days is longer than we have.

This is unresolved and it decides the whole store path. It cannot be answered from
this machine. Someone has to open the Play Console and check the account type and
creation date.

Three branches, in order of preference:

**Branch A, the account is exempt.** An organisation account, or a personal account
created before the cutoff. Publish to Google Play as originally planned. Nothing
changes.

**Branch B, the 14 day rule applies.** Publish to the **Samsung Galaxy Store**
instead. Devpost accepts it as a store, in the same sentence as the App Store and
Google Play, and it has no equivalent tester requirement. This is not a downgrade:
there is a whole extra category, **Best App for Galaxy**, that only becomes available
by taking this route. Google Play can still be started in parallel and go live later.

**Branch C, the entrant is a student.** The **Next Gen Award** takes a video and a
public source repository instead of a store listing, and explicitly needs no paid
developer account. If there is an active student email, this removes the entire
publication gate. It is a student-only category, so it does not replace the others,
but it guarantees the submission exists.

Branch B is the safe default and should be started today regardless of the answer,
because a second store listing costs little and removes a single point of failure.

## What the categories actually require

Only one influencer category may be entered, so Gaming is the pick. The same app may
enter any number of non-influencer categories.

| Category | What it needs that we do not have | Cost |
|---|---|---|
| **Required to submit at all** | A working RevenueCat purchase, and the **RevenueCat project ID** pasted into a required form field | Blocking |
| **Gaming**, Mr Lewis Blogs Gaming | save, organize, complete, **rate**, **share**. Rate and share are both missing | 2 days |
| **Growth Loop**, Layers | SDK installed, one experiment, an early measurable signal, and a written account of what was learned | Half a day |
| **Design** | Nothing new. The tree, the parallax and the harvest animation are the entry | Writeup only |
| **HAMM** | A description of the monetization model and why it was chosen | Writeup only |
| **Build in Public** | Public posts documenting the build | Not a code task |
| **Best App for Galaxy** | Only opens if we take Branch B | Comes free with B |

Two notes on the Growth Loop category, which remains the best expected value in the
event at two entrants:

The form field spells out exactly what is wanted, and ends with "a few sentences for
each part are sufficient". It does **not** need weeks of accumulated data. It needs
the SDK installed, a hypothesis, a surface, and an early response. That is achievable
inside six days, which is the reason so few entries have attempted it.

Grand Prize asks for post-launch growth numbers. We will not have them. The field is
optional, so leaving it blank costs nothing and we should not distort the plan chasing
it.

Free trial or promo code is required so judges can reach the premium features. The
30 day trial on the annual product already satisfies this, and is less work than
issuing and tracking promo codes.

## Architecture for the full app

`main.dart` is currently 276 lines that hold the repository, the collection, and every
handler. That is fine for one screen and will not survive five. The refactor below is
the smallest structure that carries the remaining work.

### State

No code generation is available on this toolchain. The chain was diagnosed and
recorded in `CONSTRAINTS.md`: Flutter 3.38.9 pins `meta 1.17.0`, which caps
`analyzer`, which caps `build_runner`, which calls `dart compile`, which Dart 3.10.8
refuses. That rules out `freezed`, `riverpod_generator` and anything similar.

Use **`provider`** with plain `ChangeNotifier`. One dependency, no generation, and
`context.select` prevents the whole tree rebuilding when one fruit changes. A single
hand rolled `InheritedNotifier` would also work but gives up `select`, which matters
on a canvas that repaints.

```
LudeckStore extends ChangeNotifier
  the loaded collection, the branches, the current filter
  every mutation goes to a service, then re-reads, then notifies
```

The store never contains SQL and never contains a RevenueCat call.

### Services

Five, each with one job. The UI talks to these and to nothing else.

```
CollectionService   the tree. add, harvest, rate, shelve, place, unplace
EntitlementService  the single point that answers "is this user pro"
CatalogService      IGDB search and lookup, through the proxy, with a local cache
ShareService        render the share card, hand it to the OS, publish the public page
AnalyticsService    Layers events, and nothing else calls Layers directly
```

`EntitlementService` exists because of a rule already in `DECISIONS.md`: no screen
queries the purchase SDK directly. One class owns it, exposes a plain boolean and a
stream, and is the only file that imports the RevenueCat package. This is also what
makes the paywall testable without a store connection.

### Backend

Supabase, and only two things live in it.

**The IGDB proxy.** Already written and **not deployed**. This is why cover art
currently renders as empty surfaces. That is not an edge case, it is the present
state, and it makes the app look broken in a screenshot. Deploying it is near the top
of the list. IGDB has no CORS, so a server side proxy is not optional. The limits are
4 requests per second and 8 concurrent, attribution is mandatory, and
`game_time_to_beats` returns **seconds**, which must be divided by 3600 exactly once
through `secondsPerHour`.

**The public tree page.** A read only page that renders somebody's tree from a share
token. Zero of the ten tracked rivals have anything like it. It is simultaneously the
Gaming criterion's "share", the Growth Loop category's measurable surface, and the
only genuinely unoccupied position we found in a corpus of 1,286 projects. It earns
its place three times over, which is why it is not cut despite the deadline.

Auth is anonymous Supabase sessions. A public page must be readable with no login, and
nothing in v1 needs an identity beyond a device.

### Business logic that must be pure and tested

These go in plain Dart functions with no Flutter imports, so they are cheap to test
and cannot drift into the UI.

- **Harvested.** `progress == finished`, and the only status the tree shows. Ripeness
  was removed on 2026-09-24; see `DECISIONS.md` for why.
- **The pick.** What to play tonight, given time available and which devices are to
  hand. This is the question the product exists to answer.
- **Season rollup.** Seasons, not streaks. A season that ends badly is still a
  season. Nothing withers and nothing nags.
- **Entitlement gating.** See the next section.
- **Rating rollup.** Average and distribution across harvested games.

### What is free and what is paid

The rule from `DECISIONS.md` is that collection size and sharing are **never** gated.
QuestLog gates at 15 games and Cibby at 10, and both are worse products for it. The
paywall sits on the insight layer.

Free, with no limit: every game, every branch, the tree, harvesting, rating, the share
card, and the public page.

Pro, entitlement `pro`: the reasoned pick with filters for time, device and mood.
Season summaries. Spend and ownership analysis across platforms. Time to clear
projections.

Products stay as frozen: `pro_annual` at 19.99 with a 30 day trial as the default,
`pro_monthly` at 2.99, `pro_lifetime` at 39.99.

## The order of work

Sequenced by who we are waiting on, not by what is interesting. Anything involving a
store, a dashboard or a review queue goes first, because those spend calendar time
rather than our time.

### Today, Thursday 24

1. **Answer the Play account question.** Everything else about the store path depends
   on it. Check the account type and creation date in the Play Console.
2. **Create the store record.** Galaxy Store certainly, Google Play as well if Branch
   A holds. `com.ludeck.android` becomes permanent at this moment and can never be
   changed.
3. **Create the three in-app products.** They are reviewed alongside the first
   submission, so they must exist hours before it, not minutes.
4. **RevenueCat dashboard.** Project, entitlement `pro`, the three products attached,
   and copy out the **project ID**, which is a required submission field.
5. **Wire the RevenueCat SDK**, `EntitlementService`, and a paywall screen.
6. **Deploy the IGDB proxy**, so cover art stops being empty rectangles.
7. **`layers setup`.** Free, and it opens the best odds category.
8. **Make the first commit.** `git init` was run and no commit exists. About 169 files
   are staged clean.

### Friday 25, the five Gaming verbs

9. `provider` and the `LudeckStore` refactor, pulling state out of `main.dart`.
10. Search and add, which is **save**. Depends on item 6.
11. Rating on harvest, which is **rate**. The field already exists.
12. Branch create, rename, reorder, and placement, which is **organize**.
13. The list view. This is the accessible path, since a canvas is invisible to a
    screen reader, and it proves the whole data layer with none of the canvas risk.

### Saturday 26, share and the growth loop

14. The share card, rendered and handed to the OS.
15. The public tree page.
16. Capture by share sheet intent, so a game can be added from a store page or a
    video. Two rivals attack this directly and it is a judged tie break.
17. Define the Layers experiment and instrument it, so a signal exists by the 30th.

### Sunday 27, ship it

18. App icon at 1024 by 1024.
19. Screenshots, at least one at exactly 1179 by 2556 with no device frame.
20. Signed release build, uploaded, review started.

### Monday 28 and Tuesday 29, buffer

Review latency is the unknown, so these two days are deliberately not scheduled. Use
them for the video, the writeup, and anything review sends back.

21. The 2 minute video, recorded on a real phone. No emulator boots on this machine,
    so a physical device is a hard submission dependency.
22. The Devpost writeup, plus the per category fields: Gaming, Design, HAMM, Growth
    Loop, and Build in Public. Field median across the corpus is 5,186 characters.

### Wednesday 30, the release deadline

The app must be **live** today. Submit on Devpost once the store URL resolves.

## Things that stay cut

Unchanged from `FEATURES.md`, with the reasons that still hold: cosmetic
customisation, because the palette is six colours on purpose. Anything 3D, deferred by
explicit decision and revisited after submission. AI features. Charts and trending,
because there is no population at launch to trend.

Newly deferred: the whole renderer question. The tree is to become interactive and
procedural, and that is a decision taken after the submission is safe. `Blender 4.2`
is already installed on this machine, which makes a pre rendered turntable the
cheapest path to real depth when the time comes.

## The thing worth repeating

Three of the four newest rivals in the Gaming lane have no store link and a zero
character writeup. The measured discriminator in this field is not features, it is
publishing. A better app that is not live scores nothing, five times over.
