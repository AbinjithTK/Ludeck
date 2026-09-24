#!/usr/bin/env python3
"""Teardown of the gaming-backlog rivals inside the Shipaton field, plus a
sweep for any social-curation / shared-list app that could pivot into
Lewis Blogs' Gaming category.

    python gaming_teardown.py [--data data/projects.json]
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

# The confirmed rivals for the Lewis Blogs Gaming brief.
RIVALS = ["QuestLog", "Playwall", "Nook", "Cibby", "NextUp"]

# A Hypelist-style app is about SHARING a curated list, not logging alone.
# GROUPED and word-boundary anchored. Two earlier bugs this fixes:
#   - "recommendation" and "recommendations" were separate terms, so any plural
#     use fired two signals and cleared the ">= 2 signals" bar on its own.
#   - bare substrings matched inside unrelated words: "curate" inside ACCURATE
#     (which flagged a snore detector and a solar-arbitrage app), and "taste"
#     inside DISTASTEFUL.
SOCIAL_LIST_SIGNALS: dict[str, str] = {
    "recommend": r"\brecommendations?\b|\brecommends?\b|\brecommended\b",
    "shared list": r"share your list|\bshared lists?\b|\bcollaborative lists?\b"
    r"|friends'? lists?\b",
    "curated": r"\bcurated?\b|\bcurating\b|\bcuration\b",
    "taste": r"\btastes?\b",
    "follow": r"\bfollow (?:friends|people|creators)\b|\bfollowers?\b",
}

# Mechanisms the Lewis brief actually names, so I can see who ships which.
BRIEF_MECHANICS = {
    "save at discovery": ["share sheet", "share extension", "save any game in seconds",
                          "moment of discovery", "from any app", "one tap to save"],
    "organise": ["organize", "organise", "shelf", "shelves", "collection", "library"],
    "complete": ["completed", "finish", "finished", "playthrough", "beat the game"],
    "rate": ["rate", "rating", "score", "review"],
    "share": ["share", "friends", "social", "feed"],
    "anti-chore": ["guilt", "shame", "chore", "pressure", "fun"],
}


def one_line(text: str, limit: int = 200) -> str:
    return " ".join((text or "").split())[:limit]


def show_rival(rec: dict[str, Any]) -> None:
    text = f"{rec['name']} {rec['tagline']} {rec['description']}".lower()
    print("=" * 78)
    print(f"{rec['name']}   [{rec['likes']} likes, {rec['comments']} comments]")
    print(f"  url:        {rec['url']}")
    print(f"  built_with: {', '.join(rec['built_with'])}")
    print(f"  links:      {[l['url'] for l in rec['links']]}")
    print(f"  video:      {'yes' if rec['video_url'] else 'NO'}   team: {rec['team_size']}")
    print(f"  tagline:    {one_line(rec['tagline'])}")

    print("  brief coverage:")
    for mech, terms in BRIEF_MECHANICS.items():
        found = [t for t in terms if t in text]
        mark = "YES" if found else " no"
        print(f"    {mark}  {mech:20} {found[:3]}")

    body = " ".join(rec["description"].split())
    print(f"  writeup ({rec['description_chars']} chars), first 900:")
    print("    " + body[:900])
    print()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--data",
        default=str(Path(__file__).resolve().parent / "data" / "projects.json"),
        help="dataset path (default: the data/ dir beside this script)",
    )
    args = ap.parse_args()

    path = Path(args.data)
    if not path.exists():
        print(f"No dataset at {path}. Run scrape_shipaton.py first.")
        return 1

    records = json.loads(path.read_text(encoding="utf-8"))
    by_name = {r["name"]: r for r in records}

    print("### RIVAL TEARDOWN (Lewis Blogs Gaming brief)\n")
    for wanted in RIVALS:
        match = next((r for n, r in by_name.items() if wanted.lower() in n.lower()), None)
        if match:
            show_rival(match)
        else:
            print(f"!! {wanted} not found in dataset\n")

    print("\n### SOCIAL-CURATION / SHARED-LIST SWEEP (Hypelist-shaped apps in the field)\n")
    found = []
    for rec in records:
        text = f"{rec['name']} {rec['tagline']} {rec['description']}"
        hits = sorted(
            g for g, pat in SOCIAL_LIST_SIGNALS.items() if re.search(pat, text, re.I)
        )
        # Two or more DISTINCT signal groups to filter out incidental word use.
        if len(hits) >= 2:
            found.append((len(hits), rec, hits))
    found.sort(key=lambda x: (-x[0], -x[1]["likes"]))
    print(f"{len(found)} projects with 2+ social-curation signals:\n")
    for count, rec, hits in found[:20]:
        print(f"  [{rec['likes']:>2}L] {rec['name'][:40]:40} ({count} signals: {','.join(hits[:4])})")
        print(f"        {one_line(rec['tagline'], 120)}")

    print("\n### ANY PROJECT MENTIONING HYPELIST / LETTERBOXD / BACKLOGGD AS A REFERENCE\n")
    # Word-boundary anchored: a bare "beli" substring matched LABELING, BELIEF
    # and BELIEVE, reporting 63 phantom hits for a reference nobody made.
    for needle in ["hypelist", "letterboxd", "backloggd", "goodreads", "beli"]:
        rx = re.compile(rf"\b{re.escape(needle)}\b", re.I)
        hitlist = [
            r["name"]
            for r in records
            if rx.search(f"{r['name']} {r['tagline']} {r['description']}")
        ]
        print(f"  {needle:12} {len(hitlist):3}  {hitlist[:8]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
