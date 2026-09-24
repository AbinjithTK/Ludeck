# Ludeck

A game collection you grow instead of a backlog you owe.

Games arrive as fruit on a tree. Finishing one is a harvest. Branches organise the
collection into groups you name yourself. Nothing withers, nags, or empties. A full
tree is a healthy tree.

Ludeck is a Shipaton 2026 entry. It tracks which device each game lives on (PS5,
Android, PC, Meta Quest, Nintendo), keeps ownership and progress on two separate
axes so selling a game never erases the fact that you finished it, and answers the
question "what should I play tonight" without making you feel behind.

## Where things are

| Path | What it is |
|---|---|
| `app/` | The Flutter app. This is what ships. |
| `fallback-kotlin/` | The Kotlin/Compose app. Builds and runs. Kept as insurance. Do not delete. |
| `docs/` | Every reference document. Start with `docs/PLAN.md`. |
| `uireferences/` | 51 Mobbin screens from Tolan and Hypelist, with a manifest. Indexed by `docs/UI-REFERENCES.md`. |
| `intel/` | Python scripts used to analyse the competing Shipaton entries. |

## Read these before writing code

1. `docs/BUILD-PLAN.md` is the current ordered plan, checked against the live Devpost
   criteria. Start here. It supersedes the ordering in `docs/PLAN.md`.
2. `docs/PLAN.md` is the earlier status and plan, kept for its record of what was done.
2. `docs/DECISIONS.md` is the frozen vocabulary and the invariants. Breaking one of
   these breaks the product, not just the build. Read it first.
3. `docs/DESIGN.md` is the binding design document, 16 sections. It governs what the
   screens are and what they are not.
4. `docs/CONSTRAINTS.md` is what the machine and the platforms actually permit,
   verified rather than assumed.
5. `docs/COMPETITION.md` is what the other entries are doing and where the gap is.
6. `docs/UI-REFERENCES.md` indexes the 51 staged screens and says what each group
   changes about the build.
7. `docs/FEATURES.md` is the scoped feature set, each feature tied to the reference
   that specifies it, split into v1, v1.1 and cut.
8. `docs/USERFLOWS.md` is every v1 flow specified screen by screen, including the dead
   states.
9. `docs/SUBMISSION.md` is the checklist that has to be complete to win anything.

## Running the app

The Flutter app targets Android and Windows. Windows is there so the canvas can be
looked at without a phone, because no emulator can boot on this machine. iOS is not
possible here at all; see `docs/CONSTRAINTS.md`.

```
cd app
flutter pub get
flutter analyze          # must be clean
flutter test             # 20 tests, all must pass
flutter run -d windows   # look at the tree
flutter build apk --debug
```

If Gradle complains about the Java version, Flutter is pointing at the wrong JDK.
Fix it once:

```
flutter config --jdk-dir "%USERPROFILE%\.gradle\jdks\eclipse_adoptium-17-amd64-windows.2"
```

## Running the fallback

```
cd fallback-kotlin
.\gradlew assembleDebug
powershell -File scripts\check.ps1
```

`check.ps1` enforces six project rules over the Kotlin, TypeScript and SQL sources.
It does not cover Dart. See `docs/PLAN.md` for that gap.

## The Rive artboard

The fruit is authored as text and built with the Rive CLI, so it can be changed and
verified without opening an editor.

```
cd app\rive\fruit
rive . --verify
rive . --screenshot --advance=1
rive build
copy build\fruit.riv ..\..\assets\fruit.riv
```

The CLI lives at `%USERPROFILE%\.rive\bin\rive.exe`. No account is needed to create,
preview or build. Signing in is only required for publishing and `.rev` export.
