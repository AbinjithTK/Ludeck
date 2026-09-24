# Constraints

Everything here was checked on this machine or read from the platform's own
documentation. Where something is believed but not verified, it says so. Treat an
unverified line as a task, not as a fact.

## Toolchain

```
JAVA_HOME      C:\Users\user\.gradle\jdks\eclipse_adoptium-17-amd64-windows.2   (Temurin 17.0.19)
ANDROID_HOME   C:\Users\user\AppData\Local\Android\Sdk                          (SDK 36.1.0)
Flutter        C:\Users\user\develop\flutter_windows_3.38.9-stable              (3.38.9 stable)
Rive CLI       C:\Users\user\.rive\bin\rive.exe                                 (1.1.1)
Node           22.22.0
npm            10.9.4
Supabase CLI   2.101.0  (not logged in)
git            2.45.1
```

`java` on PATH is a dead Oracle stub. Anything that needs a JDK must be pointed at
the Temurin path above.

`flutter doctor` is fully green. Three devices are available: Windows, Chrome, Edge.

Docker is **not** installed, which is why `supabase functions serve` cannot be used
locally.

### The Java version trap

Flutter defaulted to **JDK 25**, which is Android Studio's bundled JBR, and Gradle
could not support it. Every Android build failed until Flutter was repointed:

```
flutter config --jdk-dir "C:\Users\user\.gradle\jdks\eclipse_adoptium-17-amd64-windows.2"
```

This is a per-machine setting, not a project setting. If Android builds start failing
with a Java version error after a Flutter or Android Studio update, this is the cause.

### Code generation does not work on this toolchain

Verified on 24 September. `dart run build_runner build` fails with:

```
'dart compile' does not support build hooks, use 'dart build' instead.
```

The chain, which is worth understanding because it blocks a whole class of package:

1. Flutter 3.38.9 pins `meta 1.17.0`.
2. That caps `analyzer` at 10.0.1.
3. That caps `build_runner` at 2.15.1, where 2.16.1 is current.
4. build_runner 2.15.1 invokes `dart compile`, which Dart SDK 3.10.8 refuses.

So `drift`, `freezed`, `json_serializable`, `riverpod_generator` and anything else
needing `build_runner` **cannot run here** without upgrading Flutter. Upgrading Flutter
days before the deadline, on a machine whose JDK setup already had to be repaired
once, is a worse risk than avoiding codegen.

Consequence, already acted on: persistence is hand-written SQL on `sqflite` rather than
Drift. Five tables do not need an ORM. See `app/lib/data/db/database.dart`.

### The Windows database sits in OneDrive

`getApplicationDocumentsDirectory()` on this machine resolves to
`C:\Users\user\OneDrive\Documents`, so the Windows build writes `ludeck.db` into a
OneDrive-synced folder. Verified 24 September.

This does not affect what ships, because Android is the target and its path is
app-private. It does mean the desktop build a developer uses for visual checking has its
database synced while open, and a sync engine copying a live SQLite file can corrupt it.
If the Windows database starts behaving strangely, this is the first thing to suspect.
Deleting the file is safe: it is reseeded from the fixture on next launch.

## iOS is impossible on this machine

iOS builds require macOS and Xcode. There is no workaround on Windows, and Flutter
does not change that. This kills the JetBrains category outright and it is why
Kotlin Multiplatform had no payoff.

Later options, cheapest first: a macOS CI runner, a rented Mac, a Mac mini at roughly
600 USD. All of them additionally need the Apple Developer Program at 99 USD a year.

## The emulator CAN boot. This section was wrong.

Corrected 2026-09-24. It previously read "No emulator can boot" and treated that as a
settled constraint on the strength of one check. That was wrong, and it cost real
iteration quality: the whole first design critique was run against a 1600x900 desktop
window, so the phone layout went unjudged for no good reason.

What is actually true on this machine:

- Two AVDs are configured, `Pixel_8` and `Medium_Phone` (API 36.1).
- Both x86_64 `google_apis_playstore` system images are downloaded.
- The emulator detects the GPU fine (NVIDIA GeForce RTX 2060, Vulkan 1.4).
- The emulator's own preflight reports `hasCompatibleHypervisor: Ok` and
  `hasSufficientHwGpu: Ok`. The CPU was never the problem.
- `HypervisorPresent` is False, meaning Hyper-V is off, so the **Android Emulator
  hypervisor driver (AEHD)** is the correct accelerator here, not WHPX. If Hyper-V
  were on, AEHD would refuse and WHPX would be the path instead.

