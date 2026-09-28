"""Contact sheet of the shake: tree sway, fruit swing, petals, the fall.

  python rive/tree/shake_sheet.py            -> rive/build/shake_sheet.png

Builds a TEST scene (preview sky + the corner hook that sets drop=0), renders
the shake at several frames, then rebuilds the plain scene so nothing test-only
is left in scene.rml.
"""
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RIVE = os.path.expandvars(r"%USERPROFILE%\.rive\bin\rive.exe")
FRAMES = [int(a) for a in sys.argv[1:]] or [1, 8, 16, 24, 30, 40, 56, 80]


def build(test):
    env = dict(os.environ)
    if test:
        env["TREE_PREVIEW_SKY"] = "1"
    else:
        env.pop("TREE_PREVIEW_SKY", None)
    args = [sys.executable, os.path.join(HERE, "build_tree.py")] + (["--test-hooks"] if test else [])
    subprocess.run(args, cwd=HERE, env=env, check=True, capture_output=True)


def main():
    build(True)
    ims = []
    for f in FRAMES:
        out = os.path.join(ROOT, "build", f"_shake_{f}.png")
        r = subprocess.run([RIVE, ".", "--artboard=TreeDiscovery", f"--screenshot={out}",
                            "--data=grown=8", "--data=found=6", "--advance=150",
                            "--pointer=down@20,20", f"--advance={f}"],
                           cwd=HERE, capture_output=True, text=True, timeout=120)
        if not os.path.exists(out):
            raise SystemExit(r.stdout + r.stderr)
        ims.append(Image.open(out).convert("RGB").crop((10, 170, 402, 700)))
    build(False)
    iw, ih = ims[0].size
    s = 0.5
    cols = 4
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (int(iw * s) * cols, int(ih * s) * rows))
    for n, im in enumerate(ims):
        sheet.paste(im.resize((int(iw * s), int(ih * s)), Image.LANCZOS),
                    ((n % cols) * int(iw * s), (n // cols) * int(ih * s)))
    p = os.path.join(ROOT, "build", "shake_sheet.png")
    sheet.save(p)
    print(p, sheet.size)


if __name__ == "__main__":
    main()
