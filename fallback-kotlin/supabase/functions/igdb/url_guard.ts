// Which URLs the proxy is allowed to fetch.
//
// Step F5 makes the proxy fetch ARBITRARY user-supplied URLs so it can read Open
// Graph tags off a blog. That is a server-side request forgery hole if built
// naively: a share of `http://169.254.169.254/latest/meta-data/` would have the
// proxy read cloud instance credentials and hand them back, and
// `http://10.0.0.5/admin` would have it reach inside a private network the caller
// cannot.
//
// This file is deliberately PURE -- no Deno APIs, no fetch, no DNS -- for one
// reason: it is the part with all the logic, so it is the part that has to be
// tested, and pure functions over strings can be tested anywhere. `safe_fetch.ts`
// holds the small impure shell that calls it.
//
// The policy is an allowlist of shapes and a denylist of addresses, in that
// order. Both matter: the shape check rejects what should never be attempted, and
// the address check is applied TWICE, before and after DNS, because the name a
// URL carries and the address it resolves to are different facts and an attacker
// controls both.

/// Why a URL was refused. Returned rather than thrown so the caller can map it to
/// a response without string matching.
export type BlockReason =
  | "not-a-url"
  | "scheme"
  | "credentials"
  | "port"
  | "host-shape"
  | "blocked-address";

export type Verdict =
  | { ok: true; url: URL }
  | { ok: false; reason: BlockReason; detail: string };

function deny(reason: BlockReason, detail: string): Verdict {
  return { ok: false, reason, detail };
}

/// The only port the proxy will talk to.
///
/// 443 alone, which is stricter than "https only" and removes port scanning as a
/// capability outright: without this, `https://internal.host:9200` would let a
/// caller probe every port on a machine and read the difference between a refused
/// connection and a timeout. A blog on a non-standard https port is rare enough to
/// be worth losing.
const ALLOWED_PORT = 443;

/// IPv4 ranges that must never be fetched, as [firstOctetMask, prefixLength].
///
/// Each entry is here for a reason, not for completeness:
///   0.0.0.0/8        "this network"; 0.0.0.0 reaches localhost on some stacks
///   10/8, 172.16/12, 192.168/16   RFC1918 private networks
///   100.64/10        carrier NAT, routable inside an ISP
///   127/8            loopback, so the proxy cannot call itself
///   169.254/16       link-local, and the cloud metadata endpoint lives here
///   192.0.0/24       IETF protocol assignments
///   198.18/15        benchmarking, reachable on some networks
///   224/4            multicast
///   240/4            reserved, includes 255.255.255.255 broadcast
const BLOCKED_V4: ReadonlyArray<readonly [string, number]> = [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
];

/// Parses a dotted-quad into a 32-bit integer, or null when it is not one.
///
/// Strict on purpose: exactly four decimal octets, no leading zeros, nothing else.
/// The loose forms (`2130706433`, `0177.0.0.1`, `127.1`) are NOT handled here and
/// do not need to be, because `new URL()` normalises every one of them to a plain
/// dotted quad before this is ever called. There is a test for that, because it is
/// a load-bearing assumption rather than a hope.
export function parseIpv4(host: string): number | null {
  const parts = host.split(".");
  if (parts.length !== 4) return null;
  let value = 0;
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    if (part.length > 1 && part.startsWith("0")) return null;
    const octet = Number(part);
    if (octet > 255) return null;
    value = value * 256 + octet;
  }
  return value;
}

function inV4Range(address: number, base: string, prefix: number): boolean {
  const baseValue = parseIpv4(base);
  if (baseValue === null) return false;
  // A /0 would shift by 32, which JavaScript treats as a shift by 0.
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  return (address & mask) >>> 0 === (baseValue & mask) >>> 0;
}

export function isBlockedIpv4(host: string): boolean {
  const value = parseIpv4(host);
  if (value === null) return false;
  return BLOCKED_V4.some(([base, prefix]) => inV4Range(value, base, prefix));
}

