"""The discovery layer for TreeDiscovery: six game cards, their motion and
interaction. Emits RML fragments that build_tree.py splices into the
converted tree.

Motion (60fps frames; Ludeck's Tokens.motion where one applies):
  Pop      31f  ~520ms (Tokens.motion.harvest: this IS the delight moment)
           swings down from its stem like fruit: rotation +-0.5 -> -+0.08 -> 0,
           scale 0 -> 1.07 -> 1, opacity 0 -> 1 in the first 100ms so nothing
           reads as a ghost. Gold ring bursts outward behind it and fades.
  Idle     pendulum sway +-0.035 rad, ping-pong, a different period per card
           (2.6-3.4s) so the canopy never sways in lockstep
  Select   200ms (swap): lift 1.16, gold edge, soft glow; the other cards dim
           to 0.5 so the choice reads without any text
  Rustle   tap the canopy: the whole tree squashes and recovers, ~570ms

Card placement is keyed into the tree's OWN growth blend (animations "in" and
"out"), so every card rides the canopy as it grows instead of floating at a
fixed offset from a small sapling.
"""

CENTER, RIGHT, LEFT = "5:1232", "5:1215", "5:1201"
ANIM_IN, ANIM_OUT = "5:9110", "5:9101"   # blend poses at growth 0 and 100
VM = "5:9900"
P_FOUND = "5:9901"
P_SELECTED = "5:9960"
P_COVER0 = 9961          # cover1..6 = 5:9961..5:9966
P_RUSTLE = "5:9970"
SKY = "5:20100"
TREE = "5:101"
TREE_SCALE = 0.94

# Card centre relative to its cluster target at full growth (artboard px),
# placed from renders (tree/measure.py). Pop order = list order.
CARDS = [
    (CENTER, (23, -104)),
    (RIGHT, (24, -68)),
    (LEFT, (-10, -52)),
    (CENTER, (-7, 36)),
    (RIGHT, (-18, 22)),
    (LEFT, (-26, 42)),
]
EARLY = 0.18             # offset fraction at growth 0 (canopy is ~18% size)
CARD_W, CARD_H = 44, 58
STEM = 12                # stem length; card centre sits STEM + CARD_H/2 below
HANG = STEM + CARD_H / 2
IMG_W, IMG_H = 240, 320  # cover image pixels the host should supply

EASE_OUT = '<CubicEaseInterpolator x1="0.23" y1="1" x2="0.32" y2="1"/>'
EASE_IO = '<CubicEaseInterpolator x1="0.77" y1="0" x2="0.175" y2="1"/>'
OVERSHOOT = '<CubicEaseInterpolator x1="0.34" y1="1.4" x2="0.64" y2="1"/>'


def spring_keys(start, end, response, damping, frames, step=2):
    """Keyframes sampled from a real damped spring (Apple's response/damping).

    Linear between samples every `step` frames: at 60fps that is visually a
    continuous spring, with the true overshoot and settle a bezier cannot make.
    """
    import math
    w = 2 * math.pi / response
    wd = w * math.sqrt(1 - damping * damping)
    out = []
    for f in list(range(0, frames, step)) + [frames]:
        t = f / 60
        x = 1 - math.exp(-damping * w * t) * (
            math.cos(wd * t) + damping * w / wd * math.sin(wd * t))
        v = end if f == frames else start + (end - start) * x
        out.append(f'<KeyFrameDouble value="{v:.4f}" frame="{f}" interpolationType="linear"/>')
    return out


# Pop springs. Bouncy on purpose (damping 0.5 ~ 16% overshoot), and X and Y on
# slightly different springs so the card wobbles like something soft landing.
POP_FRAMES = 54                              # ~0.9s until fully at rest
POP_SX = dict(response=0.46, damping=0.45)
POP_SY = dict(response=0.40, damping=0.52)
POP_ROT = dict(response=0.62, damping=0.38)  # the pendulum swing, looser


def base(i):
    return 21000 + i * 100


