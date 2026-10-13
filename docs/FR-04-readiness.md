# FR-04 TEST readiness — 2026-10-13

**FR-04 FUNCTIONALLY ACCEPTED — performance/scalability qualification outstanding.** Required CNIC registration, security, actual email confirmation and Android workflows pass. A bounded hosted read measurement now passes the engineering p95 target. Full 1,000-user qualification is **NOT EXECUTED**, awaiting a Windows restart to activate the approved local runtime. This is not full system-scale acceptance.

## Criteria and source

The authoritative SRDS FR-04 (PDF page 12) requires rider CNIC number upload. Document completion/review, input validation, private storage, 15-minute access and encryption/masking are specified on PDF pages 28–32 and 43. Section 4.1 (PDF page 31) requires quick API responses and stable concurrent operation qualitatively. Whole-document text inspection found no 800 ms, p95 or 1,000-user numerical requirement. Those numbers came from the engineering task and remain qualification targets; they are not waived or relabeled as passed at full scale.

## Latency investigation and optimization

The historical 2,318.40 ms aggregate p95 measured two operations only: approval queue RPC and signed-document-link issuance. It did not measure signup, image upload or document download. Queue p95 was 392.23 ms; signing p95 approximately 2,318 ms. The eight-iteration/two-user sample included initial requests and failed the 800 ms engineering target.

Numeric `Server-Timing` now measures Auth, document-authority RPC, Storage signing and handler duration, without identities, paths, tokens or links. The default Edge region was Singapore (`ap-southeast-1`), while the verified TEST database region is Tokyo (`ap-northeast-1`). The default eight-sign-request diagnostic had median HTTP duration 765.14 ms, authority stage 313.70 ms, signing stage 257.05 ms and handler 557.80 ms. Tokyo's corresponding medians were 407.80, 65.10, 58.20 and 133.05 ms. Read-only actual authorization SQL executed in 12.544 ms, supporting transport/region overhead rather than an unindexed-table bottleneck. No new index or migration was justified.

Initial requests additionally spent approximately 1.4–2.0 seconds outside the measured handler. Exact attribution to deployment scheduling, cold start or relay is **Assumption**; no platform boot trace was obtained. Both eight-iteration diagnostics still failed p95, and their results are preserved.

