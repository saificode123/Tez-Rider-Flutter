# FR-17 progress — 2026-10-16

## Inspection and Stage A draft

Branch `feature/FR-17-stock-tracking`, base `76960fadf207f17156a2124b547f6cbe47d04b1f`.
Clean start; all9 accepted FR ancestors verified, FR28=`7e809fd`, FR20=`fa29b4c`.
No merge/cherry-pick/push. Production never accessed. TEST history31 matched.

Read AGENTS, SRDS and all9 acceptance reports. SRDS FR16/17 (PDFp14),
2.3.4, UC03(p20), vendor dashboard(p26), SEC01(p31), Table5.6 rows7/8/24
(p43/44), class diagram visually inspected(p36:Product stock:int/updateStock()).
Task's explicit interpretation: cart validates only; checkout decrements;
cancellation restores. No abandoned-cart reservations.

Read-only TEST preflight:3 products,3 available,3 unknown stock, all explicitly
synthetic-owned. No stock columns existed. Existing availability flags stay;
stock_qty0/stock_confirmedfalse means UNKNOWN, never asserted as real zero
inventory. Vendor must confirm via trusted count. No invented production stock.
Production migration needs actual vendor counts/staged confirmation; no production
change authorized. Default threshold5. Threshold change alone/same adjustment
does not alert; subsequent above-to-at-or-below quantity crossing alerts once.

Draft migration202610160002_fr17_inventory.sql applied ONCE to preserved LOCAL
database only. No accepted migration edited/replayed; hosted remains unchanged.
Integer stock/threshold/confirmed/version; append-only reconciled ledger;
trusted product-save/adjust RPCs; canonical aggregated FR10 checkout wrapper;
generic parent cancellation restoration for recorded decrements only; FR10
whole-batch product prelocks; failed-payment compensation in same bounded
existing minute worker without acquiring new parents after products. No newcron.
Existing FR30 transport already accepts the event UUID and is reused unchanged.

Lock hierarchy: customer idempotency or approved vendor identity first; existing
parents then all children then global ascending product IDs then payments.
Checkout creates only new, uncommitted parents after products; it never locks
an existing parent after products. Vendor identity uses NO KEY UPDATE to remain
compatible with FK key-share checks. No payment-row trigger reverses order locks.

