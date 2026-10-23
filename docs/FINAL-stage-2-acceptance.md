# Stage 2 functional acceptance — execution in progress

Baseline b19dc24 verified clean; branch feature/final-2-functional. SRDS PDF and approved roadmap govern scope. Stage0/1 reports remain unchanged. TEST igeisilhtmglgnqvllrx only;45existing migrations/84tables/175functions verified before implementation. Android AESWNRBAEUPNTGJZ connected on initial check. No production modifications, Docker, load test, push or merge.

Assigned scope: 18 roadmap workstreams. None is newly accepted by this matrix. Retained accepted subfeatures are reused within their exact scope.

## Execution matrix

| Requirement ID | SRDS requirement / roadmap workstream | Current implementation | Missing functionality | Backend work | Flutter work | Tests | Acceptance status |
|---|---|---|---|---|---|---|---|
| S2-01 | FR01/03/27 vendor onboarding/review | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Confirm idempotent app profile/vendor store after Auth; validate address/name; pending until approval; reasoned rejection and notices | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Fresh confirmed vendor signup/retry/rejection/approval/native login | IN PROGRESS |
| S2-02 | FR14 physical route acceptance | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Nonzero actual road route, meaningful GPS progression/ETA, off-route recompute and terminal cleanup; preserve quota guards | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Authorized Android lifecycle with real movement/screenshots/state; no quota reset/manufactured coordinates | PENDING |
| S2-03 | FR15 full identity card | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Add authorized rider photo/rating alongside name/maskedCNIC; required status stepper | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Customer own/unassigned/reassigned/terminal/error flows | PENDING |
| S2-04 | FR07 persistent multivendor cart | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Account-scoped persistence/restore, stock refresh and concurrency; decide Table5.6 add-time reservation policy | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Restart/logout/account-switch/multi-vendor/out-of-stock/concurrent checkout | POLICY INPUT PENDING; independent implementation continues |
| S2-05 | FR06 catalogue/search | Implemented real catalogue, exact server categories, bounded keyset pages; removed fabricated featured products | Native journey pending | Applied005; restrictive merchant visibility; validated invoker APIs | Dashboard/Search/ProductController integrated; no stale-response overwrite | 8SQL cases review/post;11real HTTP checks;92combined Flutter | IMPLEMENTED; native pending |
| S2-06 | FR08/UC06 payment and refund | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Truthful COD records; approved A COD-only scope; confirmed manual cash/refund ledgers; no provider integration or card handling | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Confirmed cash/refund success/failure/replay and COD ledgers | PENDING |
| S2-07 | FR10/26 refund settlement | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Reconcile pending refund actions with confirmed provider/manual outcomes; preserve dedup and whole-parent cancellation | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Duplicate/out-of-order/failure/partial-write reconciliation | PENDING |
| S2-08 | FR11/12 timeline/history | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Complete normal/shared/legacy lifecycle, per-vendor items and payment/refund context | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Every transition/itemization/history paging | PENDING |
| S2-09 | FR16 product images/full CRUD | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Repair product-images path and signed access; preserve FR17 numeric RPC/version/stock logic | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Gallery/invalid/oversize/expiry/CRUD/ownership | PENDING |
| S2-10 | FR18 vendor reporting | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Delivered-only revenue/transaction/earnings definitions; per-order breakdown and real performance | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Zero/error/delivered/cancelled/refunded datasets and native checks | PENDING |
| S2-11 | FR22 rider metrics/earnings | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Store completion rate/average duration/rating and per-delivery earned fee ledger on confirmed completion; not full order amount | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Exact-once delivery/retry/cancel/refund and timezone boundary tests | POLICY INPUT PENDING; independent implementation continues |
| S2-12 | Photo proof | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Capture/upload/read proof linked to assigned owned delivery; clarify photo timing without weakening OTP/checklist | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Wrong-role/missing/invalid/duplicate/upload retry/expiry/device tests | PENDING |
| S2-13 | FR23/24 dual feedback | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Delivered-order owner/rider/vendor targets; duplicate prevention/averages/realtime/profile display | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Cross-order/duplicate/range/realtime/native dual rating | PENDING |
| S2-14 | Automatic low-rating blocking | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Configurable trusted computation/decision/audit and notification; preserve active-delivery safety | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Threshold boundaries/repeated events/low sample/unblock/recompute | POLICY INPUT PENDING; independent implementation continues |
| S2-15 | FR29 monitoring/manual assignment | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Live counts/map/order detail; nearest eligible candidate/manual assignment after escalation; full KPIs and export | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Four-role denials/live changes/conflicts/replay/export reconciliation | PENDING |
| S2-16 | Profile/Urdu/notifications | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Name/phone/email/address/avatar/role fields; vendor settings; Urdu/RTL; required event push/inbox/iOS compatibility | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Four-role profile/relogin/locale/RTL/notification permission/reconnect tests | PENDING |
| S2-17 | S01 confirmations | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Confirm/cancel on cancellation/account deletion if present/block/review/delete as applicable | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Cancel/no-change, duplicate/in-flight, confirmed server result | PENDING |
| S2-18 | Existing non-SRDS module integration | Retained accepted subset and gaps in SRDS-traceability; inspect before editing | Preserve tailoring/prescription/chat/AI; restore only approved scoped server paths, no new features | Reuse current schema/RPCs; trusted validation and role/session guards | Reuse existing GetX screens/controllers | Ownership/network/validation/result checks | DEFERRED where B says NEEDS BUSINESS DECISION; preserve secured existing scope |

