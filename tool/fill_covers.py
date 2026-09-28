"""Fills `cover` in app/assets/catalog/games.json without touching Wikidata.

    python tool/fill_covers.py --deadline 900   # stop after 15 min, keep what's done

build_catalog.py decides WHICH games exist (Wikidata, slow: 1 req/min during its
outage). This pass only finds box art for rows that have none, from two keyless
sources that answer fast:
  * Steam store search, exact normalised title only -> 600x900 library art
  * Wikipedia REST summary for "<title> (video game)" then "<title>", accepted
    only when the page describes itself as a game (never a disambiguation page)

It is resumable and bounded: every lookup result (hit or miss) is cached in
tool/.cache/covers.json, the asset is rewritten every 200 lookups, and the run
stops cleanly at --deadline seconds. Rerunning continues where it stopped.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import threading
import time
import urllib.parse
from pathlib import Path

from build_catalog import ASSET, http_json, norm, steam_search

CACHE = Path(__file__).resolve().parent / ".cache" / "covers.json"
_lock = threading.Lock()


def wiki_by_title(title: str) -> str | None:
    for page in (f"{title} (video game)", title):
        slug = urllib.parse.quote(page.replace(" ", "_"), safe="")
        try:
            d = http_json(f"https://en.wikipedia.org/api/rest_v1/page/summary/{slug}", timeout=15)
        except Exception:  # noqa: BLE001 -- 404 or transport: try the next form
            continue
        if not isinstance(d, dict) or d.get("type") == "disambiguation":
            continue
        desc = (d.get("description") or "").lower()
        if "game" not in desc:
            continue
        src = (d.get("thumbnail") or {}).get("source")
        if isinstance(src, str) and src.startswith("https://"):
            return src
    return None


def lookup(title: str) -> tuple[str | None, list[str]]:
    cover, plats = steam_search(title)
    if cover is None:
        cover = wiki_by_title(title)
    return cover, plats


def save(doc: dict, cache: dict) -> None:
    ASSET.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(cache), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--deadline", type=int, default=900, help="seconds before a clean stop")
    ap.add_argument("--workers", type=int, default=12)
    args = ap.parse_args()
    stop_at = time.time() + args.deadline

    doc = json.loads(ASSET.read_text(encoding="utf-8"))
    cache: dict = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    games = doc["games"]

    # Apply cached results first, so a rerun is instant for everything already seen.
    for g in games:
        hit = cache.get(norm(g["title"]))
        if hit and hit.get("cover") and not g.get("cover"):
            g["cover"] = hit["cover"]
    todo = [g for g in games if not g.get("cover") and norm(g["title"]) not in cache]
    print(f"{len(games)} games, {sum(1 for g in games if g.get('cover'))} with covers, {len(todo)} to look up")

    done = 0

    def work(g: dict) -> None:
        nonlocal done
        if time.time() > stop_at:
            return
        cover, plats = lookup(g["title"])
        with _lock:
            cache[norm(g["title"])] = {"cover": cover}
            if cover:
                g["cover"] = cover
            if plats:
                g["platforms"] = sorted(set(g.get("platforms", [])) | set(plats))
            done += 1
            if done % 200 == 0:
                save(doc, cache)
                print(f"  {done}/{len(todo)}  covers={sum(1 for x in games if x.get('cover'))}", flush=True)

    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        list(ex.map(work, todo))
    save(doc, cache)
    left = sum(1 for g in games if not g.get("cover") and norm(g["title"]) not in cache)
    print(f"Done: {sum(1 for g in games if g.get('cover'))}/{len(games)} with covers; {left} not yet looked up")


if __name__ == "__main__":
    main()
