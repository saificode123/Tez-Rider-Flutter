# Mandatory pre-delivery checklist — acceptance

**PRE-DELIVERY CHECKLIST FUNCTIONALLY ACCEPTED — Ready for the next FR.**
Functional and security acceptance PASS; 1000-user scale NOT EXECUTED. Only isolated TEST
`igeisilhtmglgnqvllrx` was modified. Production untouched. No push/merge.
Branch `feature/pre-delivery-checklist`; verified base `569e8c6` includes all11
accepted features, including FR28 `7e809fd` and FR20 `fa29b4c`.

## Requirements and interpretations

SRDS physical PDF pages6/8/20/23/27/31/32/44 were inspected for §1.3, §2.3.3,
UC04, rider dashboard §3.3.1, SEC01, S01, §4.3.2 and Table5.6row16. Page44 was
rendered and visually checked. It explicitly names `rider_assignments` and
`checklist_completed=true`; GPS streaming is future work. The three initial
items are the user's approved interpretation, not item text invented from SRDS:
items match, packaging sealed/undamaged, address/customer details confirmed.
S01 concerns confirmation before destructive actions, not an800ms SLA.

Existing states are reused: FR20 reservation=`Pending`; rider pickup acceptance
=`Accepted`, parent=`ready`; checklist submission leaves parent ready; explicit
Start Delivery sets parent=`on_the_way`; existing OTP completion sets parent
`delivered` and assignment `Delivered`. Vendor portions retain their prior
`on_the_way` reservation convention; that value alone no longer starts the parent.
Every required vendor must be ready before checklist submission/start.
No new GPS stream, proof-upload, issue-report, performance module, notification
infrastructure, dependency or unrelated screen was added. Existing map simulation
and tailoring behavior remain. Future FR13 must check actual
`checklist_completed=true` before enabling GPS streaming; no GPS gate is claimed
implemented here. A damaged/unsealed package cannot be truthfully confirmed:
the rider cannot start; SRDS defines no reporting flow, which remains a limitation.

## Functional and security evidence

1. **PASS — Server definition.** Migration202610170001 seeds private approved
   definition version1. `pre_delivery_checklist` returns required items to the
   canonical assigned approved rider. Flutter renders returned IDs/labels, not a
   separate hard-coded authority. SQL and widget tests validate definition use.
2. **PASS — Data/evidence.** Existing assignment gets boolean defaultfalse and
   nullable server timestamp with paired-value constraint. Public
   `pre_delivery_checklists` has one row per assignment, rider, version, exact
   confirmed items, immutable definition snapshot and server timestamp. Append-only
   evidence, FK/index/unique constraints preserve dispute history.
3. **PASS — Validation.** RPC rejects missing/false/unknown/duplicate IDs, unknown
   properties, string booleans, null/object bodies and unapproved versions. No
   completion timestamp parameter. SQL review63/post-deployment56 assertions.
4. **PASS — Authorization.** Reuses FR28 canonical Auth UUID, confirmed identity,
   live session, approved rider and blocked-state checks. Customer/vendor/admin,
   another rider and anonymous caller cannot submit. Actual HTTP denials11checks;
   admin cannot impersonate rider through the submission RPC.
5. **PASS — Stage and cancellation.** Parent-first then assignment locking,
   rechecked rider identity/approval, active Accepted assignment and pickup parent
   ready. Cancelled/delivered/inactive/wrong-stage requests fail; any unready vendor
   portion prevents start. SQL cancellation subtransaction and real separate-session
   cancellation race passed without changing FR10 business policy.
6. **PASS — Idempotency/concurrency.** Unique assignment PK plus parent/assignment
   locks make two simultaneous submits one completion/one replay with identical
   timestamp. Two simultaneous starts produce one transition/one replay.6 actual
   independent LOCAL session assertions passed; sequential SQL is not presented
   as concurrency evidence. Actual phone fixture duplicate RPC also preserved
   evidence/time and one row after restart.
7. **PASS — Backend start gate.** `start_checklisted_delivery` requires its assigned
   approved/unblocked rider, Accepted assignment, ready parent and matching complete
   evidence. Ordinary direct status writes cannot substitute for it. Order trigger
   also rejects premature start/completion, including trusted malformed fixtures.
   Existing accept RPC now stops at pickup; vendor aggregation cannot prematurely
   start the parent. Actual HTTP bypass left parent ready; physical Start succeeded
   only after server-confirmed checklist.
