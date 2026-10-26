# Automatic low-rating blocking

Owner policy: `docs/POLICY-DECISIONS.md`, approved 2026-10-25 (Asia/Karachi). The policy is owner-approved beyond the SRDS; it is not represented as a platform provider's actual rules.

## Implementation

- Migration `202610250007_final_delivery_rating_policy.sql` persists enabled state, minimum 10 reviews, 30-day window, strict average below 2.0, daily schedule, retry schedule, active-work deferral, Admin-only unblocking, reset-on-unblock, policy actor and TEST worker endpoint in `final_delivery_private.rating_settings`. Private settings/cutoffs/queue tables have RLS and no client or direct service table grants.
- Only immutable verified Vendor/Rider feedback in the current window counts. Accounts with fewer than 10 reviews, an average exactly 2.0, expired reviews or another role are excluded.
- New population evaluation happens at most once per UTC calendar day. Initial daily schedule is UTC midnight and is configurable server-side. Deferred/pending synchronization retries run every five minutes from a separate persisted schedule, without starting another population-wide evaluation.
- Active parent/child orders or active Rider delivery assignments defer blocking. The policy never cancels or reassigns an order. Before retrying a deferred block, it rechecks the current rating window; expired, improved or Admin-reset data cannot cause a stale block.
- Actual blocking reserves through existing `public.admin_set_user_blocked`, retaining FR28 operations, fail-closed account state, Rider offline transition and the normal block audit. Each automatic operation adds an explicit `auto_low_rating` audit and notifies every Admin. A persisted approved Admin is the policy's recorded authorizing actor; the audit action identifies the scheduled policy rather than a claimed manual tap. No user JWT is generated or signed. If that actor is no longer an approved unblocked Admin, the job fails visibly with `POLICY_ADMIN_REQUIRED` rather than borrowing another identity.
- TEST-only `final-rating-worker` checks a separate private worker key in constant time, validates a bounded request and invokes the service-only evaluation API. It then reuses existing FR28 Auth Admin ban, session revocation and confirmed finish hooks. Unconfirmed Auth work remains pending and is retried; it is never reported as synchronized.
- Existing Admin unblock screen/API stays authoritative. Successful transition to unblocked stores a private cutoff, so feedback verified before the unblock cannot trigger the next block. No appeal or payout module is introduced.

## Verification

- `deno test supabase/functions/final-rating-worker/handler_test.ts supabase/functions/admin-user-status/handler_test.ts`: **25 PASS, 0 FAIL** (8 new rating-worker cases; 17 retained FR28 handler/synchronization cases). This is bounded handler evidence, not physical device acceptance.
- `deno check supabase/functions/final-rating-worker/index.ts`: **PASS**. Initial restricted-network dependency lookup failed; elevated check passed using the existing PostgreSQL library.
- Actual TEST candidate rollback SQL: **23 PASS**, including three added new-work concurrency guards, after two synthetic-test alias errors were corrected. Deployed post-check repeats the same23 assertions; they overlap and are not summed. All fixtures rolled back. Simulated SQL Auth-state completion is explicitly labelled; it does not prove an actual Auth Admin API ban.
- Hash-bound review evidence: `docs/evidence/FINAL-delivery-rating-review.json`.
- Existing migration history must match the exact locally known prefix before applying this migration once. Worker secret is generated privately in Vault on TEST, then provisioned to Edge by the guarded harness. No secret values belong in source, logs or these documents.

## Deployment and rollback

Use `tests/integration/FINAL-delivery-rating.py` with the existing configured TEST CLI: `review`, then `deploy` only after predecessor migration `202610250006` is applied, then `post`, `worker-deploy`, and `status`. Every action checks the linked TEST reference. `deploy` requires successful hash-matching rollback evidence. `worker-deploy` transfers the private Vault worker secret through an ignored temporary file and removes that file after provisioning; it deploys only `final-rating-worker` using the hosted API, without Docker.

Final deployment: migration007 applied exactly once to TEST after006; exact prefix64 at deployment and hash `1a20d4201608bfea2598ad977e651bab3ff0cf0d870415412d295c99307dd73f` matches review. TEST-only final-rating-worker deployed through the hosted API; generated Vault key provisioned privately. No Docker or production modification.

Nine actual HTTP/persistence assertions passed: forbidden public invocation; real Auth ban/FR28 finish; zero pre-block target sessions; canonical blocked state/audit/every-Admin notices; old token denied; actual Admin unblock; cutoff/Auth-unban; stale-queue clearing; fresh password recovery. Inputs are explicitly marked synthetic SQL orders/reviews and target queue, not ten real deliveries or native review submissions. Evidence: `docs/evidence/FINAL-delivery-rating-hosted.json` and `FINAL-delivery-rating-reconcile.json`.

Attempt history is preserved: first nine assertions passed but cleanup had a missing SQL whitespace. Only the exact ten newly created pending fixture orders were then retired using the corrected guarded SQL. An overlapping rerun passed six assertions before a read-only CLI timeout; its finally cleanup succeeded. Final independent reconciliation confirms the target unblocked/unbanned, cutoff present, queue CLEARED, no pending fixture orders and successful new password session. No assertion counts are added across attempts. The helper now records checks incrementally and retries only a timed-out explicitly read-only query, never an uncertain mutation.

For a functional rollback, an authorized database operator first sets private `rating_settings.enabled=false` and pauses the two `final-rating-*` cron jobs. Preserve immutable audits, queue history and FR28 operation history. Do not automatically unblock accounts or undo real review/order data. Any unblock uses the existing reviewed Admin workflow; its cutoff remains useful. Source rollback alone does not reverse applied database state. Production migration/worker deployment requires explicit authorization and a separately reviewed production endpoint/server-secret configuration; this TEST worker deliberately rejects production.

Free-service limitation: retries for deferred/pending work consume scheduled HTTP/Edge invocations (up to 288 five-minute attempts/day while work remains) plus the daily invocation. No unlimited quota or production availability claim is made. With no deferred/pending queue, retry dispatch makes no HTTP request.
