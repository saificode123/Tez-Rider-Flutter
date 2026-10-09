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

- **18 complete** (as reported)
- **5 partial**: FR-04, FR-21, FR-25, FR-26, FR-33
- **8 not implemented**: FR-10, FR-13, FR-14, FR-17, FR-20, FR-28, FR-30, FR-32
- **5 not covered by the review (must be verified in code)**: FR-15, FR-22, FR-42, FR-43, FR-44
- **Extra gap, no FR number**: mandatory pre-delivery checklist (SRDS 1.3, 2.3.3, Table 5.6 row 16)

Counts above do not add up to 36 because the five unverified FRs are listed separately from the status buckets.

## Feature status (as reported)

### User management

| FR           | Status      | Notes                                                                                                         |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------- |
| FR-01, FR-02 | Complete    | Register/login via Supabase Auth, `auth_controller.dart`. Biometric login exists (not in SRDS)                |
| FR-03        | Complete    | Vendor/rider pending until admin approval, `admin_controller.dart`                                            |
| FR-04        | **Partial** | `signup_screen.dart` has a CNIC number field. CNIC document image upload is missing (Table 5.6 row 3, SEC-09) |
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
| FR-19 | **Partial (verified during FR-21 inspection)** | Original client matching used Haversine distance but omitted verification/freshness and was not atomic. FR-21 now provides transactional matching; migration/device validation remains pending. |
| FR-20 | **Not implemented** | Returns a message if no rider found; no radius expansion and no admin notification    |
| FR-21 | **Implemented locally; production blocked (2026-10-10)** | Revised migration reuses users.verification_status, is rerunnable, protects presence/identity/assignment writes, and supplies transactional location, assignment and reservation release. Local Flutter, SQL/RLS and 1,000-VU tests executed; see docs/FR-21-verification.md for actual results and APK evidence. Remote columns/RPCs remain absent. All 10 legacy rider rows reference vendor accounts and remain unchanged; no backup/restore or production approval exists. |
| FR-22 | Not reviewed        | Rider performance metrics after each delivery                                         |

### Feedback and disputes

| FR           | Status      | Notes                                                                                                                                             |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-23, FR-24 | Complete    | Customers can rate; average ratings calculated in `vendor_controller.dart`                                                                        |
| FR-25        | **Partial** | App has a "Dispute with Admin" chat room only. SRDS requires reason dropdown, evidence images, 24 h window (Figure 3.3.1-G, Table 5.6 rows 20-21) |
| FR-26        | **Partial** | Admin can mark "Resolved", but the dispute path relies on mock fallback data                                                                      |

### Admin

| FR           | Status              | Notes                              |
| ------------ | ------------------- | ---------------------------------- |
| FR-27, FR-29 | Complete            | Approvals and analytics            |
| FR-28        | **Not implemented** | No block/unblock UI or logic       |
| FR-30        | **Not implemented** | No broadcast notification composer |

### Notifications

| FR    | Status              | Notes                                                                                                                                                                                                                                  |
| ----- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FR-31 | Complete            | In-app notifications                                                                                                                                                                                                                   |
| FR-32 | **Not implemented** | No email dispatch for invoices/confirmations                                                                                                                                                                                           |
| FR-33 | **Partial**         | `verifyOtpAndDeliver` in `rider_controller.dart` works, but the OTP is shown in plain text on the customer dashboard (`customer_dashboard.dart` around line 1400) and never sent. Needs the approved email OTP, 3-attempt limit (S-04) |

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
