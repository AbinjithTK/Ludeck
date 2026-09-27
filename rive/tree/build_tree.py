"""Build screens/tree_discovery.rml: the imported growing tree + game discovery.

Source of truth is tree/source/tree-demo.riv (the designer's file). This script
  1. decodes it and converts it to RML (tool/riv_decode.py, tool/riv_to_rml.py)
  2. replaces its deprecated number input with a view model, TreeDiscovery:
       grown     0..6   tree size; the host only ever RAISES it
       found     0..6   how many cards hang (host sets it; may reset to 0)
       selected  -1..5  which card the user tapped (the file writes it)
       cover1..6        cover images (host swaps them at runtime)
     `grown` drives the tree through a converter chain: 0..6 -> growth 20..100,
     eased over GROW_SECONDS. Growth and cards are separate so a new result
     set can re-pop its cards without the tree ever shrinking (DECISIONS.md).
  3. re-frames the 500x500 artboard as a 412x732 portrait scene on Ludeck's sky
  4. adds six game cards that hang from the canopy and pop in as `found` rises

Run from anywhere:  python rive/tree/build_tree.py [--debug]
Then:               rive rive/tree --data=grown=6 --data=found=6 ...
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tool"))

import json  # noqa: E402

import riv_decode  # noqa: E402
import riv_to_rml  # noqa: E402

sys.path.insert(0, HERE)
import discovery as D  # noqa: E402

SRC = os.path.join(HERE, "source", "tree-demo.riv")
# The tree is its own Rive project (rive/tree/rive.yaml) so the app ships a
# small .riv without the component library's embedded font.
OUT = os.path.join(HERE, "scene.rml")

W, H = 412, 732
TREE_X, TREE_Y, TREE_SCALE = 180, 668, 0.94

# Headless preview of the app's night sky (orchard_view.dart `_NightSky`),
# same colours as Tokens.cosmos.night / hill*. Never in the shipped file.
HILL_W = 980                 # the ridge is a shallow arc much wider than the screen
PREVIEW_SKY = f'''
        <Shape x="{TREE_X}" y="{TREE_Y + HILL_W * 0.09}" name="PvHill">
            <Ellipse width="{HILL_W}" height="{HILL_W * 0.18}" name="P"/>
            <Fill name="F">
                <LinearGradient startX="0" startY="{-HILL_W * 0.09}" endX="0" endY="60" name="G">
                    <GradientStop colorValue="FF1A1531" position="0"/>
                    <GradientStop colorValue="FF0D0A1C" position="1"/>
                </LinearGradient>
            </Fill>
            <Stroke thickness="1" name="S"><SolidColor colorValue="2EE3A9C6" name="C"/></Stroke>
        </Shape>
        <Shape x="{TREE_X + 10}" y="400" name="PvHalo">
            <Ellipse width="520" height="520" name="P"/>
            <Fill name="F">
                <RadialGradient startX="0" startY="0" endX="260" endY="0" name="G">
                    <GradientStop colorValue="24C77BA6" position="0"/>
                    <GradientStop colorValue="00C77BA6" position="1"/>
                </RadialGradient>
            </Fill>
        </Shape>
        <Shape name="PvSky">
            <Rectangle originX="0" originY="0" width="{W}" height="{H}" name="P"/>
            <Fill name="F">
                <LinearGradient startX="0" startY="0" endX="0" endY="{H}" name="G">
                    <GradientStop colorValue="FF0B0A1C" position="0"/>
                    <GradientStop colorValue="FF171230" position="0.55"/>
                    <GradientStop colorValue="FF2B1F47" position="1"/>
                </LinearGradient>
            </Fill>
        </Shape>'''

GROW_SECONDS = 0.9      # each found game eases the tree up over this long
GROWTH_MIN, GROWTH_MAX = 20, 100

# Bone targets the three leaf clusters follow (runtime index + 100 = RML id).
CENTER, RIGHT, LEFT = "5:1232", "5:1215", "5:1201"

# (cluster, hang-point offset from the cluster target). Order = pop order.
CARDS = [
    (CENTER, (0, 0)),
    (RIGHT, (0, 0)),
    (LEFT, (0, 0)),
    (CENTER, (0, 0)),
    (RIGHT, (0, 0)),
    (LEFT, (0, 0)),
]


def convert(blossom="blossom", wood="plum"):
    doc = riv_decode.decode(SRC)
    schema = json.load(open(os.path.join(ROOT, "tool", "rive_schema.json"),
                            encoding="utf-8"))
    return retint(riv_to_rml.Conv(doc, "5", "TreeDiscovery", schema,
                                  vm="TreeDiscovery").run(), blossom, wood)


# The source art's grass. It becomes the hill's silhouette colour, so the
# tufts read as grass on the ridge instead of a teal strip pasted under it.
GRASS_SRC = "30E1A6"
HILL_TOP = "FF1A1531"   # = Tokens.cosmos.hillTop (app/lib/ui/tokens.dart)


# ---- palettes -------------------------------------------------------------
# Each tree picks a blossom and a wood. The canopy's colour lives in ~40 shades
# across static fills, gradients and 86 keyframed colour tracks (the leaf steps
# ramp it in), and a paint's visibility is not bindable, so a palette cannot be
# switched at runtime inside one file. Each (blossom, wood) pair is baked as its
# own .riv by build_variants.py from this one mapping; the ids MUST match
# TreeBlossom / TreeWood in app/lib/ui/orchard/tree_style.dart.
#
# Blossom: (hue, saturation scale, lightness scale). Applied to the source's
# rose-toned canopy, so every shade keeps its place in the light-to-shadow
# ramp and only the hue family changes. No gold: gold means harvested.
BLOSSOMS = {
    "blossom":  (338, 1.00, 1.00),   # what shipped: soft rose
    "maple":    (14, 1.05, 0.98),    # red-orange autumn
    "jade":     (148, 0.72, 0.96),   # spring green
    "wisteria": (272, 0.74, 1.10),   # lavender
    "frost":    (204, 0.70, 1.06),   # pale ice blue
}
# Wood: (hue, saturation, lightness offset, lightness scale) for bark shades.
WOODS = {
    "plum":  None,                    # what shipped: the source's dark plum
    "oak":   (26, 0.42, 0.06, 1.25),  # warm brown
    "birch": (40, 0.10, 0.34, 1.10),  # pale silver-grey
    "ebony": (236, 0.20, 0.07, 1.05),  # blue-black
}


def _hls(argb):
    import colorsys
    r, g, b = (int(argb[2 + i:4 + i], 16) / 255 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, l, s


def _argb(a, deg, l, s):
    import colorsys
    r, g, b = colorsys.hls_to_rgb((deg % 360) / 360, min(max(l, 0), 1),
                                  min(max(s, 0), 1))
    return a + "".join(f"{round(v * 255):02X}" for v in (r, g, b))


def classify(argb):
    """Which part of the tree a source colour paints: grass, canopy, bark or
    other. Bark is the dark, low-saturation plum; the dark but saturated
    purples are the canopy's own deep shadow and recolour with it."""
    deg, l, s = _hls(argb)
    if 150 <= deg <= 200 and s > 0.25:
        return "grass"
    if not (275 <= deg or deg < 12):
        return "other"
    if l < 0.22:
        return "bark" if s < 0.45 else "canopy"
    return "canopy"


