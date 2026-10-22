# Current Stage0/1 security verification — 2026-10-22

> Current status: see the FINAL02 current checkpoint at the end and docs/evidence/FINAL02-acceptance.json. Earlier checkpoints are historical.

**PARTIAL — SECURITY ACCEPTANCE PENDING.** Authorized TEST only:igeisilhtmglgnqvllrx. Productionarrqsvejrfdbacfwtpcc untouched. No push/merge, reset/rebase, Docker, stress/1000-user testing, paid dependency, provider sending or Stage2–5 work. This is the current checkpoint; baseline FINAL-security-audit.md remains historical evidence.

## Implemented scope

- Canonical four-role approved-dashboard restoration now uses a verified server user/profile and preserves pending/block handling. Password login remains separate from biometric-only authentication; actual enrolled biometrics are required, with no device-PIN fallback on that entry.
- Unsafe legacy media helpers now fail explicitly before file reads, direct Storage requests or public URL creation. Vendor product form rejects new picked files/new URLs while allowing unchanged/cleared historical URLs and numeric inventory CRUD. Existing trusted CNIC/dispute/invoice workflows remain separate. This resolves the conditional unsafe legacy path, not missing Stage2 media functionality.
- TEST Flutter REST transport uses the fixed-origin security gateway; Auth/Storage/Realtime retain their approved separate boundaries. Shared trusted context avoids charging an incoming Edge request again for its internal user RPCs. Forwarded RPC/table requests retain the user's JWT/RLS; service identity is limited to server-only proof/audit operations. Foreign origins and production are not configured for the gateway.
- Request body/header/path limits, fixed public schema, bounded responses, private HMAC proof and safe error classification implemented. Failures401/403/5xx are classified and deduplicated hourly per actor/endpoint/class; server logging failure has a redacted provider-log fallback, not a fabricated database-success claim. Validation/business/rate responses remain separate. Only newly introduced final01_api_* events have prospective30-day bounded retention; existing Admin audit history is untouched.
- New signed CNIC/evidence/invoice URLs are capped by900seconds and remaining authorized session time. Assistant429 includes Retry-After. Shared counter is an atomic100/minute per-authenticated-actor application budget, subject to enforcement activation below.

## Hosted TEST state and actual verification

Additive migration202610220003 applied once after25metadata/pure rollback checks;25post-deploy checks pass. Current read-only catalog:41versions,83inspected tables all RLS-enabled,174functions/146definers. Existing migrations were not replayed. Private proof key generated server-side; no key/token/raw URL/PIN/CNIC emitted or committed.

Gateway plus10existing compatible Edge entrypoints deployed via API without Docker; all11reportedACTIVE. Exact versions are in evidence/FINAL01-security-results.json. Runtime secrets/configuration were not rotated or replaced.

173bounded current hosted checks PASS, using actual user JWTs:

-25prerequisites: canonical4roles/session deadlines, server-only proof/audit permissions and deduplication; invalid JWT denial.
-108compatible gateway regressions:86existing read/denial scenarios adapted to preserve userRLS, plus permitted reads, compatibility/direct-path probes, proof injection rejection, worker denials before claim/send and anonymous contacts denial. Direct REST remains permitted before activation; this is compatibility evidence, not bypass protection.
-18persistent synthetic COD workflow: newly marked example.test customer, confirmed own-profile write and role-escalation denial, vendor product/inventory, checkout and exact retry, ownership isolation, vendor acceptance/cancellation, stock restoration exactly once and no fabricated paid/refunded state. Only the privileged final accounting read is service-role; it is not RLS proof. Fixtures remain intact; cancellation is an intended business transition, not cleanup deletion.
-13boundaries: only that new fixture's counter seeded at99, two concurrent REST/Edge requests yield one allowed/one429 and persisted100, positive Retry-After; authorized Admin obtains/reads existing synthetic private CNIC while unrelated roles are denied. Exactly one fresh marked session is aged beyond168hours for a controlled-clock test: gateway denies its otherwise unexpired JWT and remains denied after provider refresh. No seven-day wall-clock/provider-refresh-expiry claim.
-9lifecycle: Admin blocks/unblocks only the new cancelled-order synthetic customer, provider login refusal while blocked, staleJWT denial, block replay, one committed Admin audit, successful fresh authorization after unblock, normal local provider logout and subsequent revoked-session denial. Unblock runs in finally after a successful block. This is hosted evidence, not physical logout/UI evidence.

## Activation boundary and anonymous-surface review

202610220004 is **reviewed only, NOT APPLIED**.25metadata/pure checks passed inside a rolled-back transaction. It would require private proof for authenticated REST, enforce created_at+168hours/earliernot_after in canonical session checks, constrain own-profile Realtime reads and update installation-secret push resolution. No readiness file was fabricated.

Current anonymous-executable public functions inspected from the actual catalog:

-fr21_order_contacts explicitly rejects missing auth.uid and filters each requested order through fr21_order_visible; fr21_actor requires confirmed canonical identity, unblocked account and live session. A real anonymous probe denied.
-fr28_vendor_visible exposes a public vendor-visibility Boolean, not private profile/order data; Admin branch uses the canonical role helper.
-fr28_pre_request is a guard with no resource result; existing nonauthenticated semantics are retained. Services remain server-authorized, not routed through a client proof.
-fr30_resolve_push is installation-secret-bound: device/user/session/token/secret-hash/notification linkage, confirmed and unblocked account, unread delivery, valid state/expiry and existing session bound. Pending activation changes only its final deadline predicate to the new absolute deadline. Its secret-bound read is intentionally separate from the authenticated REST/Edge budget; no invented universal provider quota claim.

