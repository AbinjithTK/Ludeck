// Supabase Edge Function: the ONLY path to IGDB.
//
// Why a proxy at all: IGDB does not support CORS and will not set
// Access-Control-Allow-Origin, so a direct client call both fails and leaks the
// access token. See BUILD.md section 6.
//
// Verified IGDB constraints encoded here:
//   - auth is Twitch OAuth2 client_credentials
//   - tokens last ~60 days AND an app may hold at most 25 active tokens, so the
//     token is cached and reused, never minted per request
//   - 4 requests/second, 8 concurrent maximum
//
// Deploy:  supabase functions deploy igdb --no-verify-jwt
// Secrets: supabase secrets set TWITCH_CLIENT_ID=... TWITCH_CLIENT_SECRET=...

const TWITCH_CLIENT_ID = Deno.env.get("TWITCH_CLIENT_ID") ?? "";
const TWITCH_CLIENT_SECRET = Deno.env.get("TWITCH_CLIENT_SECRET") ?? "";

// Only these IGDB endpoints are reachable. An open proxy is an open wallet.
const ALLOWED_ENDPOINTS = new Set([
  "games",
  "covers",
  "platforms",
  "genres",
  "game_time_to_beats",
  "search",
]);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------------------------------------------------------------------------
// Token cache. Module scope persists for the life of the isolate, which is the
// best available cache here; a cold isolate mints one token, not one per call.
// ---------------------------------------------------------------------------
let cachedToken: { value: string; expiresAt: number } | null = null;

async function getToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) return cachedToken.value;

  const url =
    `https://id.twitch.tv/oauth2/token?client_id=${encodeURIComponent(TWITCH_CLIENT_ID)}` +
    `&client_secret=${encodeURIComponent(TWITCH_CLIENT_SECRET)}` +
    `&grant_type=client_credentials`;

  const res = await fetch(url, { method: "POST" });
  if (!res.ok) throw new Error(`twitch auth failed: ${res.status}`);

  const body = await res.json() as { access_token: string; expires_in: number };
  cachedToken = {
    value: body.access_token,
    // expires_in is seconds; keep a margin so we never present a dead token.
    expiresAt: now + (body.expires_in - 300) * 1000,
  };
  return cachedToken.value;
}

// ---------------------------------------------------------------------------
// Rate limiting: 4 requests/second, 8 concurrent.
//
// Honest limitation: each isolate enforces this for its own traffic, so under
// heavy concurrent load across isolates the aggregate can exceed 4/sec. This is
// a floor, not a guarantee. The real protection is that the app caches
// aggressively and this is the only call site, so request volume stays low.
// ---------------------------------------------------------------------------
const MIN_INTERVAL_MS = 250; // 4 per second
const MAX_CONCURRENT = 8;

let lastRequestAt = 0;
let inFlight = 0;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function throttle(): Promise<void> {
  while (inFlight >= MAX_CONCURRENT) await sleep(25);

  const now = Date.now();
  const wait = Math.max(0, lastRequestAt + MIN_INTERVAL_MS - now);
  lastRequestAt = Math.max(now, lastRequestAt + MIN_INTERVAL_MS);
  if (wait > 0) await sleep(wait);
}

// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }
  if (!TWITCH_CLIENT_ID || !TWITCH_CLIENT_SECRET) {
    return json({ error: "proxy not configured" }, 500);
  }

  let endpoint: string;
  let query: string;
  try {
    const body = await req.json() as { endpoint?: string; query?: string };
    endpoint = (body.endpoint ?? "").trim();
    query = (body.query ?? "").trim();
  } catch {
    return json({ error: "malformed json" }, 400);
  }

  if (!ALLOWED_ENDPOINTS.has(endpoint)) {
    return json({ error: `endpoint not allowed: ${endpoint}` }, 400);
  }
  if (!query) {
    return json({ error: "query required" }, 400);
  }
  // An APICalypse query is a small DSL, not SQL, but cap it so the proxy cannot
  // be used to post arbitrary volumes.
  if (query.length > 2000) {
    return json({ error: "query too long" }, 400);
  }

  try {
    const token = await getToken();
    await throttle();
    inFlight++;
    try {
      const res = await fetch(`https://api.igdb.com/v4/${endpoint}`, {
        method: "POST",
        headers: {
          "Client-ID": TWITCH_CLIENT_ID,
          "Authorization": `Bearer ${token}`,
          "Accept": "application/json",
        },
        body: query,
      });

      if (res.status === 429) {
        return json({ error: "igdb rate limited", retry: true }, 429);
      }
      if (!res.ok) {
        // Deliberately does not echo the IGDB body, which can contain the
        // request context. Status only.
        return json({ error: `igdb ${res.status}` }, 502);
      }
      return json(await res.json(), 200);
    } finally {
      inFlight--;
    }
  } catch (err) {
    return json({ error: String(err instanceof Error ? err.message : err) }, 500);
  }
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