8. **PASS — OTP safety and physical completion.** Minimal source-guarded
   edit to `verify_delivery_otp` returns CHECKLIST_REQUIRED before tags, verifier
   rate counters, attempt records, code invalidation or completion writes. A valid
   protected mock OTP stayed ACCEPTED/attempts0 while rejected; after checklist/start
   the original verifier consumed it once, wrote one proof and returned idempotently.
   Existing issuance/email/quota logic was not edited. FR33 accepted hosted39 checks
   passed with real checklist-aware fixture preparation and explicitly mocked
   provider acceptance, no real regression email. Physical order2124 real email
   provider accepted; user entered privately and actual backend confirms USED,
   delivered, one protected proof and one completion audit.
9. **PASS — Legacy compatibility.** Migration captures exact order/rider/current
   assignment identity and migration timestamp only for already-in-transit orders;
   old orphan transit orders are explicitly recorded with null assignment. Hosted
   snapshot28orders,0fabricated checklist completions. No old response or completed
   timestamp is invented. Actual before-migration LOCAL/hosted rollback fixtures
   proved old transit compatible, old pickup not exempt, replacement/new assignment
   cannot inherit exemption. Orphan exemption disappears if an assignment is created.
   The private snapshot is append-only and inaccessible to ordinary/service clients.
10. **PASS — RLS/grants.** Public evidence RLS permits own rider/admin reads only;
    clients have SELECT, no INSERT/UPDATE/DELETE. Private definition/legacy tables
    enable RLS and have no client/service grants. Only authenticated execution on
    public read/submit/start RPCs; each authenticates role/ownership. Existing FR21
    assignment/status guards remain. Actual owner/admin/other evidence reads on the
    phone fixture proved authorization; no column-only RLS assumption is used.
11. **PASS — Rider UI behavior.** Existing panel, three large checkbox targets,
    loading, retry and actionable errors; no optimistic success. Pending reservation
    shows Accept pickup. Incomplete submit/start disabled; all checked enables submit
    but leaves start disabled. Start enabled after authoritative completion. Scroll
    constraint supports shorter displays.14 widget/service tests cover duplicate
    taps, pending response, rejection, network failure/retry, restore, assignment
    switch, account switch, stale replies and OTP message mapping. Actual device
    screenshots visually checked, all3 items visible and unclipped.
12. **PASS — Physical Android.** Initial pickup/checklist/start workflow executed
    on a fresh TEST APK, then final corrected builds installed successfully on
    AESWNRBAEUPNTGJZ. Real stocked checkout/order2124: Pending assignment, actual
    Accept pickup, partial/full item controls, authoritative submit, restart restore,
    duplicate evidence and explicit Start verified. Real emailed OTP entered by user:
    backend USED/delivered, assignment Delivered, one proof/audit, one checklist
    response with matching timestamp/version/three-item snapshot. Final app starts
    successfully, second synthetic rider sees no target job, RLS returns no evidence
    and submit RPC returns FORBIDDEN. Runtime fatal/unhandled scan PASS.
    Final APK SHA256:
    `48d2521ccfa28d7b668cb39730ea2abd312b64993c24b0e3df2a3215fd956176`.
    133104735bytes;110Dart sources byte-matched; actual APK TEST endpoint/package,
    checklist markers and protected-credential/production-endpoint scan PASS.
    Initial CLI timeout and premature OTP probes were failed attempts, not passes;
    bounded REST and actual accepted issuance/completion later passed. USB/foreground
    interruptions were resolved. No OTP value is recorded in committed evidence.
13. **PASS — Functional performance smoke; scale NOT EXECUTED.** LOCAL real
    PostgREST/RLS/RPC k6:40iterations,20distinct assignments plus20contended requests,
    2VUs per scenario (4allocated/2maximum actually observed),260HTTPrequests,
    180/180checks,0unexpected errors. Operation p95=29.914175ms, max229.4457ms;
    initial gate rejection and unauthorized submissions tracked separately as
    expected business rejections. No duplicate evidence/bypasses observed. No hosted
    load, email or quota modifications.22marked localfixtures closed, JWTfile removed,
    containers stopped.1000-user qualification NOT EXECUTED; no scale readiness claim.
14. **PASS — Flutter/build.** Pub get passed; no dependency change. Final full
    suite194PASS/2inherited skips;14focused checklist tests passed. Final targeted
    analysis of all7changed Dart files: no issues. Earlier full-project analysis
    had79inherited findings (0errors/13warnings/66notices); no clean-project claim.
    Final APK build437.8s PASS. Initial new test missing extension-method import
    was corrected with plain map writes, then full tests/analysis passed.
