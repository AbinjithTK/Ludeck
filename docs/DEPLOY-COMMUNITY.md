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

## 3. Apply the migration

```powershell
supabase db push
```

This runs `migrations/0001_community.sql` against your linked project. It is
idempotent (`create table if not exists`), so running it again later after a
future migration is added is safe.

**Verify RLS actually landed**, rather than trusting the push succeeded:

```powershell
supabase db diff --linked
```

An empty diff means the remote database now matches the migration file
exactly, including every policy.

## 4. Turn on the auth provider

The app's `SupabaseSocialBackend.signIn()` calls
`_client.auth.signInWithOAuth(OAuthProvider.google)`. In the Supabase
dashboard:

1. **Authentication → Providers → Google**
2. Toggle it on, and follow Supabase's own instructions to create a Google
   OAuth client (this needs a Google Cloud Console project -- Supabase's
   dashboard links straight to it).
3. Add the redirect URL Supabase's dashboard shows you into the Google OAuth
   client's allowed redirect URIs.

**If you'd rather use a different provider** (Apple, GitHub, email magic
link), that's a one-line change:
`app/lib/services/social/supabase_social_backend.dart`, the single
`OAuthProvider.google` in `signIn()`. Google was picked as the default because
it needs no in-app password UI, not because it's frozen.

## 5. Get the app's connection details

**Project URL and publishable key** (Settings → API in the dashboard, or):

```powershell
supabase projects api-keys --project-ref <your-project-ref>
```

Use the `anon` / `publishable` key here, never the `service_role` key. The
`service_role` key bypasses every RLS policy in step 3 -- it must never ship
in the app, and nothing in this codebase asks for it.

## 6. Wire the app to it

Tell me (or edit directly) the two values from step 5, and I'll wire
`main.dart`'s

```dart
final social = await resolveSocialBackend();
```

to

```dart
final social = await resolveSocialBackend(
  supabaseUrl: '<your-project-url>',
  supabasePublishableKey: '<your-publishable-key>',
);
```

Until this line changes, the app runs in the **local-only mode it's in right
now**: `FakeSocialBackend(configured: false)`. That's not a broken state --
it's the honest one, and it's what a device walkthrough during Stage 8 of
this build actually showed: tapping Public → "Save and share" produces
*"Sharing isn't set up yet on this build. Nothing left this device."* rather
than pretending to publish. The whole community feature (Stages 2-6 of this
build) was built and tested against `FakeSocialBackend` for exactly this
reason -- so it's provably correct before this wire-up step exists.

## 7. Confirm it actually works

After step 6, on a real device or emulator:

1. Open the app, go to the profile screen, tap **Share your tree**.
2. Choose **Public**, tap **Save and share**. This should now succeed instead
   of showing the "not set up" message -- it calls `signIn()` first, which
   opens a real Google consent screen.
3. Note the handle shown on the resulting share card.
4. On a second device (or a fresh app install, or `adb shell pm clear
   com.ludeck.android` to reset the first one), go to **Share your tree →
   Save and share → See what a visitor sees**, but change the handle in the
   URL/deep-link to the one from step 3 -- or, until real deep-linking exists
   (see the note below), edit `VisitScreen(handle: '...')`'s argument
   temporarily to test it.
5. Confirm the visited tree shows the games, react and follow work, and that
   tapping **Plant** on a game adds it to the second device's soil.

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