def wait_frames(i):
    """Delay before card i pops: 180ms + 80ms per earlier card.

    Two jobs. When games arrive one at a time it lets the canopy swell first,
    so the fruit reads as grown by the tree. When the host sets several at
    once (cached results) it staggers them instead of popping six at once.
    """
    return round((0.18 + 0.08 * i) * 60)


def cid(i, k):
    return f"5:{base(i) + k}"


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


def num_cond(path_prop, op, value):
    return (f'<TransitionViewModelCondition opValue="{op}">'
            f"<TransitionPropertyViewModelComparator><BindablePropertyNumber>"
            f'<DataBindContext sourcePathIds="{VM}-{path_prop}" propertyKey="636"/>'
            f"</BindablePropertyNumber></TransitionPropertyViewModelComparator>"
            f'<TransitionValueNumberComparator value="{value}"/>'
            f"</TransitionViewModelCondition>")


def bool_cond(path_prop, value):
    return (f"<TransitionViewModelCondition>"
            f"<TransitionPropertyViewModelComparator><BindablePropertyBoolean>"
            f'<DataBindContext sourcePathIds="{VM}-{path_prop}" propertyKey="634"/>'
            f"</BindablePropertyBoolean></TransitionPropertyViewModelComparator>"
            f'<TransitionValueBooleanComparator value="{"true" if value else "false"}"/>'
            f"</TransitionViewModelCondition>")


def write_number(prop, value):
    return (f"<ListenerViewModelChange><BindablePropertyNumber propertyValue=\"{value}\">"
            f'<DataBindContext sourcePathIds="{VM}-{prop}" propertyKey="636" direction="true"/>'
            f"</BindablePropertyNumber></ListenerViewModelChange>")


def write_bool(prop, value):
    return (f"<ListenerViewModelChange><BindablePropertyBoolean propertyValue=\"{'true' if value else 'false'}\">"
            f'<DataBindContext sourcePathIds="{VM}-{prop}" propertyKey="634" direction="true"/>'
            f"</BindablePropertyBoolean></ListenerViewModelChange>")


# ---------------------------------------------------------------- components
def card_components():
    """Front layer. Card 1 is declared last so later cards draw on top."""
    out = []
    for i in reversed(range(len(CARDS))):
        tgt, (cx, cy) = CARDS[i]
        n = i + 1
        cover = f"5:{P_COVER0 + i}"
        sx = CARD_W / IMG_W
        out.append(f'''
        <Node x="{cx * EARLY:.1f}" y="{(cy - HANG) * EARLY:.1f}" name="Game{n}" id="{cid(i, 0)}">
            <TranslationConstraint targetId="{tgt}" offset="true" name="FollowCanopy"/>
            <Node scaleX="0" scaleY="0" name="Pop" id="{cid(i, 1)}">
                <Node y="{HANG}" name="Lift" id="{cid(i, 2)}">
                    <Shape isTargetOpaque="true" name="Hit" id="{cid(i, 9)}">
                        <Rectangle width="{CARD_W + 16}" height="{CARD_H + 16}" name="P"/>
                    </Shape>
                    <Node name="Card" id="{cid(i, 3)}">
                        <Shape name="Edge">
                            <Rectangle width="{CARD_W}" height="{CARD_H}" cornerRadiusTL="7" name="P"/>
                            <Stroke thickness="1.5" name="S"><SolidColor colorValue="59F2F3F5" name="C" id="{cid(i, 4)}"/></Stroke>
                        </Shape>
                        <Image assetId="5:{9981 + i}" scaleX="{sx:.5f}" scaleY="{sx:.5f}" name="Cover" id="{cid(i, 5)}">
                            <DataBindContext sourcePathIds="{VM}-{cover}" propertyKey="206"/>
                            <ClippingShape sourceId="{cid(i, 6)}" name="Round"/>
                        </Image>
                        <Shape name="CoverMask" id="{cid(i, 6)}">
                            <Rectangle width="{CARD_W}" height="{CARD_H}" cornerRadiusTL="7" name="P"/>
                        </Shape>
                        <Shape name="Slot">
                            <Rectangle width="{CARD_W}" height="{CARD_H}" cornerRadiusTL="7" name="P"/>
                            <Fill name="F"><SolidColor colorValue="FF181A1D" name="C"/></Fill>
                        </Shape>
                        <Shape y="3" name="Shadow">
                            <Rectangle width="{CARD_W + 2}" height="{CARD_H + 2}" cornerRadiusTL="8" name="P"/>
                            <Fill name="F"><SolidColor colorValue="59000000" name="C"/></Fill>
                        </Shape>
                    </Node>
                    <Shape opacity="0" name="Glow" id="{cid(i, 7)}">
                        <Ellipse width="120" height="120" name="P"/>
                        <Fill name="F">
                            <RadialGradient startX="0" startY="0" endX="60" endY="0" name="G">
                                <GradientStop colorValue="66E8B84B" position="0"/>
                                <GradientStop colorValue="00E8B84B" position="1"/>
                            </RadialGradient>
                        </Fill>
                    </Shape>
                    <Shape opacity="0" name="Burst" id="{cid(i, 8)}">
                        <Ellipse width="70" height="70" name="P"/>
                        <Stroke thickness="2" name="S"><SolidColor colorValue="FFE8B84B" name="C"/></Stroke>
                    </Shape>
                </Node>
                <Shape y="{STEM / 2}" name="Stem">
                    <Rectangle width="1.5" height="{STEM}" cornerRadiusTL="0.75" name="P"/>
                    <Fill name="F"><SolidColor colorValue="99F2F3F5" name="C"/></Fill>
                </Shape>
            </Node>
        </Node>''')
    return "".join(out)


