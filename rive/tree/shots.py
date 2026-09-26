"""Render TreeDiscovery states headless and tile them into one contact sheet.

Usage: python rive/tree/shots.py NAME "found=6:advance=10" "found=6:advance=120" ...
Each spec is colon-separated: data assignments (k=v) and advance=<frames>,
pointer=<kind@x,y> steps in order. Writes rive/build/NAME.png (tiled at 0.5x).
"""
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RIVE = os.path.expandvars(r"%USERPROFILE%\.rive\bin\rive.exe")


def shot(spec, path):
    args = [RIVE, ".", "--artboard=TreeDiscovery", f"--screenshot={path}"]
    for part in spec.split(":"):
        k, v = part.split("=", 1)
        if k == "advance":
            args.append(f"--advance={v}")
        elif k == "pointer":
            args.append(f"--pointer={v}")
        else:
            args.append(f"--data={k}={v}")
    r = subprocess.run(args, cwd=HERE, capture_output=True, text=True)
    if "wrote" not in r.stdout + r.stderr:
        raise SystemExit(r.stdout + r.stderr)


def main(name, specs, scale=0.5, crop=None):
    ims = []
    for n, spec in enumerate(specs):
        p = os.path.join(ROOT, "build", f"_{name}_{n}.png")
        shot(spec, p)
        im = Image.open(p).convert("RGB")
        if crop:
            x, y, w, h = crop
            im = im.crop((x, y, x + w, y + h))
        ims.append(im)
    w, h = ims[0].size
    sw, sh = int(w * scale), int(h * scale)
    sheet = Image.new("RGB", (sw * len(ims), sh))
    for n, im in enumerate(ims):
        sheet.paste(im.resize((sw, sh), Image.LANCZOS), (n * sw, 0))
    out = os.path.join(ROOT, "build", f"{name}.png")
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    args = sys.argv[1:]
    crop = scale = None
    if args and args[0].startswith("--crop="):
        crop = tuple(int(v) for v in args.pop(0)[7:].split(","))
        scale = 1.0
    main(args[0], args[1:], scale or 0.5, crop)
