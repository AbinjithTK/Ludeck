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

## The emulator works. WHPX is the accelerator, not AEHD. Resolved 2026-09-24.

`Pixel_8` boots and runs the app. Three earlier versions of this section were wrong, and
the history is kept because each wrong version cost something real.

**Version one: "no emulator can boot."** Settled on one failing check. That cost the most
of any error here: the entire first design critique ran against a 1600x900 desktop
window, so the phone layout went unjudged for days.

**Version two: "the only missing piece is the AEHD driver."** Wrong. AEHD installed
cleanly and still failed to load, exit code 31.

**Version three: "AMD SVM Mode is disabled in the BIOS."** Also wrong, and wrong in the
most expensive direction, because it told a human to go reboot into firmware for nothing.

### What was actually happening

`Get-CimInstance Win32_Processor | Select VirtualizationFirmwareEnabled` reported
`False`, which reads like "SVM is off in the BIOS". It is not what that means when a
hypervisor is already running. **WSL runs on the Windows hypervisor, and a running
hypervisor holds the virtualization extensions**, which is exactly the condition AEHD's
error 31 reports: AEHD is a *bare-metal* driver and requires that no hypervisor owns the
extensions. SVM was enabled the whole time. It has to be, or the Windows hypervisor could
not have started either.

The accelerator that *coexists* with the Windows hypervisor is **WHPX** (Windows
Hypervisor Platform), and it was already installed and usable:

```
emulator -accel-check
  accel: 0  WHPX (10.0.26100) is installed and usable.
```

Exit code 0. Nothing needed installing, enabling, or rebooting.

**The diagnostic rule this cost three attempts to learn:** on a machine running WSL or
Hyper-V, `VirtualizationFirmwareEnabled: False` is not evidence about the BIOS, and
`HypervisorPresent: True` is the fact that decides which accelerator to use. Read
`HypervisorPresent` FIRST. True means WHPX and AEHD can never load; False means AEHD.

AEHD remains installed as a stopped `aehd` service. Leave it alone: it cannot load while
WSL's hypervisor is present, and it is not needed.

**Do not write `sc start aehd` in PowerShell.** `sc` is a built-in alias for
`Set-Content` there, so that command silently writes a 6-byte file named `start`
containing `aehd` and never touches the service. It does not error, which is what makes
it dangerous as advice. Use `sc.exe start aehd` or `Start-Service aehd`, both elevated.

### The emulator's /data partition is nearly full, and it blocks a fat debug APK

This is the live constraint to design around, not acceleration.

```
adb shell df -h /data
  /dev/block/dm-55  5.8G  5.3G  359M  94%  /data/user/0
```

A default `flutter build apk --debug` produces a **fat APK carrying every ABI, 167.6 MB**,
and a streamed install needs roughly twice the APK size in free space. It fails with:

```
android.os.ParcelableException: java.io.IOException: Requested internal only, but not enough space
```

Build **x86_64 only** for the emulator and it drops to **89.1 MB**, which installs fine:

```
flutter build apk --debug --target-platform android-x64
```

Two traps found while diagnosing this:

- **`flutter run` will silently install a stale artifact.** If Gradle considers
  `assembleDebug` up to date, it reuses whatever sits at
  `build\app\outputs\flutter-apk\app-debug.apk` — so a previously built fat APK gets
  installed even on a run that should have been architecture-specific. Build the
  x64-only APK first; `launch_app` then picks it up.
- `pm trim-caches 4096M` frees **nothing** here. The 5.3 GB is real installed data, and
  a large third-party package unrelated to this project (`com.pluuto.app`, 137 MB, from
  June) accounts for much of it. Do not uninstall it or wipe the AVD without asking:
  it is the user's, not ours.

`--target-platform android-x64` also makes the build markedly faster (17.5s versus
91.7s warm), so it is the right default for emulator iteration regardless of space.

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

- **Corrected 2026-09-25.** `scripts\check.ps1` used to grep only `.kt`, `.ts` and
  `.sql`, leaving the Dart that actually ships unenforced. It now reads Dart and runs
  twelve rules, comment-aware, ending with a real `flutter analyze` and `flutter test`.
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

