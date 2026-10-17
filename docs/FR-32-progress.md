# FR-32 progress

## Inspection checkpoint — 2026-10-16

Branch feature/FR-32-email-notifications, clean base57914e2d206d9c7695cc3ca286475edef88a8796.
All10 accepted commits verified as ancestors; FR28=7e809fd, FR20=fa29b4c.
Only isolated TEST igeisilhtmglgnqvllrx. Production never accessed/modified.
Read AGENTS, relevant prior acceptance reports, analysis and SRDS PDF pages9,
17,21,29-30,32,42-45; visually inspected class diagram p36 Payment.invoiceUrl.
SRDS3.3.3 lists HTTPS server logic; it names an SMS gateway, not a separate
email gateway. FR32/2.3.8 and Table5.6 row29 explicitly require invoice email.
UC06 requires validated payment before invoice; registration remains Auth.

Read-only hosted preflight:32 accepted migration versions; no outbox/invoice
table, zero existing payments.invoiceurl values. Payments writes service-only;
canonical order items price_at_time/fare/amount available. pg_cron/pg_net/Vault
installed. Existing active minute jobs1 FR30 and4 FR10 preserved. FR33 uses an
OTP-only300/day UTC reservation counter, not a shared email budget.
Existing sender secrets file present; values never printed. Auth SMTP unchanged.

Architecture: transactionally deduplicated outbox; immutable invoice source
snapshot/metadata; leased bounded worker and separate authorized invoice-sign
endpoint; private PDF bucket with900-second server-issued URLs. Account approval
hooks follow actual users transitions; CNIC verification means approved valid
document, not uploaded. Block/unblock mail follows committed FR28 SYNCED event
IDs, not intermediate fail-closed flags. Keep parent-first locks; payment
hooks must not acquire parent locks after payment rows. No payment gateway.

Brevo official300/day and API/attachment/idempotency docs inspected. Current
idempotency guide30-minute TTL differs from historical15-minute changelog;
planned automatic uncertain retries stay within10 minutes with the same key
and immutable content, then require reconciliation. Duplicate_parameter is
not proof of inbox delivery. Provider-reset timezone not verified: asked user
for verified reset timezone or approval of conservative rolling26-hour guard.
No dependent deployment/quota-policy change until answer. Independent SQL,
worker/PDF/template implementation and tests continue. Nothing deployed yet.

Changed so far: this checkpoint and supabase/inspection/FR-32-preflight.sql.
Remaining: stagesA-D, local/hosted SQL, Deno/PDF/Flutter/device/inbox checks,
operational/acceptance evidence and feature-only commit. No push/merge.

## Stage A local checkpoint
Migration 202610160003_fr32_email_outbox.sql reviewed in a full-rollback LOCAL
transaction:60 assertions PASS. Applied once to preserved local container
supabase_db_tezrider-fr30-local, history recorded; never replayed prior migrations.
Independent-session runner:6 PASS, simultaneous duplicate enqueue ->one intent,
two overlapping workers ->disjoint6-job batches,40 transactional reservations
->7 accepted/33 deferred and20 OTP reservations ->3 accepted/17 deferred with
synthetic10-budget/3-reserve. Only marked LOCAL quota fixtures cleaned afterward;
configuration restored to unverified. No real email sent. Hosted TEST unchanged.
Tests: supabase/tests/FR-32.sql, tests/integration/FR-32-{db,local}.py.
Actual FR28 SYNCED hooks tested with synthetic Auth ban/session state; no mail on
unconfirmed Auth sync. Mandatory enqueue failure rolls business transition back.
Stage B begins; pending provider-reset decision still blocks hosted shared quota
activation. Branch feature/FR-32-email-notifications. No worker/cron deployment.

