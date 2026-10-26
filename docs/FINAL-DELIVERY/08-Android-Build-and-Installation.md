# Android build and installation

## Current verified TEST artifact

- Source checkpoint: `03a9ce6` on the existing branch.
- Artifact: `build/delivery/test/app-fr21test-debug.apk` (105121274 bytes).
- SHA-256: `66B373F3531F5918C967A4032F38BA023A4A7C330FF69E86AD2A82AB5812EBA1`.
- Package: `com.example.flutter_application_1.fr21test`; version 1.0.0/code 1; minSdk 24, targetSdk 36.
- Debug TEST build; Android Debug signature verified. This is not a production release.
- Gradle completed successfully in 43.6 seconds. All 198 source hashes matched before/after build and during independent verification. All 650 ZIP entries were read to EOF/CRC checked; exact protected TEST service-key/fixture-password UTF-8/UTF-16LE scan: zero matches. This bounded scan does not certify arbitrary secrets.
- Installed on authorized device `AESWNRBAEUPNTGJZ` with `adb install -r`, without clearing app data. Installed `base.apk` SHA-256 matched the artifact exactly.

Sanitized evidence: `docs/evidence/FINAL-delivery-apk.json` and `FINAL-delivery-native.json`. Full ignored source manifest and build log: `build/delivery/test/build-evidence.json` and `build.log`.

Customer authentication/catalogue/profile and ordinary cold restoration were observed on this artifact. Credential keys survived restart, the logout fence remained absent, and no secure-read timeout was logged. Actual offline-cold-start biometric sign-in/server refresh and all four role authentication/navigation smoke checks passed. Physical movement/new geometry observed, with tracking interruptions and latency failure; complete journeys remain unqualified.

## Reproduce in this repository

Run `tool/build-android.ps1 -Environment TEST -Mode debug -Format apk -FlutterPath 'C:\Users\urreh\Downloads\flutter\bin\flutter.bat'`. Existing public TEST configuration is ignored at `.fr21-local/public-defines.json`. `-PreflightOnly` checks configuration without building/installing/deploying. Output remains in this project; no mirror, duplicate repository or output relocation was introduced.

Recovery options, only when applicable:

- `-CleanFlutterMetadata` validates repository containment and clears only `.dart_tool/flutter_build` and generated `build/app/intermediates/flutter` metadata. It resolved stale depfiles referring to a removed T: drive.
- `-CleanOfflineIntermediates` checks the absolute app-build boundary and selected variant/package paths, removing only generated files marked Offline/RecallOnDataAccess. The actual recovery removed 30 historical OneDrive placeholders, including native libraries/packaging caches; later rebuilds removed zero. Sources, dependencies, other variants and app data were preserved.
- The helper also safely clears only the selected generated merged-assets directory because Java cleanup failed on deep Windows paths. Existing compilation caches are otherwise retained. Gradle is bounded to 2GB heap/768MB metaspace/two workers on the 8GB workstation.

Failed/stalled attempts, the first two superseded artifact hashes, the native startup defect and subsequent regression results remain in `03-Test-Execution-Ledger.md`. In particular, one update reported an ADB error during USB loss; its installed hash was reconciled after reconnection before further testing. No uncertain installation was blindly replayed.

## Production

The helper supports `-Environment Production -Mode release -Format apk` or `-Format appbundle`, with private production defines and `-ProductionApplicationId`. The owner-approved ID, upload keystore and `android/key.properties` are mandatory; debug signing fallback is prohibited. They are not configured/qualified. Production push/platform acceptance, schema/history review, backup recovery and explicit deployment authorization remain outstanding. No production APK/AAB or deployment is claimed.