Local rollback SQL49 PASS (first test expected360 instead of correct440 shared
total; expectation corrected to include both vendors' delivery fees). Tests
include actual SET ROLE denials, ledger reconciliation, stock/count conflicts,
shortages/no partialwrites, atomic exception rollback, full captured PENDING
refund unchanged, COD/no refund and durable FAILED compensation.

New files: migration, inspection SQL, supabase/tests/FR-17.sql,
tests/integration/FR-17-db.py, this checkpoint. Raw ignored evidence
`.fr21-local/fr17/`. Remaining Stage A separate-session races and schema review,
then Flutter integration, hosted deployment/regressions, fresh APK/physical/load.
No feature commit; no acceptance claim.

## Stage A verified — proceed Stage B

LOCAL rollback53 PASS. Independent-session runner15 PASS: last-unit race;
200 valid attempts/10 independent buyers against100 units ->100 purchases,
stock0/one crossing notice; opposite product orders no deadlock; stale vendor
absolute count waited for checkout then STOCK_CHANGED; checkout/cancellation
locks compatible; concurrent cancellation one restoration; concurrent7→5
crossing one alert; ledger reconciled from opening0.

Three un-deployed draft function bodies revised locally (not migration replay):
NULL adjustment mode denied, removed unsold product retries report removed,
pre-FR17 original checkout payload replays without decrement. Rollback tests
also prove historical non-decremented orders never gain invented restoration.
Additional tests preserve FR16 unsold deletion with ledger snapshot retained.
First concurrency runner had a missing SQL whitespace; corrected and reran15PASS.
Hosted TEST unchanged; migration202610160002 is LOCAL draft only.

Stage B now implementing authoritative stock DTO/service, existing vendor forms
and list, catalog/cart/checkout shortage UI and Flutter tests. No dependencies
added. No push/merge/feature commit. Branch/base unchanged.

## Stage B verified — proceed Stage C

Authoritative ProductStock DTO, retry-safe InventoryWriteFlow, all6 existing
add-to-cart entry points now await refreshed availability; no mock inventory
fallback. Product model carries quantities/confirmation/version. Existing vendor
form uses one atomic product/stock RPC, preserves uploaded/existing images,
requires explicit confirmed integer count, and handles stale-count conflicts.
Vendor list: bounded30-row cursor pages, stock states and quick trusted count.
Cart disables excess increments, refreshes availability and preserves chosen
items on shortage; explicit Adjust quantities clamps/removes only affected
items. Existing checkout retains uncertain-request protection; definitive
shortage clears retry UUID and returns to cart. Catalog uses bounded pages,
stock states and visible backend errors. Existing notifications trigger scoped
stock/cart refresh; no per-product Realtime subscriptions.

Pub get PASS, no dependency/version changes. Changed Dart files formatted.
Focused38 PASS (23 inventory+15 FR10). Full suite173 PASS/2 inherited skips.
Analysis0 errors/13 inherited warnings/64 notices (77 total); no new errors.
Initial full-suite compiler lost temporary output.dill and exited; not counted
as PASS. Stopped only that task process tree; fresh serial full run passed.
Automatic review initially could not execute full tests due account usage
limit; after user continued it was retried with approval and completed.
Missing temporary Supabase CLI binaries restored from existing cli.tar.gz;
no download/reinstallation of Flutter or project setup.

Draft gained an index on open inventory orders for the existing worker's
failed-payment compensation branch; no accepted index/migration changed.
Remaining hosted rollback review/deployment53 SQL+real HTTP/regressions,
then fresh TEST APK/physical acceptance/local k6. Only local draft applied,
hosted TEST still31 versions. No feature commit/push/merge.

## Stage C deployment and HTTP checkpoint

Hosted rollback migration review53 PASS. Applied ONLY202610160002 once through
history/dry-run guard;32 versions now match source,31 accepted versions retained.
Migration is now frozen: any needed backend fix requires a new additive migration.
Deployed rollback53 PASS; accepted FR10 rollback67 PASS with owning-vendor RPC
confirming synthetic fixture stock (all original assertions preserved).

Real hosted HTTP27 PASS: atomic decrement/retry, simultaneous buyers lastunit,
stock0, structured multi-item shortage/no partial writes, aggregation, shared
accepted sibling timeout restores every item, one full600 captured PENDING
refund including delivery, rejection restoration, exact crossing notice/re-arm,
wrong roles/vendor/direct protected columns/ledger denials and blocked owner403.
Synthetic blocked vendor restored unblocked in finally; no money/email action.
Independent verification: no negative stock, ledger RLS, ordinary stock/threshold/
INSERT/ledger/internal restoration privileges denied; same two active minute
jobs/default180. Existing3 products remain unconfirmed; flags not changed.

FR10 test fixture integration changes only: SQL product created through trusted
stock-save RPC; HTTP fixture uses owning vendor to confirm100 synthetic units
when FR17 columns exist. No security/accepted assertions weakened. Remaining
eight feature regressions plus FR10HTTP running sequentially; physical/load
and feature commit still pending. No production access/push/merge.

## Stage C complete / Stage D checkpoint

All nine accepted-FR regressions PASS: FR21=47, FR04=49, FR25=83,
FR26=96, FR33=39, FR28=74, FR20=70, FR30 SQL65/HTTP25/realtime3,
FR10 SQL67/HTTP24. No original assertions removed. TEST180/same jobs retained.
Full k6 preflight469442560 bytes <1GiB; smaller local attempt after Docker
startup75042816 bytes <350MiB, both NOT EXECUTED. Stopped Docker Desktop
started for this check. Earlier real local ten-session200-attempt race passed;
it is not HTTP p95/capacity qualification. Local k6 scripts added with guards.
Observed TEST ledger25 rows, mean tuple207 bytes, table49152/index81920 bytes.

Fresh TEST APK building in existing low-memory mirror; source copied and
accepted Android configuration matches. Supplied Firebase configuration's
actual project ID tez-rider-fe12b/package matches existing mirror; initial
display-name-as-ID assertion corrected without changing configuration.
Authorized phone connected. Physical helper/artifact scanner prepared;
no FR17 physical PASS yet. Acceptance report added with pending status.
Branch feature/FR-17-stock-tracking, migration202610160002 remains frozen.
Remaining: physical checks, final source/APK scan, sanitized evidence/manifest,
feature-only commit after mandatory acceptance. No push/merge/production access.

Fresh build completed418.8s, APK206344956 bytes, SHA256
18d25891283d098420fdbb7096f9675043309fd983db68dc927dfccfafdaa18e.
Artifact scan PASS:105 Dart sources match mirror; TEST package/endpoint and
FR17 code present; protected credentials/production endpoint absent. Installed
with Success and launch submitted. Physical tests NOT EXECUTED yet: phone
reports lockscreen=true, Dozing, NotificationShade foreground. Asked user to
unlock/open TEST; no lock bypass. Five own synthetic physical fixtures seeded
(zero/valid/shared/shared2/low), separately from planned actual UI creation.
No timeout configuration changed. Feature commit remains withheld until all
mandatory physical acceptance checks pass.

Recovery checkpoint: sanitized docs/evidence/FR-17-acceptance.json and exact
docs/FR-17-changed-files.txt added (36 changed/new files). Final artifact/source
scan36 PASS. All9 regressions done; no pending build/test processes from this
turn. Phone recheck still locked/dozing; unlock question remains pending.
No temporary timeout change to restore. Work remains uncommitted on the same
feature branch; no push/merge. Resume physical actions after actual unlock;
do not repeat completed migrations or classify these pending checks PASS.

## Physical verification resumed / dialog failure found

User unlocked phone; actual vendor login succeeded. UI-created product34
FR17 physical stock persisted12/version1/threshold5/confirmedtrue and vendor
list displayed the same. Actual UI quick-count saved14/version2, but closing
the dialog then produced a Flutter red assertion (_dependents.isEmpty).
This physical attempt FAIL, not final acceptance. PID log severity-only check
missed the assertion; strengthened it to reject assertion patterns and empty
TEST accessibility screens. Screenshot/raw evidence remains ignored.

Fix in progress: StockAdjustmentDialog owns controllers in its StatefulWidget
until route removal, preventing early disposal during close animation and
state updates after successful pop. Vendor screen now delegates to it.
Three meaningful widget tests added: animated successful close, cancel,
stale version review/retry. Focused tests running before rebuilt device retest.
No SQL/native Firebase changes, no migration replay, no feature commit.

Dialog fix focused41 PASS; corrected APK built130.6s, SHA256
91a475b1ffc5d0ae8fa9b4ef37096e52f3f9f76ed09b02163827470405314694,
206344554 bytes,106 Dart sources match,38-file source/APK secret scan PASS.
Installed Success. Repeated actual UI adjustment14->16 persisted/version3,
returned visible inventory list, strengthened runtime check PASS (no red screen).

Post-fix full Flutter run stalled at19 while loading a test; aborted only its
owned process tree, not counted PASS. Fresh workspace-local TEMP retry176 PASS/
2 inherited skips. Analysis0 errors/13 inherited warnings/66 notices (79 total;
2 new brace-style notices, no new warning/error). Full analysis exit1 reflects
the remaining warnings/notices, not a clean lint pass.

Physical customer zero-stock search/detail exact message and disabled purchase
button PASS after scrolling to the control. Available product16 units, real
UI add/cart/checkout PASS: order1671, one item/decrement, stock15. Its eligibility
temporarily3600 for manual rejection; default restored180 in finally.
Two-item stale cart physical shortage PASS: requested1/available0, no new order,
valid product still20, explicit Adjust quantities removed only affected item
and retained valid quantity1. Synthetic physical count restored15 afterward.
Shared two-vendor checkout pending. One attempt found Place Order below viewport
and submitted nothing;60-second temporary config restored180. Button now visible
and timed shared-checkout retry running with finally restoration. Device briefly
switched away from TEST; only TEST brought foreground, helper now checks foreground
immediately before input. Remaining shared cron/retry, vendor rejection, low-stock
OS/inbox/rearm, final integrity/evidence/commit. No feature acceptance/commit yet.

## Stage D acceptance complete

FR-17 FUNCTIONALLY ACCEPTED — Ready for the next FR. Functional/security PASS;
HTTP p95/error-rate and1,000-buyer k6 qualification NOT EXECUTED due RAM gate.
Full post-fix176 PASS/2 inherited skips; analysis0 errors,13 inherited warnings,
66 notices (2 new style notices), exit1 with findings. Pub versions unchanged.

Actual phone two-vendor Continue confirmation created order1672/products30,32,
amount360/two decrements, both20->19. Automatic minute worker cancelled both,
both stocks20, two restores, one customer timeout notice/no COD refund, exact
customer history message for1672. Worker retry still two restores. Default180
restored in finally. Earlier old-order lookup before confirmation discarded;
record-order now requires both expected shared products before saving evidence.

Actual phone Reject child1271 cancelled parent1671 with vendor_rejected and one
restore15->16. Its saved3600 deadline was intact. Probe's initial expected
timeout notice was wrong: preserved FR10 emits that notice only for timeout;
corrected expectation0 for rejection, no app/business change. No active order
left on vendor list after refresh. No monetary refund for these COD fixtures.

Low product33: actual synthetic HTTP7->5->4 produced one owner notice and one
matching Android OS event. Phone UI restock7 rearmed; next real HTTP purchase2
produced second exact notice/OS event (total2). Actual vendor inbox showed both
and existing new-order notices; Mark all as read persisted own unread0. Final
runtime visible UI/log check PASS, fatal/unhandled/Flutter errors0. All six own
physical fixtures reconcile from opening0; duplicate/missing restores0.
Fresh hosted verifier confirms32 versions,3 unknown legacy products, denied
ordinary protected writes/internal EXECUTE, same jobs/default180. Source SQL
202610160002 remains frozen. No production access/new scheduler/paid services.

Acceptance report, sanitized evidence and exact38-file manifest finalized.
Initial real dialog failure/fix and stalled-test retry documented honestly.
Final source/APK scan and feature-only commit use this acceptance checkpoint;
commit identity/clean status are reported in final handoff/Git history. No push
or merge; requested safe push command documented for user only. No remaining
mandatory functional/security/device setup blocker.

Final source/APK credential scan PASS:38 files,106 matching Dart sources,
TEST-only endpoint/package, no protected credential/production endpoint.
Physical execution recognized from final integrity evidence. Python6 helpers
and PowerShell runner syntax parsed; whitespace check PASS. All acceptance
artifacts correspond to corrected APK91a475b1...; no credentials/APKs/build
outputs staged. Final Git review/commit is the remaining handoff operation.
