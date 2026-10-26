# Android build and installation

Use tool/build-android.ps1 -Environment TEST -Mode debug -Format apk -DefinesFile .fr21-local/public-defines.json. The script builds within this repository and writes build/delivery/test/, logs and source/APK hashes. -PreflightOnly validates configuration without claiming a build.

Device AESWNRBAEUPNTGJZ was connected as CPH2285 during read-only ADB inspection. Actual current-source build/install/runtime results are appended when executed. Earlier APK from 9d5e127 is historical and does not contain new changes.

Expected TEST artifact after successful build: build/delivery/test/app-fr21test-debug.apk. Do not claim it exists until build succeeds and hash/source checks pass. Install only on the authorized serial with adb -s AESWNRBAEUPNTGJZ install -r <artifact>, then verify installed package com.example.flutter_application_1.fr21test, startup and tested journeys. Never clear app data or reset credentials to simplify testing.

Production: tool/build-android.ps1 -Environment Production -Mode release -Format apk (or appbundle) -DefinesFile <ignored production defines> -ProductionApplicationId <owner-approved-id>. Owner keystore/key.properties are mandatory; debug signing fallback is prohibited. No approved ID/keystore exists in current observed configuration; no production APK/AAB is claimed. The delivery channel has not specified an AAB requirement.

Initial in-repository build encountered stale generatedT-drive depfiles. Reproduce safe recovery with -CleanFlutterMetadata, which validates repository containment before deleting only generated Flutter intermediate metadata; dependencies, APKs, app data and sources remain. No SDK reinstall or separate mirror/project is needed. Actual rebuild result follows.
