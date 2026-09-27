"""Place the 12 fruit so they hang INSIDE the canopy at every size the tree
passes through, not just at full growth.

Why a solver: the cards follow the three leaf clusters, and their offset from a
cluster blends linearly between two poses (sapling / full). The canopy itself
does not grow linearly, so offsets hand-placed on the full tree put a young
tree's fruit on top of its leaves with their stems in the sky. This measures the
real canopy at each game count and searches, card by card in pop order, for the
two poses that keep every card's stem inside the leaves and no two cards
overlapping, at every game count from the one that first shows it up to 12.

  python rive/tree/fit.py          # measure, solve, write tree/fruit.json
  python rive/tree/fit.py --check  # re-verify fruit.json against fresh renders

Game count -> tree size uses the same curve as the app (tree_size in
rive_tree.dart): early games grow the tree most, so a tree holding 3 games
already carries a real canopy.
"""
import json
import math
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RIVE = os.path.expandvars(r"%USERPROFILE%\.rive\bin\rive.exe")
sys.path.insert(0, HERE)
import build_tree as B  # noqa: E402

SLOTS = 12
CARD_W, CARD_H = 40, 53
EARLY_SCALE = 0.62          # card size on a sapling (x full size)
GAP = 4                     # px between any two visible cards
DEPTH = 6                   # stem top at least this far inside the leaves
GRID = 2                    # mask sampling step (px)
CLUSTERS = {"center": "5:1232", "right": "5:1215", "left": "5:1201"}
SHAPE = 1.8                 # must equal kTreeGrowthShape in rive_tree.dart


def tree_size(games):
    t = min(max(games, 0), SLOTS) / SLOTS
    return SLOTS * (1 - (1 - t) ** SHAPE)


def blend(games):
    g = 20 + 80 * tree_size(games) / SLOTS      # growth 20..100 (build_tree)
    return g / 100


def stem_len(i):
    return 9 + (i * 5) % 9


def tilt(i):
    return round(((i * 7) % 5 - 2) * 0.03, 3)


# -------------------------------------------------------------- measuring
def render(size, path):
    subprocess.run([RIVE, ".", "--artboard=TreeDiscovery", f"--screenshot={path}",
                    f"--data=grown={size:.4f}", "--advance=240"],
                   cwd=HERE, capture_output=True, check=True)
    return Image.open(path).convert("RGB")


def leaf(c):
    r, g, b = c
    return r > 105 and r - g > 45 and r >= b and b > 0.4 * r   # rose, not bark


def centroid(px, w, h, test):
    xs = ys = n = 0
    for y in range(h):
        for x in range(w):
            if test(px[x, y]):
                xs += x
                ys += y
                n += 1
    return (xs / n, ys / n) if n else None


def measure():
    rml, _ = B.build(debug=True)
    open(B.OUT, "w", encoding="utf-8", newline="\n").write(rml)
    out = {}
    for n in range(1, SLOTS + 1):
        im = render(tree_size(n), os.path.join(ROOT, "build", f"_fit{n}.png"))
        w, h = im.size
        px = im.load()
        mask = set((x, y) for y in range(0, h, GRID) for x in range(0, w, GRID)
                   if leaf(px[x, y]))
        dots = {
            "center": centroid(px, w, h, lambda c: c[0] > 240 and c[1] < 20 and c[2] < 20),
            "right": centroid(px, w, h, lambda c: c[1] > 240 and c[0] < 20 and c[2] < 20),
            "left": centroid(px, w, h, lambda c: c[2] > 240 and c[1] > 150 and c[0] < 20),
        }
        ys = sorted(p[1] for p in mask)
        xs = sorted(p[0] for p in mask)
        q = lambda v, f: v[int(f * (len(v) - 1))]   # noqa: E731
        # percentiles, so a stray petal near the ground does not stretch it
        out[n] = {"mask": mask, "t": dots,
                  "box": (q(xs, 0.01), q(ys, 0.01), q(xs, 0.99), q(ys, 0.97))}
        print(f"n={n:2d} size={tree_size(n):5.2f} canopy={out[n]['box']}", flush=True)
    return out


# ---------------------------------------------------------------- geometry
def snap(v):
    return int(round(v / GRID)) * GRID


def inside(mask, x, y, depth=DEPTH):
    return all((snap(x + dx), snap(y + dy)) in mask
               for dx, dy in ((0, 0), (depth, 0), (-depth, 0), (0, depth), (0, -depth)))


def card_rect(m, n, cl, a, b, i):
    """(node x, node y, rect) of card i at n games."""
    k = blend(n)
    tx, ty = m[n]["t"][cl]
    nx = tx + a[0] + (b[0] - a[0]) * k
    ny = ty + a[1] + (b[1] - a[1]) * k
    sc = EARLY_SCALE + (1 - EARLY_SCALE) * k
    cy = ny + sc * (stem_len(i) + CARD_H / 2)
    hw, hh = sc * CARD_W / 2, sc * CARD_H / 2
    return nx, ny, (nx - hw, cy - hh, nx + hw, cy + hh)


def overlap(r, q, gap=GAP):
    return not (r[2] + gap <= q[0] or q[2] + gap <= r[0] or
                r[3] + gap <= q[1] or q[3] + gap <= r[1])