def _tone(argb, blossom="blossom", wood="plum"):
    """Pull the source's neon magentas into a blossom that sits in the violet
    night: saturation capped by lightness, hue moved to the palette's. Bark
    takes the wood; grass becomes the hill's silhouette colour."""
    a = argb[:2]
    kind = classify(argb)
    deg, l, s = _hls(argb)
    if kind == "grass":
        return a + HILL_TOP[2:]
    if kind == "bark":
        w = WOODS[wood]
        if w is None:
            return argb
        hue, sat, lo, ls = w
        return _argb(a, hue, lo + l * ls, sat)
    if kind != "canopy":
        return argb
    hue, ss, ls = BLOSSOMS[blossom]
    src = deg if deg >= 200 else deg + 360
    if l < 0.22:                        # deep canopy shadow: hue only
        if blossom == "blossom":
            return argb                 # exactly what shipped
        return _argb(a, hue + (src - 338) * 0.65, l, s * ss)
    cap = 0.42 + 0.25 * l               # light petals keep more colour
    s = min(s, cap)
    # 65% of the source's spread around the palette hue, so the canopy keeps
    # its shading variety. For "blossom" (338) this is the shipped mapping.
    deg = hue + (src - 338) * 0.65
    l = min(l, 0.70) * 0.96 + 0.02      # nothing brighter than a petal highlight
    return _argb(a, deg, min(l * ls, 0.74), s * ss)


