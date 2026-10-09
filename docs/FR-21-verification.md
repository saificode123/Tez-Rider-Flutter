# FR-21 verification — 2026-10-10

Implemented and tested locally. **Production migration NOT APPLIED.** Target
`arrqsvejrfdbacfwtpcc` matches the configured app URL and authenticated TezRider/main
Production dashboard. A real public-key Auth health request returned HTTP 200.
Deployment requires a private production connection, verified backup/restore and
explicit approval of `docs/FR-21-deployment.md`. The private connection was requested;
none was supplied. Ten existing rider profiles reference approved vendor accounts;
they remain unchanged and ineligible. No production database writes occurred.

## Status and evidence

1. **PASS — Code implementation:** UI → existing GetX controllers → presence service
   → confirmed PostgREST RPCs; actual bigint schema and user verification source.
2. **PASS — Dart/Flutter tests:** 16 tests; `flutter test` exit 0, `All tests passed!`.
3. **FAIL — Flutter analysis:** completed exit 1; 97 repository diagnostics, no errors.
   New change-related diagnostics were corrected; unrelated warnings/info remain.
4. **PASS — Isolated migration:** PostgreSQL 17.6 reconstructed production metadata;
   final migration applied twice successfully; 80 assertions passed, exit 0.
5. **PASS — Supabase connectivity:** verified project/public anon key role; real
   `GET /auth/v1/health` HTTP 200. Real user login/device Auth was not exercised.
6. **PASS — Production migration prepared:** one reviewed/version-controlled file,
   preflight SQL, scoped changes/recovery gates in `FR-21-deployment.md`.
7. **BLOCKED — Production migration applied:** no verified backup/restore or explicit
   production approval; Free dashboard has no project backups. Missing private DSN.
8. **PASS — RLS/security:** customer/vendor/rider/admin/anonymous, cross-owner writes,
   protected role/approval/fields, forged vendor ownership and admin signup denied.
9. **PASS — Heartbeat/stale presence:** confirmed persistence, duplicate/late writes,
   session epochs, startup restoration, 121-second exclusion, logout/background and
   network/authorization failure logic covered by SQL/Dart tests.
10. **PASS — Order-assignment integration:** actual status/notification triggers,
    fresh/approved/available filters, ready retry, OTP, completion/cancellation
    release; dblink proves duplicate waits, no double reservation, one assignment.
11. **PASS — Android APK:** final debug build exit 0, archive CRC/backend checked;
    `build/fr21-apk/TezRider-debug.apk`, 174,558,172 bytes (~166.47 MiB).
12. **NOT RUN — Physical device:** `adb devices` returned an empty device list.
13. **PASS — Load/concurrency:** k6 exit 0; ramp to 1,000 VUs, five-minute hold;
    20,152 requests, p95 10.743695 ms < 800; errors 101/20,152 = 0.50119% < 1%.
    Native local PostgreSQL/PostgREST, pool 10, shared_buffers 32 MB, work_mem 1 MB;
    no Flutter build/analyzer concurrently. Coverage: heartbeat and assignment RPCs.

The bootstrap emulates Auth JWT helpers and confirmed identities; it is a real
PostgreSQL/RLS/transaction test, not a full GoTrue/Realtime stack or restored
production clone. Hosted Auth, real device lifecycle and production Realtime remain
unverified. The dormant legacy RiderAssignmentController is not instantiated by a
screen; its obsolete schema references are documented, not enabled.

## Commands and real results

Flutter 3.47.6 / Dart 3.13.5, existing JDK 17.0.13, Android SDK/build-tools 36.
Flutter doctor exit 0: no issues; `flutter pub get` exit 0: dependencies resolved.
No pubspec dependency or repository Android configuration changes were required.
The installed Windows Flutter launcher had an invalid `$git` batch command; it was
backed up outside the repo and repaired to `git`. Its generated snapshot was missing
later, so commands used the existing Flutter source launcher, not a reinstall:

