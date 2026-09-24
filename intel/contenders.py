"""Rank the Shipaton field by JUDGE-VISIBLE signal, to find likely winners.

Method, and its limits. Judging is a sub-two-minute video plus a written
argument scored against per-category criteria. None of that is in the scrape.
What IS in the scrape are proxies for effort and reach that correlate with a
serious entry: shipped to a store, has a video, declares RevenueCat, published
to BOTH stores, a long writeup, gallery screenshots, sponsor SDK breadth (which
buys multi-category eligibility), and team size.

Engagement is deliberately capped low. Likes are systematically biased against
late arrivals, and the four strongest projects in the gaming lane all have 0-3
likes. A score that leans on engagement would rank them last.

A high score means "this looks like a serious, well-presented entry", NOT
"this will win". Read the top writeups before believing anything.

Usage:
    python contenders.py [--top 30] [--lane "game backlog"]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

STORE_APPLE = re.compile(r"apps\.apple\.com|itunes\.apple\.com", re.I)
STORE_GOOGLE = re.compile(r"play\.google\.com", re.I)
STORE_SAMSUNG = re.compile(r"galaxystore\.samsung\.com|apps\.samsung\.com", re.I)

# Sponsor SDKs in built_with -> each one is a category the project can enter.
SPONSOR_SDK = {
    "revenuecat": r"^revenuecat",
    "onesignal": r"^onesignal",
    "layers": r"^layers$",
    "stripe": r"^stripe",
    "replit": r"^replit",
    "kotlin-multiplatform": r"kotlin-multiplatform|compose-multiplatform",
    "samsung": r"^samsung|galaxy",
}

# Lanes, word-boundary anchored. Grouped so one concept fires once.
LANES = {
    "game backlog": r"\bbacklog\b|game collection|games? to play|pile of shame",
    "game": r"\broguelite\b|\broguelike\b|\bplatformer\b|\bpuzzle game\b|\barcade\b|\bidle\b|\btycoon\b",
    "habit / streak": r"\bhabit\b|\bstreak\b|\broutine\b",
    "journal / reflection": r"\bjournal\b|\breflect(ion)?\b|\bdiary\b",
    "fitness": r"\bworkout\b|\bgym\b|\bfitness\b|\bpilates\b|\byoga\b",
    "food / recipe": r"\brecipe\b|\bmeal plan\b|\bcook(ing)?\b|\bnutrition\b",
    "focus / screen time": r"\bfocus timer\b|\bscreen time\b|\bpomodoro\b|\bdistraction\b",
    "money / budget": r"\bbudget\b|\bexpense\b|\bnet worth\b|\bsubscription tracker\b",
    "reading / books": r"\bbook\b|\breading\b|\bhighlight\b",
    "creator tooling": r"\bOBS\b|browser source|stream overlay|creator portal",
}


def load() -> list[dict]:
    with (HERE / "data" / "projects.json").open(encoding="utf-8") as fh:
        return json.load(fh)


def blob(rec: dict) -> str:
    return json.dumps(rec, ensure_ascii=False)


def body(rec: dict) -> str:
    parts = [str(rec.get(k) or "") for k in ("name", "tagline", "description")]
    parts.append(" ".join(rec.get("built_with") or []))
    return " ".join(parts)


def score(rec: dict) -> tuple[int, dict]:
    b = blob(rec)
    built = [t.lower() for t in (rec.get("built_with") or [])]

    apple = bool(STORE_APPLE.search(b))
    google = bool(STORE_GOOGLE.search(b))
    samsung = bool(STORE_SAMSUNG.search(b))
    has_store = apple or google or samsung
    has_video = bool(rec.get("video_url"))
    has_rc = any(re.search(SPONSOR_SDK["revenuecat"], t) for t in built)

    parts: dict[str, int] = {}

    # Eligibility gate: these three are hackathon requirements.
    parts["eligible"] = 30 if (has_store and has_video and has_rc) else 0

    # Both stores is real extra work and unlocks the JetBrains category.
    parts["both_stores"] = 15 if (apple and google) else 0

    # The written argument is half of what judges actually score.
    parts["writeup"] = min(int((rec.get("description_chars") or 0) / 200), 25)

    # Presentation effort.
    parts["gallery"] = min((rec.get("gallery_images") or 0) * 2, 10)

    # Capped low on purpose: biased against late arrivals.
    parts["engagement"] = min(
        (rec.get("likes") or 0) * 2 + (rec.get("comments") or 0) * 3, 12
    )

    # Each sponsor SDK is another category the project is eligible for.
    sdks = [
        name
        for name, pat in SPONSOR_SDK.items()
        if name != "revenuecat" and any(re.search(pat, t) for t in built)
    ]
    parts["sponsor_breadth"] = min(len(sdks) * 5, 20)

    parts["team"] = min((rec.get("team_size") or 0) * 3, 9)

    total = sum(parts.values())
    parts["_sdks"] = sdks
    parts["_stores"] = "".join(
        [("A" if apple else ""), ("G" if google else ""), ("S" if samsung else "")]
    ) or "-"
    return total, parts


def lanes_of(rec: dict) -> list[str]:
    text = body(rec)
    return [name for name, pat in LANES.items() if re.search(pat, text, re.I)]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=30)
    ap.add_argument("--lane", default=None)
    args = ap.parse_args()

    records = load()
    rows = []
    for rec in records:
        total, parts = score(rec)
        if parts["eligible"] == 0:
            continue  # cannot win: missing a hard requirement
        rows.append((total, parts, rec))

    print(f"{len(records)} projects, {len(rows)} pass the eligibility gate\n")

    if args.lane:
        rows = [r for r in rows if args.lane in lanes_of(r[2])]
        print(f"filtered to lane '{args.lane}': {len(rows)}\n")

    rows.sort(key=lambda t: -t[0])

    hdr = f"{'#':<4}{'score':<7}{'st':<5}{'wu':<5}{'gal':<5}{'eng':<5}{'sdk':<5}{'name':<34}sponsor SDKs"
    print(hdr)
    print("-" * 118)
    for i, (total, p, rec) in enumerate(rows[: args.top], 1):
        print(
            f"{i:<4}{total:<7}{p['_stores']:<5}{p['writeup']:<5}{p['gallery']:<5}"
            f"{p['engagement']:<5}{p['sponsor_breadth']:<5}"
            f"{(rec.get('name') or '?')[:32]:<34}{','.join(p['_sdks'])}"
        )

    print("\nst = stores (A=Apple G=Google S=Samsung), wu = writeup, eng = engagement")
    print("A high score means a serious, well-presented entry -- not a winner.")
    print("Read the writeups before believing the order.")


if __name__ == "__main__":
    main()