def retint(rml, blossom="blossom", wood="plum"):
    rml = re.sub(r'colorValue="([0-9A-Fa-f]{8})"',
                 lambda m: f'colorValue="{_tone(m.group(1), blossom, wood)}"', rml)
    # Most of the canopy's colour is animated (the leaf steps ramp it), so the
    # keyframes need the same treatment as the static fills.
    return re.sub(r'(<KeyFrameColor [^>]*value=")([0-9A-Fa-f]{8})"',
                  lambda m: f'{m.group(1)}{_tone(m.group(2), blossom, wood)}"', rml)


def debug_markers():
    out = []
    for n, (tid, col) in enumerate([(CENTER, "FFFF0000"), (RIGHT, "FF00FF00"),
                                    (LEFT, "FF00AAFF")]):
        out.append(f'''
        <Node name="Dbg{n}" id="5:{29000 + n}">
            <TranslationConstraint targetId="{tid}" name="Follow"/>
            <Shape name="Dot"><Ellipse width="10" height="10" name="P"/>
                <Fill name="F"><SolidColor colorValue="{col}" name="C"/></Fill></Shape>
        </Node>''')
    return "".join(out)


def build(debug, test_hooks=False, blossom="blossom", wood="plum"):
    rml = convert(blossom, wood)

    # -- view model: the old `input` number becomes `grown` ------------------
    # Growth and cards are separate on purpose. `grown` sets the tree's size
    # and the host only ever raises it (DECISIONS.md: the metaphor never
    # shrinks). `found` shows cards and may drop to 0 to re-pop a new result
    # set, while the tree stays the size it reached.
    rml = rml.replace('<ViewModelPropertyNumber name="input"',
                      '<ViewModelPropertyNumber name="grown"')

    # -- every read of it goes through the growth converter ------------------
    n_binds = rml.count('propertyKey="636"/>')
    rml = rml.replace('propertyKey="636"/>',
                      'propertyKey="636" converterId="5:20001"/>')

    # -- re-frame the artboard ------------------------------------------------
    rml = re.sub(r'(<Artboard [^>]*?)width="500" height="500"',
                 rf'\1width="{W}" height="{H}" x="1300" y="0"', rml, count=1)
    m = re.search(r'<Node [^>]*id="5:101"[^>]*>', rml)
    assert m and 'name="Tree"' in m.group(0), "Tree node not found"
    tag = m.group(0)
    for k, v in (("scaleX", TREE_SCALE), ("scaleY", TREE_SCALE),
                 ("x", TREE_X), ("y", TREE_Y)):
        tag = re.sub(rf' {k}="[^"]*"', f' {k}="{v}"', tag)
    rml = rml.replace(m.group(0), tag, 1)

    # -- front layer (declared first = drawn on top) --------------------------
    front = debug_markers() if debug else ""
    style = '<LayoutComponentStyle name="Artboard Style" id="5:9099"/>'
    assert style in rml
    # The source artboard's own background fill (grey-violet) painted over the
    # app's sky on device once the Sky shape went transparent. Clear it.
    art_bg = 'colorValue="FF4D4C61" id="5:1314"'
    assert art_bg in rml, "source artboard background fill moved"
    rml = rml.replace(art_bg, 'colorValue="00000000" id="5:1314"', 1)
    rml = rml.replace(style, style + front, 1)

    # -- back layer: the sky's HIT AREA only, declared after the tree ---------
    # The app paints the sky, the hill and the glow (orchard_view.dart
    # `_NightSky`) because a phone is taller than the artboard: a sky drawn
    # here stops at the artboard edge and leaves a seam, and on the emulator's
    # renderer this gradient came out in five hard bands. The shape stays,
    # fully transparent, because tapping the sky clears the selection.
    sky = f'''
        <Shape name="Sky" id="5:20100">
            <Rectangle originX="0" originY="0" width="{W}" height="{H}" name="P"/>
            <Fill name="F"><SolidColor colorValue="00000000" name="C"/></Fill>
        </Shape>'''
    if os.environ.get("TREE_PREVIEW_SKY"):
        # Headless renders only: the app's sky, so a render judges the tree
        # against what it will actually stand in.
        sky = PREVIEW_SKY + sky
    first_anim = rml.index("<LinearAnimation")
    rml = rml[:first_anim] + sky.strip() + "\n        " + rml[first_anim:]

    # -- converters: found 0..6 -> growth 20..100, eased ----------------------
    converters = f'''
    <DataConverterGroup name="FoundToGrowth" id="5:20001">
        <DataConverterGroupItem converterId="5:20002"/>
        <DataConverterGroupItem converterId="5:20003"/>
    </DataConverterGroup>
    <DataConverterRangeMapper minInput="0" maxInput="{D.SLOTS}" minOutput="{GROWTH_MIN}" maxOutput="{GROWTH_MAX}"
                              clampLower="true" clampUpper="true" name="FoundToGrowthRange" id="5:20002"/>
    <DataConverterInterpolator interpolationType="cubic" duration="{GROW_SECONDS}" name="GrowEase" id="5:20003">
        <CubicEaseInterpolator x1="0.23" y1="1" x2="0.32" y2="1"/>
    </DataConverterInterpolator>
'''
    rml = rml.replace("</Rive>", converters + D.image_assets() + "\n</Rive>")

    if not debug:
        rml = splice_discovery(rml, test_hooks)
    return rml, n_binds


