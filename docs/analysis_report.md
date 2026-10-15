# Tez Rider: Implementation Analysis Report

Status: **reported by an earlier code review, NOT verified line by line.** Any agent using this file must check each claim against the actual source before relying on it. Where the code and this report disagree, the code wins and this file should be corrected.

Authoritative requirements: `docs/Tez Rider SRDS updated.pdf`.
Stack: Flutter + GetX, Supabase (PostgreSQL, Auth, Storage, Realtime, Edge Functions).

## Approved SRDS deviations

| FR    | SRDS says                    | Approved change                                                                                 |
| ----- | ---------------------------- | ----------------------------------------------------------------------------------------------- |
| FR-33 | OTP delivered by SMS gateway | OTP delivered by email, sent from a server-side Edge Function (SMS has no reliable free option) |

## Corrected summary

The SRDS has 36 FRs: FR-01 to FR-33 and FR-42 to FR-44. The earlier summary (19 / 7 / 10) did not match its own details. Recounted:

- **19 functionally complete** (historical count adjusted for the narrower verified FR-31 scope; later feature rows contain newer acceptance evidence)
- **7 partial or pending verification**: FR-04, FR-21, FR-25, FR-28, FR-30, FR-31, FR-33 (see later verified feature rows)
- **5 not implemented**: FR-10, FR-13, FR-14, FR-17, FR-32
- **5 not covered by the review (must be verified in code)**: FR-15, FR-22, FR-42, FR-43, FR-44
- **Extra gap, no FR number**: mandatory pre-delivery checklist (SRDS 1.3, 2.3.3, Table 5.6 row 16)

These historical buckets are not a fresh review of every feature; use the later verified rows for current acceptance. FR-19/20 were checked against source for this task.

## Feature status (as reported)

### User management

| FR           | Status      | Notes                                                                                                         |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------- |
| FR-01, FR-02 | Complete    | Register/login via Supabase Auth, `auth_controller.dart`. Biometric login exists (not in SRDS)                |
| FR-03        | Complete    | Vendor/rider pending until admin approval, `admin_controller.dart`                                            |
| FR-04        | **Functionally accepted; scale qualification outstanding** | Implemented and integrated in code/TEST: private validated JPEG/PNG uploads, encrypted CNIC numbers, masked owned-order identity, 900-second viewing and server-enforced approval (Table 5.6 row 3; S-05/SEC-08/SEC-09). Actual hosted and Android evidence is in `FR-04-readiness.md` and `FR-04-acceptance.md`; fresh native email confirmation/upload/approval/login, oversized/corrupt rejection and real fifteen-minute viewer expiry passed. Bounded Tokyo read p95 is below 800 ms; full 1,000-user qualification awaits local-runtime restart. Updated against real implementation on 2026-10-13. |
| FR-05        | Complete    | Role-based routing to dashboards                                                                              |

### Orders

| FR                  | Status              | Notes                                                                                                                                                     |
| ------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-06, FR-07, FR-08 | Complete            | `enhanced_checkout_screen.dart`, multi-vendor cart, delivery fee split. Payment/refund integration (UC-06, Table 5.6 rows 9-11) not covered by the review |
| FR-09               | Complete            | `vendor_dashboard.dart`                                                                                                                                   |
| FR-10               | **Not implemented** | No timer, edge function or frontend logic to cancel timed-out orders                                                                                      |
| FR-11, FR-12        | Complete            | `order_timeline.dart`, `order_history_screen.dart`                                                                                                        |

### Tracking and delivery

| FR        | Status                          | Notes                                                                                                                               |
| --------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| FR-13     | **Not implemented (simulated)** | `rider_dashboard.dart` reads GPS once at startup. `map_screen.dart` runs `_simulateRider()` and pushes fake coordinates to Supabase |
| FR-14     | **Not implemented**             | Depends on FR-13. No route or ETA                                                                                                   |
| FR-15     | Not reviewed                    | Rider info before delivery                                                                                                          |
| Checklist | **Not implemented**             | No pre-delivery checklist UI or logic                                                                                               |

### Vendor and product

| FR    | Status              | Notes                                                                           |
| ----- | ------------------- | ------------------------------------------------------------------------------- |
| FR-16 | Complete            | `product_form_screen.dart`, image upload to Supabase Storage                    |
| FR-17 | **Not implemented** | `ProductModel` only has `isAvailable`; no stock quantity, no decrement on order |
| FR-18 | Complete            | `vendor_analytics_screen.dart`                                                  |

### Rider management

| FR    | Status              | Notes                                                                                 |
| ----- | ------------------- | ------------------------------------------------------------------------------------- |
| FR-19 | **Implemented/verified for FR-20 assignment scope (TEST, 2026-10-15)** | Existing FR21 transaction extended with indexed WGS84 distance, nearest approved/unblocked/fresh/available rider, atomic active-assignment uniqueness and preserved child/parent delivery flow. Final SQL63, hosted70+5 shared-parent checks and native assignment/notifications passed. Live GPS/ETA remain outside this scope. |
| FR-20 | **Functionally accepted; scale qualification outstanding (2026-10-15)** | Three new TEST migrations;5km then10km search, manual escalation/actual receipt, exactly-once notifications/audits, canonical authorization, concurrency invariants, status reconciliation and preserved shared-parent readiness. SQL63, Flutter112(two skips), hosted70+5 and native vendor/rider/admin checks passed. Local10VU p95 188.422ms;1000VU NOT EXECUTED for memory. See FR-20-acceptance.md.    |
| FR-21 | **Implemented locally; production blocked (2026-10-10)** | Revised migration reuses users.verification_status, is rerunnable, protects presence/identity/assignment writes, and supplies transactional location, assignment and reservation release. Local Flutter, SQL/RLS and 1,000-VU tests executed; see docs/FR-21-verification.md for actual results and APK evidence. Remote columns/RPCs remain absent. All 10 legacy rider rows reference vendor accounts and remain unchanged; no backup/restore or production approval exists. |
| FR-22 | Not reviewed        | Rider performance metrics after each delivery                                         |