```powershell
& 'C:/Users/urreh/Downloads/flutter/bin/cache/dart-sdk/bin/dart.exe' --packages='C:/Users/urreh/Downloads/flutter/packages/flutter_tools/.dart_tool/package_config.json' 'C:/Users/urreh/Downloads/flutter/packages/flutter_tools/bin/flutter_tools.dart' test
```

Executed commands: `doctor -v`, `pub get`, `test`, `analyze`, `build apk --debug`.
`dart format` on the 15 changed/new Dart files passed (exit 0). Requested
`dart format .` also passed on the unsynced app/test source copy: 84 files, 64
formatted, exit 0; unrelated formatting was not copied back to the checkout.
The first copy attempt used a relative test path from the temporary directory and
failed; corrected absolute paths succeeded before formatting.
Initial full test run failed on the existing splash test: unused AuthController
lookup and stale branding assertions. Removed the unused dependency, guarded delayed
animations after disposal, and retained strengthened branding/navigation assertions;
final 16 tests passed. Initial analysis: 101 diagnostics; final: 97. One intermediate
analysis crashed under host memory pressure, then completed after releasing the
owned build processes; no diagnostic was hidden or suppressed.

First APK attempt in OneDrive failed to delete generated Gradle assets. The successful
build used an unsynced source copy at
`C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-build`; the final temporary Gradle heap
was capped at 2 GB/workers 2, without editing repository Android settings. Final build
reported `Built build/app/outputs/flutter-apk/app-debug.apk` (350.2s).
Package `com.example.flutter_application_1`, minimum Android SDK 24, target 36.
APK SHA-256: `7d5c43d1356b1a027880d3319241eb3f8cd1fca6d6d18ffa6dd3217a9f18802c`.

Local database: `127.0.0.1:55432/fr21_isolated_test`, never a hosted/live project.
Ran bootstrap, final migration twice and SQL suite with `ON_ERROR_STOP=1` and
`FR21_ISOLATED_TEST=true`. Ran committed race fixtures plus the suite with
`FR21_RACE_DSN`, rider/vendor UUID and two order IDs; three lock/race assertions passed.
SQL suite rolls back its data; committed race/load fixtures are only local dummy data.
Native portable PostgreSQL/PostgREST/k6 are official free tools stored outside Git.

```powershell
& 'C:/Users/urreh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tests/load/FR-21-local.py --psql 'C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/postgres17/pgsql/bin/psql.exe' --postgrest 'C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/postgrest/postgrest.exe' --k6 'C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/k6/k6-v2.0.0-windows-amd64/k6.exe' --pool-size 10
```

Actual paths used are under `C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools`:
`postgres17/pgsql/bin/psql.exe`, `postgrest/postgrest.exe`,
`k6/k6-v2.0.0-windows-amd64/k6.exe`; bundled Python executed the script.
The first benchmark passed (p95 108.6ms, errors 0.44%). A repeat concurrent with build
and analysis failed (exit 99, p95 6.31s, errors 8.36%); PostgreSQL logged out-of-memory,
DLL allocation and pool timeouts. A native REST startup attempt also failed before
readiness; retry succeeded. The final standalone run above passed after releasing
owned build processes and reducing local database/pool memory. This is not proof of
performance alongside development workloads or a production sizing guarantee.

Evidence (ignored): `build/fr21-evidence/{doctor,pub-get,format-final,
flutter-tests-final,analyze-final,sql-final,db-races-final,connectivity,apk-final,
apk-verification,apk-manifest,k6,k6-contended,postgrest}.txt` and k6 summary JSON.
No fixture JWTs, generated config, private keys, APK/build output or files >5 MB
are included in the FR-21 commit. Unrelated `.kilo/worktrees/fluttering-derby`
deletions observed during work were preserved and excluded from the commit.
User-provided AGENTS.md and SRDS PDF remain untracked and unchanged.

## Capacity and free-tier limits (checked 2026-10-10)

