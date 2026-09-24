#!/usr/bin/env python3
"""
Measure the real competitive field for each RevenueCat Shipaton 2026
Influencer Award, against the full project writeups (not just taglines).

Each brief has an eligibility SHAPE, not just a topic. A nutrition app that
counts calories is on-topic but violates Abbey's second criterion; a workout
app that only logs sets does not answer Simone's "what should I do today?".
So each category is measured twice:

    CANDIDATES  -- on topic at all
    COMPLIANT   -- on topic AND not disqualified by the brief's own constraints

The gap between those two numbers is the real opportunity.

Usage:
    python analyze_influencer.py [--data data/projects.json] [--show 12]
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


def blob(rec: dict[str, Any]) -> str:
    """All searchable text for one project, lowercased."""
    return " ".join(
        [
            rec.get("name", ""),
            rec.get("tagline", ""),
            rec.get("description", ""),
            " ".join(rec.get("built_with", []) or []),
        ]
    ).lower()


def pitch(rec: dict[str, Any]) -> str:
    """Only what the project claims to BE -- its name and tagline.

    A keyword buried in a 4,500-character writeup means the project mentions
    a topic; a keyword in the tagline means the project IS about it. Matching
    on the pitch is what separates real category rivals from false positives
    (a film camera that happens to use the word "satisfying").
    """
    return f"{rec.get('name', '')} {rec.get('tagline', '')}".lower()


def hits(text: str, terms: list[str]) -> list[str]:
    """Which of these terms appear, matched on word boundaries."""
    found = []
    for term in terms:
        pattern = r"\b" + re.escape(term).replace(r"\ ", r"\s+") + r"\b"
        if re.search(pattern, text):
            found.append(term)
    return found


# Each category: what puts a project on topic, and what the brief rules out.
CATEGORIES: dict[str, dict[str, Any]] = {
    "Lawley -- Productivity ($20k)": {
        "brief": "Fast save + retrieve of reusable snippets, docs, files, images "
                 "for Apple power users. First criterion: speed.",
        "topic": [
            "snippet", "snippets", "clipboard", "clip", "paste", "bookmark",
            "second brain", "quick capture", "text expander", "stash",
            "save and find", "share sheet",
        ],
        "disqualify": [],
        "bonus": [
            "shortcuts", "widget", "keyboard extension", "spotlight",
            "apple pencil", "live activity", "app intent",
        ],
    },
    "Abbey -- Nutrition ($20k)": {
        "brief": "Hunger Crushing Combo: add protein / fibre / healthy fats. "
                 "Explicitly NO calorie counting, macro tracking or restriction.",
        "topic": [
            "nutrition", "meal", "meals", "eating", "food", "snack", "recipe",
            "protein", "fiber", "fibre", "hunger", "satiety", "diet",
        ],
        # These are the brief's own exclusions -- on-topic but out of bounds.
        "disqualify": [
            "calorie", "calories", "kcal", "macro", "macros", "deficit",
            "weight loss", "lose weight", "count calories", "calorie counting",
        ],
        "bonus": ["hunger crushing", "satisfying", "no counting", "intuitive eating"],
    },
    "Simone -- Yoga & Fitness ($20k)": {
        "brief": "Answers 'what should I do today?' -- one clear achievable plan "
                 "from movement, Pilates and recovery, WITHOUT more overload.",
        "topic": [
            "yoga", "pilates", "workout", "movement", "recovery", "wellness",
            "stretch", "mobility", "exercise",
        ],
        # Pure logging tools answer the opposite question: they add entry work.
        "disqualify": [
            "progressive overload", "log every set", "track your sets",
            "rep log", "training log", "workout log", "one rep max", "1rm",
        ],
        "bonus": [
            "what to do today", "today", "daily plan", "one session",
            "personalized plan", "recovery day",
        ],
    },
    "Heather -- Career Coaching ($20k)": {
        "brief": "New managers actively PRACTISE difficult conversations -- "
                 "feedback, boundaries, saying no. First criterion: realistic scenarios.",
        "topic": [
            "difficult conversation", "hard conversation", "difficult conversations",
            "manager", "managers", "feedback", "boundaries", "saying no",
            "workplace", "one-on-one", "performance review", "confrontation",
            "conflict", "rehearse", "roleplay", "role-play",
        ],
        "disqualify": [],
        "bonus": [
            "practice", "practise", "rehearse", "scenario", "scenarios",
            "roleplay", "role-play", "new manager", "first-time manager",
        ],
    },
    "Lewis -- Gaming backlog ($20k)": {
        "brief": "Save games at the MOMENT of discovery; organise, complete, "
                 "rate and share a backlog that feels fun, not a chore.",
        "topic": [
            "backlog", "game library", "games to play", "playthrough",
            "game collection", "bucket list", "gaming list", "want to play",
            "pile of shame",
        ],
        "disqualify": [],
        "bonus": ["share sheet", "discovery", "rate", "wishlist", "steam", "igdb"],
    },
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--data",
        default=str(Path(__file__).resolve().parent / "data" / "projects.json"),
        help="dataset path (default: the data/ dir beside this script)",
    )
    ap.add_argument("--show", type=int, default=12, help="rows to print per category")
    args = ap.parse_args()

    path = Path(args.data)
    if not path.exists():
        print(f"No dataset at {path}. Run scrape_shipaton.py first.")
        return 1

    records = json.loads(path.read_text(encoding="utf-8"))
    print(f"Analysing {len(records)} projects\n")

    for title, spec in CATEGORIES.items():
        mentions, rivals, ruled_out = [], [], []

        for rec in records:
            text = blob(rec)
            if not hits(text, spec["topic"]):
                continue
            mentions.append(rec["name"])

            # A real rival declares the topic in its own name or tagline.
            if not hits(pitch(rec), spec["topic"]):
                continue

            bad = hits(text, spec["disqualify"])
            row = {
                "name": rec["name"],
                "likes": rec["likes"],
                "tagline": " ".join(rec["tagline"].split())[:96],
                "bonus": hits(text, spec["bonus"]),
                "violates": bad,
            }
            (ruled_out if bad else rivals).append(row)

        print("=" * 78)
        print(title)
        print(f"  brief: {spec['brief']}")
        print(f"  mentions topic anywhere: {len(mentions)}")
        print(
            f"  REAL RIVALS (topic in name/tagline): {len(rivals) + len(ruled_out)}"
            f"  ->  compliant {len(rivals)}, ruled out by brief {len(ruled_out)}"
        )

        ranked = sorted(rivals, key=lambda r: (-len(r["bonus"]), -r["likes"]))
        print("\n  Compliant rivals (brief alignment, then likes):")
        for row in ranked[: args.show]:
            marks = ",".join(row["bonus"][:4]) or "-"
            print(f"    [{row['likes']:>2}L] {row['name'][:42]:42} | {marks}")
            print(f"          {row['tagline']}")

        if ruled_out:
            print(f"\n  On topic but ruled out by the brief ({len(ruled_out)}):")
            for row in sorted(ruled_out, key=lambda r: -r["likes"])[:8]:
                print(
                    f"    [{row['likes']:>2}L] {row['name'][:42]:42}"
                    f" | violates: {','.join(row['violates'][:3])}"
                )
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