def insert_after(rml, anchor, text):
    i = rml.index(anchor)
    return rml[:i + len(anchor)] + text + rml[i + len(anchor):]


def close_of(rml, open_anchor, close_tag):
    i = rml.index(open_anchor)
    return rml.index(close_tag, i)


def splice_discovery(rml, test_hooks=False):
    hook_comp, hook_lst = D.test_hooks() if test_hooks else ("", "")
    # cards + canopy tap target: front of everything, cards above the tap area
    style = '<LayoutComponentStyle name="Artboard Style" id="5:9099"/>'
    rml = insert_after(rml, style, hook_comp + D.card_components() + D.planting_components() + D.canopy_hit())

    # card placement rides the tree's growth blend poses
    kin, kout = D.growth_keys()
    for anim_id, keys in ((D.ANIM_IN, kin), (D.ANIM_OUT, kout)):
        j = close_of(rml, f'id="{anim_id}">', "</LinearAnimation>")
        rml = rml[:j] + keys + rml[j:]

    # new timelines, before the state machine
    j = rml.index("<StateMachine ")
    rml = rml[:j] + (D.card_animations() + D.tree_animations()).strip() + "\n        " + rml[j:]

    # layers + listeners at the end of the state machine
    j = rml.index("</StateMachine>")
    rml = rml[:j] + D.card_layers() + D.tree_layers() + D.listeners() + hook_lst + "\n        " + rml[j:]

    # view model
    grown_prop = f'<ViewModelPropertyNumber name="grown" id="{D.P_GROWN}"/>'
    rml = insert_after(rml, grown_prop, D.vm_properties())
    grown_val = f'viewModelPropertyId="{D.P_GROWN}"/>'
    rml = insert_after(rml, grown_val, D.vm_values())
    return rml


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--test-hooks", action="store_true",
                    help="add a corner tap that sets drop=0 (headless capture only; never ship)")
    ap.add_argument("--blossom", default="blossom", choices=sorted(BLOSSOMS))
    ap.add_argument("--wood", default="plum", choices=sorted(WOODS))
    a = ap.parse_args()
    rml, n = build(a.debug, a.test_hooks, a.blossom, a.wood)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(rml)
    print(f"wrote {OUT}  ({rml.count(chr(10))} lines, {n} growth binds)")


if __name__ == "__main__":
    main()
