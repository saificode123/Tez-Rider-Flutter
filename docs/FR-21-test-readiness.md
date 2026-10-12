# FR-21 TEST readiness — 2026-10-12

**FR-21 ACCEPTED — Implementation and verification complete. Ready to proceed to the next functional requirement.** Final acceptance and evidence: [FR-21-acceptance.md](FR-21-acceptance.md). The final acceptance supersedes all earlier pending/device/build status statements below; they remain as historical records. This replaces earlier audit-only readiness reports. Only TEST `igeisilhtmglgnqvllrx` was contacted. Production was never connected to or changed. Starting commit `a053567` and unrelated work were preserved.

## Actual database results

The record-free 95,674-byte schema export was restored through a secured baseline. All 40 application tables exist; all have RLS; required FR-21 functions exist; client TRUNCATE grants are absent. Applied versions in order:

1. `202610080001`: authoritative baseline with client permissions contained inside the restore transaction.
2. `202610090001`: presence leases, heartbeat, expiry, locking and assignment authorization.
3. `202610110001`: reviewed TEST ownership grants, contacts projection and five Realtime tables.
4. `202610110002`: real dashboard aggregates and vendor transition validation.
5. `202610110003`: prompt HTTP 409 for stale presence sessions.
6. `202610110004`: atomic, idempotent OTP delivery receipt.
7. `202610110005`: ready state when no eligible rider; retry emits an assignment transition.
8. `202610110006`: shared-parent vendor privacy and transactional acceptance/delivery propagation.

Each addition was reviewed, locally validated, previewed and applied after rechecking the exact TEST reference. Migration listing confirms all eight versions match local/remote. No reset, repair, production-specific data migration or incomplete root SQL script was run. Hashes: `supabase/test-environment/FR-21-reviewed-manifest.json`.

Executed results:

- Hosted rollback-only SQL: **81 presence/business assertions and 306 security assertions passed**. Roles include anonymous, customer, vendor, approved/unapproved rider and administrator.
- Hosted Auth/REST/Realtime: **46 checks passed**, including two competing assignments, 16 duplicate requests, stale-session conflict, row privacy, heartbeat/expiry/restoration, cancellation release and delivery receipt/status consistency.
- Actual Flutter Supabase client/presence integration: **2 tests passed**, with private synthetic credentials.
- Final full Flutter suite: **18 passed; 2 hosted tests skipped by default; exit 0**. Both conditional hosted tests passed in their separate real-backend run.
- `flutter pub get` and `flutter doctor -v`: succeeded; Android SDK/JDK/license checks passed.
- Local k6 against the full secured schema: **1,000 VUs; 20,128 requests; p95 15.97 ms; errors 0.477%; exit 0**. Both requested thresholds passed. **96 transport failures, zero HTTP errors** remain recorded. This localhost PostgreSQL/PostgREST benchmark does not establish hosted 1,000-connection Realtime capacity.
- Full formatting check executed but failed on Windows long generated-build paths. A read-only source fallback found 143 legacy files needing formatting; only changed FR-21 Dart files were formatted.

Evidence is retained in ignored `build/fr21-hosted-evidence/`: final behavior/security/schema/environment JSON, migration history, integration.json, Flutter/build logs and load/k6-summary.json. Keys and login credentials are outside Git; no service-role key is passed to Flutter.

## Frontend and synthetic device data

Existing GetX controllers/presence service are reused. Persisted/restored presence is server timestamped, debounced, single-flight and reconciled after errors. Approximately 45–55-second heartbeats and two-minute expiry remain. Assignment uses transactions, row locks and idempotent retries. Dashboards use bounded projections, real aggregate RPCs, one filtered channel each, throttled refresh, reconnect/error states and cleanup. Delivery no longer ignores a failed client receipt write.

Seven synthetic accounts: approved rider, second approved rider, pending rider, customer, vendor, other vendor and administrator. Private login details: `%LOCALAPPDATA%\TezRider-FR21\device-accounts.txt`, protected for the current Windows user. A synthetic product/order/item fixture is ready; manual order IDs are in `build/fr21-hosted-evidence/integration.json`. No production records/passwords/tokens were copied.

Separate Android flavor `fr21test`: suffix `.fr21test`, label **TezRider TEST**, TEST banner and explicit TEST URL/public key. Default startup has no embedded production endpoint/key and fails closed without a client key. Isolated configuration rejects other hosted projects and mismatched JWT project references. Public defines are in ignored `build/fr21-public-defines.json`.

