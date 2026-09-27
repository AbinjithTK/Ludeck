"""The interactive layer on top of the converted tree: fruit cards, planting,
shaking, and the gestures. Emits RML fragments that build_tree.py splices in.

View model TreeDiscovery (host contract, see rive/AGENTS.md):
  grown     0..12  tree size. Host only ever RAISES it (the tree never shrinks)
  found     0..12  how many fruit cards hang
  selected  -1..11 card the user tapped (the file writes it; host reads)
  cover1..12       cover images
  planted   bool   false = empty patch; flipping to true plays seed -> sapling
  drop      -1..11 host sets i: the tree shakes and fruit i falls (the pick)
  rustle    bool   written by the canopy's own tap listener

Motion (60fps frames). DECISIONS.md: bouncy overshoot only on celebration,
never on functional UI, so:
  celebration (bouncy springs): fruit pop, sprout, the dropped fruit landing
  functional (critically damped / ease): select, dim, rustle settle
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

VM = "5:9900"
P_GROWN = "5:9901"
P_FOUND = "5:9959"
P_SELECTED = "5:9960"
P_COVER0 = 9961          # cover1..12 = 5:9961..5:9972
P_RUSTLE = "5:9975"
P_PLANTED = "5:9976"
P_DROP = "5:9977"
P_PRESSED = "5:9978"     # written on pointer-down on a fruit; host reads for long-press
N_ASSETS = 6             # placeholder cover files; slots reuse them round-robin
SKY = "5:20100"
TREE = "5:101"
TREE_SCALE = 0.94
TREE_X, TREE_Y = 180, 668
GROUND_Y = TREE_Y - 58   # where a dropped fruit comes to rest (card centre)

CLUSTER_IDS = {"center": "5:1232", "right": "5:1215", "left": "5:1201"}
ANIM_IN, ANIM_OUT = "5:9110", "5:9101"   # the tree's growth blend poses (0, 100)

# Cluster targets at full growth, measured by tree/measure.py.
with open(os.path.join(HERE, "canopy.json")) as fh:
    _FULL = json.load(fh)["6"]["targets"]

CARD_W, CARD_H = 40, 53  # 3:4. 12 of them cover ~32% of the full canopy


def hang(c):
    """Stem length plus half a card: how far below its stem a card centre sits."""
    return c["stem"] + CARD_H / 2

IMG_W = 240              # cover pixels the host supplies (240x320)

# Card centres on the FULL canopy (artboard px). Hand-placed scatter, not a
# grid: a grid reads as a spreadsheet. Every pair is >= 55px apart
# (checked by min_spacing()), with stems of varied length and a slight
# resting tilt so no two fruit hang identically.
_PTS = [(192, 258), (148, 300), (236, 296), (192, 344), (96, 332), (282, 340),
        (138, 386), (212, 404), (338, 318), (270, 408), (72, 384), (326, 392)]
_CENTROID = (205, 335)


def min_spacing():
    return min(math.hypot(a[0] - b[0], a[1] - b[1])
               for n, a in enumerate(_PTS) for b in _PTS[n + 1:])


def _slots():
    pts = sorted(_PTS, key=lambda p: math.hypot(p[0] - _CENTROID[0], p[1] - _CENTROID[1]))
    out = []
    for n, (x, y) in enumerate(pts):
        name = min(_FULL, key=lambda k: math.hypot(x - _FULL[k][0], y - _FULL[k][1]))
        tx, ty = _FULL[name]
        stem = 9 + (n * 5) % 9                       # 9..17px
        tilt = ((n * 7) % 5 - 2) * 0.03              # -0.06..0.06 rad
        out.append({"cluster": CLUSTER_IDS[name], "pos": (x, y), "stem": stem,
                    "tilt": round(tilt, 3),
                    "off": (round(x - tx, 1), round(y - ty, 1))})
    return out


CARDS = _slots()
SLOTS = len(CARDS)
EARLY = 0.40             # offsets at growth 0; wide enough that a half-grown
EARLY_SCALE = 0.55       #   tree's smaller fruit never overlap

EASE_OUT = '<CubicEaseInterpolator x1="0.23" y1="1" x2="0.32" y2="1"/>'
EASE_IO = '<CubicEaseInterpolator x1="0.77" y1="0" x2="0.175" y2="1"/>'
GRAVITY = '<CubicEaseInterpolator x1="0.55" y1="0" x2="1" y2="0.45"/>'


# ----------------------------------------------------------------- springs
def spring_keys(start, end, response, damping, frames, step=2, offset=0):
    """Keyframes sampled from a damped spring (Apple's response/damping).

    Linear between samples 2 frames apart: visually continuous at 60fps, with
    the true overshoot and settle a single bezier cannot make. `offset` shifts
    the spring later in the timeline, holding `start` until then.
    """
    w = 2 * math.pi / response
    wd = w * math.sqrt(1 - damping * damping)
    out = []
    if offset:
        out.append(f'<KeyFrameDouble value="{start:.4f}" frame="0" interpolationType="linear"/>')
    for f in list(range(0, frames, step)) + [frames]:
        t = f / 60
        x = 1 - math.exp(-damping * w * t) * (
            math.cos(wd * t) + damping * w / wd * math.sin(wd * t))
        v = end if f == frames else start + (end - start) * x
        out.append(f'<KeyFrameDouble value="{v:.4f}" frame="{f + offset}" interpolationType="linear"/>')
    return out


POP_FRAMES = 54
POP_SX = dict(response=0.46, damping=0.45)
POP_SY = dict(response=0.40, damping=0.52)
POP_ROT = dict(response=0.62, damping=0.38)
SPROUT = dict(response=0.55, damping=0.55)


# ------------------------------------------------------------------ helpers
def base(i):
    return 21000 + i * 100


def cid(i, k):
    return f"5:{base(i) + k}"


def wait_frames(i):
    """Delay before card i pops: 180ms + 60ms per earlier card.

    One at a time, the canopy swells before the fruit arrives. Many at once
    (a whole tree loading), they ripple out from the centre instead of
    appearing as a block. 12 cards: the last starts ~0.84s in.
    """
    return round((0.18 + 0.055 * i) * 60)


def key(frame, value, curve=None, kind="Double"):
    if curve:
        return (f'<KeyFrame{kind} value="{value}" frame="{frame}" interpolationType="cubic">'
                f"{curve}</KeyFrame{kind}>")
    return f'<KeyFrame{kind} value="{value}" frame="{frame}"/>'


def keyed(obj, props):
    out = [f'<KeyedObject objectId="{obj}">']
    for pk, keys in props:
        out.append(f'<KeyedProperty propertyKey="{pk}">{"".join(keys)}</KeyedProperty>')
    out.append("</KeyedObject>")
    return "".join(out)


def num_cond(prop, op, value):
    return (f'<TransitionViewModelCondition opValue="{op}">'
            f"<TransitionPropertyViewModelComparator><BindablePropertyNumber>"
            f'<DataBindContext sourcePathIds="{VM}-{prop}" propertyKey="636"/>'
            f"</BindablePropertyNumber></TransitionPropertyViewModelComparator>"
            f'<TransitionValueNumberComparator value="{value}"/>'
            f"</TransitionViewModelCondition>")


def bool_cond(prop, value):
    return (f"<TransitionViewModelCondition>"
            f"<TransitionPropertyViewModelComparator><BindablePropertyBoolean>"
            f'<DataBindContext sourcePathIds="{VM}-{prop}" propertyKey="634"/>'
            f"</BindablePropertyBoolean></TransitionPropertyViewModelComparator>"
            f'<TransitionValueBooleanComparator value="{"true" if value else "false"}"/>'
            f"</TransitionViewModelCondition>")


def write_number(prop, value):
    return (f'<ListenerViewModelChange><BindablePropertyNumber propertyValue="{value}">'
            f'<DataBindContext sourcePathIds="{VM}-{prop}" propertyKey="636" direction="true"/>'
            f"</BindablePropertyNumber></ListenerViewModelChange>")


def write_bool(prop, value):
    return (f'<ListenerViewModelChange><BindablePropertyBoolean propertyValue="{"true" if value else "false"}">'
            f'<DataBindContext sourcePathIds="{VM}-{prop}" propertyKey="634" direction="true"/>'
            f"</BindablePropertyBoolean></ListenerViewModelChange>")


def layer(name, lid, entry_to, states, y):
    """A state machine layer. states: [(sid, anim_id, x, [transition xml])]."""
    body = [f'<StateMachineLayer name="{name}" id="{lid}">',
            f'<AnyState x="0" y="{y + 80}"/>', f'<ExitState x="1000" y="{y + 80}"/>',
            f'<EntryState x="0" y="{y}">{"".join(entry_to)}</EntryState>']
    for sid, anim, x, trans in states:
        body.append(f'<AnimationState x="{x}" y="{y}" animationId="{anim}" id="{sid}">'
                    f'{"".join(trans)}</AnimationState>')
    body.append("</StateMachineLayer>")
    return "\n            ".join(body)


def tr(to, conds="", duration=None, exit_pct=None):
    a = f' duration="{duration}"' if duration is not None else ""
    if exit_pct is not None:
        a += f' enableExitTime="true" exitTimeIsPercetange="true" exitTime="{exit_pct}"'
    return f'<StateTransition stateToId="{to}"{a}>{conds}</StateTransition>'


# ---------------------------------------------------------------- components
def card_components():
    """Fruit cards. Declared last-first so card 1 (the centre) draws on top."""
    out = []
    s = CARD_W / IMG_W
    for i in reversed(range(SLOTS)):
        c = CARDS[i]
        ox, oy = c["off"]
        h, stem = hang(c), c["stem"]
        out.append(f'''
        <Node x="{ox * EARLY:.1f}" y="{(oy - h) * EARLY:.1f}" scaleX="{EARLY_SCALE}" scaleY="{EARLY_SCALE}" name="Game{i + 1}" id="{cid(i, 0)}">
            <TranslationConstraint targetId="{c['cluster']}" offset="true" name="FollowCanopy"/>
            <Node scaleX="0" scaleY="0" name="Pop" id="{cid(i, 1)}">
                <Node y="{h}" name="Lift" id="{cid(i, 2)}">
                    <Shape isTargetOpaque="true" name="Hit" id="{cid(i, 9)}">
                        <Rectangle width="{CARD_W + 16}" height="{CARD_H + 16}" name="P"/>
                    </Shape>
                    <Node rotation="{c['tilt']}" name="Card" id="{cid(i, 3)}">
                        <Shape name="Edge">
                            <Rectangle width="{CARD_W}" height="{CARD_H}" cornerRadiusTL="6" name="P"/>
                            <Stroke thickness="1.5" name="S"><SolidColor colorValue="59F2F3F5" name="C" id="{cid(i, 4)}"/></Stroke>
                        </Shape>
                        <Image assetId="5:{9981 + i % N_ASSETS}" scaleX="{s:.5f}" scaleY="{s:.5f}" name="Cover" id="{cid(i, 5)}">
                            <DataBindContext sourcePathIds="{VM}-5:{P_COVER0 + i}" propertyKey="206"/>
                            <ClippingShape sourceId="{cid(i, 6)}" name="Round"/>
                        </Image>
                        <Shape name="CoverMask" id="{cid(i, 6)}">
                            <Rectangle width="{CARD_W}" height="{CARD_H}" cornerRadiusTL="6" name="P"/>
                        </Shape>
                        <Shape name="Slot">
                            <Rectangle width="{CARD_W}" height="{CARD_H}" cornerRadiusTL="6" name="P"/>
                            <Fill name="F"><SolidColor colorValue="FF181A1D" name="C"/></Fill>
                        </Shape>
                        <Shape y="3" name="Shadow">
                            <Rectangle width="{CARD_W + 2}" height="{CARD_H + 2}" cornerRadiusTL="7" name="P"/>
                            <Fill name="F"><SolidColor colorValue="59000000" name="C"/></Fill>
                        </Shape>
                    </Node>
                    <Shape opacity="0" name="Glow" id="{cid(i, 7)}">
                        <Ellipse width="110" height="110" name="P"/>
                        <Fill name="F">
                            <RadialGradient startX="0" startY="0" endX="55" endY="0" name="G">
                                <GradientStop colorValue="66E8B84B" position="0"/>
                                <GradientStop colorValue="00E8B84B" position="1"/>
                            </RadialGradient>
                        </Fill>
                    </Shape>
                    <Shape opacity="0" name="Burst" id="{cid(i, 8)}">
                        <Ellipse width="64" height="64" name="P"/>
                        <Stroke thickness="2" name="S"><SolidColor colorValue="FFE8B84B" name="C"/></Stroke>
                    </Shape>
                </Node>
                <Shape y="{stem / 2}" name="Stem">
                    <Rectangle width="1.5" height="{stem}" cornerRadiusTL="0.75" name="P"/>
                    <Fill name="F"><SolidColor colorValue="99F2F3F5" name="C"/></Fill>
                </Shape>
            </Node>
        </Node>''')
    return "".join(out)


def canopy_hit():
    return f'''
        <Node name="CanopyTap" id="5:20200">
            <TranslationConstraint targetId="{CLUSTER_IDS['center']}" name="Follow"/>
            <Shape isTargetOpaque="true" y="-20" name="Hit" id="5:20201">
                <Ellipse width="300" height="230" name="P"/>
            </Shape>
        </Node>'''


def planting_components():
    """The empty patch (unplanted) and the seed that falls into it."""
    return f'''
        <Node x="{TREE_X}" y="{TREE_Y - 6}" opacity="0" name="Seed" id="5:20510">
            <Shape name="SeedBody" id="5:20511">
                <Ellipse width="12" height="15" name="P"/>
                <Fill name="F">
                    <LinearGradient startX="-6" startY="-7" endX="6" endY="7" name="G">
                        <GradientStop colorValue="FF7C6580" position="0"/>
                        <GradientStop colorValue="FF3B2F75" position="1"/>
                    </LinearGradient>
                </Fill>
            </Shape>
        </Node>
        <Node x="{TREE_X}" y="{TREE_Y}" opacity="0" name="Patch" id="5:20500">
            <Node y="-70" name="Invite" id="5:20501">
                <Shape name="PlusH"><Rectangle width="20" height="2.5" cornerRadiusTL="1.25" name="P"/>
                    <Fill name="F"><SolidColor colorValue="B3F2F3F5" name="C"/></Fill></Shape>
                <Shape name="PlusV"><Rectangle width="2.5" height="20" cornerRadiusTL="1.25" name="P"/>
                    <Fill name="F"><SolidColor colorValue="B3F2F3F5" name="C"/></Fill></Shape>
                <Shape name="Ring">
                    <Ellipse width="84" height="84" name="P"/>
                    <Stroke thickness="1.5" cap="round" name="S">
                        <SolidColor colorValue="66F2F3F5" name="C"/>
                        <DashPath name="Dashes"><Dash length="6" name="On"/><Dash length="7" name="Off"/></DashPath>
                    </Stroke>
                </Shape>
            </Node>
            <Shape isTargetOpaque="true" y="-40" name="PatchHit" id="5:20502">
                <Rectangle width="200" height="180" name="P"/>
            </Shape>
            <Shape name="Soil">
                <Ellipse width="96" height="18" name="P"/>
                <Fill name="F"><SolidColor colorValue="FF0B0A1C" name="C"/></Fill>
            </Shape>
        </Node>'''


# ---------------------------------------------------------------- animations
def growth_keys():
    """Keys for the tree's growth blend poses: fruit rides and scales with it."""
    kin, kout = [], []
    for i, c in enumerate(CARDS):
        ox, oy = c["off"]
        h = hang(c)
        kin.append(keyed(cid(i, 0), [(13, [key(0, f"{ox * EARLY:.2f}")]),
                                    (14, [key(0, f"{(oy - h) * EARLY:.2f}")]),
                                    (16, [key(0, EARLY_SCALE)]), (17, [key(0, EARLY_SCALE)])]))
        kout.append(keyed(cid(i, 0), [(13, [key(0, ox)]), (14, [key(0, round(oy - h, 2))]),
                                     (16, [key(0, 1)]), (17, [key(0, 1)])]))
    return "".join(kin), "".join(kout)


def card_animations():
    out = []
    for i, c in enumerate(CARDS):
        pop, burst, glow, lift, card, edge = (cid(i, 1), cid(i, 8), cid(i, 7),
                                              cid(i, 2), cid(i, 3), cid(i, 4))
        swing = 0.5 if i % 2 == 0 else -0.5
        idle_len = 156 + (i * 37) % 48
        sway = 0.035 if i % 2 else -0.035
        fall = round(GROUND_Y - c["pos"][1], 1)
        HANG = hang(c)  # noqa: N806 (per-card)
        tilt = c["tilt"]
        hidden = keyed(pop, [(16, [key(0, 0)]), (17, [key(0, 0)]), (15, [key(0, 0)]), (18, [key(0, 0)])])
        out.append(f'''
        <LinearAnimation duration="1" name="Game{i + 1}Hidden" id="{cid(i, 20)}">{hidden}{keyed(burst, [(18, [key(0, 0)])])}</LinearAnimation>
        <LinearAnimation duration="{wait_frames(i)}" name="Game{i + 1}Wait" id="{cid(i, 26)}">{hidden}{keyed(burst, [(18, [key(0, 0)])])}</LinearAnimation>
        <LinearAnimation duration="{POP_FRAMES}" name="Game{i + 1}Pop" id="{cid(i, 21)}">
            {keyed(pop, [
                (16, spring_keys(0, 1, frames=POP_FRAMES, **POP_SX)),
                (17, spring_keys(0, 1, frames=POP_FRAMES, **POP_SY)),
                (15, spring_keys(swing, 0, frames=POP_FRAMES, **POP_ROT)),
                (18, [key(0, 0), key(5, 1)])])}
            {keyed(burst, [
                (16, [key(0, 0.5), key(4, 0.5, EASE_OUT), key(36, 1.8)]),
                (17, [key(0, 0.5), key(4, 0.5, EASE_OUT), key(36, 1.8)]),
                (18, [key(0, 0), key(4, 0.85, EASE_OUT), key(36, 0)])])}
        </LinearAnimation>
        <LinearAnimation loopValue="pingPong" duration="{idle_len}" name="Game{i + 1}Idle" id="{cid(i, 22)}">
            {keyed(pop, [(16, [key(0, 1)]), (17, [key(0, 1)]), (18, [key(0, 1)]),
                         (15, [key(0, -sway, EASE_IO), key(idle_len, sway)])])}
            {keyed(burst, [(18, [key(0, 0)])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Game{i + 1}Normal" id="{cid(i, 23)}">
            {keyed(lift, [(16, [key(0, 1)]), (17, [key(0, 1)])])}{keyed(card, [(18, [key(0, 1)])])}
            {keyed(glow, [(18, [key(0, 0)])])}{keyed(edge, [(37, [key(0, "59F2F3F5", kind="Color")])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Game{i + 1}Selected" id="{cid(i, 24)}">
            {keyed(lift, [(16, [key(0, 1.16)]), (17, [key(0, 1.16)])])}{keyed(card, [(18, [key(0, 1)])])}
            {keyed(glow, [(18, [key(0, 1)])])}{keyed(edge, [(37, [key(0, "FFE8B84B", kind="Color")])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Game{i + 1}Dimmed" id="{cid(i, 25)}">
            {keyed(lift, [(16, [key(0, 0.94)]), (17, [key(0, 0.94)])])}{keyed(card, [(18, [key(0, 0.5)])])}
            {keyed(glow, [(18, [key(0, 0)])])}{keyed(edge, [(37, [key(0, "33F2F3F5", kind="Color")])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Game{i + 1}Hanging" id="{cid(i, 27)}">
            {keyed(lift, [(14, [key(0, HANG)])])}
            {keyed(card, [(15, [key(0, tilt)]), (16, [key(0, 1)]), (17, [key(0, 1)])])}
        </LinearAnimation>
        <LinearAnimation duration="84" name="Game{i + 1}Fall" id="{cid(i, 28)}">
            {keyed(lift, [(14, [key(0, HANG), key(30, HANG, GRAVITY), key(52, HANG + fall)] +
                          spring_keys(HANG + fall, HANG + fall - 16, 0.3, 0.9, 8, offset=52)[2:] +
                          spring_keys(HANG + fall - 16, HANG + fall, 0.42, 0.5, 24, offset=60)[2:])])}
            {keyed(card, [
                (15, [key(0, tilt), key(30, tilt, GRAVITY), key(52, 0.35 if i % 2 else -0.35, EASE_OUT), key(64, 0)]),
                (16, [key(0, 1), key(52, 1)] + spring_keys(1, 1.4, frames=32, offset=52, **POP_SX)[2:]),
                (17, [key(0, 1), key(52, 1)] + spring_keys(1, 1.4, frames=32, offset=52, **POP_SY)[2:])])}
        </LinearAnimation>''')
    return "".join(out)


def tree_animations():
    s = TREE_SCALE
    rest_rot = keyed(TREE, [(15, [key(0, 0)])])
    return f'''
        <LinearAnimation duration="1" name="TreeRest" id="5:20300">{rest_rot}</LinearAnimation>
        <LinearAnimation duration="42" name="TreeRustle" id="5:20301">
            {keyed(TREE, [(15, [key(0, 0, EASE_IO), key(7, 0.032, EASE_IO), key(16, -0.02, EASE_IO),
                                key(25, 0.009, EASE_IO), key(34, -0.003, EASE_IO), key(42, 0)])])}
        </LinearAnimation>
        <LinearAnimation duration="36" name="TreeShake" id="5:20302">
            {keyed(TREE, [(15, [key(0, 0, EASE_IO), key(4, 0.05, EASE_IO), key(9, -0.05, EASE_IO),
                                key(14, 0.04, EASE_IO), key(19, -0.03, EASE_IO), key(25, 0.015, EASE_IO),
                                key(31, -0.005, EASE_IO), key(36, 0)])])}
        </LinearAnimation>
        <LinearAnimation duration="144" loopValue="pingPong" name="Unplanted" id="5:20320">
            {keyed(TREE, [(16, [key(0, 0)]), (17, [key(0, 0)])])}
            {keyed("5:20500", [(18, [key(0, 1)])])}
            {keyed("5:20510", [(18, [key(0, 0)]), (14, [key(0, TREE_Y - 6)])])}
            {keyed("5:20501", [(16, [key(0, 1, EASE_IO), key(144, 1.07)]), (17, [key(0, 1, EASE_IO), key(144, 1.07)])])}
        </LinearAnimation>
        <LinearAnimation duration="84" name="Sprout" id="5:20321">
            {keyed(TREE, [(16, spring_keys(0, s, frames=60, offset=24, **SPROUT)),
                          (17, spring_keys(0, s, frames=60, offset=24, **SPROUT))])}
            {keyed("5:20500", [(18, [key(0, 1, EASE_OUT), key(12, 0)])])}
            {keyed("5:20510", [
                (18, [key(0, 1), key(26, 1, EASE_OUT), key(36, 0)]),
                (14, [key(0, TREE_Y - 130, GRAVITY), key(16, TREE_Y - 6)])])}
            {keyed("5:20511", [
                (16, [key(0, 1), key(16, 1, EASE_OUT), key(20, 1.35, EASE_IO), key(26, 1)]),
                (17, [key(0, 1), key(16, 1, EASE_OUT), key(20, 0.65, EASE_IO), key(26, 1)])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Planted" id="5:20322">
            {keyed(TREE, [(16, [key(0, s)]), (17, [key(0, s)])])}
            {keyed("5:20500", [(18, [key(0, 0)])])}
            {keyed("5:20510", [(18, [key(0, 0)])])}
        </LinearAnimation>'''


# ------------------------------------------------------------ state machine
def card_layers():
    out = []
    for i in range(SLOTS):
        n = i + 1
        s = lambda k: cid(i, 40 + k)   # noqa: E731
        out.append(layer(f"Game{n} presence", cid(i, 30), [tr(s(0))], [
            (s(0), cid(i, 20), 220, [tr(s(6), num_cond(P_FOUND, "greaterThanOrEqual", n))]),
            (s(6), cid(i, 26), 330, [tr(s(1), exit_pct=100),
                                     tr(s(0), num_cond(P_FOUND, "lessThan", n))]),
            (s(1), cid(i, 21), 440, [tr(s(2), duration=300, exit_pct=100)]),
            (s(2), cid(i, 22), 660, [tr(s(0), num_cond(P_FOUND, "lessThan", n), duration=150)]),
        ], 100 + i * 60))
        others = num_cond(P_SELECTED, "notEqual", i) + num_cond(P_SELECTED, "greaterThanOrEqual", 0)
        out.append(layer(f"Game{n} focus", cid(i, 31), [tr(s(3))], [
            (s(3), cid(i, 23), 220, [tr(s(4), num_cond(P_SELECTED, "equal", i), 200),
                                     tr(s(5), others, 200)]),
            (s(4), cid(i, 24), 440, [tr(s(3), num_cond(P_SELECTED, "lessThan", 0), 200),
                                     tr(s(5), others, 200)]),
            (s(5), cid(i, 25), 660, [tr(s(4), num_cond(P_SELECTED, "equal", i), 200),
                                     tr(s(3), num_cond(P_SELECTED, "lessThan", 0), 200)]),
        ], 900 + i * 60))
        out.append(layer(f"Game{n} drop", cid(i, 32), [tr(s(7))], [
            (s(7), cid(i, 27), 220, [tr(s(8), num_cond(P_DROP, "equal", i))]),
            (s(8), cid(i, 28), 440, [tr(s(7), num_cond(P_DROP, "notEqual", i), 250)]),
        ], 1700 + i * 60))
    return "\n            ".join(out)


def tree_layers():
    return "\n            ".join([
        layer("Tree motion", "5:20310", [tr("5:20311")], [
            ("5:20311", "5:20300", 220, [tr("5:20312", bool_cond(P_RUSTLE, True)),
                                         tr("5:20313", num_cond(P_DROP, "greaterThanOrEqual", 0))]),
            ("5:20312", "5:20301", 440, [tr("5:20311", bool_cond(P_RUSTLE, False), exit_pct=100)]),
            ("5:20313", "5:20302", 550, [tr("5:20314", exit_pct=100)]),
            ("5:20314", "5:20300", 770, [tr("5:20311", num_cond(P_DROP, "lessThan", 0))]),
        ], 2600),
        layer("Planting", "5:20330",
              [tr("5:20333", bool_cond(P_PLANTED, True)), tr("5:20331", bool_cond(P_PLANTED, False))], [
            ("5:20331", "5:20320", 220, [tr("5:20332", bool_cond(P_PLANTED, True))]),
            ("5:20332", "5:20321", 440, [tr("5:20333", exit_pct=100)]),
            ("5:20333", "5:20322", 660, [tr("5:20331", bool_cond(P_PLANTED, False))]),
        ], 2800),
    ])


def test_hooks():
    """TEST BUILDS ONLY (build_tree.py --test-hooks, never shipped): a tap in
    the top-left 40px corner sets drop=0, so the fall can be captured headless
    mid-run (`--data` applies before the first frame)."""
    comp = '''
        <Shape isTargetOpaque="true" x="20" y="20" name="TestHookDrop" id="5:20600">
            <Rectangle width="40" height="40" name="P"/>
        </Shape>'''
    lst = f'''
            <StateMachineListenerSingle targetId="5:20600" listenerTypeValue="down" name="TestDrop" id="5:20601">
                {write_number(P_DROP, 0)}
            </StateMachineListenerSingle>'''
    return comp, lst


def listeners():
    out = [f'''
            <StateMachineListenerSingle targetId="{cid(i, 9)}" listenerTypeValue="click" name="TapGame{i + 1}" id="{cid(i, 50)}">
                {write_number(P_SELECTED, i)}
            </StateMachineListenerSingle>
            <StateMachineListenerSingle targetId="{cid(i, 9)}" listenerTypeValue="down" name="PressGame{i + 1}" id="{cid(i, 51)}">
                {write_number(P_PRESSED, i)}
            </StateMachineListenerSingle>''' for i in range(SLOTS)]
    out.append(f'''
            <StateMachineListenerSingle targetId="{SKY}" listenerTypeValue="click" name="TapSky" id="5:20400">
                {write_number(P_SELECTED, -1)}
            </StateMachineListenerSingle>
            <StateMachineListenerSingle targetId="{SKY}" listenerTypeValue="down" name="PressSky" id="5:20405">
                {write_number(P_PRESSED, -1)}
            </StateMachineListenerSingle>
            <StateMachineListenerSingle targetId="5:20201" listenerTypeValue="down" name="CanopyDown" id="5:20401">
                {write_bool(P_RUSTLE, True)}{write_number(P_SELECTED, -1)}
            </StateMachineListenerSingle>
            <StateMachineListenerSingle targetId="5:20201" listenerTypeValue="up" name="CanopyUp" id="5:20402">
                {write_bool(P_RUSTLE, False)}
            </StateMachineListenerSingle>
            <StateMachineListenerSingle targetId="5:20201" listenerTypeValue="exit" name="CanopyLeave" id="5:20403">
                {write_bool(P_RUSTLE, False)}
            </StateMachineListenerSingle>''')
    return "".join(out)


# --------------------------------------------------------------- view model
def vm_properties():
    p = [f'<ViewModelPropertyNumber name="found" id="{P_FOUND}"/>',
         f'<ViewModelPropertyNumber name="selected" id="{P_SELECTED}"/>',
         f'<ViewModelPropertyNumber name="drop" id="{P_DROP}"/>',
         f'<ViewModelPropertyNumber name="pressed" id="{P_PRESSED}"/>',
         f'<ViewModelPropertyBoolean name="planted" id="{P_PLANTED}"/>',
         f'<ViewModelPropertyBoolean name="rustle" id="{P_RUSTLE}"/>']
    p += [f'<ViewModelPropertyAssetImage name="cover{i + 1}" id="5:{P_COVER0 + i}"/>'
          for i in range(SLOTS)]
    return "".join(p)


def vm_values():
    v = [f'<ViewModelInstanceNumber propertyValue="0" viewModelPropertyId="{P_FOUND}"/>',
         f'<ViewModelInstanceNumber propertyValue="-1" viewModelPropertyId="{P_SELECTED}"/>',
         f'<ViewModelInstanceNumber propertyValue="-1" viewModelPropertyId="{P_DROP}"/>',
         f'<ViewModelInstanceNumber propertyValue="-1" viewModelPropertyId="{P_PRESSED}"/>',
         f'<ViewModelInstanceBoolean propertyValue="true" viewModelPropertyId="{P_PLANTED}"/>',
         f'<ViewModelInstanceBoolean propertyValue="false" viewModelPropertyId="{P_RUSTLE}"/>']
    v += [f'<ViewModelInstanceAssetImage propertyValue="5:{9981 + i % N_ASSETS}" viewModelPropertyId="5:{P_COVER0 + i}"/>'
          for i in range(SLOTS)]
    return "".join(v)


def image_assets():
    return "".join(f'<ImageAsset file="covers/cover{i + 1}.png" name="cover{i + 1}" id="5:{9981 + i}"/>'
                   for i in range(N_ASSETS))
