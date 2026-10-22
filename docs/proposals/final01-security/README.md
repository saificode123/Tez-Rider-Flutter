# Coordinated TEST security integration — approved phased rollout

## Current authority and rollout checkpoint — 2026-10-22

The user explicitly approved this exact phased TEST integration, including prospective30-day retention only for newly introduced API-failure logs. The earlier automatic approval-review rejection is resolved by that subsequent explicit implementation approval. The original proposal below and code in this directory are historical review material, **not deployable sources**. Active reviewed code is in lib/, supabase/functions/ and the separately split migrations202610220003/0004. Never deploy the unsplit prototype here.

Phases1–2 now executed on TEST: additive prerequisite migration0003 applied once (41total versions),11compatible functions deployed,25real-session prerequisite checks and108gateway compatibility checks passed. A current-source compatible APK built;290Flutter tests and175Deno tests pass.18synthetic COD workflow checks,13controlled quota/expiry/media checks and9block/unblock/revocation checks pass. Actual evidence is in ../../evidence/FINAL01-security-results.json and ../../FINAL01-security-verification.md.

Phase3 remains incomplete because AESWNRBAEUPNTGJZ is absent. No physical behavior pass is claimed. Phase4 enforcement migration0004 passed25rolled-back review checks but is **NOT APPLIED**; direct REST remains compatible and can bypass the new application counter. RLS/Realtime/installation-secret absolute deadlines are not globally activated. Do not create a readiness assertion or activate until the documented client journeys pass. No production changes, provider sending, Docker or paid dependency.

## Historical proposal (superseded status statements)

Status: UNDEPLOYED DESIGN/PROTOTYPE. This directory is outside active Supabase migration/function roots. Do not deploy it as-is. The policy deviation C was explicitly approved in chat on2026-10-22: "Approve the zero-cost deviation". That approval has not yet produced a deployed session/rate control.

The automatic approval review rejected the attempted client/Edge integration edit because its scope spans the HTTP transport and nearly every Edge Function, with outage/authorization-regression risk. No part of that rejected edit ran. Existing database history remains40versions; fr28_pre_request, Flutter HTTP transport and deployed Edge entrypoints are unchanged by this proposal. Only the separately tested assistant Retry-After header was deployed earlier.

## Exact requested implementation scope

- Adapt lib/services/account_session_service.dart and lib/main.dart so authenticated TEST REST calls pass through security-gateway while preserving user JWT, response/error semantics, query/range headers and existing account-denial handling. Auth/Storage/Realtime keep their separately approved provider/feature boundaries. No private key in Flutter.
- Add the new security-gateway Edge Function and shared security-runtime boundary. Adapt the10existing index.ts entrypoints: admin-user-status,fr04-cnic,fr13-location,fr25-evidence,fr30-dispatch-push,fr32-email-worker,fr32-invoice-url,get-delivery-route,send-delivery-otp,shopping-assistant. Preserve existing worker secrets, canonical authorization, input/file validation, transactions, idempotency and lower provider quotas. Add a gateway config entry.
- Apply separately reviewed additive TEST migrations: private shared counter/proof key/failure aggregation; POST JWT authorization; service-only request tickets and classified audit logging. Enforce session-created-at+7days (or earlier existing not_after) in canonical RLS/session checks. Require private server-to-server proof for authenticated direct REST operations so callers cannot bypass the application request budget.
- Cap newly minted CNIC/evidence/invoice signed URLs by the remaining authorization interval as well as900seconds. Preserve existing files and stored URLs; no file migration/deletion or public bucket.
- Log bounded authentication/authorization/server failure classes without tokens/CNIC/raw arguments. Validation/business-rule failures remain distinct. Proposed retention is30days ONLY for newly introduced final01_api_* failure records; existing Admin/audit history is untouched. This prospective retention is part of the requested approval, not already enabled.

## Phased rollout, not a single blind migration

1. Split the supplied migration prototype into additive prerequisites and later enforcement. Review SQL/ACL/search-path dependencies and pure deadline boundaries without destructive hosted fixtures.
2. Deploy the unused gateway and compatible shared boundaries to TEST before enforcement. Verify real signed-user positive/negative authorization and worker-secret compatibility, without actual provider spend.
3. Build/install the compatible TEST client; execute representative four-role/read/write/isolation/blocked/revoked/security-error journeys on isolated synthetic data. Adapt only affected regression callers and preserve direct-bypass denial probes.
4. Activate proof-required REST and absolute deadline only after compatible callers pass. Verify direct REST denial, expiry/refresh/revocation, shared quota/concurrency, media TTL and immutable classified audits. Re-check accepted FR integration and Android behavior.
5. Roll back an activation problem via a narrow reviewed forward change restoring only the previous pre-request transport gate, while retaining RLS/block checks/audit history. No reset, migration replay, credential rotation, production modification, push or merge. Do not mark acceptance until actual tests pass.

Prototype evidence:26mocked/pure Deno tests pass; gateway index/shared runtime type-check passes. SQL has NOT executed; Flutter transport/Edge integration is NOT implemented; hosted gateway/expiry/shared-budget tests are NOT executed. Existing79SQL/86HTTP/279Flutter/143Deno counts remain historical evidence, not proof of this prototype. Activation is unsafe until the phased integration and missing authorization/anonymous-surface/worker/Realtime tests are completed.

Files here are a reviewable starting point and require refinement, particularly splitting activation, proving every direct/anonymous bypass boundary, checking provider-owned session semantics, testing signed URL deadlines, and verifying retention scope. They are not finished production code.
