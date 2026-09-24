"""Discover game-library / backlog / collection apps across the field, and flag
which ones are absent from an earlier snapshot.

gaming_teardown.py works from a hardcoded list of five known rivals, so it can
never surface a NEW entrant. This scans the whole field instead.

Signals are grouped, and a group scores at most once, so a word and its plural
cannot both fire and fake a second signal. Every pattern is word-boundary
anchored: bare substring matching previously put 211 projects in "pet care" and
matched "beli" inside "labeling".

Output is CANDIDATES for review, not a verdict. Actual games that merely mention
rating and sharing will appear; judge them by eye.

Usage:
    python shipaton/gaming_field.py
    python shipaton/gaming_field.py --min-signals 3
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Must look like it is ABOUT games at all.
GAME_DOMAIN = re.compile(r"\bvideo ?games?\b|\bgames?\b|\bgaming\b", re.I)

# One entry = one signal, however many synonyms it holds.
SIGNALS: dict[str, str] = {
    "backlog": r"\bbacklog\b|pile of shame|\bunplayed\b|games? i(?:'ve)? never played",
    "library": r"\blibrar(?:y|ies)\b|\bcollections?\b|\bshel(?:f|ves)\b|\bcatalogue?s?\b",
    "status": r"\bwishlists?\b|want to play|\bbeaten\b|\bcompleted\b|\bdropped\b|\bplaythroughs?\b",
    "decide": r"what to play|pick(?:s|ing)? (?:tonight|a game|your next)|\broulettes?\b"
    r"|randomi[sz]|decision paralysis|choice paralysis|\bwheel\b",
    "capture": r"share extension|share[- ]sheet|moment of discovery|save (?:any )?game"
    r"|\bcapture\b|in seconds",
    "gamedb": r"\bigdb\b|\bmobygames\b|\brawg\b|\bgiant ?bomb\b|\bopencritic\b|\bmetacritic\b",
    "platform": r"\bsteam\b|\bpsn\b|\bplaystation\b|\bxbox\b|game ?pass\b|\bgog\b"
    r"|\bepic games\b|\bnintendo\b|\bswitch\b|steam ?deck",
    "howlong": r"how ?long ?to ?beat|time to beat|hours? to beat|main story",
}

# Signals that indicate library MANAGEMENT rather than merely being a game.
CORE = {"backlog", "library", "status", "decide", "gamedb", "platform", "howlong"}

STORE_RE = re.compile(
    r"apps\.apple\.com|itunes\.apple\.com|play\.google\.com|galaxystore\.samsung\.com",
    re.I,
)


def load(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def body(rec: dict) -> str:
    parts = [str(rec.get(k) or "") for k in ("name", "tagline", "description")]
    parts += [" ".join(rec.get("built_with") or [])]
    return " ".join(parts)


def key(rec: dict) -> str:
    return (rec.get("url") or rec.get("name") or "").strip().lower()


def latest_snapshot() -> Path | None:
    """Newest archived crawl, i.e. projects.<count>.json with the largest count.

    Pinning a literal filename here silently rots: the baseline stayed at
    projects.886.json for a crawl after 939 was archived, so every "NEW" flag
    was one crawl stale and re-reported the previous run's arrivals as today's.
    """
    snaps = []
    for path in (HERE / "data").glob("projects.*.json"):
        stem = path.name[len("projects.") : -len(".json")]
        if stem.isdigit():
            snaps.append((int(stem), path))
    return max(snaps)[1] if snaps else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(HERE / "data" / "projects.json"))
    ap.add_argument(
        "--old",
        default=str(latest_snapshot() or HERE / "data" / "projects.886.json"),
        help="baseline snapshot (default: newest projects.<count>.json archive)",
    )
    ap.add_argument("--min-signals", type=int, default=2)
    args = ap.parse_args()

    records = load(Path(args.data))
    try:
        old_keys = {key(r) for r in load(Path(args.old))}
    except FileNotFoundError:
        old_keys = set()
        print(f"(no old snapshot at {args.old} -- cannot flag new arrivals)\n")

    rows = []
    for rec in records:
        text = body(rec)
        if not GAME_DOMAIN.search(text):
            continue
        hit = {g for g, pat in SIGNALS.items() if re.search(pat, text, re.I)}
        core = hit & CORE
        if len(core) < args.min_signals:
            continue
        rows.append((len(core), sorted(hit), rec))

    rows.sort(key=lambda t: (-t[0], -(int(t[2].get("likes") or 0))))

    new_rows = [r for r in rows if key(r[2]) not in old_keys]

    print(f"GAME-LIBRARY CANDIDATES  ({len(rows)} of {len(records)} projects, "
          f">={args.min_signals} core signals)")
    print(f"NEW SINCE OLD SNAPSHOT: {len(new_rows)}\n")
    print(f"{'':4}{'name':<38}{'sig':<5}{'store':<7}{'RC':<5}{'likes':<7}signals")
    for score, hit, rec in rows:
        flag = "NEW " if key(rec) not in old_keys else "    "
        rc = "yes" if any("revenuecat" in t.lower() for t in (rec.get("built_with") or [])) else "-"
        store = "yes" if STORE_RE.search(json.dumps(rec, ensure_ascii=False)) else "-"
        print(
            f"{flag}{(rec.get('name') or '?')[:36]:<38}{score:<5}{store:<7}{rc:<5}"
            f"{str(rec.get('likes') or 0):<7}{','.join(hit)}"
        )

    if new_rows:
        print("\nNEW ARRIVALS IN DETAIL")
        for score, hit, rec in new_rows:
            print(f"\n### {rec.get('name')}  [{rec.get('likes') or 0} likes, {score} core signals]")
            print(f"    {rec.get('tagline')}")
            print(f"    built_with: {', '.join(rec.get('built_with') or []) or '(none)'}")
            print(f"    links: {rec.get('links')}")


if __name__ == "__main__":
    main()
