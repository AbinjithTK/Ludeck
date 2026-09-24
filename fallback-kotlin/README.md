# Ludeck

Ludeck is an Android app that imports your Steam library in one tap and then tells you which game to actually play tonight, so a collection of two hundred unplayed games stops being a source of guilt and becomes something you use.

Built for RevenueCat Shipaton 2026.

## Why it exists

People buy games faster than they play them. Every existing tracker asks you to
type your collection in by hand, which is the exact work nobody will do. Ludeck
reads your Steam library instead, including how long you have already played each
game and when you last opened it, and turns that into one recommendation you can
accept or reject in a second.

## How it is built

Kotlin and Jetpack Compose, Room for local storage, a Supabase Edge Function as
the single proxy in front of IGDB. Android only and deliberately so: the host
this was built on is Windows, so no iOS target could be built or signed, which
makes Kotlin Multiplatform all cost and no payoff.

Two rules the code holds to, both enforced mechanically by `scripts/check.ps1`:

- **Ownership and progress are orthogonal.** Selling a game must not erase the
  record that you finished it, so ownership is a set of copy rows and progress is
  its own axis. A single status chain cannot express "finished it, then sold it".
- **Every colour, size and duration resolves through `Tokens.kt`.** The generated
  look comes from adding decoration to solve a problem; a capped palette leaves
  nowhere to add it.

## Build

```powershell
scripts\env.ps1          # pins the JDK and Android SDK
.\gradlew.bat :app:assembleDebug
scripts\check.ps1        # six guard rules, must pass before any task is done
```

`BUILD.md` is the binding document: frozen identifiers, the status vocabulary,
the API contracts and the submission checklist all live there, and it outranks
any later conversation.