## Stage B checkpoint
User approved temporary conservative rolling26-hour budget; migration inserts
that mode,300 total/90 OTP reserve. No provider reset timezone is claimed.
63 latest LOCAL SQL assertions PASS;3 unreleased draft functions corrected
explicitly in local database (not accepted-migration replay). These allow PDF
preparation independently of TEST email approval while still forbidding sends.
Protected worker batch2; dedicated256-bit secret checked before privileged RPCs.
Escaped HTML/plain templates; strict approved TEST inbox redirect; stable Brevo
idempotency body header and wire hash; unknown outcomes bounded/manual recovery.
Private invoice-sign endpoint validates Auth and owner/admin RPC,900-second URLs.
Existing Order History gets Invoice action; no new screen/dependency.
pdf-lib1.17.1 +fontkit2.0.4 tested under secure default Deno. Old fork's Arabic
shaper failed because it relies on disabled __proto__; replaced without weakening
runtime. Full licensed Noto fonts embedded; real sample409751bytes,1 page,
Unicode sample2 pages. Parsed totals/vendor groups/sharedfee PASS; PNGs inspected.
76 Deno tests PASS including FR33/28/30 regressions; both runtime indexes typecheck.
Brevo preflight sender_found/active true,plan free300 sendLimit,no mail sent.
Auth settings email enabled/autoconfirm false; public settings do not expose SMTP
transport/limits. Auth SMTP untouched. Flutter pub get PASS; focused tests running.
No hosted FR32 migration/functions/cron yet. Branch unchanged; no commit/push.
Stage C guarded TEST deployment next.

## Recovery / Stage C —2026-10-17
C: initially full and Flutter compiler OOM: failed attempt, not a pass. Removed
only ignored regenerable build intermediates; source/APKs/evidence preserved.
User continued;14GB free verified. Docker stopped to conserve memory. No accepted
migrations replayed. Hosted CRLF OTP definition caused initial rollback review
guard to reject; normalized line endings only, preserved FR28 canonical/unblocked
checks verbatim. Final hosted rollback review63 assertions PASS.
Deployment complete only TEST: migration202610160003, fr32-email-worker and
fr32-invoice-url using API bundling. Dedicated256-bit worker secret stored securely
in TEST Edge secrets+Vault; values not printed. Shared rolling26h300/90 active.
Cron fr32-email-worker ID5 every2minutes; existing ID1 FR30 and ID4 FR10 identical
schedule/active/command hashes. Wrong worker key401 before privileged action.
Hosted verification quota/RLS/private bucket/one scheduler PASS. Synthetic shared
checkout and one confirmation intent PASS; uncollected COD no invoice PASS.
Flutter focused3 PASS; full179 PASS with2 inherited skips. Initial analysis80
issues included one new brace notice; fixed, final analysis rerun pending.
No emails claimed received. First approved confirmation send requested; inbox
confirmation pending. Authorized Android reconnected/detected. Fresh APK/device,
invoice attachment/signing, account emails, all10 regressions and load work remain.
76 Deno PASS; sample PDF parsed/visually checked. Local k6 harness/SQL/runner added,
not executed yet; optional1000-user qualification not claimed. No commit/push.

OneDrive conflict reconciliation2026-10-17: user paused syncing; both versions preserved in ignored archive; restored latest reviewed FR32 files. Confirmation inbox receipt explicitly confirmed by user. Supabase CLI temporary executable disappeared; restoring exact official2.120.0 with published SHA256. No migration replay.


## Stage D verified checkpoint —2026-10-17
Invoice email and attached PDF receipt explicitly confirmed by user: “invoice
verified”;440.00 total and shared200.00 delivery once. Actual Android Invoice
button opened matching private PDF in Chrome; unpaid order feedback PASS.
Fresh source-scanned TEST APK installed; SHA256
c5cfb89afff036683ff00b603c2e847740c4790ceb356ee16e70770d8731c561.
Physical checkout committed order2112, one confirmation intent/no unpaid COD
invoice/cart cleared. Notifications visible; mark-all-read persisted across reopen
for captured5 IDs; later new timeout notice is correctly separate. Runtime fatal/
unhandled scan PASS. Core device proof in native-evidence.jsonl.
Final reconciled Flutter179 PASS/2 inherited skips; analysis79 inherited findings
(0errors/13warnings/66notices), no FR32 findings. Deno76 and hosted SQL63 PASS.
All10 previous FR regression groups PASS: latest regressions-outstanding.json
supersedes failed earlier FR21/25/26/33 standalone/launcher attempts. Existing
accepted HTTP suites used; no production guards or accepted assertions weakened.
LOCAL k6 smoke executed:40 iterations/2VUs,49/49checks,0unexpected errors,
enqueue p95=57.7359ms; mocked429 resumed, quota/OTP reserve, dedup and lease
recovery PASS; seven mocked acceptances/34 deferred. No real emails/hosted load.
LOCAL old own tracked pre-send fixtures skipped safely; quota usage was zero.
Fixture config restored, harness stopped, four local containers stopped. Full
1000-user qualification NOT EXECUTED due environment memory limits.
Vendor rejection email provider accepted; receipt pending. Do not resend blindly.
Remaining5 other account-action sends/receipts must follow one at a time after
that answer; physical real-email FR33 OTP/user code entry still required. Report
and sanitized evidence updated, FR32 remains NOT FUNCTIONALLY ACCEPTED. No commit,
push or merge. Branch feature/FR-32-email-notifications; migration202610160003
already deployed once TEST, worker fr32-email-worker, cron5 */2minutes. No replay.
OneDrive must remain paused. Production untouched.

