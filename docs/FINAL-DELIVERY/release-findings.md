# Android release preparation

Date: 2026-10-25 (Asia/Karachi). Baseline revision: `9d5e127`.

## Current findings

- Existing repository, Flutter architecture and TEST package retained. No scaffold, checkout, mirror or new repository created.
- TEST package: `com.example.flutter_application_1.fr21test`; TEST backend: `igeisilhtmglgnqvllrx`.
- Production backend reference: `arrqsvejrfdbacfwtpcc`. No production connection, installation or deployment performed.
- Flutter SDK exists at `C:/Users/urreh/Downloads/flutter`; Android SDK exists at `C:/Users/urreh/AppData/Local/Android/Sdk`.
- Actual elevated `adb devices -l` identified authorized device `AESWNRBAEUPNTGJZ` as connected (`CPH2285`). Initial default-permission call could not start its daemon; that failure is not a missing-device result.
- Private `android/key.properties` is absent. Existing application ID `com.example.flutter_application_1` remains a placeholder for production. No signing credentials or production ID invented.
- Current notification client explicitly enables Android push only for isolated TEST. Production push cannot be claimed ready.
- Existing TEST manifest contains its own login-callback scheme and POST_NOTIFICATIONS permission. Equivalent production callback/push registration requires configuration and verification before production use.
- Existing historical helpers use a fixed external temporary build mirror and may retain stale Android/assets files. They remain historical; final delivery uses the new in-repository helper.

## Changes

`tool/build-android.ps1` builds from the current repository. TEST is the default. It verifies the exact environment URL, JSON boolean isolation flag, public key role/project where JWT metadata is available, and rejects privileged/unknown defines. Production requires release mode, an explicit approved application ID and private signing configuration. It never installs or deploys anything. Signing identity and production readiness still require separate review.

Generated APK/AAB, log and source/hash evidence are written under ignored `build/delivery/test/` or `build/delivery/production/`. Source hashes are compared before/after the build; concurrent changes cause rejection of artifact provenance rather than a false current-source claim. Build log/evidence remain ignored. No values from private signing/public-key configuration are copied into handover documentation.

`android/app/build.gradle.kts` now reads the ignored private signing properties and accepts the production ID through Gradle property `tezriderApplicationId`. TEST retains its debug signing identity. Production release no longer falls back to a debug key. Missing production release identity/signing fails configuration for normal production release tasks. `android/key.properties.example` contains empty fields only.

## Commands

From repository root, with the already configured SDK on PATH:

```powershell
./tool/build-android.ps1 -PreflightOnly
./tests/integration/FINAL-delivery-build-check.ps1
./tool/build-android.ps1 -Environment TEST -Mode debug -Format apk
```

Expected successful TEST output: `build/delivery/test/app-fr21test-debug.apk`. Existence is not asserted until the actual build completes. Installation must target the authorized device and TEST package after APK manifest/hash verification.

For a future authorized production build, privately copy `tool/production-defines.example.json` to ignored `.fr21-local/production-defines.json`, supply the project's public key only, and populate ignored `android/key.properties` using the owner's existing upload key. Supply the owner-approved production application ID. Do not use the placeholder ID or a newly invented signing identity. The helper supports `-Environment Production -Mode release -Format apk` and `-Format appbundle`, each with `-ProductionApplicationId` and the private defines path. Production Firebase registration must match the chosen ID. These commands have not been executed.

## Executed verification

- `tests/integration/FINAL-delivery-build-check.ps1`: 11/11 PASS. Checks TEST isolation, production endpoint mismatch, boolean type, secret key/extra server define, service-role JWT, mismatched-project JWT and production preconditions. Synthetic public-key shapes are configuration fixtures only, never used for network requests.
- `tool/build-android.ps1 -PreflightOnly`: PASS using actual private TEST defines; no key values printed.
- PowerShell parser: build helper syntax PASS.
- Elevated ADB device inventory: PASS (device connected). No installation, launch or runtime check performed by this initial inventory.
- Gradle configuration / actual new-source Android build: pending root coordination after source changes and affected tests finish.

Machine-readable preflight results: ignored `build/delivery/preflight-tests/results.json`. Baseline production status: **NOT READY** (no release signing, approved production ID, production push/runtime acceptance or complete SRDS acceptance).

References consulted: [Flutter Android deployment](https://docs.flutter.dev/deployment/android), [Android signing](https://developer.android.com/studio/publish/app-signing). These support the upload-key/release-signing preparation; they do not establish project runtime acceptance.

## In-repository build recovery (2026-10-26)

Initial generated Flutter depfiles mixed physicalC: output paths and a removedT: drive alias, causing Gradle PreCreateOutputParentsStep null-parent failure. -CleanFlutterMetadata now verifies containment and clears only generated Flutter intermediates, preserving dependencies/artifacts/sources. Regenerated output depfiles have zero staleT: paths. No SDK reinstall or external build mirror is used. Generated android/.kotlin/ is ignored to avoid transient build outputs entering source manifests.

The8GB workstation measured less than1GB available while the original Gradle settings allowed8GB heap/4GB metaspace. The long first build was cancelled deliberately after an additional owner-requested support UI change invalidated its source snapshot. Existing previously proven2GB heap/768MB metaspace/two-worker settings are now applied directly to android/gradle.properties; compiled caches retained. Final current-source build is running and remains unclaimed until successful artifact/source/package checks.

## Final superseding outcome

Source03a9ce6 TEST debug APK built in43.6s, SHA25666B373F3531F5918C967A4032F38BA023A4A7C330FF69E86AD2A82AB5812EBA1. All198 runtime-source hashes verified,650 archive entries checked, installed base.apk hash matched. Actual Android biometric cold recovery and four-role smoke checks passed. Physical walk observed movement/new geometry but interruptions and2998.7ms route latency leave FR14 partial. Full suite640PASS/2SKIP plus separate9image cases; whole analysis0errors/4inherited warnings/38infos. Production remains NOT READY; earlier build-running statements above are historical.
