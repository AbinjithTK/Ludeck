#!/usr/bin/env python3
"""
Scrape a Devpost hackathon project gallery to structured JSON + CSV.

Two stages:
  1. Gallery crawl  -- pages the public project-gallery, one request per page
                       (24 projects each), giving name / tagline / builder /
                       likes / comments / thumbnail / slug.
  2. Detail crawl   -- one request per project page, adding the full writeup,
                       "Built With" tags, app links, demo video, team and the
                       hackathons it was entered into.

Both stages are RESUMABLE: already-captured projects are skipped, so an
interrupted run picks up where it stopped instead of starting over.

Usage
    python scrape_shipaton.py                     # gallery + details (default)
    python scrape_shipaton.py --gallery-only      # fast, list-level fields only
    python scrape_shipaton.py --refresh           # ignore cache, re-fetch all
    python scrape_shipaton.py --workers 4 --delay 0.6
    python scrape_shipaton.py --hackathon some-other-hackathon

Outputs (in --outdir, default ./data):
    gallery.json    list-level records, one per project
    projects.json   full records including detail fields
    projects.csv    flat table for spreadsheets / SQL import
    state.json      run metadata (counts, timing, failures)

Politeness: this reads public pages only. Keep --workers modest and --delay
non-zero; the defaults are deliberately gentle and back off on 429/5xx.
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:  # pragma: no cover
    sys.exit("Missing dependencies. Install with: pip install requests beautifulsoup4")

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)
HEADERS = {"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"}

# Transient statuses worth retrying; anything else is a hard result.
RETRY_STATUS = {429, 500, 502, 503, 504}

_print_lock = threading.Lock()


def log(msg: str) -> None:
    with _print_lock:
        print(msg, flush=True)


def fetch(
    session: requests.Session,
    url: str,
    *,
    delay: float,
    attempts: int = 4,
    timeout: int = 30,
) -> requests.Response | None:
    """GET with jittered delay, exponential backoff and Retry-After support."""
    for attempt in range(1, attempts + 1):
        # Jitter avoids a synchronised thundering herd across worker threads.
        time.sleep(delay * random.uniform(0.6, 1.4))
        try:
            resp = session.get(url, headers=HEADERS, timeout=timeout)
        except requests.RequestException as exc:
            if attempt == attempts:
                log(f"  ! network error {url}: {exc}")
                return None
            time.sleep(2**attempt)
            continue

        if resp.status_code == 200:
            return resp
        if resp.status_code in RETRY_STATUS and attempt < attempts:
            wait = float(resp.headers.get("Retry-After") or 2**attempt)
            log(f"  . {resp.status_code} on {url}, waiting {wait:.0f}s")
            time.sleep(wait)
            continue
        log(f"  ! HTTP {resp.status_code} {url}")
        return None
    return None


def _int_from(text: str) -> int:
    m = re.search(r"\d+", text or "")
    return int(m.group()) if m else 0


def parse_gallery_page(html: str) -> list[dict[str, Any]]:
    """Extract the 24-ish project cards from one gallery page."""
    soup = BeautifulSoup(html, "html.parser")
    out: list[dict[str, Any]] = []

    for item in soup.select(".gallery-item"):
        link = item.select_one("a.link-to-software")
        if not link or not link.get("href"):
            continue
        url = link["href"]

        name_el = item.select_one(".software-entry-name h5")
        tagline_el = item.select_one("p.small.tagline")
        thumb_el = item.select_one("img.software_thumbnail_image")

        builders, profiles = [], []
        for span in item.select(".members .user-profile-link"):
            img = span.select_one("img")
            if img and img.get("alt"):
                builders.append(img["alt"].strip())
            if span.get("data-url"):
                profiles.append(span["data-url"])

        like_el = item.select_one(".count.like-count")
        comment_el = item.select_one(".count.comment-count")

        out.append(
            {
                "software_id": item.get("data-software-id"),
                "slug": url.rstrip("/").rsplit("/", 1)[-1],
                "url": url,
                "name": name_el.get_text(strip=True) if name_el else "",
                "tagline": tagline_el.get_text(strip=True) if tagline_el else "",
                "builders": builders,
                "builder_profiles": profiles,
                "likes": _int_from(like_el.get_text() if like_el else ""),
                "comments": _int_from(comment_el.get_text() if comment_el else ""),
                "thumbnail": thumb_el.get("src") if thumb_el else "",
            }
        )
    return out


def crawl_gallery(
    session: requests.Session, hackathon: str, *, delay: float, max_pages: int
) -> list[dict[str, Any]]:
    """Page the gallery until a page yields no cards."""
    base = f"https://{hackathon}.devpost.com/project-gallery"
    records: list[dict[str, Any]] = []
    seen: set[str] = set()

    for page in range(1, max_pages + 1):
        resp = fetch(session, f"{base}?page={page}", delay=delay)
        if resp is None:
            log(f"  ! giving up on page {page}")
            break

        page_records = parse_gallery_page(resp.text)
        if not page_records:
            log(f"  page {page}: empty -- end of gallery")
            break

        fresh = [r for r in page_records if r["url"] not in seen]
        seen.update(r["url"] for r in fresh)
        records.extend(fresh)
        log(f"  page {page}: {len(page_records)} cards ({len(records)} total)")

        # Devpost clamps out-of-range pages to the last real one, which would
        # otherwise loop forever returning duplicates.
        if not fresh:
            log(f"  page {page}: all duplicates -- end of gallery")
            break

    return records


def parse_detail_page(html: str) -> dict[str, Any]:
    """Extract the full writeup and metadata from one project page."""
    soup = BeautifulSoup(html, "html.parser")

    details_el = soup.select_one("#app-details-left") or soup.select_one("#app-details")
    description = details_el.get_text("\n", strip=True) if details_el else ""

    built_with = [t.get_text(strip=True) for t in soup.select("#built-with .cp-tag")]

    links = []
    for a in soup.select(".app-links a"):
        href = a.get("href")
        if href:
            links.append({"label": a.get_text(strip=True), "url": href})

    video = ""
    for iframe in soup.select("iframe"):
        src = iframe.get("src") or ""
        if "youtube" in src or "vimeo" in src:
            video = src
            break

    team = []
    for img in soup.select("#app-team img"):
        if img.get("alt"):
            team.append(img["alt"].strip())

    hackathons = [
        a.get_text(strip=True) for a in soup.select("#submissions a") if a.get_text(strip=True)
    ]

    # Awards only populate after judging; absent during the submission window.
    awards = [
        el.get_text(" ", strip=True)
        for el in soup.select(".winner, .software-awards li, #submissions .winner")
        if el.get_text(strip=True)
    ]

    return {
        "description": description,
        "description_chars": len(description),
        "built_with": built_with,
        "links": links,
        "video_url": video,
        "team": team,
        "team_size": len(team),
        "hackathons": hackathons,
        "gallery_images": len(soup.select("#gallery img")),
        "awards": awards,
    }


def scrape_details(
    records: list[dict[str, Any]],
    *,
    workers: int,
    delay: float,
    cache: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    """Fetch each project page in a bounded thread pool, reusing the cache."""
    todo = [r for r in records if r["url"] not in cache]
    log(f"  {len(cache)} cached, {len(todo)} to fetch")

    failures: list[str] = []
    done = 0
    total = len(todo)

    def work(rec: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any] | None]:
        # One Session per thread: requests Sessions are not thread-safe.
        with requests.Session() as s:
            resp = fetch(s, rec["url"], delay=delay)
        return rec, (parse_detail_page(resp.text) if resp else None)

    if todo:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(work, r) for r in todo]
            for fut in as_completed(futures):
                rec, detail = fut.result()
                done += 1
                if detail is None:
                    failures.append(rec["url"])
                else:
                    cache[rec["url"]] = detail
                if done % 25 == 0 or done == total:
                    log(f"  detail {done}/{total} ({len(failures)} failed)")

    merged = [{**r, **cache.get(r["url"], {})} for r in records]
    return merged, failures


def write_outputs(outdir: Path, records: list[dict[str, Any]]) -> None:
    (outdir / "projects.json").write_text(
        json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    columns = [
        "software_id", "slug", "name", "tagline", "builders", "likes", "comments",
        "built_with", "team_size", "video_url", "description_chars", "gallery_images",
        "links", "hackathons", "awards", "url",
    ]

    def flatten(value: Any) -> str:
        if isinstance(value, list):
            if value and isinstance(value[0], dict):
                return " | ".join(str(d.get("url", "")) for d in value)
            return " | ".join(str(v) for v in value)
        return "" if value is None else str(value)

    with (outdir / "projects.csv").open("w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh)
        writer.writerow(columns)
        for rec in records:
            writer.writerow([flatten(rec.get(col)) for col in columns])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hackathon", default="revenuecat-shipaton-2026", help="Devpost subdomain")
    # Anchored to this file, NOT the working directory: a CWD-relative default
    # silently creates a fresh empty data dir when the script is run from the
    # workspace root, which defeats the resume cache and re-fetches everything.
    ap.add_argument(
        "--outdir",
        default=str(Path(__file__).resolve().parent / "data"),
        help="output directory (default: the data/ dir beside this script)",
    )
    ap.add_argument("--workers", type=int, default=6, help="concurrent detail fetches")
    ap.add_argument("--delay", type=float, default=0.35, help="base per-request delay (seconds)")
    ap.add_argument("--max-pages", type=int, default=200, help="gallery page ceiling")
    ap.add_argument("--gallery-only", action="store_true", help="skip project detail pages")
    ap.add_argument("--refresh", action="store_true", help="ignore cached details")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    started = time.time()

    log(f"Gallery crawl: {args.hackathon}")
    with requests.Session() as session:
        gallery = crawl_gallery(
            session, args.hackathon, delay=args.delay, max_pages=args.max_pages
        )

    if not gallery:
        log("No projects found -- check the hackathon subdomain.")
        return 1

    (outdir / "gallery.json").write_text(
        json.dumps(gallery, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    log(f"Captured {len(gallery)} projects -> {outdir / 'gallery.json'}")

    records, failures = gallery, []
    if not args.gallery_only:
        cache: dict[str, dict[str, Any]] = {}
        cache_path = outdir / "projects.json"
        if cache_path.exists() and not args.refresh:
            try:
                for rec in json.loads(cache_path.read_text(encoding="utf-8")):
                    if rec.get("description_chars"):
                        cache[rec["url"]] = {
                            k: rec[k]
                            for k in (
                                "description", "description_chars", "built_with", "links",
                                "video_url", "team", "team_size", "hackathons",
                                "gallery_images", "awards",
                            )
                            if k in rec
                        }
            except (json.JSONDecodeError, KeyError, TypeError) as exc:
                log(f"  . ignoring unreadable cache: {exc}")

        log("Detail crawl:")
        records, failures = scrape_details(
            gallery, workers=args.workers, delay=args.delay, cache=cache
        )

    write_outputs(outdir, records)

    elapsed = time.time() - started
    with_detail = sum(1 for r in records if r.get("description_chars"))
    state = {
        "hackathon": args.hackathon,
        "scraped_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "projects": len(records),
        "with_detail": with_detail,
        "failed_urls": failures,
        "elapsed_seconds": round(elapsed, 1),
    }
    (outdir / "state.json").write_text(
        json.dumps(state, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    log(
        f"\nDone in {elapsed:.0f}s -- {len(records)} projects, "
        f"{with_detail} with full detail, {len(failures)} failed."
    )
    log(f"Outputs: {outdir / 'projects.json'}, {outdir / 'projects.csv'}")
    if failures:
        log("Re-run to retry the failures (cached successes are skipped).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