15. **PASS — Prior11FR regressions.** Latest FR21=47, FR04=49, FR25=83, FR33=39,
    FR28=74, FR20=70, FR30SQL65/HTTP25/Realtime3, FR10=24, FR17=27, FR32SQL63 passed.
    Final FR26=95 also passed. Initial fixture-adapter failures are retained as failed
    attempts, never passes. Earlier direct synthetic transit/delivered seeds now use
    actual checklist submission/start; original accepted assertions remain.
    Financial delivered seeds remain explicitly privileged synthetic history after
    satisfying the gate, not actual OTP/provider capture. FR33 sequential security
    scenarios retire only that marked rider's preceding synthetic assignment;
    unrelated assignments are asserted/preserved. These helpers are TEST-only and
    enabled explicitly by the checklist regression runner, never production code.
16. **PASS — Final acceptance checks.** All mandatory functional/security/device
    gates passed. Feature-only source/credential/size/diff checks precede the local
    commit. No push or merge. Commit identity is reported in Git/final response,
    avoiding a self-referential report hash.

## Changed database objects

New tables: checklist_private.definitions, checklist_private.legacy_transit,
public.pre_delivery_checklists. New assignment fields/paired constraint and evidence
rider index/FKs/PK described above. Existing data is preserved.

New functions: checklist_private.legacy, checklist_private.allowed,
checklist_private.guard_assignment, checklist_private.guard_delivery,
public.pre_delivery_checklist, public.submit_pre_delivery_checklist,
public.start_checklisted_delivery. Existing functions minimally extended:
public.fr21_accept_order, public.sync_order_status_from_vendor_order,
public.verify_delivery_otp. Existing FR33 issuance/FR32 quota/FR28 identity functions
unchanged; no Edge Function/cron or credential changes required.

New triggers: checklist_guard_assignment, checklist_guard_delivery,
checklist_evidence_immutable, checklist_legacy_immutable (last2 reuse
public.fr26_append_only). New policy: checklist_read. New grants: authenticated and
service SELECT on evidence; authenticated EXECUTE on the3 public RPCs. PUBLIC/anon/
service EXECUTE and ordinary evidence writes revoked; private schema/tables/functions
revoked from all client/service roles. No existing policy/grant was widened.
No unaudited client/admin recovery bypass is introduced; database-owner synthetic
test fixture seeding is not an application recovery feature.

## Evidence and limits

Ignored `.fr21-local/checklist/` holds rollback/concurrency/HTTP/regression/Flutter/
APK/k6 and observed physical evidence. Credentials remain DPAPI-protected outside
Git. No OTP value, JWT, password, Apple/Firebase key or private recipient is committed.
Portable sanitized evidence: `evidence/CHECKLIST-acceptance.json`.

No required paid service/dependency. Bounded assignment/order lookup and single
transaction submission/start; no additional polling timer or Realtime channel.
Local latency is not hosted/user-network capacity evidence. Physical scale remains
unqualified. Production deployment requires separate authorization.

Route audit: actual hosted callable functions containing transit/delivery status
were inspected with their EXECUTE grants. Writes are through fr21 acceptance,
vendor assignment/aggregation, checklist start and FR33 verification; legacy
fr21_complete_delivery delegates to verify_delivery_otp. Other matching public
functions are reads, upload/send preconditions or triggers, not extra start routes.
Original FR33 verifier source, after removing exactly the two new gate clauses,
normalizes identically to its preflight definition (SHA256
ea50fcb6359dd4957ca449aee8de61a2fe3b4f6cf4557366ddef5e425c68f8f6).
No HMAC/rate/expiry/replay/completion logic was rewritten.

Final weak-connectivity correction: the rider controller retains only validated
server STARTED/on_the_way and uses the existing guarded refresh. Initial complete
pickup/start proof preceded that small correction; later installed builds exercised
restored in-transit/OTP flow, completion and second-account checks. The start-refresh
failure path is not claimed physically fault-injected.

OTP attempt-display follow-up (user request): actual initial order2124 history had
three EXPIRED outcomes and no INVALID mismatch. Expired submissions correctly do
not consume mismatch attempts. The UI showed the status count even when inactive;
client now exposes remainingAttempts only for active unexpired codes. Active INVALID
server counts remain authoritative; tests verify decrement/expired/locked behavior.
No backend attempt-limit/verifier/quota changes. Final APK includes this correction;
no further real wrong-code attempt was deliberately consumed on the physical order.
