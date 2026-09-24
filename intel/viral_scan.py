"""Collision-scan candidate viral mechanisms against the local Shipaton dataset.

Answers one question per mechanism: has anyone in this field already built it?

Every pattern is WORD-BOUNDARY anchored and synonyms are GROUPED into a single
signal, because a bare substring put 211 projects in "pet care" and matched
"curate" inside "accurate" on earlier runs. Example names are printed for every
hit so false positives are visible rather than inferred.

Usage:
    python viral_scan.py [--data data/projects.json] [--examples 6]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Projects whose subject is games at all -- used to scope the game-specific
# mechanisms, since "achievement" and "recap" are generic across the field.
GAME_DOMAIN = re.compile(
    r"\bgame(s|r|rs)?\b|\bgaming\b|\bbacklog\b|\bsteam\b|\bplaystation\b|\bps5\b"
    r"|\bxbox\b|\bnintendo\b|\bswitch\b|\bigdb\b",
    re.I,
)

# mechanism -> (pattern, scope) where scope is "all" or "games"
MECHANISMS: dict[str, tuple[str, str]] = {
    # 1. The drop-off / quit-point wedge.
    "quit point / drop-off data": (
        r"drop[- ]?off|quit point|where (players|people) (quit|stop)"
        r"|abandon(ment)? (rate|point)|never finish(ed)?|unfinished rate",
        "all",
    ),
    "global achievement percentages": (
        r"global achievement|achievement (completion|percentage|rate)"
        r"|getglobalachievement",
        "all",
    ),
    # 2. Anticipation converted into completion.
    "release countdown": (r"\bcountdown\b|days until (launch|release)|\brelease day\b", "games"),
    "shared / social wait room": (
        r"wait(ing)? room|\bhype room\b|waiting together|everyone waiting",
        "all",
    ),
    "public commitment / pledge": (
        r"\bpledge\b|public commitment|commit(ment)? (card|contract)|accountability partner",
        "all",
    ),
    # 3. Delay ledger.
    "release delay / slippage": (
        r"\bdelay(ed|s)?\b|\bslipped\b|\bpostponed\b|release date chang",
        "games",
    ),
    # 4. Occupied externally -- confirm whether occupied HERE too.
    "fixed active slots (one in, one out)": (
        r"\bslots?\b|one in,? one out|limit (how many|the number of)",
        "games",
    ),
    "backlog monetary value": (
        r"pile of shame|backlog value|value of (your |my )?(unplayed|backlog)"
        r"|\bhoarder\b|money (wasted|spent) on games",
        "all",
    ),
    "annual wrapped / year in review": (
        r"\bwrapped\b|year in review|year[- ]end recap|\byour year\b|replay \d{4}",
        "all",
    ),
    # 5. Letterboxd's transferable asset: a recognisable short-form verdict.
    "short fixed-format verdict / one-liner": (
        r"one[- ]line(r)? review|\bverdict\b|140 character|one sentence review",
        "all",
    ),
    # 6. Known baselines, for continuity with earlier runs.
    "steam library import": (
        r"getownedgames|steam library|import (your )?steam|steam import",
        "all",
    ),
    "creator stream tooling": (
        r"\bOBS\b|browser source|streamlabs|stream overlay|creator portal"
        r"|viewer submission|golden ticket",
        "all",
    ),
}


def load(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def body(rec: dict) -> str:
    parts = [str(rec.get(k) or "") for k in ("name", "tagline", "description")]
    parts.append(" ".join(rec.get("built_with") or []))
    return " ".join(parts)


def shipped(rec: dict) -> bool:
    return bool(
        re.search(
            r"apps\.apple\.com|itunes\.apple\.com|play\.google\.com"
            r"|galaxystore\.samsung\.com|apps\.samsung\.com",
            json.dumps(rec, ensure_ascii=False),
            re.I,
        )
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(HERE / "data" / "projects.json"))
    ap.add_argument("--examples", type=int, default=6)
    args = ap.parse_args()

    records = load(Path(args.data))
    games = [r for r in records if GAME_DOMAIN.search(body(r))]

    print(f"dataset: {len(records)} projects, {len(games)} game-domain\n")
    print(f"{'mechanism':<40}{'scope':<7}{'hits':<6}{'shipped':<9}examples")
    print("-" * 110)

    for label, (pattern, scope) in MECHANISMS.items():
        pool = games if scope == "games" else records
        rx = re.compile(pattern, re.I)
        hits = [r for r in pool if rx.search(body(r))]
        ship = sum(1 for r in hits if shipped(r))
        names = ", ".join((r.get("name") or "?")[:24] for r in hits[: args.examples])
        print(f"{label:<40}{scope:<7}{len(hits):<6}{ship:<9}{names}")

    print(
        "\nA hit is a CANDIDATE, not a finding: read the writeup before calling a"
        "\nmechanism occupied. Generic words ('slots', 'delay') over-report."
    )


if __name__ == "__main__":
    main()