## Recorded scope decisions

- SRDS FR15 is rider identity before delivery; FR22 is stored rider performance metrics after delivery. S-01 is destructive-action confirmation, not search.
- FR14 physical road/route/ETA/progression is explicitly assigned to Stage2; existing NOT FUNCTIONALLY ACCEPTED status is retained until actual evidence passes.
- Approved A is COD-only with explicit online/callback/automatic-provider-refund deviations. No JazzCash sandbox or live financial transaction is authorized here.
- B NEEDS BUSINESS DECISION remains deferred; this task does not resolve optional gift, wishlist/tailoring/prescription/support business rules by inference.
- Rider compensation, low-rating threshold/sample/window/active-delivery/manual-unblock policy, and cart reservation expiry are unspecified. Asked once; user replied “continue implementation”. No numeric business values or material deviation inferred. Implement configurable boundaries and labelled synthetic tests while keeping actual policy-dependent acceptance pending.
- Required proof photo is additional to accepted checklist/OTP; it cannot silently replace OTP.

## Evidence status

No new functional acceptance yet. Read-only TEST schema and migration inspection completed; app implementation and positive/negative hosted/device evidence will be recorded per workstream.

## Final acceptance matrix (updated from executed evidence)

| ID | Feature | Flutter | Backend | Security | Automated tests | Hosted TEST | Android | Status |
|---|---|---|---|---|---|---|---|---|
| S2-01 | FR01/03/27 vendor onboarding/review | Implemented | Applied004 | Owned live sessions/roles, exact-once audit/notices | Included92PASS cohort | 19SQL review/post +27HTTP/Realtime | Fresh email/native pending | PARTIAL |
| S2-02 | FR14 physical route acceptance | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-03 | FR15 full identity card | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-04 | FR07 persistent multivendor cart | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-05 | FR06 catalogue/search | Implemented | Applied005 | Rejected merchant direct/API denied; anon denied | Included92PASS cohort | 8SQL review/post +11HTTP | Pending | PARTIAL |
| S2-06 | FR08/UC06 payment and refund | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-07 | FR10/26 refund settlement | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-08 | FR11/12 timeline/history | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-09 | FR16 product images/full CRUD | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-10 | FR18 vendor reporting | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-11 | FR22 rider metrics/earnings | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-12 | Photo proof | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-13 | FR23/24 dual feedback | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-14 | Automatic low-rating blocking | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-15 | FR29 monitoring/manual assignment | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-16 | Profile/Urdu/notifications | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-17 | S01 confirmations | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |
| S2-18 | Existing non-SRDS module integration | Pending | Pending | Preserve Stage1 | Not executed | Not executed | Not executed | Not accepted |

## Cohort 01 — verified implementation checkpoint (2026-10-23)

TEST now47migration versions after004and005, each applied once after matching-hash rollback review. Evidence: `evidence/FINAL2-01-results.json`; implementation notes: `FINAL2-onboarding.md`, `FINAL2-catalogue.md`.92Flutter PASS/0FAIL/0SKIP. Onboarding19SQL cases and27realHTTP/Realtime checks; catalogue8SQL cases and11HTTP checks. Candidate/post runs overlap and are not summed. No new physical acceptance or full workstream signoff is claimed.