The only thing that was ever missing: the driver had not been installed. Its installer
was already sitting in the SDK at
`%LOCALAPPDATA%\Android\Sdk\extras\google\Android_Emulator_Hypervisor_Driver\silent_install.bat`.

Installing it registers an `aehd` service with `StartType: System`. Both the install
and starting the service need administrator rights, which an agent session does not
have, so this step belongs to a person. Because it is a boot-start driver, a reboot
loads it; `sc start aehd` from an elevated prompt does the same without one.

Verify with `emulator -accel-check`. Exit code 6 means the driver is still not loaded.

### Launching it from the dart tooling

`launch_app`'s `root` argument must be a **plain path** (`F:\Abin\Ludeck\app`). Passing
a `file:///` URI fails with `ProcessException: The directory name is invalid`, despite
the parameter being described as a directory. This differs from `add_roots`, which does
want a `file://` URI.

### A real phone is still a submission dependency

The emulator working does not remove this. The demo video and the store screenshots
should come from a physical device: a screen recording of an emulator is a visibly
weaker demo, and the required screenshot size is exact (1179x2556, no device frame).
The emulator's value is iteration at phone aspect ratio, not asset production.

## Google Play

**Phone screenshots are capped at a 2:1 aspect ratio.** A Pixel-class 1080x2400 frame
is 2.22:1 and would be rejected. This was flagged from memory and is **not yet
verified against current Play policy**. Verify before capturing a full set.

In-app products are reviewed alongside the first app submission. The three products
must therefore exist in Play Console hours before submitting, not at submission time.

`QUERY_ALL_PACKAGES` does not qualify for a collection tracker. Do not request it;
it is a guaranteed policy rejection.

"Fully published" is the Shipaton requirement, not "uploaded". Review has to complete
before the deadline, and a new developer account's first review is the slowest one it
will ever have. That is the entire reason the working ship date sits days ahead of the
hard deadline.

## IGDB

- Rate limit: 4 requests per second, 8 concurrent.
- **No CORS.** A server-side proxy is mandatory; the app cannot call IGDB directly.
- `game_time_to_beats` returns **seconds**.
- User-facing attribution is mandatory.
- Commercial use goes through partner@igdb.com.

## Steam

`GetOwnedGames` returns `playtime_forever`, `playtime_2weeks` and `rtime_last_played`.
It requires a public profile.

There is no official API for PSN, Xbox or Nintendo. Those platforms are manual entry
only, which is fine, because manual entry is the fast path anyway.

## Layers (Growth Loop Award)

Gate 2 **passed**. `install_growth_measurement` supports 10 platforms, 5 of them web,
names "Android package name" in its blocker text, and tracking links write UTM into
the Play Store install referrer.

Flutter support is **not confirmed.** Three of the ten non-web slots are unnamed and
no official Layers Flutter package was found. A free `action: spec` call would settle
this definitively and has not been made.

## Rive

No account is needed to create, preview or build locally. Signing in is only required
for `--publish` and `.rev` export. A file with no Luau scripts is unaffected by this.

## Options considered and ranked last

**Unity.** Possible but ranked last. `flutter_embed_unity` (49 likes, 12.5k downloads)
and `unity_kit` (26.8k downloads) are real packages, but authoring a scene needs the
Unity Editor GUI, it adds 30 to 50 MB, and it forces a splash screen without Unity Pro.

**3D in Flutter.** Viable, and an earlier dismissal of it was too quick.
`flutter_sceneview` uses Filament and RealityKit natively. `model_viewer_plus` has 338
likes and 28.5k downloads. `flutter_fiber` builds procedural geometry from Dart data
with no WebView but has only 3 likes. The real blockers are that there is no 3D asset
and no way to judge lighting without a device.

## Tooling defects worth knowing

- `scripts\check.ps1` greps only `.kt`, `.ts` and `.sql`. **It does not protect the
  Dart code at all.** The colour-literal rule and the enum rule are currently
  unenforced in Flutter.
- `check.ps1` previously had two false positives because it matched its own
  documentation. It is now comment-aware, and five of its six rules were
  negative-tested by injecting real violations. Rule 4 (IGDB usage outside the proxy)
  has **not** been negative-tested.
- MCP cron tools are refused on this install. Use the `kirocrew cron` CLI. There is no
  `--timezone` flag and the config timezone is empty, so cron expressions are UTC.
  Double quotes in a cron message break argv parsing.
- Newly added MCP servers and newly created agents are not available in the session
  that added them. The roster binds at session start.
- Sub-agents that read multi-megabyte JSON sequentially truncate and then report "not
  found". Instruct them to grep or to write a script.
- `kiro-cli chat` needs a TTY. Non-interactive invocations produce no output.
