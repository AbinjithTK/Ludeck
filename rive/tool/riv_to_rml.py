"""Convert a decoded runtime .riv (riv_decode.py) into RML.

Runtime files reference things by INDEX; RML references by id. This maps:
  parentId                       -> element nesting
  component refs (sourceId, targetId, drawableId, drawTargetId, boneId,
    KeyedObject.objectId, KeyFrameId.value) -> "P:<artboard-local index>"
  interpolatorId                 -> the interpolator nested inside the key
  animationId                    -> "P:<ANIM_BASE + animation index>"
  stateToId                      -> id of the n-th state in the same layer
  inputId                        -> "P:<INPUT_BASE + input index>"
Owned-by-previous objects (KeyedObject under LinearAnimation, transitions
under their state, conditions under their transition, ...) are nested by
file order, which is how the runtime importer attaches them too.

Usage: python riv_to_rml.py build/x.decoded.json out.rml --prefix 5 --name Tree
"""
import argparse
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

ANIM_BASE = 9000
INPUT_BASE = 9500
SM_BASE = 9600
VM_BASE = 9800
OPS = ["equal", "notEqual", "lessThanOrEqual", "greaterThanOrEqual",
       "lessThan", "greaterThan"]

COMPONENT_REFS = {"sourceId", "targetId", "drawableId", "drawTargetId",
                  "boneId", "objectId"}
STATE_TYPES = {"EntryState", "AnyState", "ExitState", "AnimationState",
               "BlendState1DInput", "BlendState1DViewModel", "BlendStateDirect"}
CONDITION_TYPES = {"TransitionNumberCondition", "TransitionBoolCondition",
                   "TransitionTriggerCondition"}
INPUT_TYPES = {"StateMachineNumber", "StateMachineBool", "StateMachineTrigger"}
INTERP_TYPES = {"CubicEaseInterpolator", "CubicValueInterpolator",
                "ElasticInterpolator"}


def fmt_num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        if math.isnan(v) or math.isinf(v):
            return "0"
        s = f"{v:.7g}"
        return s
    return str(v)