/// Expands an IPv6 literal to its eight groups, or null when it is not one.
///
/// Handles `::` compression and a trailing embedded IPv4 (`::ffff:127.0.0.1`),
/// because that embedded form is the most common way a loopback address arrives
/// wearing an IPv6 costume.
export function parseIpv6(raw: string): number[] | null {
  let text = raw.trim();
  // A URL's IPv6 host keeps its brackets.
  if (text.startsWith("[") && text.endsWith("]")) text = text.slice(1, -1);
  // A zone id is not something the proxy has any business honouring.
  const zone = text.indexOf("%");
  if (zone !== -1) text = text.slice(0, zone);
  if (!text.includes(":")) return null;

  // A trailing dotted quad contributes the last two groups.
  let tail: number[] = [];
  const lastColon = text.lastIndexOf(":");
  const maybeV4 = text.slice(lastColon + 1);
  if (maybeV4.includes(".")) {
    const v4 = parseIpv4(maybeV4);
    if (v4 === null) return null;
    tail = [(v4 >>> 16) & 0xffff, v4 & 0xffff];
    text = text.slice(0, lastColon + 1);
    if (text.endsWith("::")) {
      // keep the compression marker intact
    } else {
      text = text.slice(0, -1);
    }
  }

  const halves = text.split("::");
  if (halves.length > 2) return null;

  const toGroups = (part: string): number[] | null => {
    if (part === "") return [];
    const out: number[] = [];
    for (const group of part.split(":")) {
      if (group === "") return null;
      if (!/^[0-9a-fA-F]{1,4}$/.test(group)) return null;
      out.push(parseInt(group, 16));
    }
    return out;
  };

  if (halves.length === 1) {
    const groups = toGroups(halves[0]);
    if (groups === null) return null;
    const all = [...groups, ...tail];
    return all.length === 8 ? all : null;
  }

  const head = toGroups(halves[0]);
  const rest = toGroups(halves[1]);
  if (head === null || rest === null) return null;
  const known = head.length + rest.length + tail.length;
  if (known > 8) return null;
  return [...head, ...new Array(8 - known).fill(0), ...rest, ...tail];
}

/// The IPv4 address embedded in an IPv6 one, or null.
///
/// Three embeddings, all of them real bypasses rather than trivia:
///   ::ffff:a.b.c.d   IPv4-mapped, what a dual-stack socket reports
///   64:ff9b::/96     NAT64, translated by the network on the way out
///   2002::/16        6to4, where the IPv4 sits in the second and third groups
export function embeddedIpv4(groups: number[]): string | null {
  const toDotted = (high: number, low: number) =>
    `${(high >> 8) & 0xff}.${high & 0xff}.${(low >> 8) & 0xff}.${low & 0xff}`;

  const isMapped =
    groups.slice(0, 5).every((g) => g === 0) && groups[5] === 0xffff;
  if (isMapped) return toDotted(groups[6], groups[7]);

  const isNat64 =
    groups[0] === 0x0064 && groups[1] === 0xff9b &&
    groups.slice(2, 6).every((g) => g === 0);
  if (isNat64) return toDotted(groups[6], groups[7]);

  if (groups[0] === 0x2002) return toDotted(groups[1], groups[2]);

  return null;
}

export function isBlockedIpv6(raw: string): boolean {
  const groups = parseIpv6(raw);
  if (groups === null) return false;

  // Unwrap first: a blocked IPv4 inside an IPv6 wrapper is still blocked, and
  // checking the wrapper's own prefix would miss it entirely.
  const embedded = embeddedIpv4(groups);
  if (embedded !== null && isBlockedIpv4(embedded)) return true;

  const [first] = groups;
  // :: unspecified and ::1 loopback.
  if (groups.every((g) => g === 0)) return true;
  if (groups.slice(0, 7).every((g) => g === 0) && groups[7] === 1) return true;
  // fc00::/7 unique local.
  if ((first & 0xfe00) === 0xfc00) return true;
  // fe80::/10 link-local.
  if ((first & 0xffc0) === 0xfe80) return true;
  // ff00::/8 multicast.
  if ((first & 0xff00) === 0xff00) return true;
  return false;
}

