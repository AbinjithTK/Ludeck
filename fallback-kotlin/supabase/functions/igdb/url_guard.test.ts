// Tests for the SSRF address policy.
//
// Run with:  node --experimental-strip-types --test url_guard.test.ts
//
// Node rather than Deno, deliberately. The guard is pure by design so it can be
// tested with whatever runtime is at hand, and Deno is not installed on this
// machine. The alternative was shipping security-critical range arithmetic with no
// executed test at all, which is not a trade worth making.
//
// One test per blocked range, because "I wrote a list of CIDRs" and "the list
// actually refuses those addresses" are different claims and only the second one
// is worth anything.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  embeddedIpv4,
  guardRequestUrl,
  guardResolvedAddresses,
  isBlockedAddress,
  parseIpv4,
  parseIpv6,
} from "./url_guard.ts";

/// Asserts a URL is refused, and for the stated reason.
function refused(raw: string, reason: string) {
  const verdict = guardRequestUrl(raw);
  assert.equal(verdict.ok, false, `expected ${raw} to be refused`);
  if (!verdict.ok) {
    assert.equal(verdict.reason, reason, `wrong reason for ${raw}`);
  }
}

function allowed(raw: string) {
  const verdict = guardRequestUrl(raw);
  assert.equal(verdict.ok, true, `expected ${raw} to be allowed`);
}

test("a load-bearing assumption: URL normalises every loose IPv4 form", () => {
  // The guard's IPv4 parser is strict, which is only safe because WHATWG URL has
  // already rewritten the sneaky forms by the time it runs. If this ever stops
  // being true, the strict parser becomes a bypass rather than a simplification,
  // so it is asserted rather than assumed.
  assert.equal(new URL("https://2130706433/").hostname, "127.0.0.1");
  assert.equal(new URL("https://0177.0.0.1/").hostname, "127.0.0.1");
  assert.equal(new URL("https://127.1/").hostname, "127.0.0.1");
  assert.equal(new URL("https://0x7f.0.0.1/").hostname, "127.0.0.1");
});

test("every blocked IPv4 range is actually refused", () => {
  const cases: Array<[string, string]> = [
    ["0.0.0.0", "this network"],
    ["0.1.2.3", "this network"],
    ["10.0.0.1", "RFC1918 private"],
    ["10.255.255.254", "RFC1918 private"],
    ["100.64.0.1", "carrier NAT"],
    ["100.127.255.254", "carrier NAT"],
    ["127.0.0.1", "loopback"],
    ["127.1.2.3", "loopback"],
    ["169.254.169.254", "cloud metadata"],
    ["169.254.0.1", "link-local"],
    ["172.16.0.1", "RFC1918 private"],
    ["172.31.255.254", "RFC1918 private"],
    ["192.0.0.1", "IETF assignments"],
    ["192.168.0.1", "RFC1918 private"],
    ["192.168.255.254", "RFC1918 private"],
    ["198.18.0.1", "benchmarking"],
    ["224.0.0.1", "multicast"],
    ["239.255.255.255", "multicast"],
    ["240.0.0.1", "reserved"],
    ["255.255.255.255", "broadcast"],
  ];
  for (const [address, why] of cases) {
    assert.equal(isBlockedAddress(address), true, `${address} (${why})`);
  }
});

test("a public address just outside each range is allowed", () => {
  // The boundaries matter as much as the ranges. An off-by-one prefix would either
  // let a private address through or refuse the whole internet, and only testing
  // the inside of a range catches neither.
  const cases = [
    "1.1.1.1",
    "9.255.255.255", // just below 10/8
    "11.0.0.1", // just above 10/8
    "100.63.255.255", // just below 100.64/10
    "100.128.0.1", // just above 100.64/10
    "126.255.255.255", // just below 127/8
    "128.0.0.1", // just above 127/8
    "169.253.255.255", // just below 169.254/16
    "169.255.0.1", // just above 169.254/16
    "172.15.255.255", // just below 172.16/12
    "172.32.0.1", // just above 172.16/12
    "192.167.255.255", // just below 192.168/16
    "192.169.0.1", // just above 192.168/16
    "198.17.255.255", // just below 198.18/15
    "198.20.0.1", // just above 198.18/15
    "223.255.255.255", // just below 224/4
    "8.8.8.8",
  ];
  for (const address of cases) {
    assert.equal(isBlockedAddress(address), false, `${address} should be fine`);
  }
});

test("blocked IPv6 ranges are refused", () => {
  const cases: Array<[string, string]> = [
    ["::", "unspecified"],
    ["::1", "loopback"],
    ["fc00::1", "unique local"],
    ["fd12:3456::1", "unique local"],
    ["fe80::1", "link-local"],
    ["febf::1", "link-local, top of range"],
    ["ff02::1", "multicast"],
  ];
  for (const [address, why] of cases) {
    assert.equal(isBlockedAddress(address), true, `${address} (${why})`);
  }
});

test("a public IPv6 address is allowed", () => {
  for (const address of ["2606:4700:4700::1111", "2001:4860:4860::8888"]) {
    assert.equal(isBlockedAddress(address), false, address);
  }
});

test("an IPv4 address wearing an IPv6 costume is still blocked", () => {
  // The three real embeddings. Checking only the IPv6 prefix would miss all of
  // them, because none of these sits in fc00::/7 or fe80::/10.
  assert.equal(isBlockedAddress("::ffff:127.0.0.1"), true, "IPv4-mapped");
  assert.equal(isBlockedAddress("::ffff:7f00:1"), true, "IPv4-mapped, hex form");
  assert.equal(isBlockedAddress("::ffff:169.254.169.254"), true, "metadata, mapped");
  assert.equal(isBlockedAddress("64:ff9b::127.0.0.1"), true, "NAT64");
  assert.equal(isBlockedAddress("64:ff9b::a00:1"), true, "NAT64, 10.0.0.1");
  assert.equal(isBlockedAddress("2002:7f00:0001::"), true, "6to4 loopback");
  assert.equal(isBlockedAddress("2002:a9fe:a9fe::"), true, "6to4 metadata");
});

