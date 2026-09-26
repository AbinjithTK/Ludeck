"""Print a decoded .riv as an indented hierarchy + animation/state-machine map.

Usage: python riv_outline.py build/x.decoded.json
"""
import json
import sys

LEAF = {"StraightVertex", "CubicMirroredVertex", "CubicDetachedVertex",
        "CubicAsymmetricVertex", "CubicWeight", "Weight", "GradientStop",
        "SolidColor", "Fill", "Stroke"}


def P(x):
    return {k: v["v"] for k, v in x["props"].items()}


def fmt(p):
    out = []
    for k, v in p.items():
        if k in ("name", "parentId"):
            continue
        out.append(f"{k}={v:.3g}" if isinstance(v, float) else f"{k}={v}")
    return " ".join(out)


def main(path):
    o = json.load(open(path, encoding="utf-8"))["objects"]
    ab = next(i for i, x in enumerate(o) if x["type"] == "Artboard")
    loc = o[ab:]
    comps = {}
    for li, x in enumerate(loc):
        if x["type"] in ("LinearAnimation", "StateMachine"):
            break
        comps[li] = x
    kids = {}
    for li, x in comps.items():
        if li:
            kids.setdefault(P(x).get("parentId", 0), []).append(li)

    def show(i, dep):
        x = comps[i]
        if x["type"] in LEAF:
            return
        p = P(x)
        print("  " * dep + f"{i} {x['type']} {p.get('name', '')}  {fmt(p)}")
        for c in kids.get(i, []):
            show(c, dep + 1)

    show(0, 0)

    print("\n== animations / state machine ==")
    anim_i = -1
    for x in loc[len(comps):]:
        t = x["type"]
        p = P(x)
        if t == "LinearAnimation":
            anim_i += 1
            print(f"ANIM[{anim_i}] {p.get('name')}  {fmt(p)}")
        elif t == "KeyedObject":
            oid = p.get("objectId")
            tgt = comps.get(oid)
            print(f"   obj {oid} {tgt['type'] if tgt else '?'} "
                  f"{P(tgt).get('name', '') if tgt else ''}")
        elif t == "KeyedProperty":
            print(f"      prop {p.get('propertyKey')}")
        elif t.startswith("KeyFrame") or t in LEAF:
            continue
        else:
            print(f"{t} {p.get('name', '')}  {fmt(p)}")


if __name__ == "__main__":
    main(sys.argv[1])
