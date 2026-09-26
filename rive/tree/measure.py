"""Measure the canopy and the three cluster targets at every `found` level.

Needs a --debug build (coloured dots at the targets). Prints, per level:
foliage bbox (artboard px) and the red/green/blue target positions.
Writes rive/tree/canopy.json for build_tree.py to place the cards from.
"""
import json
import os
import subprocess

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RIVE = os.path.expandvars(r"%USERPROFILE%\.rive\bin\rive.exe")


def render(found, path):
    subprocess.run([RIVE, ".", "--artboard=TreeDiscovery", f"--screenshot={path}",
                    f"--data=found={found}", "--advance=150"],
                   cwd=HERE, capture_output=True, check=True)
    return Image.open(path).convert("RGB")


def centroid(px, w, h, test):
    xs = ys = n = 0
    for y in range(h):
        for x in range(w):
            if test(px[x, y]):
                xs += x
                ys += y
                n += 1
    return (xs / n, ys / n) if n else None


def main():
    out = {}
    for f in range(7):
        im = render(f, os.path.join(ROOT, "build", f"_m{f}.png"))
        w, h = im.size
        px = im.load()
        # foliage: the tree's pinks (strong red, weak green)
        fol = [(x, y) for y in range(0, h, 2) for x in range(0, w, 2)
               if px[x, y][0] > 140 and px[x, y][1] < 110 and px[x, y][2] > 60]
        bbox = (min(p[0] for p in fol), min(p[1] for p in fol),
                max(p[0] for p in fol), max(p[1] for p in fol))
        dots = {
            "center": centroid(px, w, h, lambda c: c[0] > 240 and c[1] < 20 and c[2] < 20),
            "right": centroid(px, w, h, lambda c: c[1] > 240 and c[0] < 20 and c[2] < 20),
            "left": centroid(px, w, h, lambda c: c[2] > 240 and c[1] > 150 and c[0] < 20),
        }
        out[f] = {"bbox": bbox, "targets": dots}
        print(f, bbox, {k: tuple(round(v) for v in p) if p else None for k, p in dots.items()})
    with open(os.path.join(HERE, "canopy.json"), "w") as fh:
        json.dump(out, fh, indent=1)


if __name__ == "__main__":
    main()