def canopy_hit():
    """Invisible tap target over the canopy (behind the cards) for Rustle."""
    return f'''
        <Node name="CanopyTap" id="5:20200">
            <TranslationConstraint targetId="{CENTER}" name="Follow"/>
            <Shape isTargetOpaque="true" y="-20" name="Hit" id="5:20201">
                <Ellipse width="300" height="230" name="P"/>
            </Shape>
        </Node>'''


# ---------------------------------------------------------------- animations
def growth_keys():
    """Extra keys for the tree's blend poses: card placement per growth."""
    kin, kout = [], []
    for i, (_, (cx, cy)) in enumerate(CARDS):
        kin.append(keyed(cid(i, 0), [(13, [key(0, f"{cx * EARLY:.2f}")]),
                                    (14, [key(0, f"{(cy - HANG) * EARLY:.2f}")])]))
        kout.append(keyed(cid(i, 0), [(13, [key(0, cx)]), (14, [key(0, cy - HANG)])]))
    return "".join(kin), "".join(kout)


def card_animations():
    out = []
    for i in range(len(CARDS)):
        pop, burst, glow, lift, card, edge = (cid(i, 1), cid(i, 8), cid(i, 7),
                                              cid(i, 2), cid(i, 3), cid(i, 4))
        swing = 0.5 if i % 2 == 0 else -0.5
        idle_len = 156 + (i * 37) % 48          # 2.6s .. 3.4s
        sway = 0.035 if i % 2 else -0.035
        out.append(f'''
        <LinearAnimation duration="1" name="Game{i + 1}Hidden" id="{cid(i, 20)}">
            {keyed(pop, [(16, [key(0, 0)]), (17, [key(0, 0)]), (15, [key(0, 0)]), (18, [key(0, 0)])])}
            {keyed(burst, [(18, [key(0, 0)])])}
        </LinearAnimation>
        <LinearAnimation duration="{wait_frames(i)}" name="Game{i + 1}Wait" id="{cid(i, 26)}">
            {keyed(pop, [(16, [key(0, 0)]), (17, [key(0, 0)]), (15, [key(0, 0)]), (18, [key(0, 0)])])}
            {keyed(burst, [(18, [key(0, 0)])])}
        </LinearAnimation>
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
            {keyed(pop, [
                (16, [key(0, 1)]), (17, [key(0, 1)]), (18, [key(0, 1)]),
                (15, [key(0, -sway, EASE_IO), key(idle_len, sway)])])}
            {keyed(burst, [(18, [key(0, 0)])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Game{i + 1}Normal" id="{cid(i, 23)}">
            {keyed(lift, [(16, [key(0, 1)]), (17, [key(0, 1)])])}
            {keyed(card, [(18, [key(0, 1)])])}
            {keyed(glow, [(18, [key(0, 0)])])}
            {keyed(edge, [(37, [key(0, "59F2F3F5", kind="Color")])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Game{i + 1}Selected" id="{cid(i, 24)}">
            {keyed(lift, [(16, [key(0, 1.16)]), (17, [key(0, 1.16)])])}
            {keyed(card, [(18, [key(0, 1)])])}
            {keyed(glow, [(18, [key(0, 1)])])}
            {keyed(edge, [(37, [key(0, "FFE8B84B", kind="Color")])])}
        </LinearAnimation>
        <LinearAnimation duration="1" name="Game{i + 1}Dimmed" id="{cid(i, 25)}">
            {keyed(lift, [(16, [key(0, 0.94)]), (17, [key(0, 0.94)])])}
            {keyed(card, [(18, [key(0, 0.5)])])}
            {keyed(glow, [(18, [key(0, 0)])])}
            {keyed(edge, [(37, [key(0, "33F2F3F5", kind="Color")])])}
        </LinearAnimation>''')
    s = TREE_SCALE
    out.append(f'''
        <LinearAnimation duration="1" name="TreeRest" id="5:20300">
            {keyed(TREE, [(16, [key(0, s)]), (17, [key(0, s)])])}
        </LinearAnimation>
        <LinearAnimation duration="34" name="TreeRustle" id="5:20301">
            {keyed(TREE, [
                (16, [key(0, s, EASE_OUT), key(8, round(s * 1.025, 4), EASE_IO), key(20, round(s * 0.992, 4), EASE_IO), key(34, s)]),
                (17, [key(0, s, EASE_OUT), key(8, round(s * 0.972, 4), EASE_IO), key(20, round(s * 1.012, 4), EASE_IO), key(34, s)])])}
        </LinearAnimation>''')
    return "".join(out)