The client now prefers the verified database region and falls back to automatic routing only for transport/timeout/server failures, with unchanged JWT, payload and upload request ID. Authorization/validation/conflict failures are not retried. Two attempts share a 45-second budget. Auth confirmation, ownership checks, JWT verification, RLS and exact 900-second TTL remain enforced. [Official regional invocation guidance](https://supabase.com/docs/guides/functions/regional-invocation).

Expanded bounded diagnostic: **2 VUs, 40 iterations, 80 requests**, including initial requests; **0 errors**, aggregate p95 **577.85 ms**, queue **336.60 ms**, signing **665.41 ms**, exit 0. Signing median 402.96 ms; handler median 120.50 ms. This supports the safe optimization and passes only this small read measurement. It does not certify startup worst-case latency, signup/upload performance or 1,000 users. Evidence: `.fr21-local/fr04/load-timing-output.log`, `load-tokyo-timing-output.log`, `load-tokyo-40-output.log`, corresponding summary JSON, `timing-analysis.json`, `authority-explain.json`.

## Fresh-account email and device evidence

A fresh synthetic rider was created through actual Android signup using a controlled mailbox alias. Private credentials remain Windows-DPAPI protected outside Git; no raw CNIC was included in Auth metadata. Signup showed the confirmation-required message. Auth created at 10:39:30 AM Pakistan time and confirmed at 10:41:00 AM; the user explicitly confirmed receiving/opening the actual email link. No admin confirmation bypass or generated-link substitute was used.

After confirmation, Android login restored the encrypted signup draft. Hosted status was missing/pending before upload. Actual upload persisted the selected green synthetic document with exact decoded pixel equality and remained pending. The admin securely opened that exact application, approved it through the app, and subsequent password login reached Rider Dashboard. Hosted approved status, valid private document and encrypted CNIC were verified again on the final optimized APK. The pre-confirmation password-rejection probe was **NOT EXECUTED** because the user had already confirmed before it ran; its intermediate assertion is retained, not counted as a product defect or PASS.

Earlier actual device results remain valid: missing-number/image validation, invalid number, Camera/Gallery selection, interrupted replacement recovery, oversized/corrupt rejection after original-size fix, admin missing-document controls, customer masking, and real 930.8-second native viewer expiry followed by current-version Retry. Current optimized APK also rendered the authorized private document; no observed fatal, unhandled or AuthApiException logs. Evidence: `.fr21-local/fr04/device-evidence.jsonl`, `checks.jsonl`, `device-gallery-results.json`, `device-camera-results.json`, `viewer-before-expiry.png`, `viewer-after-expiry.png`, `viewer-after-retry.png`, `viewer-regional-final.png`, `customer-mask-final.png`. Images remain ignored.

## Final verification

- FR-04 hosted Auth/Storage/security: **49 PASS**, exit 0 after Edge version 6. `hosted-final.log`, `tests-results.json`.
- Rollback-only SQL: **50 PASS**, zero failures, exit 0. `sql-results.log`.
- Flutter: **33 PASS**, two conditional hosted tests skipped in ordinary suite; those **2 hosted tests separately PASS**, exit 0. `fr04-flutter-tests.log`, `fr21-flutter-hosted.log`, `build/fr21-hosted-evidence/flutter-hosted.log`.
- Scoped 12-file analysis: **0 diagnostics**, exit 0. `fr04-analysis-final.log`. Changed Dart formatting completed; previous successful dependency resolution preserved.
- FR-21 regression: final isolated run **46 PASS**, exit 0. An earlier run stopped after 19 passes due to a 60-second CLI subprocess transport timeout; unchanged isolated rerun passed. `fr21-regression-final.log`, `fr21-regression-transport-timeout.log`.
- Actual hosted 900-second expiry: previous **3 PASS**; native expiry/removal **3 PASS**, fresh native Retry **4 PASS**. TTL/security behavior did not change.
- Final optimized TEST APK built in 190.3 seconds, installed with Success, source matched all 84 Dart implementation files. **87 artifact/source/secret checks PASS**. TEST URL/public key present; production URL, service-role/Vault keys and fixture passwords absent.
- APK SHA-256 `a4fec5d13f71b22dfd9623b5fc8580be07090c402edbcb17937671328b1904a0`, 132,563,290 bytes. Path: `C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502/build/app/outputs/flutter-apk/app-fr21test-debug.apk`. `apk-manifest.json`, `artifact-results.json`, `fr04-android-build.log`.
- Read-only hosted history: nine matching versions ending `202610120001`; Edge **version 6, JWT ON**; existing private JPEG/PNG/5 MB bucket preserved. No hosted migration replay, reset, key rotation or production connection/write.

## Local scale qualification — NOT EXECUTED

Before this resume, WSL and Docker/Podman were absent and no local Supabase config existed. User approved local setup. Microsoft WSL **3.0.3** and the publisher-verified official Docker Desktop installer completed successfully. Winget first failed with `0x80072eff`; official download/signature-checked installation succeeded instead. Docker startup returned engine HTTP 500. WSL reported virtualization unavailable; elevated inspection confirmed Virtual Machine Platform Enabled with **RestartNeeded=true**. Windows was not automatically restarted.

Host: i5-8250U, four cores/eight threads, approximately 8 GB RAM; free RAM fell below 300 MB while building and starting Docker. The unused Docker process was stopped. No large load was attempted under that pressure. A restart and verified working runtime are required before the full stack/load can start. If WSL still reports virtualization unavailable after restart, firmware virtualization needs checking; it is not yet proven to be a BIOS-only problem.

An **unlinked**, ignored local project is prepared at `.fr21-local/fr04/local-stack`, with the authoritative source hash and eight reviewed migration hashes verified, plus the unchanged FR-04 migration. No local database/migrations/bucket/fixture initialization has executed. Hosted linking remains exact TEST. Local Auth's existing signup quota is preserved rather than weakened for throughput; a single-source signup ramp may hit that quota and must report actual rejection separately from hardware capacity. Full load script refuses hosted targets; Free TEST permits only bounded two-user read diagnostics. No paid dependency was introduced. [Microsoft WSL setup](https://learn.microsoft.com/en-us/windows/wsl/install), [Docker educational/free installation and requirements](https://docs.docker.com/desktop/setup/install/windows-install/).

Free hosted limits previously verified: 200 peak Realtime connections, 2 million monthly messages, 500 MB DB, 1 GB Storage and 500,000 monthly Edge invocations. **1,000 simultaneous Realtime clients exceed Free capacity** even if local HTTP testing later passes. Maximum-size 1,000 documents require about 5 GB before retained replacements. [Supabase pricing](https://supabase.com/pricing). Existing 45–55-second heartbeats imply approximately 1.57–1.92 million writes/day for 1,000 continuously online riders (arithmetic estimate).

## Changed/new files and commands

The FR-04 commit includes the existing signup/login/splash/admin/map/model integrations, new CNIC service/controller/screen/viewer, iOS permission descriptions, Edge function, unchanged applied migration, SQL/Flutter/hosted/device/k6 tests and FR-04 documentation. The exact staged paths and commit are checked separately before commit. Secrets, synthetic images, screenshots, installers, local configuration, logs and APK remain ignored/outside Git.

Executed: guarded TEST Edge deployments (timing/CORS only), read-only history/function listing and authorization EXPLAIN; FR-04 hosted/SQL suites; FR-21 backend/Flutter regressions; scoped formatting/analysis/Flutter tests/APK build; ADB install and actual synthetic signup/upload/review/login/private viewing; bounded k6 diagnostics; approved WSL/Docker installation and local config preparation. No root incomplete SQL script, db reset, blind push or production operation was executed.

## Files in the functional commit

- docs/analysis_report.md
- docs/FR-04-acceptance.md
- docs/FR-04-encryption-design.md
- docs/FR-04-readiness.md
- ios/Runner/Info.plist
- lib/controllers/admin_controller.dart
- lib/controllers/cnic_document_controller.dart
- lib/models/user_model.dart
- lib/screens/admin_dashboard.dart
- lib/screens/cnic_document_screen.dart
- lib/screens/login_screen.dart
- lib/screens/map_screen.dart
- lib/screens/signup_screen.dart
- lib/screens/splash_screen.dart
- lib/services/cnic_document.dart
- lib/widgets/cnic_document_viewer.dart
- supabase/functions/fr04-cnic/index.ts
- supabase/migrations/202610120001_fr04_cnic_document.sql
- supabase/tests/FR-04.sql
- test/cnic_document_test.dart
- tests/integration/FR-04-device.py
- tests/integration/FR-04-hosted.py
- tests/integration/FR-04-run.ps1
- tests/load/FR-04.js

Final history read initially received a Supabase pooler EAUTHQUERY secret-check timeout; a read-only retry returned all nine matching migrations. The failure is retained in migration-history-read-failure.log. No credential change, repair, reset or migration replay was used.
