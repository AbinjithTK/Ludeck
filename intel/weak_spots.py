#!/usr/bin/env python3
"""
Find WEAK competitive areas in the Shipaton field.

The mistake in naive analysis is counting rivals. A lane with nine entrants
that never shipped is weaker than a lane with two polished apps on both
stores. So this scores every project's ENTRANT STRENGTH from observable
signals, then ranks lanes by how few CREDIBLE rivals they contain.

Three reports:

  1. ELIGIBILITY SCREEN -- the rules require a first public release on the
     App Store, Google Play or Galaxy Store, and a RevenueCat integration.
     A project with no store link is very likely not a real rival at all.
     This is the single biggest thinner of any field.

  2. LANE WEAKNESS -- topic clusters ranked by credible-rival count, with
     the strongest rival's score so a small-but-strong lane is not mistaken
     for an open one.

  3. MECHANISM RARITY -- structural mechanisms almost nobody used. Rare
     mechanism plus a weak lane is where the real openings are.

Usage:
    python weak_spots.py [--data data/projects.json] [--credible 60]
"""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

STORE_HOSTS = ("apps.apple.com", "play.google.com", "galaxystore.samsung.com", "galaxy.store")

# --- entrant strength -------------------------------------------------------
# Weights are a judgement call, not a measurement. They encode "what does a
# serious, shipped, rules-compliant entry look like from the outside".
WEIGHTS = {
    "shipped": 30,      # at least one real store listing
    "multi_store": 5,   # shipped to more than one store
    "video": 15,        # demo video present (judges may score on video alone)
    "revenuecat": 15,   # the mandatory SDK actually declared
    "writeup": 15,      # effort proxy, scaled by length
    "gallery": 10,      # screenshots, scaled
    "engagement": 10,   # likes + comments, scaled
}


def store_links(rec: dict[str, Any]) -> list[str]:
    return [
        l["url"]
        for l in rec.get("links", []) or []
        if any(host in l.get("url", "") for host in STORE_HOSTS)
    ]


def strength(rec: dict[str, Any]) -> int:
    """Observable-signal score, 0-100. A proxy for 'is this a real rival'."""
    stores = store_links(rec)
    tags = [t.lower() for t in rec.get("built_with", []) or []]

    score = 0.0
    if stores:
        score += WEIGHTS["shipped"]
    if len(stores) > 1:
        score += WEIGHTS["multi_store"]
    if rec.get("video_url"):
        score += WEIGHTS["video"]
    if any("revenuecat" in t for t in tags):
        score += WEIGHTS["revenuecat"]

    score += min(rec.get("description_chars", 0) / 6000, 1.0) * WEIGHTS["writeup"]
    score += min(rec.get("gallery_images", 0) / 6, 1.0) * WEIGHTS["gallery"]
    engagement = rec.get("likes", 0) + 2 * rec.get("comments", 0)
    score += min(engagement / 6, 1.0) * WEIGHTS["engagement"]

    return round(score)


