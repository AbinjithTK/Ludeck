"""Hand-review candidates for the 'dead until a second person acts' mechanism.

weak_spots.py counts this mechanism with a narrow phrase list and reports 1 hit
across the field. A phrase miss is not evidence of absence, so this widens the
net deliberately and prints the matching sentences for human judgement rather
than emitting a count.

The test being applied is strict: the product must be INERT until another
specific person takes an action. Two-player games, shared/collaborative spaces
and social feeds do not qualify -- those work solo or with strangers.

Usage:
    python shipaton/mechanism_check.py
    python shipaton/mechanism_check.py --names WITHSTAND PostBox
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# Deliberately broad. Precision is the reviewer's job, not the regex's.
WIDE = re.compile(
    r"until (?:someone|somebody|a friend|your friend|the other|they|he|she)\b"
    r"|only works? (?:when|if|once)\b"
    r"|needs? (?:someone|another person|a partner|a friend) to\b"
    r"|requires? (?:someone|another person|a partner|a friend)\b"
    r"|waiting for (?:someone|a friend|them|a match|a reply)\b"
    r"|match(?:ed)? with (?:a|an|another) (?:stranger|peer|person|human)\b"
    r"|paired with\b|pairs? you with\b|connects? (?:you )?(?:with|to) (?:a|an|another|anonymous)\b"
    r"|both (?:of you|users|people|partners) (?:must|have to|need)\b"
    r"|someone else (?:has to|must|needs to)\b"
    r"|reply|responds? back|writes? back\b",
    re.I,
)

SENT = re.compile(r"[^.!?\n]{0,160}(?:[.!?]|$)")


def load(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def text(rec: dict) -> str:
    return " ".join(
        str(rec.get(k) or "") for k in ("tagline", "description", "summary", "writeup")
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--data",
        default=str(Path(__file__).resolve().parent / "data" / "projects.json"),
        help="dataset path (default: the data/ dir beside this script)",
    )
    ap.add_argument("--names", nargs="*", default=None, help="only these projects")
    args = ap.parse_args()

    records = load(Path(args.data))

    if args.names:
        wanted = {n.lower() for n in args.names}
        records = [
            r for r in records
            if any(w in (r.get("name") or "").lower() for w in wanted)
        ]
        print(f"Named lookup: {len(records)} record(s)\n")
        for r in records:
            print(f"### {r.get('name')}  [likes {r.get('likes') or 0}]")
            print(f"    tagline: {r.get('tagline')}")
            body = text(r)
            hits = [m.group(0).strip() for m in SENT.finditer(body) if WIDE.search(m.group(0))]
            if hits:
                for h in hits[:6]:
                    print(f"    > {h}")
            else:
                print("    > no dependence-on-another-person language found")
            print()
        return

    print("Candidates for 'inert until a second person acts' -- HAND REVIEW REQUIRED")
    print("(broad regex; expect false positives from social feeds and 2P games)\n")
    n = 0
    for r in records:
        body = text(r)
        hits = [m.group(0).strip() for m in SENT.finditer(body) if WIDE.search(m.group(0))]
        if not hits:
            continue
        n += 1
        print(f"### {r.get('name')}  [likes {r.get('likes') or 0}]")
        print(f"    {(r.get('tagline') or '')[:110]}")
        for h in hits[:2]:
            print(f"    > {h[:150]}")
        print()
    print(f"{n} candidates of {len(records)} projects.")


if __name__ == "__main__":
    main()
