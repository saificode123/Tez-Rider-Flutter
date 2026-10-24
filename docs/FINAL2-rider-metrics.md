# Stage 2 — stored Rider performance

Migration202610240004 was applied once only to TEST after28matching-hash rollback cases;28post cases PASS (overlap). TEST now56migration versions/92inspectedRLS tables (58public)/209public-private functions (145public). Eight actual authenticated gateway checks PASS. No production changes.

Private ledgers capture actual accepted assignments and completed deliveries. A confirmed OTP completion triggers one order-scoped performance record and one canonical Rider audit; terminal retries cannot duplicate either. Stored counts, completion rate (completed deliveries divided by accepted assignments), duration sample/average (acceptance to completion), and verified Customer rating update from trusted transitions. Other roles cannot use the Rider endpoint; Admin can inspect a selected Rider. Raw private data is neither client-readable nor published to Realtime. Existing accepted assignments are recorded with unknown acceptance times rather than made-up historical durations. Unlinked old completions and missing historical timing are disclosed.

The Rider Earnings page includes a real server-backed performance panel, loading/error/Retry/Refresh and account-change clearing. Six focused Flutter cases PASS. New service/panel scoped analysis0issues. Physical metrics rendering remains pending.

Compensation is still POLICY_REQUIRED with a null earned fee. This migration does not calculate wages, use order totals as wages, or transfer cash. Foodpanda's published time/distance approach is recorded in `FINAL2-policy-reference.md`; exact rates remain unspecified. S2-11 is PARTIAL until compensation and required final native verification pass. The existing checklist, OTP, refunds, financial ledger and audit boundaries remain unchanged.

Verification uses `tests/integration/FINAL2-rider-metrics.py` and the existing secured history fixture plus `supabase/tests/FINAL2-rider-metrics.sql`. Synthetic SQL OTP completion proves transaction behavior; it is not physical delivery/GPS/provider-email evidence. Detailed results: `evidence/FINAL2-14-execution-results.json`.


Physical continuation14: actual TEST Rider login restored Urdu; Earnings displayed the real stored completion/rating response and explicit missing-history/unknown-fee states. PASS, observed2026-10-24T16:36:37Z. Screenshot `evidence/FINAL2-14-rider-performance.png` was visually inspected. Existing historical All Time3 versus zero linked/timed completed records is disclosed as incomplete history; no synthetic durations or wages are added to reconcile them. This supersedes the pending physical-panel checkpoint above; compensation acceptance remains pending.
