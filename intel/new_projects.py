"""Diff two Shipaton crawl snapshots and screen the newly-arrived projects.

Usage:
    python shipaton/new_projects.py [OLD_JSON] [NEW_JSON]

With no arguments it compares the newest archived snapshot (projects.<count>.json)
against the live projects.json, both under shipaton/data. Projects are keyed on
their Devpost URL, which is stable across crawls (names and taglines get edited).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"


def latest_snapshot() -> Path:
    """Newest archived crawl, so the default baseline is the previous run."""
    snaps = [
        (int(p.name[len("projects.") : -len(".json")]), p)
        for p in DATA.glob("projects.*.json")
        if p.name[len("projects.") : -len(".json")].isdigit()
    ]
    if not snaps:
        raise SystemExit(f"no archived snapshot in {DATA} -- pass OLD_JSON explicitly")
    return max(snaps)[1]


OLD = Path(sys.argv[1]) if len(sys.argv) > 1 else latest_snapshot()
NEW = Path(sys.argv[2]) if len(sys.argv) > 2 else DATA / "projects.json"

STORE_RE = re.compile(
    r"apps\.apple\.com|itunes\.apple\.com|play\.google\.com|galaxystore\.samsung\.com"
    r"|apps\.samsung\.com",
    re.I,
)
RC_RE = re.compile(r"revenuecat", re.I)

# Lanes that current decisions depend on. Word-boundary anchored: a bare
# substring match put 211 projects in "pet care" on an earlier run.
LANES = {
    "creator stream tooling": r"\bOBS\b|browser source|streamlabs|stream overlay|creator portal|viewer submission|golden ticket",
    "twitch": r"\btwitch\b",
    "raffle / wheel / roulette": r"\braffle\b|spin the wheel|\broulette\b",
    "share sheet capture": r"share extension|share[- ]sheet",
    "game backlog": r"\bbacklog\b|\bgame(s)? to play\b|pile of shame",
    "steam library import": r"getownedgames|steam library|import (your )?steam|steam import",
    "igdb": r"\bigdb\b",
    "vat / tax refund": r"\bVAT\b|tax refund|tax[- ]free|duty[- ]free",
    "price / deal tracking": r"cheapshark|isthereanydeal|price drop|all[- ]time low",
}


def load(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def blob(rec: dict) -> str:
    """Whole-record text, so a store URL is found wherever the scraper put it."""
    return json.dumps(rec, ensure_ascii=False)


def key(rec: dict) -> str:
    return (rec.get("url") or rec.get("link") or rec.get("name") or "").strip().lower()


def shipped(rec: dict) -> bool:
    return bool(STORE_RE.search(blob(rec)))


def revenuecat(rec: dict) -> bool:
    return bool(RC_RE.search(blob(rec)))


def main() -> None:
    old, new = load(OLD), load(NEW)
    old_keys = {key(r) for r in old}
    added = [r for r in new if key(r) not in old_keys]
    new_keys = {key(r) for r in new}
    removed = [r for r in old if key(r) not in new_keys]

    print(f"old snapshot : {len(old):>4}  {OLD}")
    print(f"new snapshot : {len(new):>4}  {NEW}")
    print(f"added        : {len(added):>4}")
    print(f"removed      : {len(removed):>4}  (withdrawn or renamed URL)")
    print()

    if removed:
        print("REMOVED / URL CHANGED")
        for r in removed:
            print(f"  - {r.get('name', '?')}")
        print()

    print(f"NEW ARRIVALS ({len(added)}) -- store link / RevenueCat / likes")
    print(f"{'':2}{'name':<34}{'store':<7}{'RC':<5}{'likes':<6}tagline")
    for r in sorted(added, key=lambda r: -int(r.get("likes") or 0)):
        name = (r.get("name") or "?")[:32]
        tag = (r.get("tagline") or "")[:66]
        print(
            f"  {name:<34}{'yes' if shipped(r) else '-':<7}"
            f"{'yes' if revenuecat(r) else '-':<5}{str(r.get('likes') or 0):<6}{tag}"
        )
    print()

    both = sum(1 for r in added if shipped(r) and revenuecat(r))
    print(
        f"eligibility of new arrivals: {sum(1 for r in added if shipped(r))} shipped, "
        f"{sum(1 for r in added if revenuecat(r))} declare RevenueCat, {both} both"
    )
    print()

    old_label, new_label = f"old/{len(old)}", f"new/{len(new)}"
    print(f"{'lane':<28}{old_label:<10}{new_label:<10}{'delta':<8}new-arrival hits")
    for label, pattern in LANES.items():
        rx = re.compile(pattern, re.I)
        o = sum(1 for r in old if rx.search(blob(r)))
        n = sum(1 for r in new if rx.search(blob(r)))
        a = sum(1 for r in added if rx.search(blob(r)))
        print(f"{label:<28}{o:<10}{n:<10}{n - o:+d}{'':<5}{a}")


if __name__ == "__main__":
    main()
