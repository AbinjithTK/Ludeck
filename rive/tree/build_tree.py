"""Build screens/tree_discovery.rml: the imported growing tree + game discovery.

Source of truth is tree/source/tree-demo.riv (the designer's file). This script
  1. decodes it and converts it to RML (tool/riv_decode.py, tool/riv_to_rml.py)
  2. replaces its deprecated number input with a view model, TreeDiscovery:
       found     0..6   how many games the search has found (host sets it)
       selected  -1..5  which card the user tapped (the file writes it)
       cover1..6        cover images (host swaps them at runtime)
     `found` drives the tree through a converter chain: 0..6 -> growth 20..100,
     eased over GROW_SECONDS, so each found game grows the tree one step
     instead of jumping.
  3. re-frames the 500x500 artboard as a 412x732 portrait scene on Ludeck's sky
  4. adds six game cards that hang from the canopy and pop in as `found` rises

Run from anywhere:  python rive/tree/build_tree.py [--debug]
Then:               rive rive --artboard=TreeDiscovery --data=found=6 ...
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


def convert():
    doc = riv_decode.decode(SRC)
    schema = json.load(open(os.path.join(ROOT, "tool", "rive_schema.json"),
                            encoding="utf-8"))
    return riv_to_rml.Conv(doc, "5", "TreeDiscovery", schema,
                           vm="TreeDiscovery").run()


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


def build(debug):
    rml = convert()

    # -- view model: the old `input` number becomes `found` -----------------
    rml = rml.replace('<ViewModelPropertyNumber name="input"',
                      '<ViewModelPropertyNumber name="found"')

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
    rml = rml.replace(style, style + front, 1)

    # -- back layer: the sky, declared after the tree -------------------------
    sky = f'''
        <Shape name="Sky" id="5:20100">
            <Rectangle originX="0" originY="0" width="{W}" height="{H}" name="P"/>
            <Fill name="F">
                <LinearGradient startX="0" startY="0" endX="0" endY="{H}" name="G">
                    <GradientStop colorValue="FF0B0A1C" position="0"/>
                    <GradientStop colorValue="FF16112E" position="0.55"/>
                    <GradientStop colorValue="FF241A3D" position="1"/>
                </LinearGradient>
            </Fill>
        </Shape>
        <Shape x="{TREE_X}" y="{TREE_Y + 6}" name="GroundGlow">
            <Ellipse width="360" height="70" name="P"/>
            <Fill name="F">
                <RadialGradient startX="0" startY="0" endX="180" endY="0" name="G">
                    <GradientStop colorValue="405B4A82" position="0"/>
                    <GradientStop colorValue="005B4A82" position="1"/>
                </RadialGradient>
            </Fill>
        </Shape>'''
    first_anim = rml.index("<LinearAnimation")
    rml = rml[:first_anim] + sky.strip() + "\n        " + rml[first_anim:]

    # -- converters: found 0..6 -> growth 20..100, eased ----------------------
    converters = f'''
    <DataConverterGroup name="FoundToGrowth" id="5:20001">
        <DataConverterGroupItem converterId="5:20002"/>
        <DataConverterGroupItem converterId="5:20003"/>
    </DataConverterGroup>
    <DataConverterRangeMapper minInput="0" maxInput="6" minOutput="{GROWTH_MIN}" maxOutput="{GROWTH_MAX}"
                              clampLower="true" clampUpper="true" name="FoundToGrowthRange" id="5:20002"/>
    <DataConverterInterpolator interpolationType="cubic" duration="{GROW_SECONDS}" name="GrowEase" id="5:20003">
        <CubicEaseInterpolator x1="0.23" y1="1" x2="0.32" y2="1"/>
    </DataConverterInterpolator>
'''
    rml = rml.replace("</Rive>", converters + D.image_assets() + "\n</Rive>")

    if not debug:
        rml = splice_discovery(rml)
    return rml, n_binds


def insert_after(rml, anchor, text):
    i = rml.index(anchor)
    return rml[:i + len(anchor)] + text + rml[i + len(anchor):]


def close_of(rml, open_anchor, close_tag):
    i = rml.index(open_anchor)
    return rml.index(close_tag, i)


def splice_discovery(rml):
    # cards + canopy tap target: front of everything, cards above the tap area
    style = '<LayoutComponentStyle name="Artboard Style" id="5:9099"/>'
    rml = insert_after(rml, style, D.card_components() + D.canopy_hit())

    # card placement rides the tree's growth blend poses
    kin, kout = D.growth_keys()
    for anim_id, keys in ((D.ANIM_IN, kin), (D.ANIM_OUT, kout)):
        j = close_of(rml, f'id="{anim_id}">', "</LinearAnimation>")
        rml = rml[:j] + keys + rml[j:]

    # new timelines, before the state machine
    j = rml.index("<StateMachine ")
    rml = rml[:j] + D.card_animations().strip() + "\n        " + rml[j:]

    # layers + listeners at the end of the state machine
    j = rml.index("</StateMachine>")
    rml = rml[:j] + D.card_layers() + D.listeners() + "\n        " + rml[j:]

    # view model
    found_prop = f'<ViewModelPropertyNumber name="found" id="{D.P_FOUND}"/>'
    rml = insert_after(rml, found_prop, D.vm_properties())
    found_val = f'viewModelPropertyId="{D.P_FOUND}"/>'
    rml = insert_after(rml, found_val, D.vm_values())
    return rml


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--debug", action="store_true")
    a = ap.parse_args()
    rml, n = build(a.debug)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(rml)
    print(f"wrote {OUT}  ({rml.count(chr(10))} lines, {n} growth binds)")


if __name__ == "__main__":
    main()
