# FR-28 readiness - 2026-10-15

Dedicated TEST only: `igeisilhtmglgnqvllrx`. Production `arrqsvejrfdbacfwtpcc` was not accessed. Branch `feature/FR-28-admin-block-users` started at `ec1c63b`; all five accepted feature commits are ancestors. Unrelated `.gitignore` edits are preserved and excluded from the FR28 commit.

## Authorization and consistency

`public.users.is_blocked`: false = active account authorization; true = SRDS BLOCKED. Verification, CNIC, product availability and operational flags remain independent. `auth_user_id` binds the canonical Supabase identity. The directory selects only required fields in pages of 25, capped at 50 server-side, with newest-first cursor ordering, literal name/email search and role/status filters.

Block commits the database denial, rider Offline state and one BLOCK_USER audit before external Auth work. Unblock retains denial until Auth unban and targeted session revocation are confirmed, then commits one UNBLOCK_USER audit. A unique pending operation, UUID replay, row locks and a transaction-level advisory lock serialize requests. Failed or interrupted external work remains fail-closed; the admin screen exposes Retry synchronization with the same UUID. Auth side effects cannot be rolled back by PostgreSQL.

Auth Admin `ban_duration` is used server-side. Ban alone does not invalidate an unexpired access JWT. Session removal is a restricted server-only SQL operation against the target's Auth refresh tokens/sessions, followed by database verification. Clients never receive service-role keys or database credentials. Managed Auth schema compatibility must be rechecked after Auth upgrades. Own account-status RPC and own filtered Realtime profile subscription are narrow exceptions needed to display the support message; they do not authorize business actions.

## Deployed migrations and policies

- `202610140003_fr28_account_blocking.sql`: authority, identity binding, operations, audit uniqueness, indexes, RLS/session guards, REST pre-request 403 and guarded privileged functions.
- `202610140004_fr28_identity_trigger_context.sql`: fixed-path definer identity trigger; trusted JWT caller checks retained. Fixes the initial service-role Auth-schema lookup failure.
- `202610140005_fr28_order_policy_cycle.sql`: trusted vendor membership helper removes the inherited orders/vendor_orders RLS recursion while preserving cancellation ownership and state restrictions.
- `202610140006_fr28_active_order_bounds.sql`: separate indexed active-order branches, capped at 21 distinct IDs; existing orders remain unchanged.

All five migrations were applied once to TEST after history checks and rollback review. No reset or previous migration replay. Final history contains 24 versions. Exact 49 new policies, two modified existing policies, changed functions and four guarded Edge entry points are listed in `evidence/FR-28-policy-inventory.json`.

- `202610140007_fr28_canonical_service_identity.sql`: CNIC begin/finish and OTP actor/recipient use the bound Auth UUID and current confirmed Auth email. Rolled-back email-drift tests protect a blocked alias victim.

## Configuration and executed checks

No dependency or Android/iOS permission changes. Edge uses existing built-in server secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`. Hosted entry point is deliberately TEST-bound. Four deployed functions: `admin-user-status`, `fr04-cnic`, `fr25-evidence`, `send-delivery-otp`. JWT validation and trusted account/role checks are explicit in the function; gateway `--no-verify-jwt` does not permit anonymous actions.

- Dependency resolution: PASS; existing package constraints retained.
- Changed Dart formatting: PASS.
- Full Flutter suite: 95 PASS, two conditional hosted tests skipped. Backend regression runners separately exercised real hosted behavior.
- Mocked Edge tests: 23 PASS; secured entry-point type check PASS.
- Deployed-schema SQL: 54 PASS, all synthetic effects rolled back.
- Final hosted FR28: 74 PASS, including explicit protected mobile REST/Edge 403, real Auth ban/unban, session revocation, distinct-UUID and conflicting concurrency, audit, interruption recovery and unchanged active orders.
- Hosted regressions: FR21 47, FR04 49, FR25 83, FR26 95, FR33 39 PASS. FR33 sent no real mail. The first FR21 run failed after 42 passes due to inherited recursive RLS; the repaired rerun passed all 47.
- Whole-project final analysis: zero errors, 16 inherited warnings, 86 information diagnostics (82 inherited and four FR28 brace-style diagnostics). FR28 services/tests: no issues.
- Read-only `EXPLAIN ANALYZE`: bounded order read 47.094 ms, account guard InitPlan evaluated once in 2.142 ms. This is one database diagnostic, not an HTTP p95 or capacity claim.

Sanitized durable summaries are under `docs/evidence/FR-28-*`. Execution logs, screenshots and APK remain ignored under `.fr21-local/fr28/`. APK matches all 95 Dart sources; TEST package `com.example.flutter_application_1.fr21test`, SHA256 `5f664cd1129b726c139f4261cba846ce97f1b5ea0e9f1beabb2bff532fe20c41`. Installation preserves app data on `AESWNRBAEUPNTGJZ`. Physical scenarios and final acceptance are recorded separately.

## Limits

Load script: `tests/load/FR-28.js`, loopback-only, staged up to 1,000 VUs, synthetic-marker protected, with expected authorization/conflict rejections separated from unexpected errors. Load execution is NOT EXECUTED: dedicated local stack/fixtures have not been initialized. Docker is now operational (8 CPUs, 3.754 GiB, no containers). This is not a Docker installation failure. No hosted Free or production stress was run; 800 ms p95, <1% error and 1,000-user capacity remain unqualified.

Existing signed Storage bearer URLs remain usable until their existing TTL (up to 15 minutes); they are capabilities rather than account-authenticated calls. Revoking them individually needs a broader storage architecture/object replacement. Protected mobile REST and Edge operations are independently guarded and their blocked responses were verified as 403. Direct `POST /storage/v1/object/list/rider-cnic` with the old blocked rider JWT returned HTTP 200 and an empty list, revealing no protected data; see `evidence/FR-28-storage-status.json`. The app uses the guarded `fr04-cnic` Edge path, which returned 403. Enforcing 403 on the separately operated direct Storage API would require a broader proxy/gateway architecture; RLS is never presented as automatically returning 403 on every product.

Current [Supabase Free quotas](https://supabase.com/docs/guides/platform/billing-on-supabase): 500,000 Edge invocations/month, 200 peak Realtime connections, 2 million Realtime messages/month and 500 MB database size. These limits do not support a claim of 1,000 simultaneous hosted Free subscribers. [Auth session documentation](https://supabase.com/docs/guides/auth/sessions), [sign-out](https://supabase.com/docs/guides/auth/signout) and [Auth Admin ban API](https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid) support the separate JWT/database/session treatment. [Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits) are endpoint-specific; this implementation handles 429 and timeouts, and does not claim to add a universal gateway rate limit.

## Final acceptance

FR28 core native checks and fresh native FR25 dispute/image submission, FR26 confirmed admin rejection/private evidence and FR33 real email/code completion passed on the final APK. The user entered the email code privately on the authorized phone. One proof/completion audit, one dispute/evidence/submission notice, one decision audit/owner notice and zero refunds were verified. Native decision uncertainty recovered automatically through Realtime to read-only. Final native logs: zero fatal/unhandled/Auth/API errors. Final reconciliation: 24 migration versions, no pending operations or duplicate audits, all synthetic accounts restored. FUNCTIONALLY ACCEPTED; load qualification remains NOT EXECUTED. No production access, push or merge.