/// True when this literal address must not be fetched.
///
/// Takes a bare address, so it serves both the pre-DNS check on a URL that carries
/// a literal and the post-DNS check on what a name resolved to.
export function isBlockedAddress(host: string): boolean {
  return isBlockedIpv4(host) || isBlockedIpv6(host);
}

/// Hostnames the proxy refuses by name, before any lookup.
///
/// Not a security boundary on its own -- the address checks are -- but it stops the
/// obvious attempt without a DNS round trip, and it means a log of refusals reads
/// clearly.
const BLOCKED_NAMES = new Set([
  "localhost",
  "localhost.localdomain",
  "metadata",
  "metadata.google.internal",
  "metadata.goog",
]);

/// Checks a URL before any network call.
///
/// Rejects on shape alone: a non-https scheme, embedded credentials, a port other
/// than 443, a hostname shape that is not a name or an address, a blocked name, or
/// a literal address in a blocked range. Passing this is necessary and NOT
/// sufficient -- the caller must still re-check every resolved address, because a
/// name this accepts can resolve to anything at all.
export function guardRequestUrl(raw: string): Verdict {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return deny("not-a-url", "could not be parsed as a URL");
  }

  // https only. http would let a network-level attacker read and rewrite the
  // response, and every other scheme (file:, gopher:, data:) is a way to reach
  // something that is not a web page at all.
  if (url.protocol !== "https:") {
    return deny("scheme", `scheme ${url.protocol} is not https`);
  }

  // `https://user:pass@host` is a way to smuggle credentials into a log, and a way
  // to confuse a lazy host parser about where the host actually starts.
  if (url.username !== "" || url.password !== "") {
    return deny("credentials", "a URL with embedded credentials is refused");
  }

  const port = url.port === "" ? ALLOWED_PORT : Number(url.port);
  if (port !== ALLOWED_PORT) {
    return deny("port", `port ${port} is not ${ALLOWED_PORT}`);
  }

  const host = url.hostname.toLowerCase();
  if (host === "") return deny("host-shape", "no host");

  if (BLOCKED_NAMES.has(host)) {
    return deny("blocked-address", `${host} is refused by name`);
  }

  if (isBlockedAddress(host)) {
    return deny("blocked-address", `${host} is in a blocked range`);
  }

  // A bracketed IPv6 literal that did not parse, or a name with characters a
  // hostname cannot have, is refused rather than guessed at.
  const isV6Literal = host.startsWith("[");
  if (isV6Literal && parseIpv6(host) === null) {
    return deny("host-shape", "malformed IPv6 literal");
  }
  if (!isV6Literal && parseIpv4(host) === null &&
      !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.?$/
        .test(host)) {
    return deny("host-shape", "not a hostname or an address");
  }

  return { ok: true, url };
}

/// Checks what a hostname actually resolved to.
///
/// This is the half that cannot be skipped. `guardRequestUrl` sees only the NAME,
/// and an attacker owns the DNS for their own domain: `evil.test` can return
/// 127.0.0.1, and it can return a public address on the first lookup and a private
/// one on the second, which is DNS rebinding. Re-checking the resolved addresses
/// and then connecting to a checked address is what closes it.
///
/// Refuses when the list is empty, because "resolved to nothing" is not a reason to
/// proceed.
export function guardResolvedAddresses(
  addresses: readonly string[],
): { ok: true } | { ok: false; reason: BlockReason; detail: string } {
  if (addresses.length === 0) {
    return { ok: false, reason: "blocked-address", detail: "no addresses" };
  }
  for (const address of addresses) {
    if (isBlockedAddress(address)) {
      return {
        ok: false,
        reason: "blocked-address",
        detail: "resolved into a blocked range",
      };
    }
  }
  return { ok: true };
}
