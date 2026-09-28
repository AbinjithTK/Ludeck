# Release signing

Play accepts only an app bundle (AAB) signed with your **upload key**. Play App
Signing then re-signs it with the app signing key Google holds. If the upload key
is ever lost, Play Console can reset it (Setup, App signing, Request upload key
reset), so losing it costs days, not the app. Back it up anyway.

`app/android/app/build.gradle.kts` reads the key from `app/android/key.properties`.
Both that file and every `*.jks` are gitignored. Without the file:
- `flutter build apk --release` still works on the debug key, for the emulator.
- `flutter build appbundle` **fails on purpose**, so a debug-signed bundle never
  reaches the Play Console.

## One-time setup (you, not the agent: the passwords must not go through chat)

`JAVA_HOME` on this machine points at `C:\Program Files\Android\Android Studio\jbr`,
which no longer exists (the JDK is in `Android Studio1`). Every command below names
the working path directly, and `gradlew` needs it set for the session:

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio1\jbr"
$kt = "$env:JAVA_HOME\bin\keytool.exe"
```

1. Create the keystore outside the repository:

   ```powershell
   New-Item -ItemType Directory -Force "$env:USERPROFILE\keys" | Out-Null
   & $kt -genkeypair -v `
     -keystore "$env:USERPROFILE\keys\ludeck-upload.jks" `
     -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   It asks for a password and your name/organisation. Use the same password for
   the store and the key when asked (press Enter at the key-password prompt).

2. Create `F:\Abin\Ludeck\app\android\key.properties` with four lines:

   ```properties
   storeFile=C:/Users/user/keys/ludeck-upload.jks
   storePassword=<the password>
   keyAlias=upload
   keyPassword=<the password>
   ```

   Forward slashes in the path. No quotes.

3. Back up `ludeck-upload.jks` and the password somewhere that is not this
   machine (a password manager holds both).

## Build the bundle

```powershell
cd F:\Abin\Ludeck\app
flutter build appbundle --release `
  --dart-define=REVENUECAT_GOOGLE_KEY=goog_... `
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

Output: `app\build\app\outputs\bundle\release\app-release.aab` (about 80 MB). Every
upload needs a higher `versionCode`: bump the `+N` in `app/pubspec.yaml`
(`version: 1.0.0+1`).

**C: drive space.** C: had 120 MB free on 2026-09-28 and the bundle step failed
with "There is not enough space on the disk": bundletool writes its temp files
to C:. Stopping the Gradle daemons (`android\gradlew.bat -p android --stop`)
freed about 4 GB. If it recurs, point the build's temp at F: for that session:
`$env:TMP = $env:TEMP = "F:\Abin\tmp"`. Flutter then sometimes omits its "Built"
line even though the bundle was written, so check the file exists.

The first internal-testing upload can go out before the RevenueCat key exists
(the app then shows Pro as unavailable). That upload is what unlocks creating the
in-app products in Play Console.

## Check the signature

```powershell
& $kt -printcert -jarfile app\build\app\outputs\bundle\release\app-release.aab
```

The owner line must be the name you entered in step 1, not `CN=Android Debug`.
