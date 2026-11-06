# TezRider: Windows partner setup

Updated 2026-11-06, Asia/Karachi. Run commands in PowerShell from the repository root,
the directory containing `pubspec.yaml`. There is no nested `FYP_Final2_Backup`
in this GitHub checkout. These steps target Android TEST only.

## 1. Install tools once

Skip tools already working. Do not recreate the Flutter project.
Reserve at least 10 GB free for the SDK/dependency/build work as a planning
allowance, not a guarantee. The diagnostic requires 2 GB free working space;
the owner's universal build exhausted a nearly full C: drive during native
library extraction. This is a disk error, not a Firebase error.

1. Install [Git for Windows](https://git-scm.com/downloads/win); reopen PowerShell.
2. Download **Flutter 3.47.6 stable** from the [official SDK archive](https://docs.flutter.dev/install/archive).
   Extract to a short writable folder such as `C:\src\flutter`, outside OneDrive,
   Program Files and this repository. Add `C:\src\flutter\bin` to your user PATH.
   Reopen PowerShell. Dart **3.13.5** is bundled; do not install Dart separately.
   This is the SDK verified on the owner's machine. The lockfile requires
   Dart >=3.13.0 and Flutter >=3.44.0, regardless of older setup reports.
3. Install [Android Studio](https://developer.android.com/studio).
   Settings > Plugins: install Flutter (accept its Dart plugin dependency).
   Open the repository root as a Flutter project.
4. Install [Temurin JDK 17](https://adoptium.net/temurin/releases/?version=17).
   Android Studio's currently bundled Java may be newer than this Gradle supports.
   Set Flutter's JDK to the actual JDK 17 installation folder, for example:

   ```powershell
   flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-17.0.13.11-hotspot"
   ```

   Replace that example with your real folder (containing `bin\java.exe`). In
   Android Studio > Settings > Build Tools > Gradle select the same JDK 17.
   This command changes your local Flutter setting, not a repository file.
5. Android Studio > SDK Manager: install Android SDK Platform **36**, Build Tools
   **35.0.0**, SDK Platform-Tools, SDK Command-line Tools (latest), and NDK
   **28.2.13676358**. Enable Show Package Details to select exact versions.
   Gradle **8.14**, AGP **8.11.1**, Kotlin **2.2.20** and desugaring **2.1.4** are
   resolved by the project; no separate Gradle installation is needed.
   With the verified Flutter SDK: compileSdk/targetSdk **36**, minSdk **24**;
   Java/Kotlin bytecode target **11**, build JDK **17**.
6. Device Manager > create an Android emulator with Google Play services,
   API 24 or later (API 36 recommended). Alternatively enable Developer options
   and USB debugging on a physical Android phone, install its OEM USB driver,
   connect a data cable, unlock it and accept the RSA authorization prompt.
   Real FCM acceptance requires a compatible Google Play services device and
   notification permission. An emulator is not real Rider GPS acceptance.

Official compatibility references: [AGP 8.11](https://developer.android.com/build/releases/agp-8-11-0-release-notes),
[Gradle 8.14 Java compatibility](https://docs.gradle.org/8.14/userguide/compatibility.html),
[Android setup](https://docs.flutter.dev/platform-integration/android/setup).

## 2. Check the laptop

```powershell
git --version
flutter --version
dart --version
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

Accept licenses interactively. Resolve Android toolchain errors before building.
`flutter doctor -v` shows the Java binary Flutter actually uses; `java -version`
alone may show a different JDK. Visual Studio is unnecessary for an Android build.

## 3. Get the reviewed branch

The current fixes are on `feature/final-customer-delivery-fixes`. Main retains
the earlier portability baseline; the current delivery branch is not merged.
Use the commit recorded in `docs/FINAL-DELIVERY/FINAL-CUSTOMER-ACCEPTANCE.md`.

For a new clone:

```powershell
New-Item -ItemType Directory -Force C:\src | Out-Null
Set-Location C:\src
git clone https://github.com/saificode123/Tez-Rider-Flutter.git
Set-Location Tez-Rider-Flutter
git fetch origin --prune
git switch feature/final-customer-delivery-fixes
git status --short
git rev-parse HEAD
```

For an existing clone, first inspect `git status`. Preserve or commit your work
before switching; never use reset --hard. Update the reviewed feature branch:

```powershell
git switch feature/final-customer-delivery-fixes
git pull --ff-only origin feature/final-customer-delivery-fixes
```

The old shared commit `2a059547a3054b35d34d6e81c181ef8879e2c19b` includes the
map upgrade but predates these portability fixes. Use the portability fix commit
reported in the audit/final handover. The owner subsequently authorized putting
the earlier portability fixes on `main`; all historical feature refs were already
contained in main, so no blind replay of old branches is necessary. The current
Customer/biometric/Rider fixes remain on the feature branch and are not merged.

## 4. Supply approved TEST client configuration

```powershell
Copy-Item .env.example .env
notepad .env
```

Only do the copy for a missing `.env`; preserve any configured local file.
Ask the owner through a private channel for the approved TEST **public** key and
TEST Firebase Android client file. Fill `SUPABASE_PUBLISHABLE_KEY` in `.env`.
Legacy `SUPABASE_ANON_KEY` also works; set only one key name. Keep
`SUPABASE_URL=https://igeisilhtmglgnqvllrx.supabase.co` and
`FR21_ISOLATED_TEST=true`. Remove unused `SUPABASE_JWKS_URL` from mobile defines.

Create the directory if needed, then save the approved Firebase file as:

```powershell
New-Item -ItemType Directory -Force android\app\src\fr21test | Out-Null
```

Exact file: `android/app/src/fr21test/google-services.json`.
It must identify project `tez-rider-fe12b` and Android client
`com.example.flutter_application_1.fr21test`. The tracked root
`android/app/google-services.json` identifies the legacy project/package and
is **not** the TEST file. Obtain/download the existing TEST registration;
do not register a replacement project or copy production configuration.

`.env` uses Flutter compile-time `--dart-define-from-file`; it is **not an asset**
and is never automatically loaded. No dotenv dependency is required. Rebuild
after changing it. JSON defines files remain supported for older owner tooling.
Keys compiled into an app are extractable: only public client keys belong here.
Do not put SMTP, Brevo, service-role, Geoapify, FCM service-account, database,
password or CNIC data into any mobile configuration.

Authentication, private Storage, Realtime, invoice/email and routing calls use
the TEST Supabase backend. Email/provider/routing secrets belong only on that
backend. No mobile email or map-provider secret is required. Firebase supplies
Android push, not account authentication. For this flow there is no Google
sign-in/SMS provider or SHA registration requirement demonstrated by the source.
Configure the existing Supabase redirect `tezrider-fr21-test://login-callback/`
in the TEST Auth allowlist if absent; do not change production Auth settings.

For a deliberate push-disabled build set `FR30_ANDROID_PUSH=false`; the core app
can build without TEST Firebase. This does not pass FR-30 native-push acceptance.
The full TEST configuration keeps it `true` and
`FR30_FIREBASE_PROJECT_ID=tez-rider-fe12b`.

## 5. Resolve dependencies and verify

```powershell
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-windows-setup.ps1
flutter analyze
flutter test
```

The preflight is read-only and prints no values/keys. Resolve each FAIL using its
instruction. It fails a missing Android device; `-SkipDeviceCheck` permits a
build-only preflight. Full regression tests use mocks; do not run the historical
hosted integration send/setup scripts without reviewing their permissions.
Keep `pubspec.lock`; do not run pub upgrade to fix a missing SDK.

## 6. Run or build Android TEST

For a quick Chrome demo after configuring `.env`:

```powershell
flutter run -d chrome -t lib/main.dart --dart-define-from-file=.env
```

Chrome startup and the owner's private Rider sign-in/earnings were exercised.
Chrome does not qualify Android FCM, background GPS or physical delivery acceptance.

```powershell
flutter devices
flutter run --debug --flavor fr21test -t lib/main.dart --dart-define-from-file=.env
flutter build apk --debug --flavor fr21test -t lib/main.dart --target-platform android-arm64 --dart-define-from-file=.env
```

If several devices are listed, add `-d DEVICE_ID` to `flutter run`, replacing
DEVICE_ID with the Android ID shown by `flutter devices` (no angle brackets).
APK: `build/app/outputs/flutter-apk/app-fr21test-debug.apk`.
The command above builds for an arm64 Android phone. For an x86_64 emulator or
universal APK, omit `--target-platform android-arm64`; that universal attempt
was blocked by the owner's full disk and is not claimed as passed. `flutter run`
selects the connected device's architecture automatically.
Optional guarded builder using the same configuration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\build-android.ps1 -Environment TEST -DefinesFile .env
```

That helper also copies an arm64-only APK and build evidence into
`build/delivery/test/`; omit the architecture flag in the direct build for an
x86_64 emulator.
Debug signing is local to each laptop. Do not uninstall an owner device's app
to resolve a signature mismatch without backing up needed state and approval.

## 7. Troubleshooting by first error

- **flutter not recognized:** fix user PATH and reopen PowerShell; check `where.exe flutter`.
- **Dart version mismatch / dependency resolution:** use the verified Flutter SDK,
  check `where.exe dart`, retain the lockfile and retry `flutter pub get` after
  resolving the actual network/proxy/version error. Do not upgrade all packages.
- **Java/Gradle error / unsupported class version:** inspect `flutter doctor -v`,
  select JDK 17 as in step 1. Bytecode target 11 is not the required build JDK.
- **Android SDK/component missing:** install the named component in SDK Manager;
  if SDK discovery fails use `flutter config --android-sdk="YOUR_ACTUAL_SDK_FOLDER"`.
  Never copy another computer's `android/local.properties`.
- **Licenses missing:** install command-line tools, then `flutter doctor --android-licenses`.
- **No matching Firebase client:** check the exact flavor package/project in step 4;
  obtain the original registered TEST client. SHA fingerprints are not a cure for
  a package mismatch. Console permissions must be handled by the Firebase owner.
- **Missing .env:** create it in the folder containing pubspec.yaml; ensure Windows
  did not name it `.env.txt`. Supply `--dart-define-from-file=.env` on every run/build.
- **Backend configuration missing/invalid:** use one supported public-key name,
  the TEST URL and isolation flag. Never substitute a service-role key. Stop/rebuild
  after editing compile-time configuration; hot reload does not replace defines.
- **Gradle cache/download failure:** retain the first error; check connectivity,
  disk space, proxy and JDK. Stop the project Gradle daemon before retrying a
  specifically corrupt download. Do not delete SDKs or all user caches blindly.
- **Long path/file cleanup error:** clone to `C:\src\Tez-Rider-Flutter` outside
  synced folders. `flutter clean` is appropriate for stale generated metadata
  after moving a checkout or changing toolchains, followed by `flutter pub get`.
  It does not fix absent credentials, version conflicts or Firebase mismatch.
- **No Android device / unauthorized ADB:** start the emulator or unlock/reconnect
  the phone, accept its RSA dialog and check OEM driver/data cable and `adb devices`.
- **Install failure:** check API >=24, CPU architecture, free storage and signing
  mismatch. Use the universal direct build for an emulator, not the arm64 helper APK.
- **Login/verification/email failure:** verify the existing TEST account, email
  confirmation, role approval and Auth redirect. Owner enters passwords privately.
  A queued email is not a received email; ask the owner to inspect provider status,
  quota, spam folder and the approved recipient before any resend. No repeated sends.
- **Map/ETA failure:** verify location permission, internet, sharing consent and
  server route status. No Geoapify key belongs in Flutter. The bounded route
  allowance is not renewed by a rebuild; do not repeatedly refresh order 3180.
- **Push registration failure:** verify TEST file/flags, Google Play services,
  Android notification permission and the in-app Enable action. A matching Firebase
  file alone does not verify FCM server credentials, token registration or delivery.

## 8. Partner acceptance checklist

- Record `git rev-parse HEAD`, Flutter/Dart version and `flutter doctor -v` result.
- Preflight passes, dependencies resolve, analysis and tests have recorded results.
- Build returns the expected APK; record `Get-FileHash build\app\outputs\flutter-apk\app-fr21test-debug.apk -Algorithm SHA256`.
- App starts on her Android device with TEST backend and existing approved account.
- Owner coordinates role checks; inspect browsing/cart/history and existing notices.
- Confirm invoice display only for a legitimately invoice-eligible existing order.
- Record real email/push receipt only after recipient/purpose/remaining allowance
  approval. No unapproved broadcasts, replacement deliveries or synthetic CNIC approval.
- Preserve order 3180: its latest recorded state is delivered, unpaid, with no
  cash receipt or invoice. Do not reset it or invent cash to obtain an invoice.
- Mark second-laptop/device acceptance only after the partner executes this list.

No unlimited cloud capacity is assumed. Current quotas and remaining message
allowances must be checked by the owner before external TEST sends; see
`docs/FR-32-operations.md` and `docs/POLICY-DECISIONS.md`.

## Biometric acceptance

Sign in normally with the correct role, open Me/Profile and explicitly enable
Biometric sign-in through the genuine phone prompt. Lock and sign in or restart
to verify protected entry. Sign out revokes protected credentials; normal login
and explicit opt-in are required again. Unsupported Chrome/devices do not offer
an enabled biometric sign-in action. Never share passwords with the agent.

The November 6 report records the exact installed TEST APK/source and current
limits. Successful clone/build on the owner machine is not physical acceptance
on a partner laptop. Toolchain and matching TEST Firebase configuration are
required in addition to `.env`.