# ------------------------------------------------------------ state machine
def card_layers():
    out = []
    for i in range(len(CARDS)):
        n = i + 1
        idx = i
        s = lambda k: cid(i, 40 + k)   # noqa: E731
        out.append(f'''
            <StateMachineLayer name="Game{n} presence" id="{cid(i, 30)}">
                <AnyState x="0" y="{200 + i * 40}"/>
                <ExitState x="900" y="{200 + i * 40}"/>
                <EntryState x="0" y="{120 + i * 40}"><StateTransition stateToId="{s(0)}"/></EntryState>
                <AnimationState x="220" y="0" animationId="{cid(i, 20)}" id="{s(0)}">
                    <StateTransition stateToId="{s(6)}">{num_cond(P_FOUND, "greaterThanOrEqual", n)}</StateTransition>
                </AnimationState>
                <AnimationState x="330" y="-120" animationId="{cid(i, 26)}" id="{s(6)}">
                    <StateTransition stateToId="{s(1)}" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/>
                    <StateTransition stateToId="{s(0)}">{num_cond(P_FOUND, "lessThan", n)}</StateTransition>
                </AnimationState>
                <AnimationState x="440" y="0" animationId="{cid(i, 21)}" id="{s(1)}">
                    <StateTransition stateToId="{s(2)}" duration="300" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100"/>
                </AnimationState>
                <AnimationState x="660" y="0" animationId="{cid(i, 22)}" id="{s(2)}">
                    <StateTransition stateToId="{s(0)}" duration="150">{num_cond(P_FOUND, "lessThan", n)}</StateTransition>
                </AnimationState>
            </StateMachineLayer>
            <StateMachineLayer name="Game{n} focus" id="{cid(i, 31)}">
                <AnyState x="0" y="{500 + i * 40}"/>
                <ExitState x="900" y="{500 + i * 40}"/>
                <EntryState x="0" y="{420 + i * 40}"><StateTransition stateToId="{s(3)}"/></EntryState>
                <AnimationState x="220" y="300" animationId="{cid(i, 23)}" id="{s(3)}">
                    <StateTransition stateToId="{s(4)}" duration="200">{num_cond(P_SELECTED, "equal", idx)}</StateTransition>
                    <StateTransition stateToId="{s(5)}" duration="200">{num_cond(P_SELECTED, "notEqual", idx)}{num_cond(P_SELECTED, "greaterThanOrEqual", 0)}</StateTransition>
                </AnimationState>
                <AnimationState x="440" y="300" animationId="{cid(i, 24)}" id="{s(4)}">
                    <StateTransition stateToId="{s(3)}" duration="200">{num_cond(P_SELECTED, "lessThan", 0)}</StateTransition>
                    <StateTransition stateToId="{s(5)}" duration="200">{num_cond(P_SELECTED, "notEqual", idx)}{num_cond(P_SELECTED, "greaterThanOrEqual", 0)}</StateTransition>
                </AnimationState>
                <AnimationState x="660" y="300" animationId="{cid(i, 25)}" id="{s(5)}">
                    <StateTransition stateToId="{s(4)}" duration="200">{num_cond(P_SELECTED, "equal", idx)}</StateTransition>
                    <StateTransition stateToId="{s(3)}" duration="200">{num_cond(P_SELECTED, "lessThan", 0)}</StateTransition>
                </AnimationState>
            </StateMachineLayer>''')
    out.append(f'''
            <StateMachineLayer name="Tree rustle" id="5:20310">
                <AnyState x="0" y="800"/>
                <ExitState x="900" y="800"/>
                <EntryState x="0" y="720"><StateTransition stateToId="5:20311"/></EntryState>
                <AnimationState x="220" y="720" animationId="5:20300" id="5:20311">
                    <StateTransition stateToId="5:20312">{bool_cond(P_RUSTLE, True)}</StateTransition>
                </AnimationState>
                <AnimationState x="440" y="720" animationId="5:20301" id="5:20312">
                    <StateTransition stateToId="5:20311" enableExitTime="true" exitTimeIsPercetange="true" exitTime="100">{bool_cond(P_RUSTLE, False)}</StateTransition>
                </AnimationState>
            </StateMachineLayer>''')
    return "".join(out)


