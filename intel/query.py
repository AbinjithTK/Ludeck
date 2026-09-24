#!/usr/bin/env python3
"""Ad-hoc queries over the scraped Shipaton dataset.

Edit and re-run freely -- it is read-only over data/projects.json and costs
nothing. Kept as a file rather than a shell one-liner because PowerShell
mangles inline Python containing braces and quotes.

    python query.py [--data data/projects.json]
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

# Who each brief belongs to, and the words a project would use if it were
# deliberately aiming at that brief.
BRIEF_MENTIONS: dict[str, list[str]] = {
    "Lawley (productivity)": ["christopher lawley", "lawley"],
    "Abbey / Hunger Crushing": ["abbey", "hunger crushing", "hunger-crushing"],
    "Simone (yoga & fitness)": ["simone sharice", "simone"],
    "Heather (career coaching)": ["leadership heather", "heather"],
    "Lewis (gaming backlog)": ["lewis blogs", "mr lewis"],
    "generic 'influencer award'": ["influencer award", "influencer category"],
}

# Apps worth eyeballing directly, whatever the keyword filters decide.
VERIFY = ["krasis", "nextup", "amber", "questlog", "nyassle", "sadhana", "playwall"]


def full_text(rec: dict[str, Any]) -> str:
    return f"{rec.get('name','')} {rec.get('tagline','')} {rec.get('description','')}".lower()


def one_line(text: str, limit: int = 150) -> str:
    return " ".join((text or "").split())[:limit]


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

    print("=== EXPLICIT BRIEF / INFLUENCER MENTIONS ===")
    print("(naming the influencer is the strongest evidence of deliberate targeting)")
    for label, keys in BRIEF_MENTIONS.items():
        found = [r["name"] for r in records if any(k in full_text(r) for k in keys)]
        print(f"  {label:30} {len(found):3}  {found[:8]}")

    print("\n=== TARGETED VERIFY ===")
    for needle in VERIFY:
        for rec in records:
            if needle in rec["name"].lower():
                print(f"  -- {rec['name']} [{rec['likes']}L] built_with={rec['built_with'][:5]}")
                print(f"     {one_line(rec['tagline'])}")

    # Abbey's actual mechanism: ADDING protein / fibre / fat to a meal, rather
    # than measuring what is already there.
    print("\n=== ADDITIVE-NUTRITION MECHANISM (Abbey's core loop) ===")
    pattern = re.compile(r"\b(add|adding)\b.{0,40}\b(protein|fiber|fibre|fats?)\b")
    additive = [
        r["name"] for r in records if pattern.search(full_text(r)) or "what to add" in full_text(r)
    ]
    print(f"  {len(additive)} projects: {additive[:15]}")

    # Lawley's actual first criterion is retrieval SPEED, not storage.
    print("\n=== RETRIEVAL-SPEED CLAIMS (Lawley's first criterion) ===")
    speed = re.compile(r"(in seconds|one tap|two taps|instantly|in a keystroke|fastest way)")
    fast = [
        r["name"]
        for r in records
        if speed.search(full_text(r))
        and re.search(r"(snippet|clipboard|paste|bookmark|stash|reuse)", full_text(r))
    ]
    print(f"  {len(fast)} projects: {fast[:15]}")

    # Apparent crowding is not real crowding. A rival with no store listing
    # and no RevenueCat tag is a concept, not a competitor.
    print("\n=== PER-APP ELIGIBILITY CHECK: the conversation-rehearsal cluster ===")
    named = [
        "PeaceSpeaker", "ManagerGym", "Rehearse", "SayBetter", "NextSay",
        "BraveLine", "Second Take", "ReplayLead", "Hard Conversation",
    ]
    store_hosts = ("apps.apple.com", "play.google.com", "galaxystore.samsung.com")
    print(f"  {'app':22} {'store':>6} {'RevCat':>7} {'video':>6} {'likes':>6}   stores")
    for want in named:
        for rec in records:
            if want.lower() in rec["name"].lower():
                stores = [
                    l["url"] for l in rec.get("links", []) or []
                    if any(h in l.get("url", "") for h in store_hosts)
                ]
                tags = [t.lower() for t in rec.get("built_with", []) or []]
                rc = any("revenuecat" in t for t in tags)
                which = ",".join(
                    "iOS" if "apple" in s else "Play" if "google" in s else "Galaxy"
                    for s in stores
                ) or "-- NONE --"
                print(
                    f"  {rec['name'][:22]:22} {('YES' if stores else 'no'):>6} "
                    f"{('YES' if rc else 'no'):>7} {('yes' if rec['video_url'] else 'no'):>6} "
                    f"{rec['likes']:>6}   {which}"
                )
                break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
