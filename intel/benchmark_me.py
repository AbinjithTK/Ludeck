"""Benchmark YOUR Shipaton entry against the real competitor corpus.

Most "is my project good enough" checks compare against a generic idea of
quality. This one compares against the actual field: 1,000+ scraped Shipaton
submissions sitting in data/projects.json.

It measures only what is MEASURABLE from a submission record. It cannot judge
whether your app is fun, beautiful, or a good idea. Those go to the rubric half
of the audit (see the shipaton-polish-audit skill). What it CAN tell you is
whether your writeup is thinner than the median rival's, whether your gallery is
sparse, and where the top decile actually sits -- which is the part people guess
at and get wrong.

The comparison cohort is deliberately NOT all projects. It is the ELIGIBLE ones
(store listing + demo video + RevenueCat declared), because the other half
cannot win and comparing against them flatters you.

Usage:
    python benchmark_me.py                 # show the field thresholds only
    python benchmark_me.py --me me.json    # place your entry in the distribution

me.json shape (every field optional; omit what you do not have yet):
    {
      "name": "Hoard",
      "description_chars": 3200,
      "gallery_images": 8,
      "built_with_count": 11,
      "team_size": 1,
      "apple": false,
      "google": true,
      "video": true,
      "revenuecat": true,
      "sponsor_sdks": ["onesignal", "layers"]
    }
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent

STORE_APPLE = re.compile(r"apps\.apple\.com|itunes\.apple\.com", re.I)
STORE_GOOGLE = re.compile(r"play\.google\.com", re.I)
STORE_SAMSUNG = re.compile(r"galaxystore\.samsung\.com|apps\.samsung\.com", re.I)
RC = re.compile(r"^revenuecat", re.I)

SPONSOR_SDK = {
    "onesignal": r"^onesignal",
    "layers": r"^layers$",
    "stripe": r"^stripe",
    "replit": r"^replit",
    "kotlin-multiplatform": r"kotlin-multiplatform|compose-multiplatform",
    "samsung": r"^samsung|galaxy",
}

AXES = [
    ("description_chars", "writeup length (chars)"),
    ("gallery_images", "gallery images"),
    ("built_with_count", "built-with tags"),
    ("team_size", "team size"),
    ("likes", "likes"),
]

# Axes worth acting on. team_size is not fixable (and the field median is 1, so
# solo is normal, not a deficit). likes are noise: median 0, max 8 across 490
# eligible projects, and systematically biased against late arrivals.
ACTIONABLE = {"description_chars", "gallery_images", "built_with_count"}


def load() -> list[dict]:
    with (HERE / "data" / "projects.json").open(encoding="utf-8") as fh:
        return json.load(fh)


def eligible(rec: dict) -> bool:
    blob = json.dumps(rec, ensure_ascii=False)
    has_store = bool(
        STORE_APPLE.search(blob) or STORE_GOOGLE.search(blob) or STORE_SAMSUNG.search(blob)
    )
    has_video = bool(rec.get("video_url"))
    has_rc = any(RC.search(t.lower()) for t in (rec.get("built_with") or []))
    return has_store and has_video and has_rc


def axis_value(rec: dict, key: str) -> int:
    if key == "built_with_count":
        return len(rec.get("built_with") or [])
    return int(rec.get(key) or 0)


def pct_rank(sorted_vals: list[int], v: int) -> int:
    """Midpoint percentile of v within sorted_vals (0-100).

    Counts values below PLUS half the ties. The naive "count strictly below"
    definition breaks on low-variance axes: when almost every project has a team
    size of 1, a team of 1 scores 0th percentile and reads as bottom of the
    field, which is nonsense. Ties are shared, not lost.
    """
    if not sorted_vals:
        return 0
    below = sum(1 for x in sorted_vals if x < v)
    ties = sum(1 for x in sorted_vals if x == v)
    return round(100 * (below + ties / 2) / len(sorted_vals))


def quantile(sorted_vals: list[int], q: float) -> int:
    if not sorted_vals:
        return 0
    idx = min(len(sorted_vals) - 1, max(0, int(round(q * (len(sorted_vals) - 1)))))
    return sorted_vals[idx]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--me", default=None, help="path to me.json")
    args = ap.parse_args()

    records = load()
    cohort = [r for r in records if eligible(r)]

    print(f"corpus: {len(records)} projects, {len(cohort)} eligible (store + video + RevenueCat)")
    print(f"        eligible share: {round(100*len(cohort)/max(1,len(records)))}%\n")

    # Structural bars: what fraction of the cohort clears each one.
    both_stores = 0
    sdk_counts: list[int] = []
    for r in cohort:
        blob = json.dumps(r, ensure_ascii=False)
        if STORE_APPLE.search(blob) and STORE_GOOGLE.search(blob):
            both_stores += 1
        built = [t.lower() for t in (r.get("built_with") or [])]
        sdk_counts.append(
            sum(1 for pat in SPONSOR_SDK.values() if any(re.search(pat, t) for t in built))
        )

    print("STRUCTURAL BARS (share of the eligible cohort)")
    print(f"  published to BOTH Apple and Google   {round(100*both_stores/len(cohort))}%")
    print(f"  declares >=1 extra sponsor SDK       "
          f"{round(100*sum(1 for c in sdk_counts if c >= 1)/len(cohort))}%")
    print(f"  declares >=2 extra sponsor SDKs      "
          f"{round(100*sum(1 for c in sdk_counts if c >= 2)/len(cohort))}%")
    print()

    dists: dict[str, list[int]] = {}
    print(f"{'axis':<26}{'p25':>8}{'median':>8}{'p75':>8}{'p90':>8}{'max':>9}")
    print("-" * 67)
    for key, label in AXES:
        vals = sorted(axis_value(r, key) for r in cohort)
        dists[key] = vals
        print(
            f"{label:<26}{quantile(vals,0.25):>8}{int(statistics.median(vals)):>8}"
            f"{quantile(vals,0.75):>8}{quantile(vals,0.90):>8}{vals[-1]:>9}"
        )

    if not args.me:
        print("\nNo --me supplied, so this is the field only.")
        print("Write a me.json (see the docstring) and re-run to place yourself.")
        return

    me = json.loads(Path(args.me).read_text(encoding="utf-8"))
    print(f"\n{'='*67}")
    print(f"YOUR ENTRY: {me.get('name', '(unnamed)')}")
    print(f"{'='*67}\n")

    weak: list[str] = []
    print(f"{'axis':<26}{'you':>8}{'median':>8}{'percentile':>12}")
    print("-" * 54)
    for key, label in AXES:
        if key not in me:
            print(f"{label:<26}{'-':>8}{int(statistics.median(dists[key])):>8}{'not set':>12}")
            continue
        v = int(me[key])
        p = pct_rank(dists[key], v)
        med = int(statistics.median(dists[key]))
        # Only mark actionable axes, or the table contradicts the verdict: a
        # tied-at-median value lands just under 50 on a midpoint percentile.
        mark = "  <- below median" if (p < 50 and key in ACTIONABLE) else ""
        print(f"{label:<26}{v:>8}{med:>8}{str(p) + 'th':>12}{mark}")
        if p < 50 and key in ACTIONABLE:
            weak.append(f"{label}: {v} vs median {med} ({p}th percentile)")

    # Hard gates.
    print("\nHARD GATES")
    gates = [
        ("store listing", bool(me.get("apple") or me.get("google") or me.get("samsung"))),
        ("demo video", bool(me.get("video"))),
        ("RevenueCat powering a purchase", bool(me.get("revenuecat"))),
    ]
    for label, ok in gates:
        print(f"  {'PASS' if ok else 'FAIL'}  {label}")
    if not all(ok for _, ok in gates):
        print("  A failed gate means the entry cannot win any category. Fix first.")

    mine_sdks = me.get("sponsor_sdks") or []
    print(f"\n  extra sponsor SDKs: {len(mine_sdks)} ({', '.join(mine_sdks) or 'none'})")
    print(f"  cohort share with >=1: "
          f"{round(100*sum(1 for c in sdk_counts if c >= 1)/len(cohort))}%")

    print("\nVERDICT")
    if weak:
        print("  Below the median rival on:")
        for w in weak:
            print(f"    - {w}")
        print("  These are cheap to fix and they are what judges actually see.")
    else:
        print("  At or above the median eligible rival on every measured axis.")
    print("\n  Measured axes only. Fun, beauty and idea quality are not in here --")
    print("  run the rubric half of the shipaton-polish-audit skill for those.")


if __name__ == "__main__":
    main()