Free: 200 peak Realtime connections, 2 million messages/month, 500 MB database per
project, 500,000 Edge Function invocations/month.
[Official quotas](https://supabase.com/docs/guides/platform/billing-on-supabase).
Realtime also limits messages and joins to 100/second.
[Official Realtime limits](https://supabase.com/docs/guides/realtime/limits).
**1,000 connected app users do not fit hosted Free**: the known connection cap is
200; message/join bursts could exceed their limits sooner. One filtered channel per
dashboard reduces subscriptions, not connections. Free mitigation: cap connections
at 200 or self-host open-source Supabase on existing suitable hardware.
**Assumption:** such hardware/network can sustain the full app; the RPC benchmark
does not establish production Realtime/Auth or application-wide capacity.

Online-only 45–55-second jitter means ~20 heartbeat writes/second at 1,000 riders;
~51.84 million writes/30 days at mean 50 seconds. Updates reuse rows, but indexes,
vacuum, WAL and I/O still cost resources. No new rider heartbeat Realtime subscription
was added; any other subscribers can still receive changes. FR-21 uses PostgREST
RPCs and consumes no Edge Function invocations. Stored online intent can remain
true after a crash; server eligibility always requires freshness within two minutes.

## Device checklist (NOT RUN; after approved deployment)

Install with USB debugging enabled:

```powershell
& 'C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe' install -r 'C:/Users/urreh/OneDrive - Punjab Group of Colleges/Documents/Fall 2026/Project/FYP_Final2_Backup (2)/FYP_Final2_Backup/build/fr21-apk/TezRider-debug.apk'
```

1. Sign in as a confirmed, approved rider: actual DB role opens rider dashboard;
   own missing rider profile is provisioned; enable GPS to save real coordinates.
2. Toggle online: pending disables double taps, confirmed DB is_online=true and
   server last_seen advances; rapid taps produce no contradictory writes.
3. Wait 55 seconds: last_seen advances; toggle offline: false persists and no more
   heartbeat timestamps advance while offline.
4. Restart after online/offline: toggle restores confirmed DB state; after a normal
   background/close cleanup it restores offline when that write succeeded.
5. Force-stop online; wait over 120 seconds: vendor retry cannot select that rider,
   even when stored is_online remains true. Reopen stale: restores offline.
6. Disconnect network during toggle/heartbeat: clear error, reverted/disabled state;
   reconnect and Retry reconciles DB state, without simulated success.
7. Logout online and expire a session: best-effort false before sign-out; denied or
   offline requests stop heartbeats, with server freshness bounding crash cases.
8. Sign in with pending/rejected rider and attempt protected/other-rider updates
   using approved disposable test accounts: approval screen/permission denial;
   other fields/owners and role/self-approval edits remain unchanged.
9. Approved vendor readies a real accepted order: one fresh approved available
   rider receives it; retry/double tap keeps one assignment/notification. With no
   rider, ready persists and Retry matching becomes available.
10. Verify correct/incorrect OTP and cancel a reserved test order: wrong OTP keeps
   reservation; confirmed delivery or authorized cancellation releases both flags;
   vendor lists refresh, and unassigned ready orders can be matched later.

## Changed/new files

```text
docs/FR-21-deployment.md
docs/FR-21-production-audit.md
docs/FR-21-verification.md
docs/analysis_report.md
lib/controllers/rider_controller.dart
lib/controllers/vendor_controller.dart
lib/main.dart
lib/screens/login_screen.dart
lib/screens/rider_dashboard.dart
lib/screens/signup_screen.dart
lib/screens/splash_screen.dart
lib/screens/vendor_dashboard.dart
lib/services/account_access.dart
lib/services/backend_config.dart
lib/services/rider_presence.dart
supabase/inspection/FR-21-current.sql
supabase/inspection/FR-21-preflight.sql
supabase/migrations/202610090001_fr21_presence.sql
supabase/tests/FR-21-bootstrap.sql
supabase/tests/FR-21-race-fixtures.sql
supabase/tests/FR-21.sql
test/account_access_test.dart
test/backend_config_test.dart
test/rider_presence_test.dart
test/widget_test.dart
tests/load/FR-21-local.py
tests/load/FR-21.js
```