def feasible(m, placed, i, cl, a, b):
    """Every game count that shows card i: stem in the leaves, card clear of
    every other visible card, card not poking above the canopy."""
    for n in range(i + 1, SLOTS + 1):
        nx, ny, r = card_rect(m, n, cl, a, b, i)
        if not inside(m[n]["mask"], nx, ny):
            return False
        if r[1] < m[n]["box"][1] + 4:
            return False
        for j, p in enumerate(placed):
            if overlap(r, card_rect(m, n, p["cluster_name"], p["a"], p["b"], j)[2]):
                return False
    return True


def cost(m, placed, i, cl, a, b):
    """Lower is better. Fruit hangs in the LOWER canopy (weight pulls it
    down), the first few near the middle, all of them spread apart."""
    c = 0.0
    for n in (max(i + 1, 1), SLOTS):
        x0, y0, x1, y1 = m[n]["box"]
        nx, ny, r = card_rect(m, n, cl, a, b, i)
        v = ((r[1] + r[3]) / 2 - y0) / max(1, y1 - y0)       # 0 top .. 1 bottom
        u = ((r[0] + r[2]) / 2 - (x0 + x1) / 2) / max(1, x1 - x0)
        c += 3.0 * abs(v - 0.58) + (2.0 if i < 3 else 0.3) * abs(u)
        others = [card_rect(m, n, p["cluster_name"], p["a"], p["b"], j)[2]
                  for j, p in enumerate(placed) if j < n]
        mid = lambda q: ((q[0] + q[2]) / 2, (q[1] + q[3]) / 2)  # noqa: E731
        near = min((math.dist(mid(r), mid(q)) for q in others), default=140)
        c -= 0.03 * min(near, 140)
        # the fruit as a whole balances on the trunk: no lopsided tree
        if others:
            mx = sum(mid(q)[0] for q in others + [r]) / (len(others) + 1)
            c += 2.5 * abs(mx - (x0 + x1) / 2) / max(1, x1 - x0)
    return c


def solve(m):
    full = m[SLOTS]
    placed = []
    for i in range(SLOTS):
        best = None
        # full-tree stem tops: every leaf point deep enough, on a coarse grid
        cand_b = [(x, y) for (x, y) in full["mask"] if x % 6 == 0 and y % 6 == 0
                  and inside(full["mask"], x, y)]
        scored = []
        for (x, y) in cand_b:
            cl = min(CLUSTERS, key=lambda k: math.dist((x, y), full["t"][k]))
            tx, ty = full["t"][cl]
            # b is solved at k=blend(12)=1, so node = t + b there
            b = (x - tx, y - ty)
            _, _, r = card_rect(m, SLOTS, cl, b, b, i)
            if r[1] < full["box"][1] + 4:
                continue
            if any(overlap(r, card_rect(m, SLOTS, p["cluster_name"], p["a"], p["b"], j)[2])
                   for j, p in enumerate(placed)):
                continue
            scored.append((cost(m, placed, i, cl, b, b), cl, b))
        scored.sort()
        for _, cl, b in scored[:60]:
            for f in (0.35, 0.45, 0.55, 0.65, 0.75, 0.9, 1.0):
                for dy in (0, 6, 12, 18, -6):
                    for dx in (0, -6, 6):
                        a = (b[0] * f + dx, b[1] * f + dy)
                        if not feasible(m, placed, i, cl, a, b):
                            continue
                        c = cost(m, placed, i, cl, a, b)
                        if best is None or c < best[0]:
                            best = (c, cl, a, b)
            if best and len(scored) > 20 and best[0] < scored[0][0] + 0.3:
                break
        if best is None:
            raise SystemExit(f"no placement for card {i + 1}")
        _, cl, a, b = best
        placed.append({"cluster_name": cl, "a": a, "b": b})
        print(f"card {i + 1:2d} on {cl:6s} sapling {tuple(round(v, 1) for v in a)} "
              f"full {tuple(round(v, 1) for v in b)}", flush=True)
    return placed


def write(m, placed):
    out = []
    for i, p in enumerate(placed):
        _, _, r = card_rect(m, SLOTS, p["cluster_name"], p["a"], p["b"], i)
        out.append({"cluster": CLUSTERS[p["cluster_name"]], "cluster_name": p["cluster_name"],
                    "a": [round(v, 1) for v in p["a"]], "b": [round(v, 1) for v in p["b"]],
                    "stem": stem_len(i), "tilt": tilt(i),
                    "pos": [round((r[0] + r[2]) / 2, 1), round((r[1] + r[3]) / 2, 1)]})
    with open(os.path.join(HERE, "fruit.json"), "w") as fh:
        json.dump({"early_scale": EARLY_SCALE, "shape": SHAPE, "cards": out}, fh, indent=1)
    print("wrote fruit.json")


def check(m):
    cards = json.load(open(os.path.join(HERE, "fruit.json")))["cards"]
    placed = [{"cluster_name": c["cluster_name"], "a": c["a"], "b": c["b"]} for c in cards]
    bad = 0
    for i in range(SLOTS):
        if not feasible(m, placed[:i], i, placed[i]["cluster_name"], placed[i]["a"], placed[i]["b"]):
            print(f"card {i + 1} FAILS"); bad += 1
    print("check:", "all 12 cards inside the canopy, no overlap, at every game count"
          if not bad else f"{bad} failing")
    return bad


def main():
    m = measure()
    try:
        if "--check" in sys.argv:
            sys.exit(1 if check(m) else 0)
        write(m, solve(m))
    finally:
        # restore the real scene (a fresh process, so discovery.py re-reads
        # the fruit.json just written)
        subprocess.run([sys.executable, os.path.join(HERE, "build_tree.py")], check=True)


if __name__ == "__main__":
    main()