# --- topic lanes -----------------------------------------------------------
# Each project is assigned to the lane it matches most strongly, so counts
# do not double-count one app across five lanes.
LANES: dict[str, list[str]] = {
    "habit/streak tracker": ["habit", "streak", "routine", "daily check-in"],
    "focus/pomodoro": ["pomodoro", "focus timer", "deep work", "focus session"],
    "screen-time blocker": ["screen time", "block apps", "app blocker", "digital detox", "doomscroll"],
    "fitness/gym log": ["workout", "gym", "reps", "sets", "lifting", "training log"],
    "yoga/pilates/recovery": ["yoga", "pilates", "stretch", "mobility", "recovery day"],
    "calorie/macro tracking": ["calorie", "macros", "kcal", "food tracker"],
    "recipe/meal planning": ["recipe", "meal plan", "what to cook", "pantry", "fridge"],
    "journaling/reflection": ["journal", "diary", "reflection", "gratitude"],
    "meditation/calm": ["meditation", "mindfulness", "breathwork", "calm"],
    "sleep/alarm": ["sleep", "alarm", "snore", "bedtime"],
    "expense/budget": ["expense", "budget", "spending", "subscriptions tracker"],
    "save-it/snippet/clipboard": ["snippet", "clipboard", "paste", "bookmark", "second brain"],
    "language learning": ["vocabulary", "language learning", "flashcard", "jlpt", "fluency"],
    "study/exam planner": ["study", "exam", "revision", "student planner", "lecture"],
    "game backlog/collection": ["backlog", "game library", "playthrough", "game collection"],
    "game: puzzle": ["puzzle", "sudoku", "word game", "logic game", "match-3"],
    "game: arcade/one-tap": ["one tap", "endless", "arcade", "reflex", "high score"],
    "game: idle/tycoon": ["idle", "tycoon", "incremental", "clicker"],
    "game: rpg/roguelite": ["roguelite", "roguelike", "rpg", "dungeon", "deckbuilder"],
    "pet care/tracker": ["pet care", "my dog", "my cat", "veterinary", "vet visit", "dog walk", "pet owner"],
    "virtual pet/companion": ["virtual pet", "companion creature", "tamagotchi"],
    "couples/relationship": ["couple", "couples", "partner", "relationship", "anniversary"],
    "family/chores": ["chores", "household", "kids tasks", "family calendar"],
    "wardrobe/outfit": ["wardrobe", "outfit", "closet", "what to wear"],
    "photo cleanup/memories": ["photo cleaner", "camera roll", "screenshots", "declutter photos"],
    "scam/security scanner": ["scam", "scams", "phishing", "fraud", "hidden camera"],
    "elder care/medication": ["medication", "elderly", "senior", "caregiver", "pills"],
    "travel/itinerary": ["itinerary", "travel plan", "trip planner", "road trip"],
    "accessibility/assistive": ["blind", "visually impaired", "deaf", "tremor", "accessibility", "assistive", "screen reader", "low vision"],
    "conversation rehearsal": ["difficult conversation", "difficult conversations", "rehearse", "roleplay", "practice conversation"],
    "business/invoice/CRM": ["invoice", "invoices", "crm", "bookkeeping", "quotes"],
    "dev tools": ["deploy", "deploys", "ci/cd", "developer tool", "code review", "pull request"],
    "coffee/wine/hobby log": ["espresso", "coffee", "whisky", "wine", "brewing"],
    "reading/books": ["reading", "book", "books", "ebook", "epub"],
    "music creation/practice": ["metronome", "chords", "singing", "instrument", "sheet music"],
}

# --- structural mechanisms -------------------------------------------------
MECHANISMS: dict[str, list[str]] = {
    "same-room two-device multiplayer": ["same room", "two phones", "pass the phone", "local multiplayer", "airplane mode", "one phone hosts"],
    "gated on another person acting": ["until everyone", "both of you", "invite a friend to unlock", "shared with one other", "quorum", "when they respond"],
    "mic/camera as continuous controller": ["counts your reps", "blow into", "your voice controls", "live camera tracks", "breath pressure"],
    "per-outcome pricing": ["pay per", "only pay when", "success fee", "refundable deposit", "pay on result"],
    "rewarded ads unlock content": ["rewarded ad", "rewarded ads", "watch an ad to unlock", "ad-supported unlock", "revenuecat ads"],
    "web purchase before install": ["web checkout", "buy on the web", "web funnel", "web-to-app"],
    "foldable / cover screen": ["foldable", "flex mode", "cover screen", "one ui", "samsung dex", "galaxy store"],
    "Live Activity / Dynamic Island": ["live activity", "live activities", "dynamic island"],
    "hardware / IoT dependency": ["bluetooth", "nfc", "esp32", "raspberry pi", "hardware sensor"],
    "offline peer-to-peer / mesh": ["bluetooth mesh", "peer-to-peer", "multipeer", "nearby share", "no server"],
}


def text_of(rec: dict[str, Any]) -> str:
    return " ".join(
        [rec.get("name", ""), rec.get("tagline", ""), rec.get("description", "")]
    ).lower()


