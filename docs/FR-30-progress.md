# FR-30 progress

Branch: `feature/FR-30-admin-broadcasts`; starting commit: `fa29b4c`.
Accepted ancestors verified: FR21 1173736, FR04 fd478a4, FR25 281c8a8,
FR26 aabd6ca, FR33 ec1c63b, FR28 7e809fd, FR20 fa29b4c.
Unrelated `.gitignore` edits preserved. Production is prohibited.

## Architecture (before migration)
1. Choose A: one UUID broadcast and set-based existing notifications per recipient.
2. Existing owner RLS, bigint cursor, unread count and read updates remain intact.
3. Notification rows form the immutable send-time recipient snapshot.
4. New users/role joiners receive no historical deliveries; existing recipients retain theirs.
5. FR28 prevents blocked recipients reading; blocked users at send time are excluded.
6. A shared design still needs recipient mappings and changes all FR31 queries/read state.
7. Its smaller payload storage does not justify that extra authorization and pagination surface here.
8. A uses N notification writes/events plus one broadcast and one audit; no per-user RPC.
9. One own-user Realtime channel/session remains a hint; refresh on subscribe/resume.
10. Atomic commit confirms database acceptance, never device receipt or OS push.
11. Indexed unread counts/history and configurable rate limits bound ordinary use.
12. Free-tier database/Realtime quotas limit large audiences; capacity requires measured evidence.

## Initial inspection
Existing FR31 list/read/count/channel and FR28 canonical session gates are reusable.
Missing composer, broadcast history, trusted broadcast RPC, limits and UUID deduplication.
Audit target_id is bigint: retain it using a unique internal broadcast audit number plus UUID FK.
No messaging dependency, token registration or push sender; legacy Firebase config is insufficient.
SRDS PDF pp9/16/22/28/31/32 requires broadcasts, push, RLS, audit and confirmation.
Remaining: Stage A database/tests; B Flutter/tests; C TEST deployment/regressions;
D native verification/load/acceptance. Push infrastructure requires explicit approval.

## Stage A checkpoint
Created migration `202610150004_fr30_admin_broadcasts.sql`, `supabase/tests/FR-30.sql`
and guarded FR30 TEST runners. Reviewed migration with 64 passing SQL assertions in
a rollback-only TEST transaction: no migration applied or notification committed.
Verified 27 accepted migration versions and notifications Realtime publication.
Synthetic customer/vendor cohorts are safe; one unmarked rider prohibits committed
ALL/RIDERS tests. Authorization/RLS, limits, snapshot, audit and sequential replay pass;
genuine concurrent requests remain pending. Flutter dependencies resolved successfully.
Branch `feature/FR-30-admin-broadcasts`, HEAD `fa29b4c`; no production changes.
Next: Flutter checks, then reviewed TEST deployment and genuine concurrent requests.

## Stage B checkpoint
Added injectable broadcast backend/GetX controller/composer/history and admin dashboard
entry. Existing notifications show a broadcast label; subscribe/resume refreshes are
authoritative and reuse the single existing channel. Timeout retries retain the UUID
and original payload; confirmation and loading prevent duplicate taps.
`pub get` succeeded; changed Dart files formatted. New controller/composer tests: 10 PASS.
Whole Flutter suite: 122 PASS, 2 inherited conditional skips in existing build mirror.
Initial OneDrive run had a cache-copy error; sequential mirror rerun exited zero.
Whole analyzer: 0 errors, 16 inherited warnings, 86 inherited infos; no new FR30 findings.
SQL migration review rerun: 65 PASS, fully rolled back, still not deployed.
Branch `feature/FR-30-admin-broadcasts`, HEAD `fa29b4c`; `.gitignore` preserved.
Next: apply only reviewed FR30 migration to TEST, then hosted/security/concurrency/regressions.

## Stage C deployment checkpoint (regressions in progress)
Applied only `202610150004` to TEST; history exactly matches all 28 repository versions.
Hosted SQL: 65 PASS (rollback-only). Bounded HTTP/security: 25 PASS, including four
simultaneous same-key calls (one SENT/three ALREADY_SENT) and two different-key
calls (one SENT/one COOLDOWN). No unrelated users targeted.
Actual two-session Realtime: recipient received one insert; unauthorized user zero (3 PASS).
FR04 regression: 49 PASS. Other requested regressions running. FR21 initial race
assertion failed; sanitized diagnostic rerun underway, no accepted logic weakened.
Fresh TEST APK built, source matches all 99 Dart files, endpoint/package/credential
guards pass; installed on authorized phone. Native verification ongoing.
Separate unlinked local FR30 stack initializing for SQL/load tests; no hosted load.
Branch `feature/FR-30-admin-broadcasts`, HEAD `fa29b4c`; production untouched.

