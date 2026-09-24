# UI references

51 screens pulled from Mobbin on 24 September 2026, staged in `uireferences/`.
`uireferences/manifest.json` is authoritative: it carries the Mobbin URL and a
written rationale for every screen. This file is the index and the reading order,
not a copy of it.

Two apps, chosen for different reasons:

- **Tolan** answers "how does a living scene hold a whole screen and still let the
  interface work". Layout, camera, placement, celebration.
- **Hypelist** answers "how does a collection get authored, shared and visited".
  Rows, sections, sharing, profile.

## One tension to settle before using these

Every Tolan reference is a real 3D scene. Ludeck's tree is **not** 3D:
`docs/DESIGN.md` section 3 fixes rendering as `CustomPainter`, and
`docs/CONSTRAINTS.md` ranks 3D last, with the reasons.

So take the **composition and the interaction** from Tolan and leave the rendering.
A pulled-back camera, chrome at the edges, a placement ring, a celebration beat: all
of those work in 2D. Perspective, orbit and dolly do not, and chasing them is how the
next four days disappear.

Note also that `manifest.json` describes Ludeck as having "a 3D navigable tree home
screen". That phrase predates nothing and settles nothing; `docs/DECISIONS.md` and
`docs/DESIGN.md` win.

## Read these six first

| Screen | What it settles |
|---|---|
| `tolan/home/01-world-character-collapsed-ui.png` | The core tree-screen layout. Scene owns the middle, all chrome at the edges, a chevron collapses the card stack. |
| `tolan/world/01-object-placement-ring.png` | A placement ring on the ground, a rotate handle, Done top-right, and an inventory tray of owned items along the bottom. This is how a saved game becomes a fruit on a chosen branch. |
| `hypelist/list/03-status-sections-playing-shelved.png` | Collapsible, user-named status sections. Maps one to one onto user-named branches. |
| `hypelist/share/01-make-public-to-share.png` | A Private/Public segmented control with the consequence of each written in plain language, then "Save and share". Consent before sharing. |
| `hypelist/share/03-share-story-card.png` | A generated, swipeable story card carrying the cover and a sample item, with destinations beneath. This is the shareable artifact. |
| `hypelist/list/01-empty-state-game-bucket-list.png` | The empty state, with a drawn arrow pointing at the add button. |

## What this changes about the plan

**The header has to float.** Tolan pushes every control to the screen edge so the
scene owns the middle. Ludeck currently reserves a fixed strip about 130px tall at
the top, which is why the tree reads as a diagram in a box. Floating the status line
over the canvas is a small change with a large effect, and it is item 11 in
`docs/PLAN.md`.

**Placement is a better interaction than filtering.** `tree_view.dart` currently
filters when you tap a branch. The Tolan world-edit references describe something
better and more ownable: a newly captured game arrives unplaced, and you put it on a
branch you choose. That is also the answer to "what do I do with a game I just
saved", which the current build has no answer to.

**The share flow is the growth loop, and it is fully specified here.** Seven screens
cover consent, collaborators, the story card, a QR code, the copied-link toast, and
the create flow. `docs/COMPETITION.md` records that zero of ten gaming rivals have a
public shareable page, and that the same artifact is the Layers surface. There is now
no design work left blocking it, only build work.

**Completion should not remove the row.** `hypelist/list/05-checked-off-strikethrough.png`
keeps a finished item in place with a filled checkbox and a struck-through title.
That is the same principle as the two-axis model in `docs/DECISIONS.md`: finishing
something is a record, not a deletion.

## Folder map

### `tolan/home/` (11 screens)

The tree screen. 01 is the baseline layout. 02 floats a card over the scene with page
dots, which is how "latest saved game" surfaces without leaving the tree. 03 shows the
zoom range a navigation gesture should cover. 06 zooms all the way out so the world
becomes a small object with orbit rings, which is the model for a whole-tree overview
or for switching between trees. 08 is the add-a-game entry point: a plus expands into
a short stack of pills and morphs to a close icon. 09 layers a conversation over the
live scene with no modal, which is how a detail flow keeps the tree present. 10 is the
celebration beat for a harvest, with the scene dimmed and blurred behind.

### `tolan/world/` (4 screens)

The placement mechanic, and the most transferable group in the set. 01 is the
placement ring and inventory tray. 02 shows a placed object selected, with confirm,
delete, rotate and a four-way move puck arranged around it in world space. 03 shows
the scene reading as inhabited once objects accumulate, which is the payoff as a tree
fills. 04 renders the profile as the world itself, with an XP bar, a level chip and
category cards beneath.

### `tolan/customize/` (4 screens)

A live preview above, a tab strip and swatch grid below, active option ring-selected.
The template if tree species, bark, foliage or season ever become customisable. Note
02's grey silhouette thumbnails, which is how to offer shape choices cheaply.

### `tolan/onboarding/` (3 screens)

The "meet your thing" opener. 02 is the one that matters: a serif name, trait chips, a
descriptive line and a floating call to action. That is the template for naming and
revealing a freshly planted tree.

### `hypelist/list/` (10 screens)

The list view, which is `docs/PLAN.md` item 6 and the accessible path. 01 empty state.
02 the row anatomy: cover thumbnail, title, expand chevron, platform line, star
rating, overflow. 03 collapsible user-named sections. 04 multi-select for bulk moves.
05 completion without removal. 06 the sectioned-versus-flat toggle. 07 "NEW" ribbons
on freshly added rows, which is exactly the "saved but not yet placed" state. 08 the
full authoring surface. 09 the read-only visitor view of someone else's list, where
rows offer save instead of checkboxes.

### `hypelist/share/` (7 screens)

The growth loop, start to finish. Read in file order; they are already in flow order.

### `hypelist/discover/` (11 screens)

Browse and detail. 01 is the list card anatomy and the unit of sharing. 09 is the game
detail page with Info and Community tabs and a save pill pinned over the key art. 10 is
"item also added in", which turns one game into a discovery hub and is called out in the
manifest as a differentiator worth copying. 11 shows how platform-aware metadata is
presented compactly in a recommendation row.

### `hypelist/profile/` (1 screen)

The profile shelf, with a long-press menu offering Edit, Share, Pin to Profile, Folder
Options and Delete. Ludeck's equivalent puts the tree where the avatar is.

## Provenance

Mobbin image URLs expire roughly 30 days after issue, so the PNGs in `uireferences/`
are the durable copy and the `url` field in the manifest will rot. The `mobbin` field
is the stable link to cite.