_PATTERN_CACHE: dict[str, "re.Pattern[str]"] = {}


def matches(text: str, term: str) -> bool:
    """Word-boundary match.

    Substring matching is fatal here: 'vet' matches "every", 'cat' matches
    "category", 'dex' matches "index", 'hum' matches "human". A first run of
    this script put 211 projects in the pet-care lane for exactly that reason.
    Multi-word terms tolerate any whitespace run.
    """
    pattern = _PATTERN_CACHE.get(term)
    if pattern is None:
        pattern = re.compile(r"\b" + re.escape(term).replace(r"\ ", r"\s+") + r"\b")
        _PATTERN_CACHE[term] = pattern
    return pattern.search(text) is not None


def count_hits(text: str, terms: list[str]) -> int:
    return sum(1 for t in terms if matches(text, t))


def assign_lane(text: str) -> tuple[str | None, int]:
    """Best-matching lane, so each project is counted once."""
    best, best_hits = None, 0
    for lane, terms in LANES.items():
        n = count_hits(text, terms)
        if n > best_hits:
            best, best_hits = lane, n
    return best, best_hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--data",
        default=str(Path(__file__).resolve().parent / "data" / "projects.json"),
        help="dataset path (default: the data/ dir beside this script)",
    )
    ap.add_argument("--credible", type=int, default=60, help="strength score for a 'credible' rival")
    args = ap.parse_args()

    path = Path(args.data)
    if not path.exists():
        print(f"No dataset at {path}. Run scrape_shipaton.py first.")
        return 1

    records = json.loads(path.read_text(encoding="utf-8"))
    for rec in records:
        rec["_strength"] = strength(rec)
        rec["_stores"] = store_links(rec)
        rec["_text"] = text_of(rec)

    total = len(records)

    # ---- 1. eligibility screen -------------------------------------------
    print("=" * 78)
    print("1. ELIGIBILITY SCREEN -- how many entrants look like real rivals")
    print("=" * 78)
    shipped = [r for r in records if r["_stores"]]
    has_rc = [r for r in records if any("revenuecat" in t.lower() for t in r["built_with"])]
    has_video = [r for r in records if r["video_url"]]
    complete = [
        r for r in records
        if r["_stores"] and r["video_url"] and any("revenuecat" in t.lower() for t in r["built_with"])
    ]
    print(f"  total projects in gallery          {total}")
    print(f"  with a real store listing          {len(shipped)}  ({len(shipped)/total:.0%})")
    print(f"  declaring RevenueCat               {len(has_rc)}  ({len(has_rc)/total:.0%})")
    print(f"  with a demo video                  {len(has_video)}  ({len(has_video)/total:.0%})")
    print(f"  ALL THREE (store + video + RC)     {len(complete)}  ({len(complete)/total:.0%})")
    print(f"\n  -> the field of serious rivals is ~{len(complete)}, not {total}.")

    dist = defaultdict(int)
    for rec in records:
        dist[min(rec["_strength"] // 20 * 20, 80)] += 1
    print("\n  strength distribution:")
    for bucket in sorted(dist):
        bar = "#" * max(1, dist[bucket] // 8)
        print(f"    {bucket:>3}-{bucket+19:<3} {dist[bucket]:>4}  {bar}")

    # ---- 2. lane weakness -------------------------------------------------
    print("\n" + "=" * 78)
    print(f"2. LANE WEAKNESS -- ranked by fewest CREDIBLE rivals (strength >= {args.credible})")
    print("=" * 78)
    lanes: dict[str, list[dict[str, Any]]] = defaultdict(list)
    unassigned = 0
    for rec in records:
        lane, hits = assign_lane(rec["_text"])
        if lane and hits >= 1:
            lanes[lane].append(rec)
        else:
            unassigned += 1

    rows = []
    for lane, members in lanes.items():
        credible = [m for m in members if m["_strength"] >= args.credible]
        top = max(members, key=lambda m: m["_strength"])
        rows.append(
            {
                "lane": lane,
                "total": len(members),
                "credible": len(credible),
                "top_score": top["_strength"],
                "top_name": top["name"],
            }
        )
    # Weakest first: fewest credible rivals, then weakest best-rival.
    rows.sort(key=lambda r: (r["credible"], r["top_score"]))

    print(f"  {'lane':32} {'all':>4} {'credible':>9} {'best rival':>11}   strongest entry")
    for row in rows:
        print(
            f"  {row['lane']:32} {row['total']:>4} {row['credible']:>9} "
            f"{row['top_score']:>11}   {row['top_name'][:30]}"
        )
    print(f"\n  ({unassigned} projects matched no lane -- the genuine long tail)")

    # ---- 3. mechanism rarity ---------------------------------------------
    print("\n" + "=" * 78)
    print("3. MECHANISM RARITY -- structural approaches almost nobody used")
    print("=" * 78)
    mech_rows = []
    for mech, terms in MECHANISMS.items():
        users = [r for r in records if any(matches(r["_text"], t) for t in terms)]
        credible = [u for u in users if u["_strength"] >= args.credible]
        mech_rows.append((len(credible), len(users), mech, users))
    mech_rows.sort()

    print(f"  {'mechanism':38} {'all':>4} {'credible':>9}   examples")
    for credible_n, all_n, mech, users in mech_rows:
        top = sorted(users, key=lambda u: -u["_strength"])[:3]
        names = ", ".join(f"{u['name'][:20]}({u['_strength']})" for u in top) or "-- none --"
        print(f"  {mech:38} {all_n:>4} {credible_n:>9}   {names}")

    # ---- 4. prize categories by CREDIBLE rival count ----------------------
    # This is the most robust view: SDK and hardware names are unambiguous
    # tokens, so unlike the topic lanes above there is little false matching.
    print("\n" + "=" * 78)
    print("4. PRIZE CATEGORIES -- credible + shipped rivals per category")
    print("=" * 78)
    category_signals: dict[str, tuple[str, list[str]]] = {
        "Growth Loop (Layers) $15k": ("layers", ["layers sdk", "layers.com", "layers.to"]),
        "Funnel Vision (Stripe) $15k": ("stripe", ["stripe", "web funnel", "web-to-app", "web checkout"]),
        "Idea to Income (Replit) $15k": ("replit", ["replit"]),
        "Best App for Galaxy (no cash)": ("samsung", ["galaxy store", "foldable", "flex mode", "cover screen", "one ui", "samsung dex"]),
        "Keep Them Coming Back (OneSignal) $25k": ("onesignal", ["onesignal"]),
        "Catvertising $20k": ("rc-ads", ["revenuecat ads", "rewarded ad", "rewarded ads", "ad-supported"]),
        "Ship Kotlin Everywhere (JetBrains) $15k": ("kmp", ["kotlin multiplatform", "compose multiplatform"]),
        "Most Viral App (Noise) $15k": ("noise", ["noise", "ugc creators"]),
    }

    print(f"  {'category':42} {'mentions':>8} {'credible+shipped':>17}")
    cat_rows = []
    for label, (_key, terms) in category_signals.items():
        users = [
            r for r in records
            if any(matches(r["_text"], t) for t in terms)
            or any(any(matches(tag.lower(), t) for t in terms) for tag in r["built_with"])
        ]
        credible = [u for u in users if u["_strength"] >= args.credible and u["_stores"]]
        cat_rows.append((len(credible), len(users), label, credible))
    cat_rows.sort()
    for credible_n, all_n, label, credible in cat_rows:
        print(f"  {label:42} {all_n:>8} {credible_n:>17}")
    print("\n  Named credible rivals in the three thinnest:")
    for credible_n, all_n, label, credible in cat_rows[:3]:
        names = ", ".join(f"{c['name'][:26]}({c['_strength']})" for c in
                          sorted(credible, key=lambda c: -c["_strength"])[:6]) or "-- none --"
        print(f"    {label}\n      {names}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
