"""Builds app/assets/catalog/games.json: a large offline catalogue with covers
and platforms, using only sources that need no key.

    python tool/build_catalog.py            # full build
    python tool/build_catalog.py --limit 50 # quick smoke run

Sources, in order of trust:
  * Wikidata (SPARQL): which games exist, title, first release year, platforms,
    Steam app id, English Wikipedia article. Filtered by sitelink count so the
    list is games people have heard of, not every shovelware entry.
  * Steam CDN: portrait 600x900 library art for games with a Steam app id.
  * Wikipedia REST summary: the infobox image for everything else (consoles,
    mobile, Nintendo). Same source the app already uses at runtime in
    lib/services/cover_art.dart.

The existing hand-authored rows are merged in, not replaced: their curated
`hours` survive, and any title Wikidata does not know is kept as it was.

IGDB is still the better source (licensed art, complete platform lists). When a
proxy with Twitch credentials exists this script should gain an IGDB pass; until
then this is what ships, and the app's live search upgrades it at runtime.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "app" / "assets" / "catalog" / "games.json"
UA = "LudeckCatalogBuilder/1.0 (build-time script; contact via repo)"

# Wikidata platform label -> the app's platform key. Anything unmapped is dropped:
# the app shows badges for platforms people own today, not every chip ever made.
PLATFORM_KEYS = {
    "microsoft windows": "pc", "windows": "pc", "linux": "pc", "steamos": "pc",
    "macos": "mac", "classic mac os": "mac",
    "android": "android",
    "ios": "ios", "ipados": "ios", "iphone os": "ios",
    "meta quest": "quest", "meta quest 2": "quest", "meta quest 3": "quest",
    "meta quest pro": "quest", "oculus quest": "quest", "oculus quest 2": "quest",
    "meta quest 3s": "quest", "meta horizon os": "quest",
    "nintendo switch": "switch", "nintendo switch 2": "switch2",
    "playstation 4": "ps4", "playstation 5": "ps5", "playstation 3": "ps3",
    "xbox one": "xone", "xbox series x and series s": "xsx",
    "xbox series x|s": "xsx", "xbox 360": "x360",
    "wii u": "wiiu", "nintendo 3ds": "3ds", "playstation vita": "vita",
}

# The biggest platform items come back from the label query without an English
# label (observed: PS4, PS5, Switch, iOS, Android, Xbox One/360 all unlabeled,
# the long-tail platforms labeled fine), so the ones that matter are keyed by
# their stable Wikidata id and never depend on a label round-trip.
PLATFORM_QIDS = {
    "Q1406": "pc",          # Microsoft Windows
    "Q388": "pc",           # Linux
    "Q5014725": "ps4",      # PlayStation 4
    "Q63184502": "ps5",     # PlayStation 5
    "Q10683": "ps3",        # PlayStation 3
    "Q19610114": "switch",  # Nintendo Switch
    "Q94": "android",       # Android
    "Q48493": "ios",        # iOS
    "Q13361286": "xone",    # Xbox One
    "Q48263": "x360",       # Xbox 360
    "Q64513817": "xsx",     # Xbox Series X and Series S
    "Q122761124": "switch2",  # Nintendo Switch 2
    "Q14116": "mac",        # macOS
    "Q63777286": "quest",   # Meta Quest
    "Q99620218": "quest",   # Meta Quest 2
    "Q119090835": "quest",  # Meta Quest 3
    "Q130437846": "quest",  # Meta Quest 3S
    "Q115368568": "quest",  # Meta Quest Pro
}

QUERY = """
SELECT ?g ?label ?links (MIN(?date) AS ?d) (SAMPLE(?steam) AS ?s) (SAMPLE(?art) AS ?a)
       (GROUP_CONCAT(DISTINCT ?p; separator="|") AS ?plats) WHERE {
  ?g wdt:P31 wd:Q7889 ; wikibase:sitelinks ?links .
  FILTER(?links >= %(min_links)d)
  # Wikidata moved many well-known items' names from `en` to the
  # language-neutral `mul` label. Filtering on `en` alone silently dropped Hades,
  # Astro Bot and Disco Elysium; accept either, preferring `en`.
  OPTIONAL { ?g rdfs:label ?en FILTER(LANG(?en) = "en") }
  OPTIONAL { ?g rdfs:label ?mul FILTER(LANG(?mul) = "mul") }
  BIND(COALESCE(?en, ?mul) AS ?label)
  FILTER(BOUND(?label))
  OPTIONAL { ?g wdt:P577 ?date }
  OPTIONAL { ?g wdt:P1733 ?steam }
  OPTIONAL { ?art schema:about ?g ; schema:isPartOf <https://en.wikipedia.org/> }
  OPTIONAL { ?g p:P400/ps:P400 ?p }
} GROUP BY ?g ?label ?links ORDER BY DESC(?links) LIMIT %(limit)d
"""

PLATFORM_LABELS = """
SELECT ?p ?l WHERE {
  VALUES ?p { %s }
  ?p rdfs:label ?l FILTER(LANG(?l) = "en" || LANG(?l) = "mul")
}
"""


def http_json(url: str, timeout: int = 60) -> object:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def sparql(q: str) -> list[dict]:
    # Cached by query text so a rerun (tuning the platform map, fixing a cover
    # rule) does not wait on WDQS's one-request-per-minute outage limit again.
    import hashlib, tempfile
    cache = Path(tempfile.gettempdir()) / "ludeck_wdqs" / (hashlib.sha1(q.encode()).hexdigest() + ".json")
    if cache.exists():
        return json.loads(cache.read_text(encoding="utf-8"))
    rows = _sparql_live(q)
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(rows), encoding="utf-8")
    return rows


def _sparql_live(q: str) -> list[dict]:
    # WDQS is rate-limiting to 1 req/min during its current outage; space every
    # call and back off a full minute on 429 rather than hammering it.
    global _last_sparql
    wait = 65 - (time.time() - _last_sparql)
    if _last_sparql and wait > 0:
        time.sleep(wait)
    url = "https://query.wikidata.org/sparql?format=json"
    body = urllib.parse.urlencode({"query": q}).encode()
    for attempt in range(5):
        try:
            _last_sparql = time.time()
            req = urllib.request.Request(url, data=body, headers={
                "User-Agent": UA, "Accept": "application/sparql-results+json",
                "Content-Type": "application/x-www-form-urlencoded"})
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)["results"]["bindings"]
        except Exception as e:  # noqa: BLE001 -- retry any transport failure
            print(f"  sparql attempt {attempt + 1} failed: {e}", file=sys.stderr)
            time.sleep(66)
    raise SystemExit("Wikidata did not answer; nothing written.")


_last_sparql = 0.0


def norm(title: str) -> str:
    t = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", t).strip()


def head_ok(url: str) -> bool:
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status == 200
    except Exception:  # noqa: BLE001
        return False


def steam_cover(appid: str) -> str | None:
    url = f"https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/{appid}/library_600x900.jpg"
    return url if head_ok(url) else None


def steam_search(title: str) -> tuple[str | None, list[str]]:
    """Exact-title Steam store match: (cover, platforms). No fuzzy guesses -- a
    wrong cover is worse than no cover."""
    q = urllib.parse.quote(title)
    try:
        data = http_json(f"https://store.steampowered.com/api/storesearch/?term={q}&l=english&cc=US", 20)
    except Exception:  # noqa: BLE001
        return None, []
    for item in (data.get("items") or []) if isinstance(data, dict) else []:
        if norm(item.get("name", "")) == norm(title):
            cover = steam_cover(str(item["id"]))
            plats = []
            p = item.get("platforms") or {}
            if p.get("windows") or p.get("linux"):
                plats.append("pc")
            if p.get("mac"):
                plats.append("mac")
            return cover, plats
    return None, []


def wiki_cover(article_url: str) -> str | None:
    title = article_url.rsplit("/wiki/", 1)[-1]
    try:
        data = http_json(f"https://en.wikipedia.org/api/rest_v1/page/summary/{title}", timeout=20)
    except Exception:  # noqa: BLE001
        return None
    thumb = data.get("thumbnail") if isinstance(data, dict) else None
    src = thumb.get("source") if isinstance(thumb, dict) else None
    return src if isinstance(src, str) and src else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=6000)
    ap.add_argument("--min-links", type=int, default=12)
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--no-covers", action="store_true", help="skip cover lookups (fast dry run)")
    args = ap.parse_args()

    existing = json.loads(ASSET.read_text(encoding="utf-8"))
    old_rows: list[dict] = existing["games"]
    old_by_norm = {norm(r["title"]): r for r in old_rows}

    print(f"Querying Wikidata (>= {args.min_links} sitelinks, limit {args.limit})...")
    rows = sparql(QUERY % {"min_links": args.min_links, "limit": args.limit})
    print(f"  {len(rows)} games")

    qids = sorted({p.rsplit("/", 1)[-1] for r in rows for p in r["plats"]["value"].split("|") if p})
    labels: dict[str, str] = {}
    for i in range(0, len(qids), 1500):
        chunk = " ".join(f"wd:{q}" for q in qids[i:i + 1500])
        for b in sparql(PLATFORM_LABELS % chunk):
            labels[b["p"]["value"].rsplit("/", 1)[-1]] = b["l"]["value"].lower()

    games: dict[str, dict] = {}
    unmapped: dict[str, int] = {}
    for r in rows:
        title = r["label"]["value"].strip()
        if not title or re.fullmatch(r"Q\d+", title):
            continue
        key = norm(title)
        if key in games:
            continue  # same title twice: keep the better-known (rows are sorted)
        plats = set()
        for p in r["plats"]["value"].split("|"):
            if not p:
                continue
            qid = p.rsplit("/", 1)[-1]
            lab = labels.get(qid, "?" + qid)
            k = PLATFORM_QIDS.get(qid) or PLATFORM_KEYS.get(lab)
            if k:
                plats.add(k)
            else:
                unmapped[lab] = unmapped.get(lab, 0) + 1
        steam = r.get("s", {}).get("value")
        if steam:
            plats.add("pc")
        year = r.get("d", {}).get("value", "")[:4]
        row = {"title": title}
        if year.isdigit() and 1970 <= int(year) <= 2030:
            row["year"] = int(year)
        old = old_by_norm.get(key)
        if old and old.get("hours"):
            row["hours"] = old["hours"]
        if plats:
            row["platforms"] = sorted(plats)
        row["_steam"] = steam
        row["_article"] = r.get("a", {}).get("value")
        row["_links"] = int(r["links"]["value"])
        games[key] = row

    top = sorted(unmapped.items(), key=lambda kv: -kv[1])[:25]
    print("  unmapped platforms (top):", ", ".join(f"{k}={v}" for k, v in top))
    print(f"  {len(labels)} platform labels resolved for {len(qids)} platform ids")

    # Hand-authored rows Wikidata did not match stay exactly as they were.
    kept = 0
    for k, old in old_by_norm.items():
        if k not in games:
            games[k] = dict(old)
            kept += 1
    print(f"  merged; {kept} hand-authored rows kept unmatched")

    todo = [] if args.no_covers else list(games.values())
    print(f"Resolving covers for {len(todo)} games with {args.workers} workers...")

    def resolve(g: dict) -> None:
        url = steam_cover(g["_steam"]) if g.get("_steam") else None
        if url is None and g.get("_article"):
            url = wiki_cover(g["_article"])
        if url is None:
            url, plats = steam_search(g["title"])
            if plats:
                g["platforms"] = sorted(set(g.get("platforms", [])) | set(plats))
        if url:
            g["cover"] = url

    done = 0
    with cf.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for _ in ex.map(resolve, todo):
            done += 1
            if done % 250 == 0:
                print(f"  {done}/{len(todo)}")

    out_rows = sorted(games.values(), key=lambda g: (-g.get("_links", 0), g["title"]))
    for g in out_rows:
        for k in ("_steam", "_article", "_links"):
            g.pop(k, None)
        # No cover URLs in the shipped asset (2026-09-28). The project
        # invariant is that the bundle names no third-party host, and the
        # matched art was Steam store capsules and Wikipedia fair-use infobox
        # images, neither licensed for an app. Covers come from IGDB through
        # the proxy, with attribution; the bundle is titles, years, hours and
        # platforms, which are facts.
        g.pop("cover", None)

    with_plat = sum(1 for g in out_rows if g.get("platforms"))
    doc = {
        "version": 3,
        "note": ("Generated by tool/build_catalog.py from Wikidata, Steam and Wikipedia title "
                 "lists, merged over the original hand-authored list. Not IGDB data. Rows are "
                 "ordered best-known first. platforms uses the app platform keys. No cover art: "
                 "covers come from IGDB through the proxy, which licenses and attributes them."),
        "games": out_rows,
    }
    text = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
    assert "http" not in text and ".com" not in text, "the bundle must name no third-party host"
    ASSET.write_text(text, encoding="utf-8")
    print(f"Wrote {len(out_rows)} games ({with_plat} with platforms) -> {ASSET}")


if __name__ == "__main__":
    main()