## The hanging `flutter test`, diagnosed 2026-09-25

Three runs wedged over two sessions and it was blamed on Rive twice. Rive was not
the cause. There were three distinct faults in a chain, and each one hid the next.

**1. The deadlock, which is the real bug.** `testWidgets` runs its body inside a
FakeAsync zone. sqflite does real file I/O that never completes under fake time.
`TreeScreen.initState` starts a load, so mounting the screen outside
`tester.runAsync` began a query that could never finish, and that query **held the
database lock**. Every later real-async call waited on a lock nothing would release.

**2. The warning that misleads.** After ten seconds sqflite prints

    Warning database has been locked for 0:00:10.000000
    Make sure you always use the transaction object for database operations
    during a transaction

That sentence is the canned message for ANY lock held over ten seconds. It is not
evidence of transaction misuse, and there was none: every `transaction((txn)` block
in `repository.dart` uses only `txn.*`, and no Database-level call is nested inside
one. Reading that message literally sends you looking for a bug that does not exist.

**3. Why it hung instead of failing.** The lock wait happens in REAL time inside
`runAsync`, while the test framework's own timeout runs on the FAKE clock. The fake
clock never advances, so the timeout never fires. A test that would have failed in
30 seconds instead hangs indefinitely, and `flutter test` never exits.

**4. The cascade into the next run.** The orphaned `flutter_tester.exe` keeps a
handle on `build\native_assets\windows\sqlite3.dll`. `Remove-Item` on it fails with
Access denied, and the NEXT `flutter test` crashes immediately with

    PathExistsException: Cannot copy file to
    ...build\native_assets\windows\sqlite3.dll (errno = 183)

So a hang in one run presents as a completely unrelated crash in the next.

### Fix and guard

Mount inside `runAsync`:

```dart
await tester.runAsync(() async {
  await tester.pumpWidget(MaterialApp(home: TreeScreen(repo: repo, ...)));
});
```

`share_to_library_test.dart` went from hanging indefinitely to 8/8 in 5 seconds.
Full suite: 213 tests in 7 seconds.

`check.ps1` rule 8 now fails any `pumpWidget` that is not inside a `runAsync` block
in a test file importing `data/repository.dart`. Negative-tested by injecting a
violating probe test and watching it go red.

### Recovery when a run has already wedged

1. `Get-Process | Where ProcessName -match '^(flutter_tester|dart)$'` and read CPU.
   CPU that does not climb between two reads a minute apart means wedged, not slow.
   A genuinely busy run keeps accumulating CPU.
2. `Stop-Process -Id <pid> -Force` on the orphan.
3. `Remove-Item -Recurse -Force app\build\native_assets`. It fails while any orphan
   lives, which is itself the signal that step 2 was incomplete.
4. Never run `flutter test` from a tool call with no timeout. Use
   `Start-Process -PassThru` plus `WaitForExit(ms)` so a hang returns a result
   instead of silence.

## A computed inset can never clear a header that wraps (2026-09-25)

The home screen shipped with rows rendering under the headline and the status-bar
clock. `CollectionView` computed its own top inset as
`padding.top + space.md + type.display * leadingDisplay + space.lg`, which budgets
for ONE line of display type. The header is two lines (headline over subline) plus
an optional notice line, so the inset was short by the subline.

Fixing the sum was the wrong instinct, and a test proved it. A first attempt
MEASURED both lines with a TextPainter and was still 20px short, because the
header had WRAPPED. Its height depends on the font, the text scale and the
available width, so any number computed away from the real layout is a guess that
happens to be close on the device you tried.

Fix: the header is now an ordinary layout sibling above the content (a `Column`,
with the content in an `Expanded`), so an overlap is not expressible. Arithmetic
remains only for the bottom band, where the value genuinely is fixed: a 52px
control a known distance off the bottom edge (`ChromeMetrics.bottom`).

Two traps this surfaced, both worth remembering:

- **flutter_test's default font renders every glyph as a full em square**, so text
  is much wider in a widget test than on a device and wraps where the real app
  does not. A layout test can therefore fail for a font reason while the device is
  fine. That is not a reason to loosen the test: it is a free large-text-scale
  case, and the code has to survive it either way.
- **`Column` centres its children on the cross axis.** Moving the header from a
  `Positioned` into a `Column` child silently centred it, because the block
  shrink-wrapped to its text width. `crossAxisAlignment: CrossAxisAlignment.stretch`
  is required, and a test now locks the header's left edge to `space.md`.

Padding alone was also only half the fix. It governs where a list comes to REST;
while it is being dragged, rows still travel behind the add control. A bottom
scrim sized from the same `ChromeMetrics.bottom` fades them out, and it must be
wrapped in `IgnorePointer` or the bottom band of the screen goes dead to touch
(there is a test for exactly that, on a deliberately short viewport so the list
actually overflows -- a drag that moves nothing on a non-scrolling list proves
nothing).

Also: `Set-Content -Encoding UTF8` in PowerShell 5 writes a BOM. A negative-test
probe that rewrote `main.dart` with it left a BOM behind; check the first three
bytes (`EF BB BF`) after any scripted rewrite and strip with
`UTF8Encoding($false)`.

## Auditing accessibility: `uiautomator dump` lies about Flutter

A device dump is **not** a valid way to check whether a Flutter screen is
labelled, and reading one cost a design critique a wrong headline finding.

`adb shell uiautomator dump` attaches as an accessibility service, and that
attachment is itself what makes Flutter start building its semantics tree. So a
dump taken on a freshly-pushed route can read a tree that has not been populated
yet and come back nearly empty. It reported **one** labelled node on the tree
screen. The header alone exposes seven:

```
[6 on the tree.] [Level 2 · 2 more harvests to 3] [Level 2. Open your profile]
[Branches] [Level 2, 0 percent to level 3] [1 harvested] [2 seeds] [0 branches]
```

The same dump showed the share card and the visitor view as having no actionable
controls, while `ensureSemantics` proved `Copy link`, `See what a visitor sees`,
`Admire`, `Wishlist`, `Played too`, `Follow` and `Plant` were all present.

**The authority is Flutter's own semantics tree**, because that is what TalkBack
consumes:

- In a test: `final h = tester.ensureSemantics();` then
  `find.bySemanticsLabel('...')`, and `h.dispose()` at the end.
- To discover what actually exists rather than assert a guess, walk the tree and
  print every label:

```dart
void walk(SemanticsNode n) {
  final d = n.getSemanticsData();
  if (d.label.isNotEmpty) print('[${d.label}]');
  n.visitChildren((c) { walk(c); return true; });
}
walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
```

One genuine gap did exist and the dump was not what found it:
**`IconButton(tooltip: 'Branches')` does NOT put its tooltip in the semantics
tree.** An icon-only button needs `Icon(..., semanticLabel: 'Branches')`; the
tooltip is for sighted hover only. See `test/accessibility_semantics_test.dart`,
which now pins every header, share-card and visitor control.

Note that file imports `repository.dart`, so checker rule 8 requires **every**
`pumpWidget` in it to sit inside `tester.runAsync` -- including the ones that
never touch the database. The rule matches per file, not per test.

## A fixed-ms wait measures the host, not the code

`visit_screen_test` waited a flat 50 ms for a real sqflite write after tapping
Plant. It passed in isolation and failed inside the full suite, twice, because
under concurrency the round trip outlives the guess -- and it failed only when
run the way `check.ps1` runs it (`flutter analyze` immediately before
`flutter test`, which leaves analysis processes competing for the machine).

Replace such a wait with a bounded poll on the condition itself:

```dart
final deadline = DateTime.now().add(const Duration(seconds: 10));
while ((store.items?.isEmpty ?? true) && DateTime.now().isBefore(deadline)) {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}
```

Faster in the common case and deterministic under load. When a test passes alone
and fails in the suite, suspect a fixed delay before suspecting the code.