### Feedback and disputes

| FR           | Status      | Notes                                                                                                                                             |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-23, FR-24 | Complete    | Customers can rate; average ratings calculated in `vendor_controller.dart`                                                                        |
| FR-25 | **Functionally accepted; performance qualification outstanding** | Structured customer disputes/evidence/history and secured TEST RPC/Storage passed hosted and final-APK Android verification, including exact messages, expiry, network Retry, private viewing, account isolation and preserved chat/Realtime. FR-04/FR-21 regressions passed. Isolated 1,000-VU qualification aborted for RAM without a complete latency/error result. See `FR-25-readiness.md` and `FR-25-acceptance.md`. |
| FR-26 | **Functionally accepted; scale qualification outstanding** | TEST admin queue/details, private900-second expiry/refresh, confirmed Resolve/Reject, atomic pending-refund/audit/owner notice, immutable/replayed outcomes, physical Realtime/customer notes/notifications and native FR-25 submission/chat verified. Final hosted95, SQL91, canonical-payment6, Flutter19 new tests passed. Paired local10-VU passed; 1,000-VU NOT EXECUTED for RAM. See `FR-26-readiness.md`, `FR-26-acceptance.md` and evidence. |

### Admin

| FR           | Status              | Notes                              |
| ------------ | ------------------- | ---------------------------------- |
| FR-27, FR-29 | Complete            | Approvals and analytics            |
| FR-28 | **Functionally accepted; scale qualification outstanding (2026-10-15)** | Real admin UI; canonical `users.is_blocked` authorization; recoverable Auth synchronization; restrictive RLS/REST 403 and audit. Five FR28 migrations/four Edge functions deployed only to TEST. Flutter 95 (two skips), SQL 54, Edge 23 and hosted 74 passed; physical FR28 customer/rider/vendor checks passed. Fresh native FR25 private-image submission, FR26 confirmed admin rejection/private viewer and FR33 real-email/code completion passed. Final reconciliation and runtime logs passed. Load NOT EXECUTED; local commit authorized, no push/merge. See FR-28 acceptance/readiness. |
| FR-30 | **Partial — native push pending approval** | In-app composer, confirmation, estimates, secure atomic fan-out, stable admin history, canonical blocked/session guards, UUID replay and audit implemented. TEST SQL/HTTP/Realtime and Flutter evidence: `FR-30-progress.md`; final status: `FR-30-acceptance.md`. |

### Notifications

| FR    | Status              | Notes                                                                                                                                                                                                                                  |
| ----- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-31 | **Partially verified** | Trusted personal and broadcast notices use owner RLS, bounded stable pagination, unread count, own read state and one Realtime channel with reconnect/resume refresh. OS push absent; legacy client `sendNotification` writes are denied by current grants, so not all automatic notification creation paths are accepted. See `FR-30-acceptance.md`.                                                                                                                                                                                                                   |
| FR-32 | **Not implemented** | No email dispatch for invoices/confirmations                                                                                                                                                                                           |
| FR-33 | **Functionally accepted on TEST** | Server-only CSPRNG email OTP through TEST Edge Function/Brevo, Vault HMAC verifier, no plaintext client/DB code, three-attempt lockout, atomic idempotent delivery proof/audit/notifications. Hosted security/races, Flutter tests and physical Android/email checks passed; see `FR-33-readiness.md` / `FR-33-acceptance.md`. Additional local load qualification not executed due RAM; inherited vendor-rating permission denial documented. |

### Security

| FR                       | Status       | Notes                               |
| ------------------------ | ------------ | ----------------------------------- |
| FR-42 (RLS)              | Not reviewed | SEC-01 requires RLS on all tables   |
| FR-43 (input validation) | Not reviewed |                                     |
| FR-44 (audit log)        | Not reviewed | `security_audit_log` table (SEC-07) |

## Other SRDS items not covered by the review

- Payment integration and refunds (FR-08, UC-06, Table 5.6 rows 9-11, 22)
- S-02: "Location temporarily unavailable" after 30 s without a GPS update
- S-04: OTP limited to 3 attempts, then expires
- Low-stock alerts (Table 5.6 row 24)
- Automated blocking of consistently low-rated vendors/riders (2.3.6)
- CNIC stored encrypted and masked on customer-facing screens (SEC-09)
- Inconsistent timeout in SRDS: S-06 says 2-3 minutes, Table 5.6 row 12 says 10 minutes (needs a decision)

## Code observations (as reported)

- **Mock data fallbacks:** `mock_data.dart` is used by `vendor_controller.dart`, `admin_controller.dart` and `OrderHistoryScreen`. Controllers catch backend errors and inject fake data (mock earnings, orders, disputes), which hides real failures. Must be removed from any path being implemented.
- **State management:** GetX, with screens in `screens/` and logic in `controllers/`.
- **Out-of-scope features already built (not in SRDS, keep, do not extend):** tailoring services, pharmacy prescription uploads, AI assistant.

## Implementation log

Update after each merged feature.

| FR  | Branch | Status | Date |
| --- | ------ | ------ | ---- |
|     |        |        |      |