test("a mapped PUBLIC address is not blocked by the unwrapping", () => {
  // The unwrap must not become a blanket refusal of every mapped address.
  assert.equal(isBlockedAddress("::ffff:8.8.8.8"), false);
  assert.equal(isBlockedAddress("64:ff9b::8.8.8.8"), false);
});

test("embeddedIpv4 reads the three embeddings and nothing else", () => {
  assert.equal(embeddedIpv4(parseIpv6("::ffff:1.2.3.4")!), "1.2.3.4");
  assert.equal(embeddedIpv4(parseIpv6("64:ff9b::1.2.3.4")!), "1.2.3.4");
  assert.equal(embeddedIpv4(parseIpv6("2002:0102:0304::")!), "1.2.3.4");
  assert.equal(embeddedIpv4(parseIpv6("2606:4700::1111")!), null);
});

test("the IPv4 parser refuses the forms it is not responsible for", () => {
  assert.equal(parseIpv4("1.2.3.4"), 16909060);
  assert.equal(parseIpv4("0.0.0.0"), 0);
  assert.equal(parseIpv4("255.255.255.255"), 4294967295);
  // Leading zeros are refused rather than read as octal, which is the historical
  // source of this whole class of bug.
  assert.equal(parseIpv4("0177.0.0.1"), null);
  assert.equal(parseIpv4("1.2.3"), null);
  assert.equal(parseIpv4("1.2.3.4.5"), null);
  assert.equal(parseIpv4("256.0.0.1"), null);
  assert.equal(parseIpv4("1.2.3.-4"), null);
  assert.equal(parseIpv4("example.com"), null);
});

test("the IPv6 parser handles compression and brackets", () => {
  assert.deepEqual(parseIpv6("::1"), [0, 0, 0, 0, 0, 0, 0, 1]);
  assert.deepEqual(parseIpv6("[::1]"), [0, 0, 0, 0, 0, 0, 0, 1]);
  assert.deepEqual(
    parseIpv6("2001:db8::1"),
    [0x2001, 0x0db8, 0, 0, 0, 0, 0, 1],
  );
  // A zone id is stripped rather than honoured.
  assert.deepEqual(parseIpv6("fe80::1%eth0")?.[0], 0xfe80);
  assert.equal(parseIpv6("not an address"), null);
  assert.equal(parseIpv6("gggg::1"), null);
});

test("only https on port 443 is allowed", () => {
  allowed("https://example.com/post");
  allowed("https://example.com:443/post");

  refused("http://example.com/", "scheme");
  refused("file:///etc/passwd", "scheme");
  refused("gopher://example.com/", "scheme");
  refused("data:text/html,<b>x</b>", "scheme");
  // Port scanning is removed as a capability rather than merely discouraged.
  refused("https://example.com:9200/", "port");
  refused("https://example.com:22/", "port");
});

test("embedded credentials are refused", () => {
  refused("https://user:pass@example.com/", "credentials");
  refused("https://user@example.com/", "credentials");
});

test("the obvious internal targets are refused as whole URLs", () => {
  // The two that matter most, in the form an attacker would actually send.
  refused("https://169.254.169.254/latest/meta-data/", "blocked-address");
  refused("https://metadata.google.internal/computeMetadata/v1/", "blocked-address");
  refused("https://127.0.0.1/admin", "blocked-address");
  refused("https://localhost/admin", "blocked-address");
  refused("https://[::1]/admin", "blocked-address");
  refused("https://10.0.0.5/admin", "blocked-address");
  refused("https://[::ffff:127.0.0.1]/", "blocked-address");
  // And in the normalised loose forms, which URL rewrites for us.
  refused("https://2130706433/", "blocked-address");
  refused("https://0177.0.0.1/", "blocked-address");
});

test("an ordinary blog URL is allowed", () => {
  allowed("https://www.polygon.com/some-review");
  allowed("https://blog.example.co.uk/2026/09/post.html");
  allowed("https://sub.domain.example.com/path?q=1#frag");
});

test("a host that is neither a name nor an address is refused", () => {
  refused("https://exa mple.com/", "not-a-url");
  refused("https://[not:an:address]/", "not-a-url");
  refused("not a url at all", "not-a-url");
});

test("the post-DNS check is what closes rebinding", () => {
  // The pre-DNS check sees only the NAME, and an attacker owns the DNS for their
  // own domain. Without this second check, evil.test resolving to 127.0.0.1 walks
  // straight through.
  assert.equal(guardResolvedAddresses(["93.184.216.34"]).ok, true);

  const loopback = guardResolvedAddresses(["127.0.0.1"]);
  assert.equal(loopback.ok, false);

  const metadata = guardResolvedAddresses(["169.254.169.254"]);
  assert.equal(metadata.ok, false);

  // ONE bad address among good ones is enough to refuse: the connection would pick
  // whichever the resolver hands it.
  const mixed = guardResolvedAddresses(["93.184.216.34", "10.0.0.5"]);
  assert.equal(mixed.ok, false);

  // Resolving to nothing is not a reason to proceed.
  assert.equal(guardResolvedAddresses([]).ok, false);
});

test("a name the pre-check allows can still be refused after DNS", () => {
  // The two halves in sequence, which is the whole design.
  const verdict = guardRequestUrl("https://evil.test/collect");
  assert.equal(verdict.ok, true, "the name alone looks fine");
  assert.equal(guardResolvedAddresses(["169.254.169.254"]).ok, false);
});