class Conv:
    def __init__(self, doc, prefix, name, schema, vm=None):
        self.vm = vm
        self.o = doc["objects"]
        self.P = str(prefix)
        self.name = name
        self.types = {}
        for n, s in schema.items():
            self.types[n] = {p["name"]: p for p in s["properties"]}

    def pid(self, n):
        # +100: low object numbers are reserved for system enums.
        return f"{self.P}:{n + 100}"

    def vm_path(self, input_index):
        # Input index counts every SM input; numbers were renumbered 0.. in order.
        return f"{self.pid(VM_BASE)}-{self.pid(VM_BASE + 1 + input_index)}"

    def attrs(self, x, skip=(), extra=None):
        out = []
        tprops = self.types.get(x["type"], {})
        for k, v in x["props"].items():
            v = v["v"]
            if k in skip or k in ("parentId", "stageX", "stageY", "dependentIds"):
                continue
            meta = tprops.get(k)
            if meta is None:
                continue  # not authorable on this type in RML
            t = meta["type"]
            if t == "Color":
                v = f"{v:08X}"
            elif t == "String":
                v = (str(v).replace("&", "&amp;").replace('"', "&quot;")
                     .replace("<", "&lt;"))
            elif isinstance(v, dict):
                continue  # raw bytes
            else:
                v = fmt_num(v)
            out.append(f'{k}="{v}"')
        for k, v in (extra or {}).items():
            out.append(f'{k}="{v}"')
        return " ".join(out)

    def run(self):
        o = self.o
        ab = next(i for i, x in enumerate(o) if x["type"] == "Artboard")
        loc = o[ab:]
        end = next((i for i, x in enumerate(loc)
                    if x["type"] in ("LinearAnimation", "StateMachine")), len(loc))
        comps = loc[:end]
        rest = loc[end:]
        self.comps = comps

        kids = {}
        for i, x in enumerate(comps):
            if i == 0 or x["type"] in INTERP_TYPES:
                continue
            kids.setdefault(x["props"].get("parentId", {"v": 0})["v"], []).append(i)
        self.kids = kids

        lines = []
        w = lambda d, s: lines.append("    " * d + s)

        sm_count = sum(1 for x in rest if x["type"] == "StateMachine")
        art = comps[0]
        ab_attrs = self.attrs(art, skip=("name",))
        dsm = f' defaultStateMachineId="{self.pid(SM_BASE)}"' if sm_count else ""
        w(0, '<Rive version="1" kind="fragment">')
        vmid = ""
        if self.vm:
            # Deprecated StateMachineNumber inputs become view-model numbers,
            # so hosts (and `rive --data`) can drive them by name.
            nums = [x["props"].get("name", {"v": f"input{n}"})["v"]
                    for n, x in enumerate(r for r in rest if r["type"] in INPUT_TYPES)
                    if x["type"] == "StateMachineNumber"]
            w(1, f'<ViewModel defaultInstanceId="{self.pid(VM_BASE + 99)}" '
                 f'name="{self.vm}" id="{self.pid(VM_BASE)}">')
            for n, nm in enumerate(nums):
                w(2, f'<ViewModelPropertyNumber name="{nm}" id="{self.pid(VM_BASE + 1 + n)}"/>')
            w(2, f'<ViewModelInstance exports="true" name="Default" id="{self.pid(VM_BASE + 99)}">')
            for n, _ in enumerate(nums):
                w(3, f'<ViewModelInstanceNumber propertyValue="0" '
                     f'viewModelPropertyId="{self.pid(VM_BASE + 1 + n)}"/>')
            w(2, "</ViewModelInstance>")
            w(1, "</ViewModel>")
            vmid = f' viewModelId="{self.pid(VM_BASE)}"'
        w(1, f'<Artboard{vmid}{dsm} styleId="{self.pid(8999)}" {ab_attrs} '
             f'name="{self.name}" id="{self.pid(0)}">')
        w(2, f'<LayoutComponentStyle name="Artboard Style" id="{self.pid(8999)}"/>')
        for c in kids.get(0, []):
            self.emit_comp(c, 2, w)

        # animations, then state machines, nested by file order
        anim_i = -1
        i = 0
        open_stack = []  # (depth, closing tag)

        def close_to(depth):
            while open_stack and open_stack[-1][0] >= depth:
                d, tag = open_stack.pop()
                w(d, f"</{tag}>")

        state_idx = {}
        layer_states = []
        input_i = -1
        sm_i = -1
        while i < len(rest):
            x = rest[i]
            t = x["type"]
            p = {k: v["v"] for k, v in x["props"].items()}
            if t == "LinearAnimation":
                close_to(2)
                anim_i += 1
                w(2, f'<LinearAnimation {self.attrs(x)} id="{self.pid(ANIM_BASE + anim_i)}">')
                open_stack.append((2, "LinearAnimation"))
            elif t == "KeyedObject":
                close_to(3)
                w(3, f'<KeyedObject objectId="{self.pid(p["objectId"])}">')
                open_stack.append((3, "KeyedObject"))
            elif t == "KeyedProperty":
                close_to(4)
                w(4, f'<KeyedProperty {self.attrs(x)}>')
                open_stack.append((4, "KeyedProperty"))
            elif t.startswith("KeyFrame"):
                close_to(5)
                extra = {}
                skip = ["interpolatorId"]
                if t == "KeyFrameId":
                    skip.append("value")
                    # An absent id is the runtime's "none" (-1): leave it unset.
                    if "value" in p:
                        extra["value"] = self.pid(p["value"])
                a = self.attrs(x, skip=skip, extra=extra)
                interp = p.get("interpolatorId")
                if interp is not None and interp < len(comps):
                    ic = comps[interp]
                    w(5, f"<{t} {a}>")
                    w(6, f"<{ic['type']} {self.attrs(ic, skip=('name',))}/>")
                    w(5, f"</{t}>")
                else:
                    w(5, f"<{t} {a}/>")
            elif t == "StateMachine":
                close_to(2)
                sm_i += 1
                input_i = -1
                w(2, f'<StateMachine {self.attrs(x)} id="{self.pid(SM_BASE + sm_i)}">')
                open_stack.append((2, "StateMachine"))
            elif t in INPUT_TYPES:
                close_to(3)
                input_i += 1
                if self.vm and t == "StateMachineNumber":
                    pass  # became a view-model number, declared at the top
                else:
                    w(3, f'<{t} {self.attrs(x)} id="{self.pid(INPUT_BASE + input_i)}"/>')
            elif t == "StateMachineLayer":
                close_to(3)
                # pre-scan this layer's states so stateToId can be mapped
                layer_states = []
                j = i + 1
                while j < len(rest) and rest[j]["type"] not in (
                        "StateMachineLayer", "StateMachine", "LinearAnimation"):
                    if rest[j]["type"] in STATE_TYPES:
                        layer_states.append(j)
                    j += 1
                w(3, f'<StateMachineLayer {self.attrs(x)} id="{self.pid(SM_BASE + 10 + i)}">')
                open_stack.append((3, "StateMachineLayer"))
                n_state = -1
            elif t in STATE_TYPES:
                close_to(4)
                n_state += 1
                extra = {"id": self.pid(SM_BASE + 1000 + layer_states[n_state]),
                         "x": 220 * n_state, "y": 0}
                skip = ["animationId", "inputId"]
                if "animationId" in p:
                    extra["animationId"] = self.pid(ANIM_BASE + p["animationId"])
                vm_blend = self.vm and t == "BlendState1DInput"
                if "inputId" in p and not vm_blend:
                    extra["inputId"] = self.pid(INPUT_BASE + p["inputId"])
                tag = "BlendState1DViewModel" if vm_blend else t
                w(4, f"<{tag} {self.attrs(x, skip=skip, extra=extra)}>")
                if vm_blend:
                    w(5, "<BindablePropertyNumber>")
                    w(6, f'<DataBindContext sourcePathIds="{self.vm_path(p.get("inputId", 0))}" propertyKey="636"/>')
                    w(5, "</BindablePropertyNumber>")
                open_stack.append((4, tag))
            elif t == "BlendAnimation1D":
                close_to(5)
                extra = {"animationId": self.pid(ANIM_BASE + p["animationId"])}
                w(5, f"<{t} {self.attrs(x, skip=('animationId',), extra=extra)}/>")
            elif t == "StateTransition":
                close_to(5)
                to = layer_states[p.get("stateToId", 0)]
                extra = {"stateToId": self.pid(SM_BASE + 1000 + to)}
                w(5, f"<{t} {self.attrs(x, skip=('stateToId',), extra=extra)}>")
                open_stack.append((5, t))
            elif t in CONDITION_TYPES:
                close_to(6)
                if self.vm and t == "TransitionNumberCondition":
                    op = x["props"].get("opValue", {"v": 0})["v"]
                    val = fmt_num(p.get("value", 0.0))
                    w(6, f'<TransitionViewModelCondition opValue="{OPS[op]}">')
                    w(7, "<TransitionPropertyViewModelComparator>")
                    w(8, "<BindablePropertyNumber>")
                    w(9, f'<DataBindContext sourcePathIds="{self.vm_path(p.get("inputId", 0))}" propertyKey="636"/>')
                    w(8, "</BindablePropertyNumber>")
                    w(7, "</TransitionPropertyViewModelComparator>")
                    w(7, f'<TransitionValueNumberComparator value="{val}"/>')
                    w(6, "</TransitionViewModelCondition>")
                    i += 1
                    continue
                extra = {}
                if "inputId" in p:
                    extra["inputId"] = self.pid(INPUT_BASE + p["inputId"])
                w(6, f"<{t} {self.attrs(x, skip=('inputId',), extra=extra)}/>")
            else:
                raise ValueError(f"unhandled object after components: {t}")
            i += 1
        close_to(0)
        w(1, "</Artboard>")
        w(0, "</Rive>")
        return "\n".join(lines) + "\n"

    def emit_comp(self, i, d, w):
        x = self.comps[i]
        t = x["type"]
        extra = {"id": self.pid(i)}
        skip = []
        for k, v in x["props"].items():
            if k in COMPONENT_REFS:
                skip.append(k)
                extra[k] = self.pid(v["v"])
        a = self.attrs(x, skip=skip, extra=extra)
        ch = self.kids.get(i, [])
        if not ch:
            w(d, f"<{t} {a}/>")
            return
        w(d, f"<{t} {a}>")
        for c in ch:
            self.emit_comp(c, d + 1, w)
        w(d, f"</{t}>")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("decoded")
    ap.add_argument("out")
    ap.add_argument("--prefix", default="5")
    ap.add_argument("--name", default="Tree")
    ap.add_argument("--vm", default=None,
                    help="convert number inputs to a view model of this name")
    a = ap.parse_args()
    doc = json.load(open(a.decoded, encoding="utf-8"))
    schema = json.load(open(os.path.join(HERE, "rive_schema.json"), encoding="utf-8"))
    rml = Conv(doc, a.prefix, a.name, schema, vm=a.vm).run()
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(rml)
    print(f"wrote {a.out} ({rml.count(chr(10))} lines)")


if __name__ == "__main__":
    main()
