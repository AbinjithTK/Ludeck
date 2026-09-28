# RevenueCat + Play Console setup

What the app expects, fixed in code (`app/lib/services/revenuecat_entitlement_source.dart`):

| Thing | Value |
|---|---|
| Package name | `com.ludeck.android` |
| Entitlement id | `pro` |
| Subscriptions | `pro_annual`, `pro_monthly` (one base plan each) |
| One-time product | `pro_lifetime` |
| Key passed at build | `--dart-define=REVENUECAT_GOOGLE_KEY=goog_...` |

The app asks the store for these ids directly, so the ids must match exactly.
Keep ONE base plan per subscription: the paywall shows the first plan it gets.

Order matters, because Play will not let you create products until a build
that uses billing has been uploaded.

## 1. Upload key (5 min, on this machine)

Follow `docs/RELEASE-SIGNING.md`: create `C:\Users\user\keys\ludeck-upload.jks`
and `app\android\key.properties`. Back up both off this machine.
Then tell me, and I build the first `.aab`.

## 2. Play Console: app record

1. Create app: name `Ludeck`, App, Free, default language English.
2. Setup > App integrity > App signing: keep "Google manages the app signing key".
3. Testing > Internal testing > Create release > upload the `.aab`. Add
   yourself as a tester (an email list with your Google account). Roll out.
4. Copy the opt-in link and open it on your phone, accept, install from Play.

## 3. Play Console: products

Monetize > Products (appears once the internal build is processed).

**Subscriptions** > Create subscription:

| Product ID | Name | Base plan ID | Billing period | Price |
|---|---|---|---|---|
| `pro_annual` | Ludeck Pro (yearly) | `annual` | 1 year, auto-renewing | your choice |
| `pro_monthly` | Ludeck Pro (monthly) | `monthly` | 1 month, auto-renewing | your choice |

Activate each base plan. Optional free trial: on the `annual` base plan,
Add offer > Free trial (e.g. 7 days) > Activate. The paywall shows
"Start N days free" only when this offer exists.

**One-time products** > Create: ID `pro_lifetime`, name "Ludeck Pro (lifetime)",
set a price, Activate.

**Licence testing**: Settings (the Play Console home, not the app) > License
testing > add your Google account, response "RESPOND_NORMALLY". Test purchases
are then free and subscriptions renew every few minutes.

## 4. Google Cloud: service account (lets RevenueCat verify purchases)

RevenueCat's own guide walks this with screenshots:
[RevenueCat: Google Play service credentials](https://www.revenuecat.com/docs/service-credentials/creating-play-service-credentials).
In short:

1. Google Cloud Console, the project linked to Play (Play Console > Setup >
   API access shows or creates it). Enable "Google Play Android Developer API"
   and "Google Play Developer Reporting API".
2. IAM > Service accounts > Create: name `revenuecat`. Roles: "Pub/Sub Admin"
   and "Monitoring Viewer". Keys > Add key > JSON. Download it.
   This file is a secret: keep it out of the repo (`service-account*.json` is
   gitignored), and never paste it into chat.
3. Play Console > Users and permissions > Invite new user: the service account's
   email. App permissions: Ludeck. Account permissions: "View app information",
   "View financial data", "Manage orders and subscriptions". Invite.

Credentials can take up to 36 hours to validate in RevenueCat. Do this step
first thing, it is the slow one.

## 5. RevenueCat dashboard

1. Project > Apps > + New > Google Play Store. Package name
   `com.ludeck.android`. Upload the service account JSON from step 4.
2. Product catalog > Products > Import: pick `pro_annual`, `pro_monthly`,
   `pro_lifetime`. (Subscriptions show as `pro_annual:annual` etc; that is fine.)
3. Product catalog > Entitlements > + New: identifier `pro` (exactly). Attach
   all three products.
4. Product catalog > Offerings: create `default`, mark it current, add three
   packages (Annual, Monthly, Lifetime) with the products. The app does not
   read offerings today, but RevenueCat's paywalls and experiments need one,
   and it costs a minute.
5. Project settings > API keys: copy the public Google key (starts with
   `goog_`). This key is public by design; send it to me.
6. Optional, for real-time status: Apps > Ludeck > Google developer
   notifications > connect (creates the Pub/Sub topic the role in step 4 allows).

## 6. Verify (what Shipaton checks)

When I have the `goog_` key I build the internal release with it. Then on your
phone, installed from the internal track:

1. You > Ludeck Pro: prices show in your currency (not "unavailable").
2. Buy annual as the licence tester. The row turns into "Ludeck Pro is on".
3. RevenueCat > Customers: your test purchase appears within a minute, with
   the `pro` entitlement active.
4. Uninstall, reinstall, Restore purchases: Pro comes back.

## Still open on our side

The paywall lists features that are not built yet, so buying unlocks nothing.
That has to be settled before production review (Play rejects paid features
that do not exist). See the options at the end of my last message.
