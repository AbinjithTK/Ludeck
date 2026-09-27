"""Bake every (blossom, wood) tree variant the app can pick.

For each pair: build scene.rml with that palette, compile it with the Rive CLI,
and copy the .riv to app/assets/rive/trees/tree_<blossom>_<wood>.riv. The
default pair (blossom, plum) is also copied to app/assets/rive/tree_discovery.riv,
which the Add screen's discovery tree uses.

  python rive/tree/build_variants.py              # all pairs
  python rive/tree/build_variants.py --sheet      # + contact sheet, preview sky
  python rive/tree/build_variants.py jade oak     # one pair

Why baked, not bound: see BLOSSOMS in build_tree.py.
"""
import os
import shutil
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
APP = os.path.join(os.path.dirname(ROOT), "app", "assets", "rive")
RIVE = os.path.expandvars(r"%USERPROFILE%\.rive\bin\rive.exe")
sys.path.insert(0, HERE)
import build_tree as B  # noqa: E402

BUILT = os.path.join(HERE, "build", "tree_discovery.riv")


def bake(blossom, wood, preview=False):
    rml, _ = B.build(False, False, blossom, wood)
    # The CLI can hold scene.rml for a moment after it exits (Errno 22 on
    # Windows); retry the write briefly rather than fail the whole bake.
    import time
    for attempt in range(20):
        try:
            with open(B.OUT, "w", encoding="utf-8", newline="\n") as f:
                f.write(rml)
            break
        except OSError:
            if attempt == 19:
                raise
            time.sleep(0.25)
    if os.path.exists(BUILT):
        os.remove(BUILT)
    r = subprocess.run([RIVE, ".", "--once"], cwd=HERE, capture_output=True, text=True)
    if not os.path.exists(BUILT):
        raise SystemExit(f"{blossom}/{wood}: no .riv written\n{r.stdout}{r.stderr}")
    if not preview:
        os.makedirs(os.path.join(APP, "trees"), exist_ok=True)
        shutil.copyfile(BUILT, os.path.join(APP, "trees", f"tree_{blossom}_{wood}.riv"))
        if (blossom, wood) == ("blossom", "plum"):
            shutil.copyfile(BUILT, os.path.join(APP, "tree_discovery.riv"))
    return os.path.getsize(BUILT)


def render(path, grown=6, found=4):
    args = [RIVE, ".", "--artboard=TreeDiscovery", f"--screenshot={path}",
            f"--data=grown={grown}", f"--data=found={found}", "--advance=120"]
    r = subprocess.run(args, cwd=HERE, capture_output=True, text=True)
    if "wrote" not in r.stdout + r.stderr:
        raise SystemExit(r.stdout + r.stderr)
    return Image.open(path).convert("RGB")


def sheet(pairs, name):
    """Tile renders (on the headless preview sky) into rive/build/<name>.png."""
    os.environ["TREE_PREVIEW_SKY"] = "1"
    ims = []
    for n, (b, w) in enumerate(pairs):
        bake(b, w, preview=True)
        im = render(os.path.join(ROOT, "build", f"_{name}_{n}.png"))
        ims.append(im.crop((20, 150, 392, 700)))
    del os.environ["TREE_PREVIEW_SKY"]
    iw, ih = ims[0].size
    s = 0.5
    out = Image.new("RGB", (int(iw * s) * len(ims), int(ih * s)))
    for n, im in enumerate(ims):
        out.paste(im.resize((int(iw * s), int(ih * s)), Image.LANCZOS), (n * int(iw * s), 0))
    p = os.path.join(ROOT, "build", f"{name}.png")
    out.save(p)
    print(p, out.size)


def main(argv):
    if "--sheet" in argv:
        sheet([(b, "plum") for b in B.BLOSSOMS], "palette_blossoms")
        sheet([("blossom", w) for w in B.WOODS], "palette_woods")
        argv = [a for a in argv if a != "--sheet"]
        if not argv:
            return
    pairs = [tuple(argv)] if len(argv) == 2 else \
        [(b, w) for b in B.BLOSSOMS for w in B.WOODS]
    total = 0
    for b, w in pairs:
        n = bake(b, w)
        total += n
        print(f"{b:9s} {w:6s} {n:7d} bytes")
    print(f"{len(pairs)} variants, {total} bytes")
    # Leave the default in scene.rml so a plain `rive .` previews what shipped.
    bake("blossom", "plum", preview=True)


if __name__ == "__main__":
    main(sys.argv[1:])