Final review: TEST quota/RLS/private bucket/one FR32 job and accepted cron active
reverified. Changed38-file secret scan PASS. Temporary mirror source file later
removed; initial successful artifact manifest retained108source hashes. Current
source hashes and actual APK SHA identical; full APK/manifest/secret rescan PASS.
Evidence artifact.json/source-scan.json, no fabricated mirror restoration.
Remaining manual inbox and physical OTP gates prevent acceptance/commit.

Vendor rejection actual inbox receipt explicitly confirmed by user. Next single
action vendor approval; no migration replay, no commit/push/merge.
Genuine vendor approval emitted exactly one new account event; approved TEST
inbox send accepted. User receipt requested; wait before next account email.

Vendor approval actual inbox receipt confirmed by user. Next single action:
rider rejection through actual admin transition, isolated TEST only.
Actual rider rejection emitted exactly one new intent; provider accepted the
approved TEST inbox send. Rider-rejection receipt requested; wait before next
account email. Remaining rider CNIC verification, blocked/unblocked receipts and
physical FR33 OTP; acceptance/commit still pending. No push/merge.

Rider rejection actual inbox receipt confirmed by user. Next single action:
synthetic rider CNIC document upload and actual admin approval; TEST only.
Actual synthetic document storage upload and rider admin approval succeeded;
exactly one combined CNIC-verification/approval intent was created. Provider
accepted approved TEST inbox delivery. User receipt requested; wait before
blocked/unblocked account emails. Physical FR33 OTP still pending; no commit.

Rider verification actual inbox receipt confirmed by user. Next single action:
block own synthetic other-customer via existing FR28 Auth-sync endpoint; TEST only.
FR28 actual synthetic-account block/Auth sync succeeded and emitted exactly one
new intent. Provider accepted approved TEST inbox send; user receipt pending.
Wait before unblocking/send. No production changes, commit, push or merge.

Blocked-account actual inbox receipt confirmed by user. Next single action:
unblock same synthetic account through existing FR28 Auth-sync endpoint; TEST only.
FR28 actual synthetic-account unblock/Auth sync succeeded; exactly one new
intent. Provider accepted approved TEST inbox send; user receipt requested.
All other account email receipts user-confirmed. Physical FR33 OTP still pending.
No production changes, commit, push or merge.

Unblocked-account actual inbox receipt confirmed by user. All6 account-action
receipts now user-confirmed. Remaining physical FR33 OTP and final acceptance.

## Final functional acceptance —2026-10-17
All6 actual account-action emails explicitly user-confirmed, plus confirmation
and paid invoice/attachment. Fresh native FR33 delivery2113 real email OTP USED,
order delivered, shared OTP admission1, proof1/audit1; user confirmed OTP verified
without disclosing code. Intermediate code-entry-screen assertion did not pass
as user completed flow; final PASS relies on actual backend state +user receipt,
not a fabricated screen assertion. Final runtime fatal/unhandled scan PASS.
Mandatory functional criteria complete; report/evidence FUNCTIONALLY ACCEPTED.
Optional1000-user qualification NOT EXECUTED; actual inbox latency not measured.
No production changes. Preparing feature-only local commit after final staging
review; no push/merge. Branch feature/FR-32-email-notifications; TEST migration
202610160003 and existing FR32 cron5 unchanged, no replay.

Final staging found two additional OneDrive conflict copies. Both original and
conflict content preserved in ignored onedrive-conflicts-final; latest typed
Uint8Array upload and suppressed-email PDF test restored to canonical sources.
Copies unstaged/excluded. Deno entries check PASS;76 tests PASS after adding
required narrow PDF write permission (initial74/2 permission errors not counted).
Final worker deployed only isolated TEST; no migration/cron replay.36 feature
files remain; production untouched. Final protected source scan/staging next.
Final36-file protected-credential scan PASS. Hosted wrong-key401, private
owner/admin signing and actual PDF download PASS; cross-customer/public object
and customer/vendor/rider outbox denials PASS. Mandatory acceptance complete.
Preparing local feature-only commit; hash obtained from Git, no push/merge.
