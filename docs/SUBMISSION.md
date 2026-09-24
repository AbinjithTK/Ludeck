# Submission checklist

Shipaton 2026. Nothing here is optional unless it says so. Tick items in this file as
they land, so the state survives a lost chat session.

## Eligibility, all categories

- [ ] RevenueCat SDK integrated and making a real call
- [ ] Entitlement `pro` configured in the RevenueCat dashboard
- [ ] Products `pro_annual`, `pro_monthly`, `pro_lifetime` created in RevenueCat
- [ ] The same three products created in Play Console
- [ ] A paywall the judges can actually reach from the running app
- [ ] Purchase tested at least once, even in a test track

Without the first item the entry is ineligible for every category, including the free
ones. It is the only true blocker in this document.

## Google Play

- [ ] Developer account active and identity verification complete
- [ ] App record created with applicationId `com.ludeck.android`, which is permanent
- [ ] App signing set up
- [ ] Release APK or AAB uploaded, not just debug
- [ ] Data safety form completed
- [ ] Content rating questionnaire completed
- [ ] Target audience declared
- [ ] Privacy policy URL live and reachable
- [ ] Store listing: short description, full description, app icon 512x512
- [ ] Feature graphic 1024x500
- [ ] Phone screenshots, **aspect ratio 2:1 or narrower.** Verify the current cap
      before capturing a full set; a 1080x2400 frame is 2.22:1 and is rejected.
- [ ] Submitted for review with enough days left for review to finish
- [ ] **Actually published**, not "pending publication"

The last line is the requirement. Uploaded is not published.

## Devpost

- [ ] Project created
- [ ] Title and tagline
- [ ] Writeup targeting about 6,000 characters. Field median is 5,186; p75 is 6,898.
      A zero-character writeup is what three of the four new gaming rivals have, and it
      is the cheapest place to beat them.
- [ ] Demo video, 90 seconds, recorded on a real Android phone. No emulator can boot
      on this machine; see `docs/CONSTRAINTS.md`.
- [ ] Play Store link
- [ ] Repository link
- [ ] Screenshots in the gallery
- [ ] Built-with tags including `revenuecat`, `flutter`, `rive`
- [ ] Category opt-ins selected

## Category specifics

### Growth Loop Award (Layers), 15,000 USD, best odds

2 projects entered, 1 eligible, out of 1,286. This is the single best expected value in
the event.

- [ ] `npm install -g @layers/cli`
- [ ] `layers setup` (the browser sign-in is a human step)
- [ ] Confirm Flutter support with `install_growth_measurement` using `action: spec`.
      Gate 2 passed but Flutter support is not confirmed; see `docs/CONSTRAINTS.md`.
- [ ] A real growth loop in the product, which is the public shareable tree page. Zero
      of ten gaming rivals have one.
- [ ] Tracking link created, UTM confirmed arriving in the Play install referrer
- [ ] A few sentences in the writeup describing the loop

### Gaming (Mr Lewis Blogs Gaming), 20,000 USD

- [ ] Opt in
- [ ] The writeup names the two orthogonal axes explicitly, because no rival has them
- [ ] The writeup names the device tracking, because PSN, Xbox and Nintendo have no
      API and manual entry is the honest answer

The lane went from 4 credible rivals to 7 in one day, including Couch Quest, which
shares both the positioning and the stack. Do not assume this is winnable.

### Free entries, expecting nothing

- [ ] OneSignal (53 projects, 37 eligible, crowded)
- [ ] Design
- [ ] Grand Prize

### Not enterable

JetBrains needs iOS. iOS is impossible on this machine; see `docs/CONSTRAINTS.md`.

## Hard dependencies on a physical phone

Both of these are blocked without an Android device in hand:

- [ ] Screenshots
- [ ] The 90-second video

Plan for this before the last day.

## Housekeeping

- [ ] `intel/me.json` updated with the shipped description
- [ ] `intel/benchmark_me.py` re-run so the entry is scored against the final corpus
- [ ] Repository committed and pushed
- [ ] `docs/PLAN.md` status section updated to match reality
