# Deploying the community backend

The schema is already written and does not need to change:
`fallback-kotlin/supabase/migrations/0001_community.sql`. Profiles, published
trees, published games, reactions, follows -- every table has row-level
security enabled in the same statement block that creates it, and the
`published_games` table's columns are exactly the invariant-10 payload (title,
cover, status, rating, branch name). This is a checklist, not a design
document; the design reasoning lives in the migration's own comments.

None of this can run through the chat agent, for the same reason as the IGDB
proxy: `supabase login` opens a consent screen in your real browser, and only
you can click it. Run these yourself, in a terminal, in order.

## 0. You may already be most of the way there

**State on 2026-09-28:** the Supabase CLI (2.101.0) is installed and already logged
in. `supabase projects list` shows two projects, `gameworld` and `agentgame`, both
in Singapore, and no Ludeck project. **The free plan allows two active projects per
organisation**, so creating `ludeck` needs one of: pausing one of those two in the
dashboard, a paid plan, or a new organisation. Decide that before step 2 of
`docs/DEPLOY-PROXY.md`.

If you already followed `docs/DEPLOY-PROXY.md` for the IGDB proxy, you are
already logged in and already have a project. Skip straight to step 2.

## 1. Log in (skip if already done for the proxy)

```powershell
supabase login
supabase projects list
```

If that lists something instead of erroring, you're in.

## 2. Link the project

```powershell
cd fallback-kotlin\supabase
supabase link --project-ref <your-project-ref>
```

Get `<your-project-ref>` from `supabase projects list`, or from step 7 of
`docs/DEPLOY-PROXY.md` if you already did that.

## 3. Apply the migrations

```powershell
cd F:\Abin\Ludeck\fallback-kotlin\supabase
supabase db push
```

This applies both migrations in order:
- `0001_community.sql`: profiles, published trees and games, reactions, follows,
  every table with RLS.
- `0002_profiles_and_deletion.sql`: a trigger that creates each new user's profile
  row (without it the first publish fails its foreign key), and
  `delete_my_account()`, which the app's Delete account button calls. Google Play
  requires that button.

**Verify** rather than trusting the push:

```powershell
supabase db diff --linked
```

An empty diff means the remote database matches the migration files exactly,
including every policy, the trigger and the function.

## 4. Turn on Google sign-in

The app signs in with `signInWithOAuth(OAuthProvider.google, redirectTo:
'com.ludeck.android://login-callback')` (`SupabaseSocialBackend.signIn`). The
manifest catches that link; the SDK finishes the sign-in.

1. **Google Cloud Console, APIs & Services, Credentials:** create an OAuth client of
   type **Web application**. Its authorised redirect URI is the callback Supabase
   shows on its Google provider page (`https://<ref>.supabase.co/auth/v1/callback`).
   The OAuth consent screen must be **In production** (not Testing), or only
   listed test users can sign in, and that includes the Play reviewer.
2. **Supabase, Authentication, Providers, Google:** turn it on and paste that
   client's ID and secret.
3. **Supabase, Authentication, URL Configuration, Redirect URLs:** add
   `com.ludeck.android://login-callback`. Without it Supabase redirects to the
   Site URL instead and the app never gets the session.

This is a browser flow, so no Android OAuth client and no SHA-1 fingerprint are
needed.

## 5. Get the app's connection details

**Project URL and publishable key** (Settings, API keys in the dashboard, or):

```powershell
supabase projects api-keys --project-ref <your-project-ref>
```

Use the `anon` / `publishable` key, never the `service_role` key. The
`service_role` key bypasses every RLS policy in step 3. It must never ship in the
app, and nothing in this codebase asks for it. (Account deletion runs as a
database function on the caller's own id precisely so no service key is needed.)

## 6. Wire the app to it

Nothing to edit. Both values go in at build time, and the same `SUPABASE_URL` also
switches game search onto the IGDB proxy (`http_catalog.dart`, `catalogBaseUrl`):

```powershell
flutter build appbundle --release `
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key> `
  --dart-define=REVENUECAT_GOOGLE_KEY=goog_...
```

A build without them runs local-only: publishing says "Sharing isn't set up yet on
this build. Nothing left this device." and search uses the bundled catalogue.

## 7. Confirm it actually works

On a device or emulator, from a build made with step 6's defines:

1. **Search** "hollow knight" in Add a game. Results beyond the bundled catalogue
   mean the proxy answered.
2. **Publish:** You, Share your orchard, turn on Public link. Google's consent
   screen opens in the browser and returns to the app. A link appears.
3. **The profile row exists:** Supabase, Table Editor, `profiles` has one row whose
   handle is the `g…` in that link.
4. **Delete:** You, Delete account, Delete. Then check that `profiles`,
   `published_trees` and `published_games` have no rows for that user, and that
   Authentication, Users no longer lists them.
5. **Visiting** a tree from a second install needs the public web page or deep
   link, which does not exist yet (below).
## What this does NOT include

**Real deep-linking / sharing the link outside the app.** `ShareCardScreen`'s
"Copy link" puts `https://ludeck.app/t/<handle>` on the clipboard, but nothing
in this codebase serves that URL or routes an incoming link back into
`VisitScreen`. That's a real gap for the actual growth loop (someone taps a
link from outside the app) and is genuinely outside what Stage 8 covers --
flagging it here rather than quietly leaving it undiscovered.

**Rate limiting beyond the unique-constraint dedup already in the schema.**
`0001_community.sql`'s primary keys stop a visitor from admiring the same tree
twice, but nothing throttles *how many* trees one account can react to per
minute. Supabase's own dashboard has basic abuse controls (Auth → Rate
Limits); nothing beyond the default was configured here.
