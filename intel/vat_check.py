#!/usr/bin/env python3
"""Check the scraped Shipaton field for collisions with a VAT-refund /
tax-free-shopping app for international travellers.

    python vat_check.py [--data data/projects.json]
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

# Grouped so I can tell a direct hit from a merely adjacent travel app.
PROBES: dict[str, list[str]] = {
    "VAT / tax refund (direct)": [
        "vat", "vat refund", "tax refund", "tax-free", "tax free", "duty free",
        "duty-free", "global blue", "customs refund",
    ],
    "customs / border / immigration": [
        "customs", "border control", "immigration", "passport control", "declaration",
    ],
    "receipt capture / expense claim": [
        "receipt", "receipts", "invoice scan", "expense claim", "reimbursement",
    ],
    "traveller money / currency": [
        "currency", "exchange rate", "forex", "travel money", "foreign transaction",
    ],
    "unclaimed money / entitlements": [
        "unclaimed", "settlement", "claim what you are owed", "rebate", "refund you",
        "money you are owed", "benefits you qualify",
    ],
    "airport / flight logistics": [
        "airport", "terminal", "boarding", "layover", "flight delay", "queue time",
    ],
    "travel planning (adjacent, expected crowded)": [
        "itinerary", "trip planner", "travel plan", "packing list",
    ],
}


def full_text(rec: dict[str, Any]) -> str:
    return f"{rec.get('name','')} {rec.get('tagline','')} {rec.get('description','')}".lower()


def pitch(rec: dict[str, Any]) -> str:
    """Name + tagline only -- what the project claims to BE."""
    return f"{rec.get('name','')} {rec.get('tagline','')}".lower()


_CACHE: dict[str, re.Pattern[str]] = {}


def matches(text: str, term: str) -> bool:
    """Word-boundary match. 'vat' as a substring hits 'private', 'innovate'."""
    pat = _CACHE.get(term)
    if pat is None:
        pat = re.compile(r"\b" + re.escape(term).replace(r"\ ", r"\s+") + r"\b")
        _CACHE[term] = pat
    return pat.search(text) is not None


def one_line(text: str, limit: int = 130) -> str:
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
    print(f"Checking {len(records)} projects\n")

    for label, terms in PROBES.items():
        anywhere, declared = [], []
        for rec in records:
            hits = [t for t in terms if matches(full_text(rec), t)]
            if not hits:
                continue
            anywhere.append((rec, hits))
            if any(matches(pitch(rec), t) for t in terms):
                declared.append((rec, hits))

        print("=" * 76)
        print(f"{label}")
        print(f"  mentions anywhere: {len(anywhere)}   declares it in name/tagline: {len(declared)}")
        show = declared or anywhere
        for rec, hits in sorted(show, key=lambda x: -x[0]["likes"])[:8]:
            stores = [
                l["url"] for l in rec.get("links", []) or []
                if "apple" in l.get("url", "") or "google" in l.get("url", "")
            ]
            flag = "SHIPPED" if stores else "no store"
            print(f"    [{rec['likes']:>2}L] {rec['name'][:38]:38} ({flag}) hits: {','.join(hits[:3])}")
            print(f"          {one_line(rec['tagline'])}")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
