# Android final acceptance

2026-10-27. Authorized phone AESWNRBAEUPNTGJZ, Android 13 confirmed by getprop. TEST package com.example.flutter_application_1.fr21test. Production package unchanged.

Build and installation results are appended below only after actual verification. The first updated APK built successfully, but was not installed after the phone disconnected. Notification-icon integration invalidated that artifact for final acceptance. Subsequent packaging attempts exposed Windows access-denied errors in generated resource merge/package folders. The build helper now validates and cleans only those generated directories under build before rebuilding. No Flutter reinstall or new application/repository was created.

Automatic approval review temporarily failed due to its usage limit, not an unsafe-action determination. A later authorized retry succeeded in reaching the device tool, but found the phone disconnected. The owner reconnected it. No installation/resume/logout PASS is inferred from these attempts.

Required checks remain separately recorded: final source/APK hash; installed base.apk hash; visible app name/icon/splash; login language persistence; Customer catalogue; four-role smoke checks; controlled background/resume/logout/cold-start. Historical screenshots and APK results are not relabelled.

Production signing, iOS, full physical delivery/OTP/new earnings, every rendered control and moving/background-GPS acceptance remain outside a debug APK build result.

2026-10-28 update: the next build exposed unreadable generated merged_res_blame_folder state. The helper now clears that exact current-variant generated path with the same build-root boundary validation. Final assistant regression after the history-bound correction: 2/2 PASS (already included in the 46-case suite, not added to the total).

## Verified final APK — 2026-10-28 Asia/Karachi

- Build PASS; current source manifest matched after compilation. Artifact: build/delivery/test/app-fr21test-debug.apk.
- SHA-256: 4C021066EE8F38CB50120F299227540824976AB58A747A4E2B9A13218917534F.
- Installation PASS on AESWNRBAEUPNTGJZ; installed base.apk SHA-256 independently matched.
- APK metadata confirms com.example.flutter_application_1.fr21test and display name TezRider. Launcher icon resources were inspected; final launcher/splash visual capture still NOT RUN.
- Customer dashboard loaded actual TEST catalogue data. Captured product price/favourite/rating/review rows fit without visible overflow in the observed view. This is one-device evidence, not every text scale or the exact historical 25-pixel reproduction.
- Account tab survived same-process background/resume (MY ACCOUNT observed before and after).
- Sign Out confirmation returned to Sign in as Customer. Force-stop/relaunch remained signed out.
- The device disconnected before empty English/Urdu login screenshots and remaining three-role smoke checks. Those are NOT RUN on this artifact.
- Floating assistant control overlaps scrolling catalogue content in the capture; exhaustive visual polish is not accepted.

Evidence: docs/evidence/REPAIR-android-build.json, REPAIR-native-results.jsonl, REPAIR-customer-catalogue.png, REPAIR-customer-product-footer.png. Recorded machine timestamps are UTC; the acceptance date above is Asia/Karachi.

## Follow-up build after observed overlap repair

The preceding APK is superseded by the source-verified build with a reserved assistant/navigation area. Final artifact SHA-256: 0EBD74CE98C3034FF70A8D0388C4C3DA8E8F3910F39E417E67357DE51605793E. Build, install and installed base.apk hash PASS. Previous results remain tied to their original hash in REPAIR-native-results.jsonl.

On the previous artifact, English/Urdu empty-form screenshots and Urdu cold-start persistence PASS after reconnection. Rider dashboard/home and profile controls were observed. Vendor initially loaded, then the app lost foreground; its timed assertion failed and is not counted as PASS. Reopening the final APK confirmed Store Dashboard and allowed the final screenshot/profile navigation.

Final-build observations: Customer catalogue, Vendor Store Dashboard and Admin Panel PASS. Vendor/Admin screenshots captured; no administrative records were changed. Customer screenshot REPAIR-customer-docked-final.png visually confirms the assistant is in its own bottom area and no longer overlays cards. Price/rating/review rows fit in that view. Account-tab same-process background/resume PASS again on the final hash. Rider smoke and bilingual persistence were measured on the preceding build; those role/login sources did not change in the docking-only follow-up, but are not relabelled as final-hash execution.

Final-hash logout confirmation and signed-out force-stop/relaunch PASS. Empty English and Urdu login screenshots captured on the final hash; Urdu persisted through a cold restart. Restored English, kept account signed out. Android's package-specific App info page visually confirms TezRider and the approved green delivery-bike icon (REPAIR-installed-app-info.png); no settings changed. Dedicated launcher-home/splash animation recording was not captured. Device helper temporary XML files cleaned.

Overall Android acceptance remains PARTIAL: bounded smoke/layout/session checks passed; complete delivery, OTP/proof/new earnings, moving/background GPS, every screen/control, accessibility and device matrix are still unverified.
