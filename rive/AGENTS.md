# Ludeck Rive UI

Rive CLI source for Ludeck's animated screens and components. RML text in,
`build/ludeck_ui.riv` out. No Rive account is needed to build or preview.

RML and the Rive CLI postdate model training data. Read `rive docs <topic>`
and `rive schema <Type>` before writing anything; never guess a type or
property name. `_docs/` holds a local copy of the topics (gitignored,
regenerate with `rive docs <topic>`).

## What is here

| Artboard | File | Id prefix | Drives |
|---|---|---|---|
| (shared) | `assets.rml` | `0:` | Inter font, component registry |
| LoadingDisc | `components/loading_disc.rml` | `1:` | nothing; loops. Host pauses it |
| PrimaryButton | `components/primary_button.rml` | `2:` | VM `PrimaryButton`: `hover`, `down`, `label` |
| GameCard | `components/game_card.rml` | `3:` | VM `GameCard`: `title`, `meta`, `coverLoaded` |
| SearchLoading | `screens/search_loading.rml` | `4:` | nothing; loops |
| TreeDiscovery | `tree/scene.rml` (GENERATED, own project) | `5:` | VM `TreeDiscovery`: `found`, `selected`, `cover1`..`cover6`, `rustle` |

Every `.rml` compiles as ONE document, so ids must be unique across files.
A new artboard takes the next free prefix (`5:`) and a row in this table.

## Rules

- **Colours come from `app/lib/ui/tokens.dart`.** Copy the ARGB value and name
  the token in a comment. Never invent a colour here that the app does not have.
- **Timing comes from `Tokens.motion`.** press 100ms, swap 200ms, grow 260ms.
  `LinearAnimation.duration` is FRAMES at 60fps (260ms = 16), but
  `StateTransition.duration` is MILLISECONDS.
- **Easing:** strong ease-out `CubicEaseInterpolator x1=0.23 y1=1 x2=0.32 y2=1`
  for entrances, `0.77 0 0.175 1` for on-screen moves, `linear` for loops.
  A `cubic` keyframe with no interpolator child eases nothing.
- **Rotation is radians** (one turn = 6.2831855).
- **Draw order is front to back:** the first shape declared paints on top.
- **Rectangles are centred by default** (origin 0.5). For top-left placement
  set `originX="0" originY="0"`.
- **State via view-model booleans**, not deprecated state-machine inputs. One
  hold-key animation per state; the transition `duration` is the cross-fade.
- **Every artboard needs a state machine**, or binds and listeners are inert
  in the previewer.
- **A nested artboard must be a component:** `isComponent="true"` on it and a
  `<ComponentAsset>` in `assets.rml`.
- **No Luau scripts.** Local builds carry unsigned scripts, which runtimes
  reject. Everything here is plain RML.
- **Reduced motion is the host's job:** pause the state machine or the
  NestedArtboard. Nothing here reads the OS setting.

## Commands (run in this folder)

```powershell
$rive = "$env:USERPROFILE\.rive\bin\rive.exe"
& $rive . --verify                                  # compiles?
& $rive inspect . --summary                         # problems must be []
& $rive . --artboard=GameCard --screenshot=build/card.png --advance=30
& $rive . --artboard=GameCard --data=coverLoaded=true --screenshot=build/loaded.png --advance=30
& $rive . --artboard=PrimaryButton --advance=1 --pointer=down@140,32 --advance=20 --screenshot=build/press.png
& $rive .                                           # live preview window (does not exit)
& $rive . --once                                    # writes build/ludeck_ui.riv
```

A clean verify proves names, not appearance. After every edit: `inspect` for
problems, then screenshot and LOOK. Probe a bind with an unmistakable value
(`--data=label=BOUND-PROBE`); if the literal stays, the bind is dead.
Only `--once`/`--screenshot` rewrite the `.riv`; `--verify` does not.

## TreeDiscovery (the game-discovery moment)

`tree/` is its OWN Rive project (`tree/rive.yaml`), so the app's file does not
carry the component library's 880KB font. `tree/scene.rml` is GENERATED:
never hand-edit it; edit the inputs and run `python tree/build_tree.py`.

Ship a change to the app:
```powershell
python rive/tree/build_tree.py
& $rive rive/tree --once
Copy-Item rive/tree/build/tree_discovery.riv app/assets/rive/tree_discovery.riv
```
The app side is `app/lib/ui/add/discovery_tree.dart`, shown above the Add
screen's results.

- `tree/source/tree-demo.riv` is the designer's tree (runtime .riv). The CLI
  cannot import a .riv, so `tool/riv_decode.py` reads the binary and
  `tool/riv_to_rml.py` writes RML. `tool/dump_schema.py` refreshes the
  type/property table they use after a CLI update.
- `tree/build_tree.py` re-frames it to 412x732 on the sky, and turns its old
  number input into view-model `found` through a converter chain
  (0..6 -> growth 20..100, eased 0.9s).
- `tree/discovery.py` holds everything added on top: card geometry and
  placement, the pop / idle / select / rustle timelines, the state-machine
  layers and listeners. Tune values there.
- `tree/shots.py` renders states to a contact sheet;
  `tree/measure.py` (on a `--debug` build) measures canopy and cluster
  targets per growth level.

Host contract:
- set `grown` 0..6 for the tree's size and ONLY EVER RAISE IT (DECISIONS.md:
  the metaphor never shrinks). The app enforces this with `nextGrown` in
  `discovery_tree.dart`, which is unit-tested.
- set `found` 0..6 for how many cards hang. Card `found` pops (staggered if
  several arrive at once). Lowering it hides cards, never the tree, so a new
  result set resets `found` to 0 and back up to re-pop its cards.
- read `selected` (-1 none, 0..5 = card). Tapping a card sets it; tapping
  the sky or the canopy clears it. Tapping the canopy also rustles the tree.
- set `cover1`..`cover6` to 240x320 images (runtime image property).
- reduced motion: render the settled state (advance past ~2s before first
  paint) or skip the moment; nothing in the file reads the OS setting.

## Shipping into the app

`package:rive` 0.14.11 is back in the app (pinned exact), for TreeDiscovery.
Rules learned wiring it:
- Load the file yourself (`rv.File.asset` in a try/catch) and pass
  `FileLoader.fromFile` to `RiveWidgetBuilder`. The builder's own asset load
  surfaces a failure as an unhandled async error, which fails widget tests
  (the headless host has no Rive native library) instead of degrading.
- Degrade to `SizedBox.shrink()` on failure; the Rive layer must never be
  the only way to reach content.

The component library (`build/ludeck_ui.riv`) is not shipped: ~880KB, almost
all of it Inter. Subset the font before shipping any of it.