## Stage C regression checkpoint
All seven suites passed: FR21 47 (original assertions with fresh GPS/ready secondary
line fixture adaptation), FR04 49, FR25 83, FR26 95, FR33 39 (zero real emails),
FR28 74, FR20 70. Initial FR21 stale GPS fixture and FR33 transport timeout are
retained as failed attempts; successful reruns are the acceptance evidence.
Added migration `202610150005_fr30_sender_lock.sql`: serialize sender with NO KEY
UPDATE so concurrent ALL recipient foreign keys do not conflict across admins.
Its rollback TEST review passed 65 assertions; local applied tests passed 65 and
two real simultaneous ALL sends both committed (no deadlock).
TEST deployment retry ongoing after CLI login-password conflict during concurrent
remote CLI work; verify history before any further apply. Never replay 004.
Final Flutter suite: 123 PASS / 2 inherited skips. Final TEST APK built; installing.
Native initial composer/audience/estimate/confirmation/cancel/send/history passed.
Remaining: final APK recipient/read/reconnect checks, final DB guards, acceptance,
secrets scan and commit. Native push approval remains mandatory.
Branch `feature/FR-30-admin-broadcasts`, HEAD `fa29b4c`; unrelated changes preserved.

## Stage C complete / Stage D checkpoint
005 deployed successfully after remote CLI jobs finished. All 29 accepted/new
versions match; final audit verifies zero count/audit mismatches, zero duplicate
recipient rows, zero unmarked recipients, fixed search paths and denied client forgery.
Final scoped Dart analysis: no issues. Final suite 123 PASS / 2 conditional skips.
Final APK SHA256 `21143201bfc0f0db1e607832785ab72c737114808af3a1689494c62102bb6185`,
205955455 bytes; all 99 Dart source files match build mirror; TEST endpoint/package
and credential guards pass. Installed with data preserved on AESWNRBAEUPNTGJZ.
Final APK native customer broadcast+personal list, badge 2, mark-all → badge0,
offline/background send to 13 synthetic customers (blocked+other-role excluded),
restore network/resume → badge1, actual notice, individual read → badge0 all PASS.
Android error summary: fatal/unhandled/Auth/API all zero.
Initial local 10 VU load: 771 HTTP requests, p95 17.17ms, zero unexpected errors,
one 1000-recipient broadcast/one audit/no duplicate recipients. Full 1000 VU run
NOT EXECUTED: 753561600 available bytes < 1GiB safety preflight. Separate latency
metrics being collected on a bounded rerun; no hosted high load or real messages.
Remaining: final native vendor/double-tap checks, documentation, scan and commit.
Push remains unimplemented pending explicit approval; concrete proposal documented
in `FR-30-push-decision.md`, including iOS APNs/zero-cost dependency.
Branch `feature/FR-30-admin-broadcasts`, HEAD `fa29b4c`; production untouched.


## Stage D final navigation correction
Physical vendor sign-in revealed VendorDashboard has neither AppDrawer nor a
notification action. Added one AppBar Notifications button routing to the existing
screen; no notification business logic duplicated. Final suite/build rerunning for
this required FR31 integration; earlier APK hashes are historical until final scan.
Native final confirmation double tap returned9 vendor recipients; eight backend
persistence checks prove one broadcast/audit, role isolation and native read states.
Synthetic blocked fixture restored; final database audit still passes29 versions.
Separate local per-operation latency rerun hit the256MiB host-memory guard at
170811392 bytes. Its stale pre-existing summary is explicitly excluded; load helper
now uses unique run summaries and never imports metrics after resource abort.
Initial successful10 VU/1000-recipient evidence retained separately. Latest full
1000 VU preflight:321413120 available bytes <1GiB; NOT EXECUTED.
Owned FR30 local containers stopped with volumes preserved. No hosted load.

## Stage D complete — authorized in-app scope
Final vendor navigation correction passed full123 tests/2 inherited skips and final
whole analysis0 errors/16 inherited warnings/86 inherited infos (no new findings).
Final APK SHA256 `e2c8ad739869e486a33e9bf873bdc77cda80e0197751f29686a34d5228983c93`,
205955532 bytes,99 matching Dart source files, TEST package/endpoint/credential guards
passed. Installed; refreshed synthetic vendor login after session restoration routed
to login. Observed vendor Notifications action, actual targeted broadcast, and zero
fatal/unhandled/Auth/API errors. Physical double tap and8 persisted backend checks
confirmed one vendor broadcast/audit and customer/vendor isolation.
Actual timestamp/UUID history cursor passed3 checks over4 pages (six rows), no drops
or duplicates. Final29-version DB verification and restored fixture passed.
Acceptance, push proposal and sanitized evidence prepared. All safe in-app work is
complete; native OS push remains NOT IMPLEMENTED pending explicit infrastructure
approval; full1000 VU qualification NOT EXECUTED due measured RAM limits.
Final review/security scan and feature-only commit next; no Git push or merge.
Branch `feature/FR-30-admin-broadcasts`, HEAD `fa29b4c`; unrelated `.gitignore` preserved.

## Finalization checkpoint
All authorized in-app checks passed. Final candidate manifest:38 FR30 files.
Secret/artifact scan found zero credential matches or unexpected files over5MB.
Acceptance status remains partial solely for mandatory native push approval and
verification; performance qualification separately records RAM-blocked full1000 VUs
and aborted per-operation rerun. Initial successful local10 VU evidence retained.
No paid infrastructure, production modification, Git push or merge. All original
accepted commits remain ancestors. Preparing the requested feature-only commit;
HEAD before commit `fa29b4c`, branch `feature/FR-30-admin-broadcasts`.
