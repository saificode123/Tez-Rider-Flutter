# FR-21 TEST readiness — 2026-10-12

**FR-21 ready for physical Android testing: hosted TEST verified and final TEST APK built and checked.** This replaces earlier audit-only readiness reports. Only TEST `igeisilhtmglgnqvllrx` was contacted. Production was never connected to or changed. Starting commit `a053567` and unrelated work were preserved.

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
