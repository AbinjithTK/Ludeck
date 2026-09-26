# Research: the Branch Tree redesign

Stage 1 of the tree redesign. Covers what players actually do, what Ludeck does today, the gaps between the two ranked by cost to the user, and the feature list that follows. Written 2026-09-26.

## 1. How players organise games they find

### The grouping axes, most common first

Taken from the sources in section 5. Players group by **the kind of evening they want**, not by what the game is.

1. **Mood or energy**: "brain fried", "cozy", "comfort games", "want a challenge". This is the sort order TAG recommends above alphabetical or recently added ([TAG](https://www.twoaveragegamers.com/what-game-to-play-next/)).
2. **Session length or time commitment**: "30 minutes or less", "Max 3h", "Epic dedication (30h+)", with the length taken from HowLongToBeat ([Grouvee forum](https://discuss.grouvee.com/t/what-categories-do-you-place-games-under/6189)).
3. **A "next up" or "in session" shortlist**: TAG recommends at most 3 games: one long, one short, one new ([TAG](https://www.twoaveragegamers.com/what-game-to-play-next/)).
4. **Social**: "Co-op backlog" kept "to refer to when I discuss gaming plans with friends" ([Grouvee](https://discuss.grouvee.com/t/what-categories-do-you-place-games-under/6189)).
5. **Status**: to complete, complete, never-ending ([How-To Geek](https://www.howtogeek.com/how-to-complete-gaming-backlog/)).
6. **Genre**, and it gets **nested**: "Backlog (RPG)", "Backlog (Puzzle/Indie)" ([Grouvee](https://discuss.grouvee.com/t/what-categories-do-you-place-games-under/6189)).
7. **Interest tier**: numbered categories that rank how badly the player wants each game (same thread).
8. **Series or franchise** (same thread).
9. **Replay value, or "endless" games** that never finish (same thread, plus How-To Geek).
10. **Setting or aesthetic, and yearly challenges**: "Retro style", "Era: Ancient", "Play Along 2020" (same thread).

**Two structural facts matter most for the redesign:**

- **Real users nest their groups.** People build "Backlog (genre)" by hand because their tools are flat. A Playnite feature request asks for a real tree view, and categories there are only filter links ([Playnite #170](https://github.com/JosefNemec/Playnite/issues/170)). **Nested branches are a real, unmet need, not decoration.**
- **One game sits in many groups.** Hades is at once "roguelike", "30 minutes or less" and "co-op with Dev". Steam collections and Playnite categories both allow this, and it is how people think. A game can only be in one branch at a time is the wrong constraint.

### What users get from each tool

| Tool | What users like | What's missing |
|---|---|---|
| Steam collections | Dynamic collections fill themselves by tag or play state ([TheGamer](https://www.thegamer.com/steam-how-to-sort-your-games-into-genres-and-tags/)); "most users underutilize" them ([SteamNavigator](https://www.steamnavigator.com/blog/organize-steam-library-guide)) | Flat, and it only covers games you already own |
| Playnite | Filter presets that combine conditions ([docs](https://api.playnite.link/docs/manual/features/filtersAndFiltersPresets.html)) | "Requires to fill all those categories by hand" ([#3983](https://github.com/JosefNemec/Playnite/issues/3983)); no tree view |
| Backloggd | The journal (dates, statuses) is "the fun" ([ResetEra](https://www.resetera.com/threads/logging-and-reviewing-games-ive-played-on-backloggd-has-become-extremely-fun.440560/)); users asked for friends on the front page ([1.11 update](https://backloggd.medium.com/a-new-home-1-11-update-78428609490c)) | Lists are flat |
| Letterboxd | Lists "on any given topic" are the core social object. **Cloning** a list copies its items with "a reference back to the list from which it was cloned" ([Letterboxd](https://letterboxd.com/journal/cloning/)). Private lists can be shared by link ([Letterboxd](https://letterboxd.com/journal/between-us-private-lists-sharing/)) | — (the benchmark) |
| Spreadsheets / Notion | Total freedom, one sheet per category ([Medium](https://medium.com/teeny-tiny-game-dev-essays/the-game-backlog-f6eb9c8cbe65)) | Manual work, no covers, nothing social |

### The "what do I play tonight" problem

It is the pain point everyone describes. One user takes "three to ten days" to choose a game. Others start a game and quit after 10 minutes. Psychologists call it choice overload ([TAG](https://www.twoaveragegamers.com/what-game-to-play-next/), [GameTalk Therapy](https://crimson-parrotfish-klrl.squarespace.com/blog/paradox-of-play-gaming-backlog-paralysis)). The fixes that work:

- A shortlist of three.
- Choosing by mood: *"what kind of session am I in the mood for?"* is easy to answer.
- A randomizer, "no backsies".
- The five-minute rule.

All four fit a branch tree: **pick a branch (the mood), then get one suggestion from inside it.**

### What makes a shared list spread (Letterboxd model)

- A list has a **name and a point of view** ("Games for when you're sad"), not just a set of items.
- **One tap to take it**: clone it, with credit going back to the curator. The credit is what brings people back to the original.
- **Share by link, even when private**, so the owner decides who sees it.
- Covers in a grid or collage make the list readable in a single glance on a feed.

### UI references (Mobbin)

- **Nested collapsible folders**: [Perplexity](https://mobbin.com/screens/1e0dceb1-b100-4035-bde6-1f49c209c977), [LinkedIn](https://mobbin.com/screens/8013b997-467a-4fce-9054-6bc5078f5181). Standard pattern: a row with a count and a chevron that expands in place.
- **Shared list or collection page** with curator and save/copy action: [corner](https://mobbin.com/screens/45922905-1af0-49d5-a67c-b3820237b927), [Places](https://mobbin.com/screens/d5055b21-fa1f-44cb-b903-7b38e1216cf1), [Posh](https://mobbin.com/screens/0cbc92e2-d9c0-46ae-92b5-630293b011e7).
- **Node and branch canvas**: [Noom](https://mobbin.com/screens/4d8656cc-674e-4449-ba02-812f21d0e7fc), [Givingli](https://mobbin.com/screens/dbd7bb1a-a7d3-44c6-8fa4-5ad61d9c0d85). No mainstream mobile app ships a true mind-map as its main screen. That is both the opening and the risk: it only works if it reads at a glance.
- **Visual direction Abin supplied**: Liven, a "Ready to say goodbye?" screen. A smooth 2D branch in a deep plum colour: tapered, curved strokes that thin toward the tips, small teardrop leaves in a warm amber, a few leaves falling, on a soft gradient. It is flat, calm and poster-like. It's being carried into Stage 2 as the main style candidate. Notes for building it:
  - **What makes it look good:** each branch tapers continuously from thick to thin, curves are smooth (no joints), leaves are small and repeated at many points, and there are only 2 colours.
  - **Can it be built in code?** Much more realistically than the old 3D tree, because it is tapered Bézier strokes plus one leaf shape repeated. A past lesson still applies: this is a *drawn* hero illustration, not a layout driven by data. Code can get close in style, but it won't match hand-drawn quality. Every render has to be checked by eye, not by passing tests.
  - **What has to change for Ludeck:** leaves can't be game covers at this scale, because the image would get cluttered. Keep leaves decorative. Games show as small cover chips at a branch tip, which open into a list when tapped, and each branch carries a text label so the tree still works as navigation.

## 2. Ludeck today: the flows as they exist in code

| Flow | Steps a user takes | Where |
|---|---|---|
| Add by search | FAB, add menu, search, pick → game lands **unplaced** | `app/lib/main.dart` `_onAdd`, `app/lib/ui/add/add_screen.dart` |
| Add by share | Share a link from another app, confirm sheet, game plus source saved | `app/lib/ui/intake/confirm_sheet.dart` |
| Set status | Tap node → status sheet (progress + ownership + branch) | `app/lib/main.dart` status sheet |
| Rate | Only on the transition into Finished | `app/lib/main.dart` `_setProgressAndMaybeRate` |
| Create / rename / reorder / delete branch | Header icon → separate Branches screen | `app/lib/ui/branches/branch_screen.dart` |
| Put a game on a branch | Tap node → status sheet → choose branch. **This is a move**: every other placement is removed | `app/lib/main.dart` `_fileGame` |
| See games by branch | Library tab (grouped list); **the home roadmap ignores branches** | `app/lib/ui/collection/collection_view.dart`, `app/lib/ui/roadmap/roadmap_view.dart` |
| Pick what to play | **No UI**. `choosePick` is fully written and tested but nothing imports it | `app/lib/domain/pick.dart` |
| Share | Publish → roadmap story card + link | `app/lib/ui/publish/` |
| Visit a friend | Read-only tree grouped by branch; "plant" copies **one game** | `app/lib/ui/visit/visit_screen.dart` |
| Onboarding | 4 static pages; skippable | `app/lib/ui/onboarding/onboarding_screen.dart` |

**Data model today** (`app/lib/data/db/database.dart`): `branches(id, name, sort_order, created_at)`, flat, no parent, and `placements(branch_id, igdb_id, position)`, which is many-to-many already. Unplaced games are a supported state.

## 3. Gaps, ranked by cost to the user

**High: breaks the main job**

1. **The main screen doesn't show the user's own organisation.** Home is a roadmap in insertion order, and the branches they named only appear in Library and on a separate screen. The one thing players want to see (their categories) is two taps away. `app/lib/ui/roadmap/roadmap_view.dart` takes `branches` as a parameter and never uses it.
2. **Branches can't nest.** There's no `parent_id`, so "Co-op → Couch / Online" can't be expressed. Players build nesting by hand in every tool they use (section 1).
3. **The UI forces one branch per game even though the data allows many.** `_fileGame` is written as a move to avoid "silent duplication". So the most natural act, "Hades is roguelike AND short", is blocked by the UI and not by the data.
4. **"What do I play tonight?" has no entry point.** Players' biggest pain point is already solved in `choosePick` and never shown.
5. **Filing is buried.** Putting a game in a branch means tap node, open status sheet, find branch. New games land unplaced with no prompt. The Library badge ("10") counts that debt but doesn't say what to do about it.

**Medium: friction and confusion**

6. **Branches are managed away from where they're used.** Create, rename and delete all happen on a separate pushed screen with no preview of the tree.
7. **The social unit is a single game, not a list.** Visit → "plant" copies one game at a time. Letterboxd shows the thing that spreads is a curated, named list you can clone with credit.
8. **The share card shows the whole collection, not a point of view.** A roadmap of everything says less than "My 5 cozy games for rainy nights".
9. **Mixed metaphors.** The header, nav and onboarding were just switched to roadmap words, while statuses still use "Bud", "Harvested" and "Pressed" (`app/lib/data/enums.dart` `tree` labels). The user reads the metaphor before they read the label. A branch tree brings the tree words back naturally, but only if every piece is consistent.
10. **Two counts that may not match.** In the screenshot, the header says 8 games while the Library badge says 10. I haven't verified whether they count different things (placed vs unplaced vs shelved). If they do, neither is labelled.
11. **No undo.** Filing, status changes and branch deletion show a snackbar at most. There's no undo action, and the only safety net is a confirm dialog on delete.
12. **Gestures are hidden.** Long-press to reorder is only taught in onboarding. Nothing on the node itself hints that it can be pressed and held.

**Low: polish**

13. No starter branches. An empty tree asks a new user to invent a taxonomy from nothing.
14. No search or filter inside the collection once it grows.
15. Onboarding is 4 static text pages. It explains features instead of letting the user do the first action.
16. Haptics exist nowhere in the code (`HapticFeedback` isn't used anywhere).

## 4. Feature list for the redesign

Each item traces back to a gap above. Stage numbers match the plan.

**The tree (Stage 3–4)**
- Nested branches: add a `parent_id` on `branches` (migration v4, additive), with depth capped at 2–3 so it stays easy to read.
- Games on many branches: stop `_fileGame` from removing other placements. The status sheet becomes checkboxes, not a single choice.
- Home **is** the tree: trunk, then branches, then sub-branches, then game leaves (cover chips). Branches expand and collapse, the collapsed state is saved, and each branch shows its count.
- An "Unsorted" bud on the trunk holds unplaced games, so nothing is hidden.

**Ease of use (Stage 5)**
- Create a branch where you are: a "+ branch" on any branch, with the name edited in place.
- File by drag: drag a leaf onto a branch. There's also a non-drag path, "Add to branch…", for accessibility, matching the Branches screen's existing Move up/down rule.
- File on capture: after adding a game, show a one-tap row of recent branches.
- Starter branch templates at first run: "Cozy nights", "Short & sweet (< 5h)", "Co-op with friends", "Up next (3)". Each can be edited or deleted.
- **"What should I play?" on every branch**: wire in `choosePick`, scoped to that branch, with its sentence reason and a "not this one" reroll.
- Undo snackbars for file, move, status and delete. Haptics on drop, expand and harvest.
- Coach marks on first real use instead of static onboarding pages.
- One metaphor all the way through: branch, leaf, bud and harvest, with plain labels next to every metaphor word.

**Social (Stage 6)**
- Share **a branch** as a story card: branch name as the title, cover collage, owner handle.
- Clone a branch from a friend's tree into yours, crediting them ("from @dev's Co-op night").
- Existing privacy rule kept: only title, cover, status, rating and branch name are shared.

**Explicitly not in scope:** automatic branches (Steam-style dynamic collections, e.g. "all games under 5h"). It's a strong later feature, but it needs HowLongToBeat data on every game and filter rules. Record it as a follow-up; don't build it now.

## 5. Sources and limits

- Sources: TAG ([what to play next](https://www.twoaveragegamers.com/what-game-to-play-next/)), Grouvee forum ([categories thread](https://discuss.grouvee.com/t/what-categories-do-you-place-games-under/6189)), How-To Geek, Steam guides (TheGamer, SteamNavigator, PC Gamer), Playnite docs and GitHub issues #135 / #170 / #3983, Backloggd dev blog and ResetEra, Letterboxd journal (cloning, private sharing).
- **Not done:** Reddit threads (r/patientgamers, r/backlog) were searched but not fetched. The patterns above come from forums and articles that quote those communities, not from the threads themselves. One Steam guide returned HTTP 429 and wasn't read.
- **The code audit** is based on reading the source listed in section 2, not a run-through on a device. The header vs Library count mismatch (gap 10) is taken from the user's screenshot and not yet traced in code.
