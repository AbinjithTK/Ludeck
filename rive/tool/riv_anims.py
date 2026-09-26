"""Print every animation's keyframes per object/property, compactly.

Usage: python riv_anims.py build/x.decoded.json
"""
import json
import sys

PROPS = {13: "x", 14: "y", 15: "rot", 16: "sx", 17: "sy", 18: "op",
         37: "col", 7: "w", 8: "h"}


def P(x):
    return {k: v["v"] for k, v in x["props"].items()}


def main(path):
    o = json.load(open(path, encoding="utf-8"))["objects"]
    ab = next(i for i, x in enumerate(o) if x["type"] == "Artboard")
    loc = o[ab:]
    end = next(i for i, x in enumerate(loc) if x["type"] == "LinearAnimation")
    comps = loc[:end]
    line = []
    n = -1

    def flush():
        if line:
            print(" ".join(line))
            line.clear()

    for x in loc[end:]:
        t = x["type"]
        p = P(x)
        if t == "LinearAnimation":
            flush()
            n += 1
            print(f"\nANIM[{n}] {p.get('name')} dur={p.get('duration', 60)} "
                  f"fps={p.get('fps', 60)} loop={p.get('loopValue', 0)}")
        elif t == "KeyedObject":
            flush()
            ob = comps[p["objectId"]]
            nm = P(ob).get("name") or ob["type"]
            line.append(f"  #{p['objectId']} {nm}")
        elif t == "KeyedProperty":
            line.append(f"| {PROPS.get(p['propertyKey'], p['propertyKey'])}:")
        elif t.startswith("KeyFrame"):
            v = p.get("value")
            fr = p.get("frame", 0)
            if isinstance(v, float):
                line.append(f"{fr}={v:.2f}")
            elif t == "KeyFrameColor":
                line.append(f"{fr}={v:08X}")
            else:
                line.append(f"{fr}={v}")
        elif t in ("StateMachine",):
            break
    flush()


if __name__ == "__main__":
    main(sys.argv[1])