def listeners():
    out = []
    for i in range(len(CARDS)):
        out.append(f'''
            <StateMachineListenerSingle targetId="{cid(i, 9)}" listenerTypeValue="click" name="TapGame{i + 1}" id="{cid(i, 50)}">
                {write_number(P_SELECTED, i)}
            </StateMachineListenerSingle>''')
    out.append(f'''
            <StateMachineListenerSingle targetId="{SKY}" listenerTypeValue="click" name="TapSky" id="5:20400">
                {write_number(P_SELECTED, -1)}
            </StateMachineListenerSingle>
            <StateMachineListenerSingle targetId="5:20201" listenerTypeValue="down" name="CanopyDown" id="5:20401">
                {write_bool(P_RUSTLE, True)}
                {write_number(P_SELECTED, -1)}
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
    p = [f'<ViewModelPropertyNumber name="selected" id="{P_SELECTED}"/>']
    p += [f'<ViewModelPropertyAssetImage name="cover{i + 1}" id="5:{P_COVER0 + i}"/>'
          for i in range(len(CARDS))]
    p.append(f'<ViewModelPropertyBoolean name="rustle" id="{P_RUSTLE}"/>')
    return "".join(p)


def vm_values():
    v = [f'<ViewModelInstanceNumber propertyValue="-1" viewModelPropertyId="{P_SELECTED}"/>']
    v += [f'<ViewModelInstanceAssetImage propertyValue="5:{9981 + i}" viewModelPropertyId="5:{P_COVER0 + i}"/>'
          for i in range(len(CARDS))]
    v.append(f'<ViewModelInstanceBoolean propertyValue="false" viewModelPropertyId="{P_RUSTLE}"/>')
    return "".join(v)


def image_assets():
    return "".join(f'<ImageAsset file="covers/cover{i + 1}.png" name="cover{i + 1}" id="5:{9981 + i}"/>'
                   for i in range(len(CARDS)))
