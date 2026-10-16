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

## Android TEST push approval and implementation checkpoint
User explicitly approved Android TEST FCM. In-app implementation was committed as
`ddc8a54`; branch remains `feature/FR-30-admin-broadcasts`. New migration006,
server sender, Android lifecycle and guarded notification rendering are in progress;
none is deployed or physically verified yet. Dispatch defaults disabled.
Package resolution completed; new code checks remain pending. Firebase TEST client
configuration and dedicated server credential paths requested; browser access is
unavailable. No credentials invented or exposed. iOS remains unresolved.
Background rendering uses an encrypted random device capability scoped server-side
to one existing unread snapshot delivery, live Auth session and one-hour job.
Normal FR31 JWT/RLS authorization is preserved. No production access or Git push.

## Firebase files supplied — secure TEST configuration
User provided external client/server paths and authorized continuing, with no new
commit until mandatory acceptance checks pass. Both files exist and match TEST
package; verified actual Firebase project ID is `tez-rider-fe12b` (display name
`tez-rider`). Service credential shape and real Google OAuth authorization passed;
no private credential or OAuth token was printed. New flavor `.gitignore` excludes
the copied TEST client JSON. Server account remains outside repository; Edge TEST
secrets and Vault worker key configured using temporary external files, then erased.
Worker redeployed with exact project ID; `android_push_enabled` remains false.
Migration006 applied once (30 versions); SQL45 push and65 in-app checks pass in
rollback, final audit/recipient/grant integrity verified. Flutter131 pass/2 skips;
Node worker4 tests pass. Configured APK, proper lint configuration, Deno checks,
updated seven-feature regressions and physical foreground/background/termination
remain in progress. Authorized device reconnected and detected. No Git push/merge.

## Live Android push verified; final safety rerun
Real foreground/background/normal-terminated deliveries passed with exact OS title
and body, one notification tag, and independent in-app evidence. Termination
precondition proved process absent and package not force-stopped. OEM shade did
not yield an idle accessibility tree; observed screenshot taps expanded the TEST
group and selected its terminated notification. Existing cold-start customer
sign-in remains required; pending route opened the correct list after authentication.
No unrelated notification contents were exported as evidence. Read-all/badge0
passed. Logout removed registration and OS notices; signed-out broadcast produced
zero jobs/provider calls/OS notices. Private snapshot jobs remain immutable.
Review found a cross-isolate logout/platform-post race: final code rechecks the
encrypted session credential after the OS post and withdraws a stale notice.
Four focused race tests added; full Flutter135 passed/2 inherited skips. Final
whole-workspace analyzer:0 errors/16 inherited warnings/86 inherited infos,
zero new push findings. Deno2.9.7 official checksum verified, entry-point check and
four sender/security tests passed; formatted worker redeployed to TEST.
Seven regression reruns passed:47/49/83/95/39/74/70, zero real emails.
Final APK `ad2676f55ba055c20b95ed6bc33fbbe0d2403b8c3183fd8586e82ee53ea680e7`,
206306517 bytes,101 matching Dart sources; protected source/APK scans0 matches.
Installed final APK; foreground-final OS check passed. Final background/termination,
blocked fixture exclusion/restoration and final evidence/security review in progress.
No new commit before remaining mandatory acceptance checks; no push/merge.

## Android TEST acceptance complete
Final race-fixed APK passed foreground/background/normal-terminated OS receipt,
each exact title/body and one notification tag. Final physical list omitted the
blocked-time broadcast after unblock; mark-all and badge0 passed. Intentional
block removed registration, denied sign-in and produced0 jobs/provider calls/OS
notices; fixture restored and exactly one current installation re-registered.
Nine persisted real scenarios passed snapshot count/targeting, trusted single audit
and exact job/provider-state checks. Final30-version integrity check passed with
zero mismatches/unmarked recipients/client forgery. No migration repeated.

Runtime investigation: final customer startup logs one inherited
`VendorInfoController/get_vendor_ratings`42501. Baseline migration202610080001
revokes public-function access and this unchanged caller logs its denial. The
exact sanitized context was captured after earlier Android log rotation made
classification difficult. No ratings authorization/source was modified or error
hidden. FR30 errors0; fatal/unhandled/Auth0. Controlled negative capture also
recorded0 matching errors. This inherited non-FR30 limitation is explicit in
acceptance/evidence; no claim that the entire application's API logs are clean.

Acceptance: FR30 functionally accepted for explicitly authorized Android TEST.
iOS/APNs remains a separate unverified platform dependency; full1000 VUs remain
NOT EXECUTED. Updated sanitized evidence includes actual final APK, SQL45, Deno4,
Flutter135/2 skips, seven regression counts and nine live scenarios. Final source
review, credential scan and feature-only follow-up commit next. Branch unchanged,
HEAD `ddc8a54`; root `.gitignore` preserved; no Git push/merge.

## Final review and commit checkpoint
Autonomous cron/Vault dispatch delivered an exact OS notification without a manual
worker call; badge0→1→0 passed. Final persisted verification now covers10 scenarios,
all correct single audits/counts/targeting/jobs. Seven actual OS deliveries total;
final APK covers all3 lifecycle modes. Fixture unblocked, one authorized registration,
phone returned to normal customer home with unread0.42 follow-up files reviewed;
seven accepted ancestors preserved. Final feature-only scan/staging/commit follows.
Root `.gitignore` remains unrelated and unstaged; no push/merge or production change.

## iOS/APNs inspection — 2026-10-15, base 40ad2ca

See `FR-30-ios-acceptance.md` and `evidence/FR-30-ios.json`. iOS/APNs is
**NOT EXECUTED**, with static readiness **FAIL**: missing TEST iOS Firebase app
configuration, signing/capabilities/native dependency integration and iOS client/
sender support. Installed Firebase plugins require iOS15; Runner targets13.
Windows cannot run the iOS build; Mac/Xcode, an authorized Apple team and a
physical iPhone are required. Apple/Firebase console APNs setup is unverified.
Added iOS config/signing-file ignore rules only; Android runtime and all backend
configuration remain unchanged. No production operation, commit, push or merge.
Current-checkout FR30 delivery/broadcast regressions:23 passed, exit0. Ignore
probes and Git whitespace check passed. Native iOS verification remains unexecuted.
