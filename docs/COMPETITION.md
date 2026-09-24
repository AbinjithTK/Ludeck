# Competition

Built from a crawl of the Shipaton 2026 project directory. The corpus grew 886, 939,
981, 1017, 1080, then **1286 projects**. The last crawl added 207 projects in about a
day and a half, roughly 138 a day, which is a closing surge. Zero failures, 185
seconds. Snapshots were archived as `projects.1080.json` and `state.1080.json`.

The corpus itself is about 40 MB and stayed on the original machine. The scripts that
produce these numbers are in `intel/`.

## The gaming lane changed sharply on 24 September

It had been stable at 5 projects and 4 credible rivals across four consecutive
crawls. The latest crawl found **37 candidates with 8 new arrivals**, three of them
serious.

| Rival | Concept | Steam | Social | Store link | Writeup |
|---|---|---|---|---|---|
| QuestLog | Bucket list | yes | yes | **yes** | 2,804 chars |
| **Couch Quest** | "An answer to what to play tonight" | yes | yes | none | **0** |
| Barklog | Share a clip, AI names the game | yes | yes | none | **0** |
| Backlogue | Share-sheet capture, KMP plus OneSignal | yes | yes | none | **0** |
| Cibby | Collection, PSN and Xbox | – | yes | yes | – |

**Couch Quest is close to a clone.** Same positioning and the same stack
(`jetpack-compose, kotlin, material3, revenuecat`). It offers three picks chosen by
time, energy and mood where Ludeck offers one.

## Two earlier assumptions are dead

**Steam import is not a wedge.** Four projects already reference Steam plus import.

**Social is table stakes, not differentiation.** Eight of the ten gaming rivals
mention it. For scale on what social alone is worth: Hypelist has roughly 20,000
monthly installs and **zero monthly revenue**.

## What is genuinely unoccupied

**A public, shareable shelf or tree page. Zero of ten rivals have one.** That artifact
is also the Layers growth-loop surface, so one piece of work serves both the
differentiation and the best-odds prize category.

**The two orthogonal axes.** Barklog uses a single chain. Nobody models a sale that
preserves the completion record, and nobody models multiple copies of one game.

## Publishing is the discriminator, not features

Three of the four new rivals have **no store link and a zero-character writeup**. The
field's writeup median is 5,186 characters (p25 3,779, p75 6,898). QuestLog's 2,804 is
below the 25th percentile.

A finished, published app with a 6,000 character writeup beats a better app that is
still a repository. Spend marginal time on shipping, not on the canvas.

## Prize targets, ranked by assessed win probability

1. **Growth Loop Award (Layers).** 15,000 USD. **2 projects, 1 eligible, out of 1,286.**
   By far the best expected value in the whole event. Entry cost is an SDK install and
   a few sentences. See `docs/CONSTRAINTS.md` for what is verified about Layers.
2. **Gaming (Mr Lewis Blogs Gaming).** 20,000 USD, but the lane went from 4 credible
   rivals to 7 in one day, including a near clone.
3. Free entries expecting nothing: OneSignal (53 projects, 37 eligible, crowded),
   Design, Grand Prize.

**RevenueCat integration is a hard eligibility requirement for every category.**
It does not exist in either codebase yet. Nothing else on this list matters until it
does.

## Design references

Mobbin screens pulled 24 September, for the record:

**Tolan** (character-forward home screen)
[screen](https://mobbin.com/screens/90722ad9-55fe-4a5d-8df2-de63dae1a2ff)

What to take: the character owns the frame and the chrome floats at the edges rather
than occupying a reserved strip. The background is a soft ambient field with depth,
not a flat rectangle. Ludeck currently does the opposite, with a fixed header eating
roughly 130px at the top.

**Hypelist** (list and collection screens)
[1](https://mobbin.com/screens/f6afab12-1007-4196-b345-f86f32c1d6fd)
[2](https://mobbin.com/screens/0b318933-cb44-476a-9ac1-c01b36009957)
[3](https://mobbin.com/screens/894c4e00-522a-4c17-9fcf-bc5c8c52fe09)
[4](https://mobbin.com/screens/d3a34ec4-6a82-4dfb-a153-926f119e395f)
[5](https://mobbin.com/screens/2c0a344d-6e52-4c2e-8788-5d262166b7ac)
[6](https://mobbin.com/screens/d0bb8e4b-7f11-43e5-abd7-d638e26272a9)

What to take: cover art is the unit of meaning and carries the row; title and metadata
sit underneath it and stay quiet. Sections are labelled in plain words and separated by
space, not by rules. Social proof appears inline on the item rather than on its own
screen.

Also named as references by the user: Mobbin generally, Tolan, Hypelist.
