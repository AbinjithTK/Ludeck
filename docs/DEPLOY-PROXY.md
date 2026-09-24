# Deploying the IGDB proxy

The function is already written and does not need to change:
`fallback-kotlin/supabase/functions/igdb/index.ts`. Endpoint allowlist, a
2000 character query cap, rate limiting, and error bodies that never echo
IGDB's response back to the caller. This is a checklist, not a design
document.

None of this can run through the chat agent. `supabase login` opens a
consent screen in your real browser and only you can click it, and pasting a
Twitch client secret into a chat is the kind of thing that ends up logged
somewhere it shouldn't. Run these yourself, in a terminal, in order.

## 1. Log in

```powershell
supabase login
```

Opens a browser tab. Approve it there. Confirm it worked:

```powershell
supabase projects list
```

If that lists something instead of erroring, you're in.

## 2. Create the project, if one does not already exist

```powershell
supabase projects create ludeck --org-id <your-org-id> --region <closest-region>
```

Find `<your-org-id>` with `supabase orgs list`.

**For `<closest-region>`, use `us-east-1`.**

The thing that makes this an easy choice, and which an earlier version of this
document got wrong: **the project region does not control where the edge function
runs.** Supabase executes edge functions in the region closest to whoever is
calling them, automatically. So the proxy will run out of Mumbai when you call it
from India and out of a US region when a judge calls it from there, regardless of
what the project region says.

What the project region *does* control is the **Postgres database**. That is
stateful, it is what the public tree page will eventually store rows in, and
Supabase's own answer to changing it is "create a new project and migrate". So the
region should be chosen for where the data belongs long-term, which is `us-east-1`
for a US audience. The dev-loop cost of that choice is zero, because of the
paragraph above.

Two consequences for this specific function:

**Do not set `x-region` on it.** Supabase suggests pinning a function to the
database region when it does heavy database work, since round trips to Postgres
then stay local. This proxy touches no database at all: it calls Twitch and IGDB
and returns. Pinning it would force every call through one region and throw away
the automatic caller-local routing for nothing.

**`api.igdb.com` resolves to `18.161.246.x`, which is AWS CloudFront.** IGDB is
CDN-fronted, so the function reaches it via a nearby edge and AWS's backbone from
wherever it happens to execute. Measured steady-state round trip from this machine
to IGDB is about 270ms.

If you already have a Supabase project for this, skip to step 3 and link it
instead:

```powershell
supabase link --project-ref <your-project-ref>
```

## 3. Get a Twitch application

IGDB auth runs through Twitch. If you do not already have one:

1. Open https://dev.twitch.tv/console/apps
2. Register a new application. Any name, any OAuth redirect URL (unused by
   this flow, since it's the client-credentials grant, not a user login).
   Category: doesn't matter, pick "Application Integration".
3. Copy the **Client ID** and generate a **Client Secret**.

## 4. Set the secrets

Run this from `fallback-kotlin/supabase/`, with your real values in place of
the angle-bracketed parts:

```powershell
cd fallback-kotlin\supabase
supabase secrets set TWITCH_CLIENT_ID=<your-client-id> TWITCH_CLIENT_SECRET=<your-client-secret>
```

This goes straight into Supabase's own encrypted secret store, never into a
file this repository tracks and never through me.

## 5. Deploy

```powershell
supabase functions deploy igdb --no-verify-jwt
```

`--no-verify-jwt` is there on purpose: this function is a public proxy the
app calls directly with no Supabase auth session, so requiring a Supabase
JWT would just break every call. The function's own endpoint allowlist and
rate limiting are what keep it from being an open pipe to IGDB, not JWT
verification.

## 6. Confirm it actually works

```powershell
supabase functions list
```

Should show `igdb`, active. Then a real request:

```powershell
$url = "https://<your-project-ref>.supabase.co/functions/v1/igdb"
$body = '{"endpoint":"games","query":"fields name; where name ~ \"Hollow Knight\"*; limit 1;"}'
Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json"
```

Get `<your-project-ref>` from `supabase projects list`. A real response back
means the token exchange, the allowlist, and the throttle all worked. An
empty array is also fine, it means the endpoint answered and just didn't
match; an error means something in steps 1 through 5 needs a second look.

To confirm the caller-local routing is genuinely happening rather than assumed,
read the region back out of the response headers:

```powershell
$r = Invoke-WebRequest -Uri $url -Method Post -Body $body -ContentType "application/json"
$r.Headers["x-sb-edge-region"]
```

Called from India that should report a nearby region such as `ap-south-1`, even
though the project itself lives in `us-east-1`. If it reports `us-east-1`, the
function is being pinned somewhere it should not be; check that nothing is
sending an `x-region` header or a `forceFunctionRegion` query parameter.

## 7. Tell me the project ref

Once step 6 comes back clean, tell me the project ref (not the secret, not
the client secret, just the ref itself, which is not sensitive). I'll wire
the app's catalogue lookups to
`https://<ref>.supabase.co/functions/v1/igdb` and swap `CatalogService` off
`fixtureTree()` onto the real proxy.