This is a targeted bypass review, not full independent proof of all174retained function bodies/lifecycles. Storage/Realtime policies rely on canonical live-session helpers; real expiry enforcement there and signed URL near-deadline/actual expiry boundary tests remain pending. Existing inherited900-second wall-clock media evidence is not relabeled as a new run.

## Local checks and physical blocker

Full Flutter290PASS/2inherited skips; full Deno175PASS/0FAIL with scoped file/env permissions; all11Edge entrypoints type-check. Full analyzer0errors/14warnings/46infos, exit1; unresolved baseline warnings and style infos remain, including one new brace-style info in transport. Initial biometric test-double compilation and Deno index typing problems were corrected before the final passing runs; no failed run is hidden as success. Python helpers compile and diff/secret checks are recorded separately at finalization.

Compatible current-source arm64 TEST APK built using the existing configured build mirror, correct packagecom.example.flutter_application_1.fr21test; every mirrored Dart source and APK hash recorded privately. No SDK reinstall or platform upgrade. DeviceAESWNRBAEUPNTGJZ previously connected but is currently absent; attempted install did not execute. No new physical behavior test passed.

Finalization checks:9new Python helpers compile; git diff --check passes. The refreshed bounded secret scan inspected765current UTF-8 files/1015reachable small blobs at its checkpoint: no matched privileged/provider/static-private-key candidate, one current public Firebase client configuration candidate and6historical candidates. No candidate value printed, used, rotated or rewritten. This is bounded pattern evidence, not a universal secret-free assertion. Latest device-list check is still empty.

Approved rollout phase3 requires installation and physical four-role read/write/isolation/blocked/revoked/security-error journeys before enforcement. Therefore activation and enforcement acceptance are blocked on the device. After those journeys: activate0004 once, verify direct/spoofed-proof REST denials and compatible gateway/internalRPC operation, quota reset/concurrency, expired/revoked Storage/Realtime/push resolution, signed URLs near deadline, durable classified audit/immutability and accepted FR regressions. Use only a narrow reviewed forward recovery if activation fails; never reset/replay/delete fixtures.

FR42/43/44 are partially supported by passing role/server-validation/audit cases, not universally accepted. Remaining rendered Stage0/retained-body lifecycle and physical secure-storage/biometric fault/enrollment evidence are explicit gaps. Original HIGH findings remain resolved; conditional media path secured; biometric policy documented in FINAL-biometric-security-policy.md, actual device policy evidence pending. FR14 remains NOT FUNCTIONALLY ACCEPTED. Stage2 readinessNO.

## Decisions and Git

User approvalsA/B/C and exact phased TEST integration are recorded in FINAL-stage-0-1-acceptance.md; no policy reapproval required. NEEDS BUSINESS DECISION rows remain deferred for later stages. COD collected/online payment/refund settlement is never inferred. No Stage4 hides or payment provider work started.

Branchfeature/final-0-1-completion, baseline553039d, Stage0 documentation1458b2a. External unrelated a4df14a committed only the298pre-existing worktree deletions; preserved untouched. Security completion checkpoint is a separate scoped commit. No secrets/APKs/raw build or sensitive logs are included. Exact file manifest is recorded in the redacted evidence artifact during finalization.

## FINAL02 current checkpoint — 2026-10-23 (Asia/Karachi)

Stage0 PARTIAL; Stage1 PARTIAL — SECURITY ACCEPTANCE PENDING; Stage2 readiness NO. This supersedes earlier pending-approval/device/activation labels while preserving their history. A/B/C approvals remain granted within their exact scopes.

Canonical inventory:56files,410source templates,295noncontrol references,707historical crosswalk rows. Corrects the earlier406/297checkpoint for three interactive maps/PageView; passive map preview remains composition. Source-template counts are not runtime pass counts. See [canonical controls](FINAL02-ui-canonical.md) and [rendered-state evidence](FINAL02-rendered-states.md).

TEST0004applied once after successful readiness/25rollback checks;25post checks passed. Current42versions/83RLS-enabled tables/174functions. Post-activation108four-role,13boundary,20targeted,5real signed-CNIC deadline,12own-profile Realtime,8rollback-only and10actual anonymous installation-capability,11physical/hosted lifecycle checks passed within their named scopes. Installed TEST APK/source hashes match; four-role routing/restoration, blocked/re-login and revoked/logout observations recorded individually. Marked customer confirmed active; phone logged out. Final affected18PASS; scoped analysis0issues. Historical290Flutter/2skips,175Deno and173hosted results are not new full-suite runs or additive totals.

See [current acceptance checkpoint](FINAL-stage-0-1-acceptance.md#final02-current-checkpoint--2026-10-23-asiakarachi), [policy/validation/Admin-audit matrix](FINAL02-security-matrix.md), [current evidence](evidence/FINAL02-acceptance.json) and [retained feature reconciliation](evidence/FINAL02-retained-features.json). Remaining evidence: full conditional rendering/handlers, other private Realtime topics/media paths, physical error/retry and secure-storage faults, independent retained-definer/legacy-operation proof. FR42/43/44 PARTIAL; FR14 NOT FUNCTIONALLY ACCEPTED. No Stage2–5 work, production modification, reset/replay, push or merge.