## Limits and remaining verification

Physical-device installation/runtime: **Not executed; no Android phone connected**. See `FR-21-android-testing.md`.

The complete public schema exists, but unrelated whole-app workflows are not certified. Unreviewed chat, prescription, payment, review and admin mutations remain denied. Authoritative private Storage bucket/access policies and signup email delivery configuration were not supplied. Storage remains empty; confirmed synthetic password logins work. Presence/assignment/OTP receipt needs no bucket; document/image uploads remain unverified. Dormant broken legacy functions remain client-inaccessible. See `FR-21-schema-validation.md`.

Supabase Free does **not** fit 1,000 simultaneous Realtime users: **200 concurrent connections, 100 messages/second, 2 million messages/month, 500 MB database, 500,000 Edge Function invocations/month**. The connection cap is the first known hard limit for 1,000 connected dashboards; join/message bursts can fail earlier. Free mitigation: limit simultaneous live sessions to 200 or self-host the open-source stack on existing hardware. **Assumption:** available self-host hardware can support this load; unverified. No polling workaround or paid dependency was added. [Realtime limits](https://supabase.com/docs/guides/realtime/limits), [pricing](https://supabase.com/pricing), [function pricing](https://supabase.com/docs/guides/functions/pricing).

A mean 50-second heartbeat for 1,000 riders causes approximately **72,000 writes/hour; 1.728 million/day**, excluding startup/toggle/location writes. Riders are not published to Realtime, preventing heartbeat row-message fanout; database WAL/vacuum/CPU costs still apply. FR-21 uses no Edge Functions.

## Commands actually executed

The installed CLI path is `C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe`. Every remote write explicitly used TEST and immediately checked the linked reference. Reviewed initialization is already applied; do not reset or repeat it.

```powershell
if ((Get-Content supabase/.temp/project-ref -Raw).Trim() -cne 'igeisilhtmglgnqvllrx') { throw 'Wrong target' }
./supabase/test-environment/prepare.ps1
supabase db push --linked --project-ref igeisilhtmglgnqvllrx --dry-run
# After reviewing the pending migration list and rechecking the link:
supabase db push --linked --project-ref igeisilhtmglgnqvllrx --yes
supabase migration list --linked --project-ref igeisilhtmglgnqvllrx
supabase db query --linked --project-ref igeisilhtmglgnqvllrx --file build/fr21-reviewed-plan/FR-21-hosted-transaction.sql --output json
supabase db query --linked --project-ref igeisilhtmglgnqvllrx --file supabase/tests/FR-21-test-security.sql --output json
supabase db query --linked --project-ref igeisilhtmglgnqvllrx --file supabase/inspection/FR-21-schema-contract.sql --output json
supabase db query --linked --project-ref igeisilhtmglgnqvllrx --file supabase/inspection/FR-21-test-environment.sql --output json
./tests/integration/FR-21-run.ps1 -Kind backend
./tests/integration/FR-21-run.ps1 -Kind flutter
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --flavor fr21test --dart-define-from-file=build/fr21-public-defines.json
```

Flutter commands used the installed Dart source launcher because the shell wrapper was not suitable in this environment. Local load used `tests/load/FR-21-local.py --database fr21_secure_validation --pool-size 10 --output-directory build/fr21-hosted-evidence/load` plus explicit installed psql/PostgREST/k6 paths. No hosted load test ran.

## Final Flutter and Auth checks

Final `flutter test --no-pub`: **18 passed, 2 conditional hosted tests skipped; exit 0**. The separate private hosted Flutter run passed both skipped tests. Full analysis: **105 diagnostics, no errors; exit 1** (17 warnings and 88 infos). These are existing unused legacy fields, deprecated APIs and print lint findings; FR-21 target analysis is recorded separately. Unrelated sources were not changed to silence them.

Public TEST Auth settings verified read-only: email enabled, phone/OAuth/anonymous disabled, signup enabled, email autoconfirm disabled. Synthetic fixtures were explicitly confirmed through authorized TEST administration. Real email delivery/signup remains unverified.

The final incremental build initially failed at cleanMergeFr21testDebugAssets (Windows could not remove a long generated asset directory). That output was preserved under ignored build/fr21-stale-assets; retry uses temporary T: mapping of this same repository, not a copied project. No source or database reset was used.

Focused analysis of changed FR-21 controllers, dashboard, backend config and tests: **No issues found, exit 0**. Changed Dart formatting check: **7 files, 0 changes, exit 0**. Export/baseline whitespace is preserved to protect provenance/applied hashes; all other staged files pass whitespace checks. .gitattributes disables SQL newline conversion to preserve exact source and applied-migration hashes on Windows.

## Final Android result

**Final build succeeded, exit 0.** Delivered APK: `build/fr21-apk/TezRider-FR21-Test-debug.apk`; 174,557,548 bytes (approximately 166.5 MiB, debug/universal build). SHA256 `40be279d8a767bd644765a3c8f7cd1a2417534d171df10e097ba07b3e5cfe2b7`.

Verified ZIP CRC, compiled exact TEST URL/public anon key, TEST JWT reference/role, no production reference or encoded production JWT, no service-role/secret key/privileged JWT, and no private fixture passwords. Android metadata confirms package `com.example.flutter_application_1.fr21test`, label `TezRider TEST`, launch activity `com.example.flutter_application_1.MainActivity`, INTERNET permission, minimum API **24 (Android 7.0)** and target API 36.

Three final rebuild attempts failed on read-only generated OneDrive directories (assets, AAR metadata, plugin shaders). Previous generated outputs were preserved, not deleted. Clearing ReadOnly on 3,102 generated directories allowed the final build to complete; Kotlin's cross-drive incremental-cache diagnostic recovered through its fallback. No application dependencies or SDK versions were upgraded. Existing AGP/Kotlin future-support warnings remain. Evidence: apk-final-retry.log, apk-verification.json and apk-badging.log. Native compilation finished successfully; no warning is reported as a clean warning-free build.

The latest adb device check still shows no connected phone. Installation, GPS/lifecycle and visible UI checks on a physical device: **Not executed**. The owned local PostgreSQL test server was shut down after testing; its data/evidence were preserved. Credentials remain outside Git with no broad Users/Everyone permission.

## Auth/mobile follow-up — 2026-10-12

Supersedes the earlier APK/device status only: `.fr21-local/TezRider-FR21-Test-debug.apk` is the latest arm64 debug build (101,303,203 bytes), SHA256 `c2732d71e788bfb8d5eb6c41f2bff2afa5b7f6659606f1b5770c5eeee3193da5`. Installed successfully on the connected phone. Actual saved TEST session and visible approved Rider Dashboard verified after password sign-in; native Auth callback also verified. Full physical FR-21 scenario acceptance still requires the manual checklist.

Fixed own-profile login recovery: use authenticated canonical email and an INSERT instead of a protected email/role upsert, with duplicate recovery and real error propagation. Preserved the user's existing error-display edit. TEST-only callback manifest added. Auth Site URL/allowlist changed from localhost to `tezrider-fr21-test://login-callback/`; email verification remains enabled. No production settings touched, no approval bypass and no additional SQL migration. Synthetic approved-rider credentials synchronized privately; the user-provided value now authenticates. Personal password unchanged; personal email was already confirmed.

Executed: hosted Auth permission regression (three assertions passed), real signed callback/server redirect and device Auth validation, Flutter tests (18 passed/2 conditional skips), changed login formatting (0 changes), login analysis (one existing user-edit info, no errors), final debug build, adb install -r, native callback resolution, APK CRC/backend/credential scan. Original workspace build failed because generated Windows plugin links were inaccessible after its build directory was cleared. Built an exact temporary copy outside OneDrive using the existing SDK; no source reset or dependency upgrade. Final app source includes the user's error-display edit.

Some prior build logs/APKs were removed when the original build directory was cleared. Historical test claims remain actual recorded runs; do not treat their now-missing local files as currently available evidence. Current safe evidence is retained in ignored `.fr21-local/`: APK, public defines, Auth redirect/callback results, APK verification and current Flutter analysis/test/build logs. Private keys/passwords/tokens are absent from those logs. The standalone PostgreSQL 17 executable was unavailable for this follow-up; no new local SQL run is claimed or required since SQL was unchanged.

## Physical-device verification in progress — 2026-10-12

Device: AESWNRBAEUPNTGJZ. Dedicated TEST reference was checked by the runner before every remote operation. Production was not accessed. Existing changes preserved.

Confirmed defect and fix: splash previously always routed saved sessions to Customer login. Startup now verifies the saved identity and own approved rider profile server-side, then opens RiderDashboard and restores presence. Other startup roles retain their existing login behavior. Corrected TEST APK built successfully (327.0s), passed ZIP/backend/public-key/privileged-credential checks and installed with app data preserved. Latest SHA256: 34feaaeff5fac97e146682a94f076daf487fd5ca4e52b789a3c3ffeea2d1d332. Artifact: .fr21-local/TezRider-FR21-Test-debug.apk.

Verified physical evidence:
- Online and Offline writes matched dashboard and hosted riders row.
- Foreground heartbeat advanced last_seen from 09:16:52 to 09:17:38 UTC; later phone heartbeat sequences continued advancing.
- Fresh Online restored after abrupt restart: epoch 25 became 26 and UI/server were Online. Offline restored after restart at epoch 27; floating app bar was recovered by scrolling to the top.
- With phone network disconnected, heartbeat stopped, UI showed Offline/connection error/Retry and last_seen became older than two minutes while stored is_online remained true. Effective availability was false.
- A synthetic assignment while physically stale selected no rider (order 17/vendor order 21). Reconnection plus Retry restored Offline; explicit Online made the rider eligible again.
- Synthetic order 18/vendor order 22 assigned to the phone rider. Android received Active Delivery and Order #18 through Realtime without restart/manual refresh. Initial exact-label probe missed merged semantics; corrected probe and screenshot confirmed the card. Authorized synthetic-customer cancellation removed the card and released both availability flags through Realtime.
- Rapid double taps left a stable Offline result. Exact request count is not independently captured; automated debounce/idempotency checks are the stronger evidence.
- Current TEST process log probes reported zero fatal/unhandled exceptions, AuthException/invalid-login/expired-JWT mentions, and PostgrestException/SocketException/HandshakeException mentions. This is scoped to captured process logs, not a guarantee about all historical Android logs.

Executed automated checks: hosted integration 46 passed/0 failed (authorization, stale exclusion, concurrent reservation, duplicate assignment, Realtime and delivery integrity); splash analysis no issues; Flutter tests 18 passed/2 conditional hosted skips. First Flutter run failed because the existing splash widget test had not initialized Supabase; test setup was updated and the suite passed. Formatting splash: zero changes. No new database migration required.

NOT COMPLETE: the session was interrupted during the failed-write rollback repeat. An earlier offline read encountered an expired saved access token, so that read was not counted as proof of UI rollback; after connectivity returned, a valid refreshed session was verified. Failed-write rollback and isolated force-stop expiry still require final device verification. Full FR-21 acceptance must not be marked passed yet. Latest interrupted network test ended with original Wi-Fi and mobile-data settings restored at 10:12:31 UTC. No TEST reset, real data creation, production connection, push or merge.

Evidence: ignored .fr21-local/device-evidence.jsonl and apk-verification.json; current build/test/analysis logs in the existing private temporary Android build directory. Reusable synthetic-only probes: tests/integration/FR-21-device.py, via tests/integration/FR-21-run.ps1 -Kind device -DeviceAction status. Probe actions can operate the TEST app, restore original network settings, and create/cancel only guarded synthetic fixtures. Private keys/tokens/passwords are never written to evidence.

## Final acceptance closure — 2026-10-12

Both remaining mandatory device tests passed: isolated rejected presence update with unchanged persisted state and real Offline UI rollback/error/Retry recovery; physical ADB force-stop with unchanged stored Online heartbeat, expiry after173.91s, no final Offline write, no rider assigned to order19, reopening Offline, and heartbeat/Realtime renewal after explicit Online. Final post-regression order25 had exactly one assignment and appeared through Android Realtime; cancellation and HOME-background Offline were verified. Phone remains synchronized Offline with valid Auth and original network settings.

Final regressions: hosted46/0, general Flutter18 passed/2 conditional skips, hosted Flutter2/0, scoped analysis no issues/exit0, Python probes compile, final TEST-process logs0 observed crash/auth/API errors. All8 migrations match; none reapplied. Installed APK hash matches34feaaeff5fac97e146682a94f076daf487fd5ca4e52b789a3c3ffeea2d1d332 and103 source/config/asset files match its build copy. No application-source change during final acceptance; no rebuild needed. Intermediate harness failures are recorded in the acceptance report and corrected, not hidden.

Durable sanitized evidence is now in docs/evidence/FR-21-* and the criterion-by-criterion table is docs/FR-21-acceptance.md. Protected test credentials remain outside Git. Production was never connected to or changed. No reset, unrelated feature change, push or merge.