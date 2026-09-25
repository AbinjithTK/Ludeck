// The fetcher. Small on purpose: all the judgement lives in url_guard.ts.
//
// This is the impure shell -- DNS, sockets, a clock -- and it is kept thin because
// it is the part that cannot be unit tested without a network. Everything with a
// decision in it was pushed into the guard, which IS tested (see
// url_guard.test.ts, 17 tests, run with node).
//
// HONEST LIMITATION, stated here rather than buried: after checking the resolved
// addresses this still connects by HOSTNAME, because Deno's fetch cannot be told
// "connect to this IP but present this SNI and Host". A resolver that returns a
// public address to our lookup and a private one to the connect a millisecond
// later is therefore not fully closed by this code -- that is the residual DNS
// rebinding window. Closing it properly needs either a pinned-IP connect or an
// egress firewall that refuses private destinations at the network level, and the
// second is the right answer in production. What IS closed here: every literal
// address, every blocked name, every redirect hop, and any domain whose lookup
// shows a private address at request time.

import {
  guardRequestUrl,
  guardResolvedAddresses,
  type BlockReason,
} from "./url_guard.ts";

export type FetchRefusal = { ok: false; reason: BlockReason | "too-many-redirects" | "too-large" | "timeout" | "unreachable"; detail: string };
export type FetchSuccess = { ok: true; finalUrl: string; contentType: string; text: string };
export type FetchOutcome = FetchSuccess | FetchRefusal;

/// Caps. Every one of these is a way a hostile page can cost the proxy money or
/// availability, not a tidiness preference.
const MAX_REDIRECTS = 3;
const MAX_BODY_BYTES = 512 * 1024;
const TIMEOUT_MS = 6000;

/// Content types worth reading. Anything else is a download, not a page.
const READABLE = ["text/html", "application/xhtml+xml", "text/plain"];

function refuse(reason: FetchRefusal["reason"], detail: string): FetchRefusal {
  return { ok: false, reason, detail };
}

/// Resolves a host to addresses, or null when it cannot be resolved.
///
/// A literal address needs no lookup, and asking for one would fail: `resolveDns`
/// wants a name. Returning the literal itself keeps the caller's single code path.
async function resolve(hostname: string): Promise<string[] | null> {
  const bare = hostname.startsWith("[") ? hostname.slice(1, -1) : hostname;
  // Already an address if it parses as one; the guard has already vetted it.
  if (/^[\d.]+$/.test(bare) || bare.includes(":")) return [bare];

  const found: string[] = [];
  for (const kind of ["A", "AAAA"] as const) {
    try {
      // deno-lint-ignore no-explicit-any
      const records = await (globalThis as any).Deno.resolveDns(hostname, kind);
      for (const record of records) found.push(String(record));
    } catch {
      // A missing AAAA is ordinary, not a failure. Only "neither" is.
    }
  }
  return found.length === 0 ? null : found;
}

/// Checks one URL completely: shape, then what its name resolves to.
async function vet(raw: string): Promise<{ ok: true; url: URL } | FetchRefusal> {
  const shape = guardRequestUrl(raw);
  if (!shape.ok) return refuse(shape.reason, shape.detail);

  const addresses = await resolve(shape.url.hostname);
  if (addresses === null) {
    return refuse("unreachable", "the host did not resolve");
  }

  const resolved = guardResolvedAddresses(addresses);
  if (!resolved.ok) return refuse(resolved.reason, resolved.detail);

  return { ok: true, url: shape.url };
}

/// Fetches a page for metadata extraction.
///
/// Returns the response TEXT for the caller to parse in-process. The route must
/// never put this in a response: the point of the proxy is to hand back extracted
/// fields, and echoing a fetched body would turn it into an open relay that
/// launders requests through our address.
export async function safeFetchPage(raw: string): Promise<FetchOutcome> {
  let current = raw;

  // Every hop is re-vetted from scratch. A redirect is an attacker-controlled URL
  // exactly like the first one, and asking the runtime to FOLLOW redirects for us
  // would have it chase that URL with no checks at all, which is how a guarded
  // fetcher ends up reading the metadata endpoint anyway. check.ps1 rule 11 refuses
  // that follow mode by name anywhere in this directory, including inside a
  // comment, which is why this paragraph describes it in words.
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const checked = await vet(current);
    if (!checked.ok) return checked;

    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), TIMEOUT_MS);
    let response: Response;
    try {
      response = await fetch(checked.url, {
        method: "GET",
        redirect: "manual",
        signal: abort.signal,
        headers: {
          // Identifies the caller honestly, and asks for a page rather than a file.
          "User-Agent": "Ludeck-link-reader/1.0",
          "Accept": "text/html,application/xhtml+xml;q=0.9,text/plain;q=0.8",
        },
      });
    } catch (error) {
      clearTimeout(timer);
      if (abort.signal.aborted) return refuse("timeout", "took too long");
      return refuse("unreachable", String((error as Error)?.message ?? error));
    } finally {
      clearTimeout(timer);
    }

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      // Drain, so the connection is not left hanging on a body nobody reads.
      await response.body?.cancel();
      if (location === null) {
        return refuse("unreachable", "redirect with no location");
      }
      // Resolved against the current URL, because a Location may be relative.
      current = new URL(location, checked.url).toString();
      continue;
    }

    if (!response.ok) {
      await response.body?.cancel();
      return refuse("unreachable", `status ${response.status}`);
    }

    const contentType = (response.headers.get("content-type") ?? "")
      .split(";")[0]
      .trim()
      .toLowerCase();
    if (!READABLE.includes(contentType)) {
      await response.body?.cancel();
      return refuse("too-large", `content-type ${contentType || "unknown"}`);
    }

    // A declared length over the cap is refused before a byte is read.
    const declared = Number(response.headers.get("content-length") ?? "0");
    if (declared > MAX_BODY_BYTES) {
      await response.body?.cancel();
      return refuse("too-large", "content-length over cap");
    }

    const body = response.body;
    if (body === null) return refuse("unreachable", "no body");

    // Read to the cap and STOP, rather than reading it all and checking after. A
    // page that streams forever would otherwise exhaust memory before any check
    // ran, which is the whole reason the cap exists.
    const reader = body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (value === undefined) continue;
        total += value.byteLength;
        if (total > MAX_BODY_BYTES) {
          await reader.cancel();
          return refuse("too-large", "body over cap");
        }
        chunks.push(value);
      }
    } catch (error) {
      return refuse("unreachable", String((error as Error)?.message ?? error));
    }

    const joined = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      joined.set(chunk, offset);
      offset += chunk.byteLength;
    }

    return {
      ok: true,
      finalUrl: checked.url.toString(),
      contentType,
      text: new TextDecoder("utf-8", { fatal: false }).decode(joined),
    };
  }

  return refuse("too-many-redirects", `more than ${MAX_REDIRECTS} hops`);
}
