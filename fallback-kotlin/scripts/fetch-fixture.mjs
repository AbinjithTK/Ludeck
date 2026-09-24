#!/usr/bin/env node
// Build the 30-game seed fixture from REAL IGDB data.
//
// Why a script and not a hand-written JSON file: inventing IGDB ids would break
// every cover image and quietly poison the one identity the whole data model
// rests on. Real ids or nothing.
//
// BUILD.md section 5 requires the fixture to deliberately contain awkward data:
// a very long title, one with no cover art, a 200-hour RPG beside a 2-hour
// indie, and games owned on two platforms. Placeholder data hides layout bugs
// and looks poor on camera. This script ASSERTS those cases rather than hoping.
//
// Usage:
//   $env:SUPABASE_URL="https://xxxx.supabase.co"
//   $env:SUPABASE_ANON_KEY="ey..."
//   node scripts/fetch-fixture.mjs
//
// Output: app/src/main/assets/fixture.json

import { writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error("Set SUPABASE_URL and SUPABASE_ANON_KEY first.");
  process.exit(1);
}

const PROXY = `${SUPABASE_URL}/functions/v1/igdb`;
const OUT = resolve("app/src/main/assets/fixture.json");

// Real titles, chosen to cover the awkward cases. Console/PC heavy at the top,
// mobile deliberately represented because mobile games are first-class here and
// no rival claims them.
const TITLES = [
  // long, sprawling RPGs — the 100h+ end of the range
  "Elden Ring",
  "Persona 5 Royal",
  "Baldur's Gate 3",
  "The Witcher 3: Wild Hunt",
  "Monster Hunter: World",
  "Divinity: Original Sin II",
  // deliberately long titles, to stress text layout
  "Atelier Ryza: Ever Darkness & the Secret Hideout",
  "Danganronpa V3: Killing Harmony",
  "Zero Escape: Virtue's Last Reward",
  "The Stanley Parable: Ultra Deluxe",
  // short games — the 2h end of the range
  "A Short Hike",
  "Thomas Was Alone",
  "Journey",
  "Gone Home",
  "Firewatch",
  // multi-platform staples, for the two-copies case
  "Hades",
  "Stardew Valley",
  "Celeste",
  "Hollow Knight",
  "Dead Cells",
  // mobile-first or mobile-prominent
  "Monument Valley",
  "Alto's Odyssey",
  "Slay the Spire",
  "Vampire Survivors",
  "Balatro",
  "Card Thief",
  "Mini Metro",
  "Threes!",
  "Reigns",
  "Florence",
];

async function igdb(endpoint, query) {
  const res = await fetch(PROXY, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify({ endpoint, query }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`proxy ${res.status} on ${endpoint}: ${text.slice(0, 200)}`);
  }
  return res.json();
}

function escapeQuoted(s) {
  return s.replace(/"/g, '\\"');
}

async function resolveTitle(title) {
  const rows = await igdb(
    "games",
    `fields id,name,slug,cover.image_id,first_release_date,platforms.name,platforms.id;` +
      ` search "${escapeQuoted(title)}"; limit 5;`
  );
  if (!Array.isArray(rows) || rows.length === 0) return null;

  // Prefer an exact case-insensitive name match; IGDB search is fuzzy and will
  // happily return a DLC or a remaster above the base game.
  const exact = rows.find(
    (r) => (r.name ?? "").toLowerCase() === title.toLowerCase()
  );
  return exact ?? rows[0];
}

async function timeToBeat(gameIds) {
  if (gameIds.length === 0) return new Map();
  const rows = await igdb(
    "game_time_to_beats",
    `fields game_id,hastily,normally,completely,count;` +
      ` where game_id = (${gameIds.join(",")}); limit 500;`
  );
  const out = new Map();
  for (const r of rows ?? []) out.set(r.game_id, r);
  return out;
}

// IGDB cover image_id -> a real URL. t_cover_big is 264x374.
const coverUrl = (imageId) =>
  imageId
    ? `https://images.igdb.com/igdb/image/upload/t_cover_big/${imageId}.jpg`
    : null;

async function main() {
  const resolved = [];
  const missing = [];

  for (const title of TITLES) {
    try {
      const row = await resolveTitle(title);
      if (!row) {
        missing.push(title);
        continue;
      }
      resolved.push({ requested: title, row });
      process.stdout.write(`. ${row.name} (${row.id})\n`);
    } catch (err) {
      console.error(`! ${title}: ${err.message}`);
      missing.push(title);
    }
  }

  const ttb = await timeToBeat(resolved.map((r) => r.row.id));

  const games = resolved.map(({ row }) => {
    const t = ttb.get(row.id);
    return {
      igdbId: row.id,
      title: row.name,
      slug: row.slug ?? null,
      coverUrl: coverUrl(row.cover?.image_id),
      releaseYear: row.first_release_date
        ? new Date(row.first_release_date * 1000).getUTCFullYear()
        : null,
      // IGDB returns SECONDS. Stored as seconds; converted exactly once, in the
      // Kotlin mapper. Never divide here.
      timeToBeatSeconds: t?.normally ?? null,
      timeToBeatSampleCount: t?.count ?? 0,
      platforms: (row.platforms ?? []).map((p) => p.name).filter(Boolean),
    };
  });

  // --- assert the awkward cases BUILD.md requires -------------------------
  const problems = [];

  const longest = games.reduce(
    (a, g) => (g.title.length > a.title.length ? g : a),
    games[0] ?? { title: "" }
  );
  if (longest.title.length < 34) {
    problems.push(
      `no long title: longest is "${longest.title}" at ${longest.title.length} chars`
    );
  }

  const noCover = games.filter((g) => !g.coverUrl);
  if (noCover.length === 0) {
    problems.push(
      "no game without cover art. Add one, or the missing-cover layout is never exercised"
    );
  }

  const withTtb = games.filter((g) => g.timeToBeatSeconds);
  const longGame = withTtb.find((g) => g.timeToBeatSeconds >= 100 * 3600);
  const shortGame = withTtb.find((g) => g.timeToBeatSeconds <= 3 * 3600);
  if (!longGame) problems.push("no game over 100 hours in the fixture");
  if (!shortGame) problems.push("no game under 3 hours in the fixture");

  const multi = games.filter((g) => g.platforms.length >= 2);
  if (multi.length < 2) problems.push("fewer than two multi-platform games");

  await mkdir(dirname(OUT), { recursive: true });
  await writeFile(OUT, JSON.stringify({ games }, null, 2), "utf8");

  console.log(`\nwrote ${games.length} games -> ${OUT}`);
  console.log(
    `time-to-beat coverage: ${withTtb.length}/${games.length}` +
      ` (expect gaps, and expect them to be worst on mobile titles)`
  );
  if (missing.length) console.log(`unresolved titles: ${missing.join(", ")}`);

  if (problems.length) {
    console.log("\nFIXTURE PROBLEMS — the awkward cases are not all covered:");
    for (const p of problems) console.log(`  - ${p}`);
    process.exitCode = 1;
  } else {
    console.log("\nall required awkward cases present.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
