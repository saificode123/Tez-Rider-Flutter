# Stage 0 SRDS traceability

> Current status: FINAL03 final closure at the end and FINAL-stage-0-1-signoff.md. Earlier checkpoints are historical.

> Historical Stage0 matrix retained below. Stage1 evidence update (2026-10-22): see the dated addendum at the end and FINAL-security-audit.md. Stage1 remains PARTIAL; the131-row historical counts are not rewritten.

2026-10-21, Asia/Karachi. Base `f8bce533f20650649deef31304d235554af35735`. **PARTIAL audit.**

The authoritative PDF has45 pages. Physical pages12–17 contain36 FRs:01–33 and42–44; FR34–41 are absent. The contents page's payment-table label conflicts with the actual feedback table. Payment is nevertheless mandatory under UC06,2.5.2 and Table5.6. Screen descriptions are on physical pages23–28; safety/security31–32; decision table42–45.

VERIFIED below means inherited credible **isolated TEST functional evidence in its stated scope**, usually Android/backend. It does not certify production, iOS, scale or untested broader clauses. File/function existence alone is not a pass. PARTIAL records demonstrated source gaps; NOT TESTED records insufficient evidence. No new functional test pass is claimed. Refer to FINAL-progress.md for commit ancestry and exact inspection limitations. Paths are repository-relative; migration dates identify exact files under supabase/migrations.

## Functional requirements

| ID | SRDS Requirement | Implementation Status | Code Location | Test Evidence | Missing Work | Priority |
|---|---|---|---|---|---|---|
| FR-01 | Name/email/phone/password/role registration | PARTIAL | lib/screens/signup_screen.dart; users; Supabase Auth | FR04 fresh rider signup/email acceptance | Vendor store creation uses direct denied vendors upsert; full four-role registration not accepted | P1 |
| FR-02 | Supabase authentication/JWT | IMPLEMENTED-UNVERIFIED | lib/screens/login_screen.dart; controllers/auth_controller.dart; services/account_session_service.dart | FR04/28 login evidence; account_session_test.dart | General four-role login/session expiry; hosted Auth settings | P1 |
| FR-03 | Inactive Vendor/Rider until approval | IMPLEMENTED-UNVERIFIED | services/account_access.dart; login_screen.dart; fr04_review_rider | FR04 rider approval; account_access_test.dart | Complete vendor approval/rejection and every entry route | P1 |
| FR-04 | Rider CNIC number; document prerequisites elsewhere | VERIFIED | services/cnic_document.dart; cnic_document_controller.dart; cnic_document_screen.dart; fr04-cnic;202610120001 | FR-04-acceptance.md; cnic_document_test.dart; FR14 latest hosted49 | Historical TEST functional scope only; production/iOS/scale unqualified | P1 |
| FR-05 | RBAC for all users | PARTIAL | routes/app_routes.dart; middleware/auth_middleware.dart; admin_middleware.dart; FR28 guards | account_access_test.dart; FR28 denials | Named dashboards only require session; AdminMiddleware always returns null; enforce canonical role/approval on routes | P0 |
| FR-06 | Keyword/category browse/search | PARTIAL | controllers/product_controller.dart::getProductsByCategory; screens/search_screen.dart::_search | Inventory tests cover availability only | Filter grammar encoding, stale-response race/error state, complete paged categories | P1 |
| FR-07 | Persistent shopping cart | PARTIAL | controllers/cart_controller.dart; customer/cart_screen.dart; cart/cart_items tables | inventory_test.dart stock logic | RxList has no persistence/account restore; database cart tables denied | P1 |
| FR-08 | Order/item/payment checkout records | PARTIAL | customer/enhanced_checkout_screen.dart; fr10_checkout; FR17 wrapper; orders/vendor_orders/order_items/payments | FR10/17 accepted COD checkout | Actual online payment/callback/refund adapter absent | P1 |
| FR-09 | Vendor accept/reject | VERIFIED | controllers/vendor_controller.dart::updateOrderStatus; fr10_vendor_transition | FR-10-acceptance.md; maintained FR14 HTTP24 | Historical TEST transition scope; general UI evidence separate | P1 |
| FR-10 | Timeout cancel and refund | PARTIAL | cancel_timed_out_orders; order_refund_actions;202610160001 | FR-10-acceptance.md SQL67/HTTP24; latest HTTP24 | Cancellation/refund initiation accepted; actual provider refund settlement absent | P1 |
| FR-11 | Complete order status timeline | PARTIAL | widgets/order_timeline.dart; order_timeout_summary.dart; order_timeline_events | FR10 physical timeout timeline | Every normal/shared/historical transition needs complete acceptance | P1 |
| FR-12 | Itemized order history | IMPLEMENTED-UNVERIFIED | customer/order_history_screen.dart::_loadOrders; fr25_order_history | FR25/32 history/invoice acceptance | Full multivendor itemization acceptance; no current mock history fallback | P1 |
| FR-13 | GPS every2–3seconds | PARTIAL | services/delivery_location.dart; ios_rider_location_source.dart; fr13-location; delivery_latest_locations;202610180001 | FR-13-acceptance.md; FR-13-ios-acceptance.md; latest SQL55 | Android accepted; iOS runtime unverified; approved latest-only persistence | P1 |
| FR-14 | Tracking route/ETA | PARTIAL | screens/map_screen.dart; services/delivery_route.dart; get-delivery-route;202610190001/002,202610200001 | FR-14-acceptance.md at f8bce53; Flutter70 focused; SQL54/Deno35 | NOT FUNCTIONALLY ACCEPTED; physical nonzero road/progression/deviation pending; separate local latency FAIL | P1 |
| FR-15 | Rider info before delivery | PARTIAL | screens/map_screen.dart::_loadOrder; fr04_order_rider_identity | FR04 masked identity acceptance | Name/masked CNIC exist; required photo/rating absent; assignment-to-delivery acceptance | P1 |
| FR-16 | Product CRUD | PARTIAL | vendor/vendor_products_screen.dart; product_form_screen.dart::_save; fr17_save_product/delete | FR17 numeric CRUD acceptance | product-images bucket absent; image uploader uses public URL | P1 |
| FR-17 | Stock on checkout/cancel | VERIFIED | services/inventory_service.dart; inventory_movements;202610160002 | FR-17-acceptance.md SQL53/HTTP27/races15; latest HTTP27 | Historical TEST acceptance; legacy stock unconfirmed; scale excluded | P1 |
| FR-18 | Vendor earnings/performance | PARTIAL | vendor/vendor_analytics_screen.dart::_loadData/_applyMockAnalytics; fr21_dashboard_stats | FR21 summary evidence not analytics acceptance | Fake empty/error analytics; revenue includes all statuses; no complete per-order transactions | P1 |
| FR-19 | Nearest available verified rider | VERIFIED | services/rider_assignment_service.dart; fr21_ready_and_assign;202610150001 | FR20 SQL63/HTTP70; latest maintained HTTP70 | TEST assignment scope; route/GPS separate | P1 |
| FR-20 | Radius expansion/admin notice | VERIFIED | rider_assignment_controller.dart;202610150001–003 | FR-20-acceptance.md SQL63/HTTP70+shared5/native | Accepted expansion/escalation; manual response screen separately missing | P1 |
| FR-21 | Realtime online/offline | VERIFIED | services/rider_presence.dart; controllers/rider_controller.dart; FR21 migrations | FR-21-acceptance.md; latest hosted47; FR14 recovery | Android TEST scope; production unknown | P1 |
| FR-22 | Store post-delivery rider metrics | PARTIAL | rider_controller.dart::loadEarnings; fr21_dashboard_stats | Current TEST aggregate definition inspected | Sums orders.amount using order creation time; no verified fee ledger/completion-rate/duration/rating updates | P1 |
| FR-23 | Ratings/feedback after delivery | PARTIAL | customer/rating_screen.dart::_submitReview; reviews | No passing complete rating flow identified | Direct reviews INSERT denied on TEST; canonical reviewer/order/role validation; both vendor/rider entry points | P1 |
| FR-24 | Realtime average ratings | PARTIAL | product_detail_screen.dart::_loadRating; get_vendor_ratings; vendor_info_controller.dart | FR30/33 reports retain42501; current TEST function ACL denies client execution | Remove sample reviews; trusted aggregate and realtime updates for both roles | P1 |
| FR-25 | Disputes/evidence | VERIFIED | services/dispute_service.dart; dispute_controller.dart; customer/dispute_screen.dart; fr25-evidence; FR25 migrations | FR-25-acceptance.md; committed hosted83/device/SQL; dispute_test.dart | TEST functional/security scope; scale unqualified | P1 |
| FR-26 | Admin resolve/reject | VERIFIED | admin_dispute_service.dart; admin_dispute_state.dart; admin_disputes_screen.dart; FR26 RPCs | FR-26-acceptance.md; latest hosted96; admin_dispute_test.dart | Decision/pending-refund accepted; settlement separate | P1 |
| FR-27 | Vendor/rider approve/reject | PARTIAL | admin_controller.dart::updateStatus; fr04_review_rider; admin_dashboard.dart | FR04 rider review accepted | Vendor direct update lacks equivalent audit RPC; confirm reasons/notifications/confirmations | P1 |
| FR-28 | Block/unblock | VERIFIED | admin_users_service.dart; admin_users_screen.dart; admin-user-status; FR28 migrations | FR-28-acceptance.md; latest hosted74; admin_users_test.dart | TEST manual moderation accepted; automatic low-rating blocking separate | P1 |
| FR-29 | Admin live monitoring/analytics | PARTIAL | admin_dashboard.dart::_overviewTab; admin_controller.dart::_listenToOrders | Source counts/stream; no full UC08 acceptance | Operational map/order drilldown/export/daily-weekly revenue/disputes/top-vendor/rider KPIs | P1 |
| FR-30 | Admin notification sending | PARTIAL | admin_broadcast_controller.dart; admin_broadcasts_screen.dart; fr30-dispatch-push | FR-30-acceptance.md Android; FR-30-ios-acceptance.md readiness FAIL | Android TEST accepted; iOS configuration/APNs incomplete | P1 |
| FR-31 | Realtime order/system notifications | PARTIAL | notification_controller.dart; notifications_screen.dart; AndroidBroadcastPushService | FR30 inbox/realtime/broadcast push acceptance | Legacy client sendNotification writes denied; generic-event push/iOS coverage incomplete | P1 |
| FR-32 | Email invoice/confirmation/account | VERIFIED | fr32-email-worker; fr32-invoice-url; invoice_service.dart; email_outbox/invoices;202610160003 | FR-32-acceptance.md SQL63/Deno76; fr32_invoice_test.dart | TEST scope with shared mail budget, not unlimited/production acceptance | P1 |
| FR-33 | SMS delivery OTP | DEVIATION-APPROVED | send-delivery-otp; delivery_otp_service.dart; issue/verify_delivery_otp; FR33 migrations | FR-33-srds-deviation.md explicit approval; FR-33-acceptance.md; actual inbox/native evidence | Approved server-email alternative;3-failure/security rules retained | P1 |
| FR-42 | RLS database isolation | PARTIAL | migrations; current TEST catalog below | Stage0 metadata plus feature denials | Production uninspected; private limits exception; final whole-app authorization matrix | P0 |
| FR-43 | Validate/sanitize all inputs | PARTIAL | Feature handlers/RPCs; legacy direct Flutter writes/search/storage | Feature Dart/Deno/SQL suites | Search grammar/profile bounds/general uploads/legacy APIs not universally validated | P0 |
| FR-44 | Audit critical Admin actions | PARTIAL | security_audit_log; FR04/26/28/30 inserts | Feature audit assertions; current users-trigger inventory | Vendor direct reviews/manual assignment/unhandled-error coverage incomplete | P0 |

## Use cases

| ID | SRDS Requirement | Implementation Status | Code Location | Test Evidence | Missing Work | Priority |
|---|---|---|---|---|---|---|
| UC-01 | Registration/login/role routing | PARTIAL | signup/login/auth controller/account access/routes | FR04/28 historical subset | FR01–05 gaps; all roles and entry points | P0 |
| UC-02 | Browse/cart/order/payment/history | PARTIAL | product/search/cart/enhanced checkout/history | FR10/17/25/32 subset | Persistence/payment and complete itemization | P1 |
| UC-03 | Approved vendor manages product/stock | PARTIAL | product form/products/inventory service | FR17 acceptance | Images/storage; general onboarding and permissions | P1 |
| UC-04 | Assignment/accept/pickup/GPS/delivery | PARTIAL | assignment/rider/checklist/location/OTP services | FR20/checklist/FR13/33 acceptance | Complete iOS and required photo/navigation workflows | P1 |
| UC-05 | Customer live rider route/ETA | PARTIAL | map_screen.dart; delivery_route.dart; get-delivery-route | FR14 automated/recovery subset | Physical road/progression/deviation gates pending | P1 |
| UC-06 | Secure payment/refund/invoice | PARTIAL | COD checkout/refund-action records/invoice worker | FR10/26/32 subset | Provider initiation/authenticated callbacks/refunds/reconciliation | P1 |
| UC-07 | Ratings and structured dispute/decision | PARTIAL | rating/dispute/admin dispute screens | FR25/26 accepted; ratings unaccepted | Denied ratings writes and dual averages; payment settlement | P1 |
| UC-08 | Admin orders/users/reports/moderation | PARTIAL | admin dashboard/users/disputes/broadcasts | FR04/26/28/30 subset | Vendor review audit; full monitoring/analytics/export | P1 |

## Safety and security

| ID | SRDS Requirement | Implementation Status | Code Location | Test Evidence | Missing Work | Priority |
|---|---|---|---|---|---|---|
| S-01 | Destructive confirmations | PARTIAL | admin disputes/users; product delete; admin approvals | Existing confirm/cancel feature evidence | Approval/rejection and every destructive route need consistent confirmation | P1 |
| S-02 | GPS missing30s: unavailable/no stale pin | VERIFIED | delivery_location.dart; map_screen.dart | FR13 physical stale; FR14 network test; delivery_location_test.dart | Historical Android TEST scope | P1 |
| S-03 | Payment failure PENDING/notice within2s/retry | MISSING | No real payment adapter; payment_screen.dart simulated | No provider failure evidence | State-machine semantics and time-bound notice; reconcile Table5.6 row10 wording | P1 |
| S-04 | Three OTP failures then expire/new code | VERIFIED | verify_delivery_otp; delivery_otp_service.dart | FR33 hosted/native lockout and latest39 | Approved email TEST scope | P1 |
| S-05 | Validated image-only CNIC/delivery proof | PARTIAL | fr04-cnic/fr25-evidence; storage_service.dart | CNIC/evidence validation tests | Missing delivery-photo path; generic uploader permits PDFs/extensions | P0 |
| S-06 | Default2–3min vendor timeout | DEVIATION-APPROVED | cancel_timed_out_orders/private timeout180 | FR-10-acceptance.md explicit180s policy | Contradicts Table5.6 row12 ten minutes; preserve accepted180s | P1 |
| SEC-01 | RLS on every table | PARTIAL | TEST policy inventory below | Current56 public tables enabled; feature denials | Private exception and production unknown | P0 |
| SEC-02 | GoTrue hashed passwords/no plaintext logs | IMPLEMENTED-UNVERIFIED | Supabase Auth login/signup | Historical authentication evidence | Hosted Auth/log/history scan not complete | P0 |
| SEC-03 | JWT1h/refresh7d/silent refresh | NOT TESTED | SDK/session gate | Source cannot establish hosted expiry | Inspect Auth settings, safe expiry/revocation scenarios | P0 |
| SEC-04 | Keys in dart-define/Vault; never hardcoded/committed | PARTIAL | main.dart; backend_config.dart; ai_service.dart | backend_config_test.dart; prior feature artifact scans | Client AI key architecture; complete Git-history secret audit pending | P0 |
| SEC-05 | Signed callback before payment mutation | MISSING | No payment Edge adapter | No tests | Server signature/amount/currency/order/idempotency verification | P0 |
| SEC-06 | Gateway100requests/min/authenticated user | NOT TESTED | Feature-specific throttles only | Feature quotas do not prove universal gateway policy | Hosted gateway settings unavailable; free feasibility unresolved | P0 |
| SEC-07 | Critical audit actor/action/target/time | PARTIAL | security_audit_log; FR04/26/28/30 | Feature assertions | Vendor reviews/manual assignment/error coverage | P0 |
| SEC-08 | All media signed URL15min | PARTIAL | Protected CNIC/evidence/invoice APIs; product_form/storage_service | FR04/25/26 viewer expiry acceptance | Public URL calls/product/general upload design conflicts; buckets absent | P0 |
| SEC-09 | Encrypted CNIC/customer mask | VERIFIED | fr04_private encryption; fr04_order_rider_identity; map | FR04 acceptance/latest hosted49 | TEST scope; production unknown | P0 |
| SEC-10 | All inputs sanitized in Edge Functions | PARTIAL | Edge feature handlers plus direct PostgREST writes | Feature Deno/SQL suites | Direct profile/filter/upload paths need server equivalent validation/explicit architectural interpretation | P0 |

## Table5.6: all30 scenarios

Each linked FR supplies code and test details; outcomes below cover the whole row, not only its successful subset.

| ID | SRDS Requirement | Implementation Status | Code Location | Test Evidence | Missing Work | Priority |
|---|---|---|---|---|---|---|
| T5.6-01 | Valid unique registration/email verification | PARTIAL | FR01/02 signup/Auth | FR04 fresh rider | General role/vendor flow and exact messages | P1 |
| T5.6-02 | Duplicate-email exact rejection | NOT TESTED | signup_screen.dart | No distinct current acceptance identified | Real duplicate states without account enumeration regression | P1 |
| T5.6-03 | No CNIC document blocks rider completion | VERIFIED | FR04 signup/CNIC API | FR04 physical/hosted acceptance | TEST scope | P1 |
| T5.6-04 | Vendor approval/notice | PARTIAL | FR27 direct update; FR32 account trigger | Rider/email subset only | Vendor atomic audit/reasons/confirmation/in-app notice | P1 |
| T5.6-05 | Vendor reject/support message | PARTIAL | FR27 same path | No full vendor rejection acceptance | Persist reason and exact user outcome | P1 |
| T5.6-06 | Rider approval after CNIC/notice | VERIFIED | fr04_review_rider | FR04 acceptance | TEST scope | P1 |
| T5.6-07 | Add cart/reserve stock/badge | PARTIAL | CartController.addItem | Inventory unit tests | No persistent cart or add-time stock reservation; checkout decrement is different | P1 |
| T5.6-08 | Out-of-stock reject | VERIFIED | CartController/FR17 checkout | FR17 native/HTTP shortages | TEST scope | P1 |
| T5.6-09 | HMAC-valid payment/order/invoice | MISSING | FR08/SEC05 | COD evidence is not gateway evidence | Actual authenticated payment lifecycle | P0 |
| T5.6-10 | Failed payment rollback/log/retry | MISSING | S03/FR08 | None | Clarify rollback semantics, implement/reconcile | P0 |
| T5.6-11 | Bad HMAC401/audit/Admin alert | MISSING | SEC05 | None | Authenticated callback boundary and negative/replay tests | P0 |
| T5.6-12 | Vendor accept within10min | DEVIATION-APPROVED | FR10 180s policy | Explicit FR10 approval | Accepted180s supersedes ten-minute wording | P1 |
| T5.6-13 | Timeout cancellation/refund | PARTIAL | FR10 | Cancellation and pending refund accepted | Real refund settlement absent | P1 |
| T5.6-14 | Assign verified available rider within5km | VERIFIED | FR19/20 RPC | SQL63/HTTP70/native | TEST scope | P1 |
| T5.6-15 | Expand10km once then manual escalation | PARTIAL | FR20 escalation/receipt | Accepted radius/receipt | Admin manual assignment response absent | P1 |
| T5.6-16 | Complete checklist unlocks GPS | VERIFIED | pre_delivery_checklist_service; checklist_private; FR13 | CHECKLIST acceptance; latestSQL56 | TEST scope | P1 |
| T5.6-17 | Correct OTP proof/DELIVERED | VERIFIED | FR33 issue/verify RPC | Real email/native completion | Approved email TEST scope | P1 |
| T5.6-18 | Wrong OTP/remaining attempts | VERIFIED | FR33 | Native2/1 remaining evidence | TEST scope | P1 |
| T5.6-19 | Third failure expires/flags admin | IMPLEMENTED-UNVERIFIED | FR33 lockout/audit | Expiry verified | Inspect distinct Admin-review flag/notification end-to-end; expiry alone not entire row | P1 |
| T5.6-20 | Within24h evidence/Admin notice/48h message | VERIFIED | FR25 service/RPC | FR25 acceptance | Historical TEST scope, not48h operational SLA guarantee | P1 |
| T5.6-21 | After24h exact rejection | VERIFIED | FR25 server time guard | FR25 expiry/hosted tests | TEST scope | P1 |
| T5.6-22 | Resolve triggers refund API | PARTIAL | FR26 dispute_refund_actions | Pending-refund/action accepted | No external refund API settlement; pending is not refunded | P1 |
| T5.6-23 | Reject with reason | VERIFIED | FR26 | Physical/hosted rejection | TEST scope | P1 |
| T5.6-24 | Configurable low-stock vendor notice | VERIFIED | FR17 threshold crossing | Native low-stock/rearm/HTTP | TEST scope | P1 |
| T5.6-25 | Admin block/revoke/next call403 | VERIFIED | FR28 canonical/session/Auth workflow | FR28 hosted/native | TEST scope | P0 |
| T5.6-26 | Active GPS insert/broadcast | DEVIATION-APPROVED | FR13 latest-state/private Broadcast | FR13 approved persistence design/native/Realtime | No per-fix history; preserve approved privacy alternative | P1 |
| T5.6-27 | GPS30s unavailable/no stale pin | VERIFIED | FR13/14 client age logic | Physical stale/recovery evidence | TEST Android scope | P1 |
| T5.6-28 | Delivered rating/recompute vendor/rider | PARTIAL | FR23/24 reviews | No complete passing rating flow | TEST denies direct writes/aggregate invocation; dual rating lifecycle | P1 |
| T5.6-29 | SUCCESS invoice PDF email | VERIFIED | FR32 canonical payment/event/outbox | FR32 actual inbox/PDF acceptance | Event-to-email TEST scope; no gateway integration acceptance; COD must not imply capture | P1 |
| T5.6-30 | Unhandled API error audit/500/retry | PARTIAL | Feature handlers; scattered catches | Feature errors only | No universal security_audit_log logging; silent client empty/success paths | P0 |

## Required screens

| ID | SRDS Requirement | Implementation Status | Code Location | Test Evidence | Missing Work | Priority |
|---|---|---|---|---|---|---|
| UI-A | Splash/onboarding/logo/tagline | IMPLEMENTED-UNVERIFIED | screens/splash_screen.dart | Historical app navigation | Exact content/indicators/restore on both platforms | P1 |
| UI-B | Customer greeting/search/featured/categories/promotions/nav | PARTIAL | customer_dashboard.dart/search_screen.dart | Selected checkout/stock flows | Complete search, promotion specification, paging/Urdu | P1 |
| UI-C | Vendor-grouped cart/steppers/total/payment | PARTIAL | customer/cart_screen.dart; enhanced_checkout_screen.dart | FR10/17 shared checkout | Persistence/gift/payment/hardcoded rider suggestion | P1 |
| UI-D | Rider pin/route/ETA/photo/rating/maskedCNIC/status | PARTIAL | map_screen.dart | FR04/13 accepted; FR14 incomplete | Photo/rating/status-stepper completeness and physical road acceptance | P1 |
| UI-E | Vendor queues/inventory/earnings/chart | PARTIAL | vendor_dashboard.dart; vendor_analytics_screen.dart | FR10/17 stock/transitions | Fake analytics, earnings breakdown, image storage | P1 |
| UI-F | Rider jobs/navigation/checklist/OTP/proof photo | PARTIAL | rider_dashboard.dart; map/checklist/OTP | Checklist/FR13/33 selected native | Proof photo, metrics/earnings, profile controls | P1 |
| UI-G | Dispute order/reason/images/status/window | VERIFIED | customer/dispute_screen.dart; admin_disputes_screen.dart | FR25/26 acceptance | Historical Android TEST functional scope | P1 |
| UI-H | Admin approvals/documents/users/disputes/charts/broadcast | PARTIAL | admin_dashboard/users/disputes/broadcast screens | FR04/26/28/30 subset | Vendor review audit; monitoring/map/real chart/report/export | P1 |

## Other mandatory clauses and design constraints

| ID | SRDS Requirement | Implementation Status | Code Location | Test Evidence | Missing Work | Priority |
|---|---|---|---|---|---|---|
| O-01 | 2.3.1 profile name/phone/email/address/avatar/role fields | PARTIAL | customer/profile_screen.dart; vendor store settings | Name/phone source only | Authenticated full profile workflow; store writes denied; confirmed affected row | P1 |
| O-02 | 2.3.2 persistent multivendor cart/full order lifecycle | PARTIAL | CartController/fr10_checkout/vendor_orders/history | FR10/17 shared-order subset | Persistence/fee split/every child-parent status/history | P1 |
| O-03 | 1.3/2.3.3 mandatory checklist | VERIFIED | pre_delivery_checklist_service.dart;202610170001 | CHECKLIST-acceptance.md; latestSQL56 | Historical TEST scope | P1 |
| O-04 | 2.3.4 configurable low-stock alerts | VERIFIED | FR17 save/threshold/ledger | FR17 native rearm/inbox | TEST scope | P1 |
| O-05 | 2.3.4 vendor per-order transactions/performance | PARTIAL | VendorAnalytics/FR21 aggregates | No complete reporting acceptance | Delivered revenue/payments/refunds/earnings breakdown; no sample figures | P1 |
| O-06 | 2.3.5 rider completion rate/average duration/rating | PARTIAL | rider_controller.dart/fr21_dashboard_stats | Current aggregate definition | Trusted stored post-delivery metrics; current counts not completion rate | P1 |
| O-07 | 2.3.5 rider per-delivery earnings history | PARTIAL | Same aggregate | Current TEST uses orders.amount/created_at | Fee allocation/ledger/earned_at/history; full order amount is not established rider pay | P1 |
| O-08 | 2.3.6 public dual ratings on profiles | PARTIAL | reviews/product detail/rider profile | Mock/current denied paths | Secure dual feedback and real averages/profile visibility | P1 |
| O-09 | 2.3.6 automatic consistently-low-rating blocking | MISSING | No complete trusted automation located | FR28 manual tests do not cover this | Configurable threshold/sample/window/appeal decision and server audit/dedup | P1 |
| O-10 | 2.3.7 real-time counts/order map | PARTIAL | AdminController stream/overview | Source only | Actual order monitoring map/drilldown/authorized projection | P1 |
| O-11 | 2.3.7 daily-weekly volumes/revenue/disputes/top vendors/riderKPIs | PARTIAL | Admin overview | No full chart acceptance | Server aggregates/live charts/date filters/metric definitions | P1 |
| O-12 | 2.3.7 exportable management reports | MISSING | app_drawer.dart Reports Coming Soon | No export test | Authorized real data export without personal-document leakage | P1 |
| O-13 | Table5.6-15 manual assignment | MISSING | FR20 receipt/escalation only | Accepted escalation not response | Authorized conflict-safe candidate selection/assignment/audit | P1 |
| O-14 | 2.3.8 order/assignment/dispute/broadcast push | PARTIAL | AndroidBroadcastPushService/fr30 worker/notifications | Android broadcast acceptance | Complete event push and iOS/APNs coverage | P1 |
| O-15 | 2.4 Urdu-friendly/simple navigation | PARTIAL | app_translations.dart/app_drawer.dart | Locale toggle source | Many hardcoded English screens; persistence/RTL/all-role tests | P1 |
| O-16 | 2.4 rider turn-by-turn navigation/proof tools | PARTIAL | rider dashboard/map/QR pickup | No full navigation/photo acceptance | Confirm external navigation vs in-app guidance; photo proof mandatory | P1 |
| O-17 | 2.5.1 device/RAM/storage/network requirements | NOT TESTED | Android/iOS configs | Selected physical Android only | Minimum device/storage/network/battery matrix; no fabricated guarantees | P1 |
| O-18 | 2.5.2 Flutter3/Dart3/specified package constraints | IMPLEMENTED-UNVERIFIED | pubspec.yaml/pubspec.lock | Declared Dart^3.9.2 and existing packages | Current platform build compatibility; no dependency upgrade | P1 |
| O-19 | 2.5.2 Android8/API26 and iOS13+ | PARTIAL | android/app/build.gradle.kts; ios/Podfile | Android minSdk delegated; iOS target15.0 | Confirm supported minimum; no silent downgrade/change | P1 |
| O-20 | 2.5.2 PostgreSQL15/Supabase services | PARTIAL | baseline migration header/backend integration | Baseline exported from PostgreSQL17.6 | Interpret version constraint; no database downgrade proposed | P1 |
| O-21 | 3.3.2 camera/GPS/session/network interfaces | PARTIAL | image_picker/geolocator/secure storage/platform configuration | CNIC/GPS physical subset | Delivery proof photo/session/platform coverage | P1 |
| O-22 | 3.3.3 REST/WSS/Storage/Edge/maps/payment/SMS | PARTIAL | services/functions/main.dart | Accepted feature subset | Missing payment; email/RPC/latest-state deviations recorded | P1 |
| O-23 | 3.3.4 HTTPS/WSS/JWT/callback signatures | PARTIAL | BackendConfig/Realtime/handlers | backend_config_test.dart; FR13/28 denial tests | Callback absent; production transport uninspected | P0 |
| O-24 | 4.1 fast APIs/screens/GPS/payment/OTP and stable concurrency | NOT TESTED | Existing feature load reports/FR14 acceptance | FR14 separate local p95 latency FAIL | No new load; Docker/1000-user expressly excluded; 4.1 is qualitative;800ms/1000-user are separate prior engineering gates, not numeric SRDS4.1 targets | P1 |
| O-25 | 4.3.1 99.9%SLA/failover/retry/backoff | PARTIAL | location/session retry; legacy catches | FR14 controlled Android recovery passed | Free SLA not established; no universal retries/failover evidence | P1 |
| O-26 | 4.3.2 first order<3min/large rider controls | NOT TESTED | signup/checkout/rider screens | Existing functional tests not timed usability study | Timed onboarding/Urdu/accessibility/device review | P1 |
| O-27 | 4.3.3 Clean feature layers/Riverpod/versioned schema | PARTIAL | GetX controllers/routes; migrations | 38 migration versions; AGENTS mandates GetX | Record Riverpod conflict; preserve GetX; no rewrite without decision | P1 |
| O-28 | 4.3.4 Android/iOS/backend portability | PARTIAL | android/ios/BackendConfig | iOS static reports only | macOS/device/build/data portability acceptance | P1 |
| O-29 | 4.3.5 scalable PostgREST/Realtime/Edge | NOT TESTED | Managed infrastructure | Historical bounded results only | Free quotas; no1000-user qualification/unlimited claim | P1 |
| O-30 | 4.3.6 unit/Deno/integration/80%coverage | PARTIAL | test; functions/*test.ts; tests/integration | Historical suites | Measured80%domain/data coverage missing; Riverpod conflict; Docker excluded | P1 |
| O-31 | 4.3.7 standard REST/payment interoperability | PARTIAL | Supabase/PostgREST | Source integration | Provider adapter after ApprovalA | P1 |
| O-32 | 4.3.8 modular/versioned schema adaptability | IMPLEMENTED-UNVERIFIED | migrations/models/routes |38 observed versions | New-role extension not acceptance-tested | P2 |
| O-33 | 5 deployment/package/class/ER/sequence/state diagrams | PARTIAL | PDF physical34–42; schema/services | Overview figures visually inspected | Fine diagram-label comparison NOT INSPECTED fully; legacy table aliases differ | P1 |

## Deviations and decisions

- **Approved:** email instead of SMS: FR-33-srds-deviation.md explicitly records user approval. Preserve three failures, server-only code, confirmed recipient and atomic delivery receipt.
- **Approved:** GPS latest-only/throttled persistence instead of per-fix history: FR-13-progress.md and acceptance record user approval. Preserve private assignment-scoped Broadcast, explicit consent and cleanup.
- **Approved:** transactional assignment RPC instead of Edge assignment: FR-20-acceptance.md records the task explicitly selected RPC.
- **Approved:** 180-second default/shared-order cancellation: FR-10-acceptance.md records explicit user policy resolving S06 versus ten-minute decision table.
- **Needs confirmation:** permanent free routing substitution approval beyond FR14 checkpoint approval; GetX versus SRDS Riverpod; iOS minimum15 versus13; PostgreSQL17.6 baseline versus15.
- **Needs confirmation:** S03 says rollback status to PENDING, Table5.6 row10 says rollback order record. Proposed auditable failed payment attempt/resumable pending checkout requires approval, never simulated capture.
- **Not an approved deviation:** cart add-time reservations absent; approved checkout decrement is narrower. Photo proof remains required even though OTP receipt exists. COD-only does not satisfy online-payment/HMAC/refund requirements without ApprovalA deviation.
- **Business definition needed:** low-rating threshold/sample/window and appeal/unblock semantics; rider fee allocation/earnings; support contacts; any optional gift/vehicle/bank settings scope.

## Security findings

Counts: **CRITICAL0 / HIGH2 / MEDIUM4 / LOW3**. These include conditional design/compliance findings, not nine demonstrated production exploits. No production exploitation performed.

| ID | Severity | Evidence | Impact and limits | Required action |
|---|---|---|---|---|
| SEC-A01 | HIGH | ai_service.dart::_loadApiKey reads provider key from app_settings into Flutter, then sends Bearer | Current TEST app_settings has no client grants: access denied; granting it later would expose private provider credential. No value inspected | Move provider operation/key lookup server-side; preserve denied client boundary |
| SEC-A02 | HIGH | payment_screen.dart::_processPayment invokes success callback after2s without provider | Latent false-payment behavior; no live caller located by current lib reference search; no actual capture | Replace before use with trusted payment flow; approved hide only for optional UI |
| SEC-A03 | MEDIUM | Named dashboard AuthMiddleware checks session only; AdminMiddleware returns null | Wrong-role dashboard navigation; no server RLS bypass demonstrated | Canonical role/approval/block route checks |
| SEC-A04 | MEDIUM | storage_service.dart/product_form_screen.dart use getPublicUrl/general upload | Current missing buckets fail; future public policies would conflict SEC08/privacy; generic upload accepts PDFs | Scoped validated uploads/15min signed access |
| SEC-A05 | MEDIUM | Vendor AdminController.updateStatus direct users update; current users triggers include FR32 email event but no decision audit | Critical vendor approval/rejection lacks identified security_audit_log insert | Atomic authorized decision RPC/audit/reason/confirmation |
| SEC-A06 | MEDIUM | search_screen.dart interpolates raw query into .or grammar; catches convert error to empty list | Filter-grammar/errors/stale responses; not demonstrated SQL injection | Bounded safely encoded search/server RPC, request/lifecycle guards, error/retry |
| SEC-A07 | LOW | Current TEST fr30_private.limits RLS=false; no client table grants | No exposure demonstrated; literal all-table requirement unmet; schema privileges still need exhaustive review | Later approved deny-client RLS migration/test |
| SEC-A08 | LOW | AuthController biometricOnly:false | Device-credential fallback allowed; not inherently a bypass; fingerprint-only intent unresolved | Confirm fallback/enrollment/session lifecycle and test |
| SEC-A09 | LOW | db_test.dart:6, test_db.dart:9, test_schema.dart:8/9 embed production anon JWTs | Decoded role is anon, not service_role; public client key is not privileged secret. Still violates literal SEC04 no committed API keys; accidental production diagnostic targeting risk | Read config from environment; guard diagnostic target; do not rotate public keys merely from this finding |

Hosted Auth/gateway settings, complete Git-history secret scan and full definer-body proof remain NOT INSPECTED. Do not count absence of evidence as a demonstrated exploit or a security pass.

Current tracked-text pattern scan covered714 extant UTF-8 files up to2MB, excluding missing deleted paths and unreadable/binary files. Candidate values were never printed. Matches classified: anon JWTs in the three diagnostic files above; Firebase client configuration key in android/app/google-services.json (not by itself a privileged secret; restrictions uninspected); PRIVATE KEY header in push_test.ts generated test fixture and FR-30-configure-push.py header-validation code (no static PEM payload found). No matching private/provider key values in the four audit docs. This bounded pattern scan is not a comprehensive secret/history certification.

## Critical audit-operation coverage

| Operation | Server path | Evidence | Remaining gap |
|---|---|---|---|
| Rider approval/rejection | fr04_review_rider | security_audit_log insert; FR04 acceptance | UI confirmation consistency |
| Vendor approval/rejection | AdminController direct users update | No identified decision-audit trigger; FR32 trigger creates account email event | Atomic decision/audit needed |
| Block/unblock | FR28 operation/Edge reconciliation | BLOCK_USER/UNBLOCK_USER accepted | Preserve replay/session denial |
| Dispute decisions | FR26 atomic RPC | Accepted audit assertions | Refund settlement separate |
| Broadcast | FR30 RPC | Accepted audit/replay tests | iOS/general push separate |
| Radius escalation | FR20 RPC/receipt | Exactly-once audit/receipt accepted | Manual assignment response absent |
| Manual assignment | No complete flow found | None | Authorization/conflict/audit implementation |
| Unhandled errors | Feature handlers/scattered catches | No universal audit coverage | Table5.6 row30 incomplete |

## Current TEST security metadata

Collected with read-only catalog transactions on2026-10-21. Project `igeisilhtmglgnqvllrx`;38 migration versions match38 local files.78 tables:56 public,20 private,2 Storage.165 functions,140 SECURITY DEFINER. All observed definers have proconfig settings; this does not prove safe bodies. Production is **NOT INSPECTED**, because the CLI reports IPv6 unsupported. Hosted token expiry/global gateway policy are not established by these catalogs.

Table/column policy inventory and function ACL ledger follow. Policy/grant presence alone is not authorization acceptance. Missing table UPDATE does not mean missing column UPDATE. Empty policy lists mean deny ordinary access when RLS applies; revoked grants are additional boundaries. No user records, private image paths, signed URLs or secret values selected.

### Tables and policies

| Table | RLS | Client table grants | Policies and predicates |
|---|---|---|---|
| checklist_private.definitions | True | No anon/authenticated table grants | None |
| checklist_private.legacy_transit | True | No anon/authenticated table grants | None |
| fr10_private.checkout_requests | True | No anon/authenticated table grants | None |
| fr10_private.configuration | True | No anon/authenticated table grants | None |
| fr13_private.live_state | True | No anon/authenticated table grants | None |
| fr13_private.sessions | True | No anon/authenticated table grants | None |
| fr14_private.attempts | True | No anon/authenticated table grants | None |
| fr14_private.configuration | True | No anon/authenticated table grants | None |
| fr14_private.quota_reservations | True | No anon/authenticated table grants | None |
| fr14_private.user_limits | True | No anon/authenticated table grants | None |
| fr25_private.drafts | True | No anon/authenticated table grants | None |
| fr25_private.evidence | True | No anon/authenticated table grants | None |
| fr30_private.limits | False | No anon/authenticated table grants | None |
| fr30_private.push_deliveries | True | No anon/authenticated table grants | None |
| fr30_private.push_devices | True | No anon/authenticated table grants | None |
| fr32_private.account_events | True | No anon/authenticated table grants | None |
| fr32_private.configuration | True | No anon/authenticated table grants | None |
| fr32_private.invoice_snapshots | True | No anon/authenticated table grants | None |
| fr32_private.order_snapshots | True | No anon/authenticated table grants | None |
| fr32_private.quota_reservations | True | No anon/authenticated table grants | None |
| public.addresses | True | No anon/authenticated table grants | addr_delete [DELETE] roles=authenticated USING true CHECK None; addr_insert [INSERT] roles=authenticated USING None CHECK true; addr_read [SELECT] roles=authenticated USING true CHECK None; addr_update [UPDATE] roles=authenticated USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.admin_broadcasts | True | authenticated:SELECT | fr30_admin_history [SELECT] roles=authenticated USING ((( SELECT fr21_role() AS fr21_role) = 'admin'::text) AND (EXISTS ( SELECT 1    FROM users   WHERE ((users.id = ( SELECT fr21_actor() AS fr21_actor)) AND (users.verification_status = 'approved'::text))))) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.admins | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.analytics | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.app_settings | True | No anon/authenticated table grants | app_settings_read [SELECT] roles=public USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.audit_logs | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.cart | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.cart_items | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.categories | True | authenticated:SELECT | Anyone can read categories [SELECT] roles=public USING true CHECK None; categories_read [SELECT] roles=public USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.chat_messages | True | authenticated:SELECT | chat_msg_insert [INSERT] roles=authenticated USING None CHECK true; chat_msg_read [SELECT] roles=authenticated USING true CHECK None; fr25_message_read [SELECT] roles=authenticated USING fr25_chat_owned(room_id) CHECK None; fr25_message_insert [INSERT] roles=authenticated USING None CHECK ((sender_id = ( SELECT fr21_actor() AS fr21_actor)) AND fr25_chat_owned(room_id) AND ((char_length(btrim(message)) >= 1) AND (char_length(btrim(message)) <= 2000)) AND (image_url IS NULL)); fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.chat_participants | True | No anon/authenticated table grants | chat_part_insert [INSERT] roles=authenticated USING None CHECK true; chat_part_read [SELECT] roles=authenticated USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.chat_rooms | True | authenticated:SELECT | chat_rooms_insert [INSERT] roles=authenticated USING None CHECK true; chat_rooms_read [SELECT] roles=authenticated USING true CHECK None; fr25_chat_read [SELECT] roles=authenticated USING ((( SELECT fr21_actor() AS fr21_actor) = user1_id) OR (( SELECT fr21_actor() AS fr21_actor) = user2_id)) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.complaints | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.customer | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.customers | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.delivery_latest_locations | True | authenticated:SELECT | fr13_latest_read [SELECT] roles=authenticated USING fr13_can_read(assignment_id) CHECK None |
| public.delivery_otp_budgets | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.delivery_otp_rates | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.delivery_otp_verifications | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.delivery_otps | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.delivery_proof | True | authenticated:SELECT | fr21_receipt_owner [SELECT] roles=authenticated USING ((riderid = (( SELECT auth.uid() AS uid))::text) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.delivery_route_cache | True | authenticated:SELECT | fr14_cache_read [SELECT] roles=authenticated USING fr14_can_read(order_id) CHECK None |
| public.dispute_refund_actions | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.disputes | True | authenticated:SELECT | disputes_insert [INSERT] roles=authenticated USING None CHECK true; disputes_select [SELECT] roles=authenticated USING true CHECK None; disputes_update [UPDATE] roles=authenticated USING true CHECK None; fr25_dispute_read_guard [SELECT] roles=authenticated USING (((customer_id = ( SELECT fr21_actor() AS fr21_actor)) AND (( SELECT fr21_role() AS fr21_role) = 'customer'::text)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)) CHECK None; fr25_dispute_insert_deny [INSERT] roles=authenticated USING None CHECK false; fr25_dispute_update_deny [UPDATE] roles=authenticated USING false CHECK None; fr25_dispute_delete_deny [DELETE] roles=authenticated USING false CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.email_outbox | True | No anon/authenticated table grants | None |
| public.favorites | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.favourite | True | No anon/authenticated table grants | fav_delete [DELETE] roles=authenticated USING true CHECK None; fav_insert [INSERT] roles=authenticated USING None CHECK true; fav_read [SELECT] roles=authenticated USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.feedback | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.fr28_operations | True | No anon/authenticated table grants | None |
| public.gifts | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.gps_locations | True | No anon/authenticated table grants | gps_locations_insert [INSERT] roles=authenticated USING None CHECK true; gps_locations_select [SELECT] roles=authenticated USING true CHECK None; gps_locations_update [UPDATE] roles=authenticated USING true CHECK None; fr13_legacy_closed [ALL] roles=anon,authenticated USING false CHECK false; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.inventory_movements | True | authenticated:SELECT | fr17_ledger_read [SELECT] roles=authenticated USING (is_current_user_allowed() AND ((vendor_id = fr21_actor()) OR (fr21_role() = 'admin'::text))) CHECK None |
| public.invoices | True | authenticated:SELECT | fr32_invoice_owner_read [SELECT] roles=authenticated USING (is_current_user_allowed() AND ((owner_id = fr21_actor()) OR (fr21_role() = 'admin'::text))) CHECK None |
| public.messages | True | No anon/authenticated table grants | messages_insert [INSERT] roles=authenticated USING None CHECK true; messages_select [SELECT] roles=authenticated USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.notifications | True | authenticated:SELECT | notif_insert [INSERT] roles=authenticated USING None CHECK true; notif_read [SELECT] roles=authenticated USING true CHECK None; notif_update [UPDATE] roles=authenticated USING true CHECK None; fr21_test_notifications_read [SELECT] roles=authenticated USING (user_id = ( SELECT fr21_actor() AS fr21_actor)) CHECK None; fr21_test_notifications_update [UPDATE] roles=authenticated USING (user_id = ( SELECT fr21_actor() AS fr21_actor)) CHECK (user_id = ( SELECT fr21_actor() AS fr21_actor)); fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.order_items | True | authenticated:SELECT | order_items_insert [INSERT] roles=authenticated USING None CHECK true; order_items_select [SELECT] roles=authenticated USING true CHECK None; fr21_test_items_read [SELECT] roles=authenticated USING (EXISTS ( SELECT 1    FROM vendor_orders vo   WHERE ((vo.id = order_items.vendor_order_id) AND fr21_order_visible(vo.order_id)))) CHECK None; fr21_test_items_insert [INSERT] roles=authenticated USING None CHECK ((( SELECT fr21_role() AS fr21_role) = 'customer'::text) AND (EXISTS ( SELECT 1    FROM (vendor_orders vo      JOIN orders o ON ((o.id = vo.order_id)))   WHERE ((vo.id = order_items.vendor_order_id) AND (o.user_id = ( SELECT fr21_actor() AS fr21_actor)))))); fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.order_refund_actions | True | authenticated:SELECT | fr10_refund_read [SELECT] roles=authenticated USING (is_current_user_allowed() AND ((customer_id = fr21_actor()) OR (fr21_role() = 'admin'::text))) CHECK None |
| public.order_timeline_events | True | authenticated:SELECT | fr10_timeline_read [SELECT] roles=authenticated USING (is_current_user_allowed() AND fr21_order_visible(order_id)) CHECK None |
| public.orders | True | authenticated:SELECT | orders_insert [INSERT] roles=authenticated USING None CHECK true; orders_select [SELECT] roles=authenticated USING true CHECK None; orders_update [UPDATE] roles=authenticated USING true CHECK None; fr21_test_orders_read [SELECT] roles=authenticated USING fr21_order_visible(id) CHECK None; fr21_test_orders_insert [INSERT] roles=authenticated USING None CHECK ((user_id = ( SELECT fr21_actor() AS fr21_actor)) AND (( SELECT fr21_role() AS fr21_role) = 'customer'::text)); fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed); fr21_test_orders_update [UPDATE] roles=authenticated USING ((user_id = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text) OR fr28_vendor_owns_order(id)) CHECK (order_status = 'cancelled'::text) |
| public.payment | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.payments | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.pre_delivery_checklists | True | authenticated:SELECT | checklist_read [SELECT] roles=authenticated USING (((fr21_role() = 'rider'::text) AND (rider_id = fr21_actor())) OR (fr21_role() = 'admin'::text)) CHECK None |
| public.prescription_items | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.prescriptions | True | No anon/authenticated table grants | Customers can view their own prescriptions [SELECT] roles=public USING (((auth.uid())::text = (customer_id)::text) OR ((auth.uid())::text = (reviewed_by)::text)) CHECK None; Vendors can view prescriptions for their orders [SELECT] roles=public USING (vendor_order_id IN ( SELECT vo.id    FROM vendor_orders vo   WHERE (vo.vendor_id = ( SELECT users.id            FROM users           WHERE (users.email = (auth.jwt() ->> 'email'::text)))))) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.product_recommendations | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.products | True | authenticated:SELECT | customers_can_view_available_products [SELECT] roles=authenticated USING (is_available = true) CHECK None; products_delete [DELETE] roles=authenticated USING true CHECK None; products_insert [INSERT] roles=authenticated USING None CHECK true; products_read [SELECT] roles=authenticated USING true CHECK None; products_update [UPDATE] roles=authenticated USING true CHECK None; vendor_delete_own_products [DELETE] roles=authenticated USING is_current_vendor(vendor_id) CHECK None; vendor_insert_own_products [INSERT] roles=authenticated USING None CHECK is_current_vendor(vendor_id); vendor_select_own_products [SELECT] roles=authenticated USING is_current_vendor(vendor_id) CHECK None; vendor_update_own_products [UPDATE] roles=authenticated USING is_current_vendor(vendor_id) CHECK is_current_vendor(vendor_id); fr28_product_vendor_guard [SELECT] roles=anon,authenticated USING fr28_vendor_visible(vendor_id) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed); fr17_product_update_owner [UPDATE] roles=authenticated USING ((fr21_role() = 'vendor'::text) AND (vendor_id = fr21_actor()) AND is_current_user_allowed()) CHECK ((fr21_role() = 'vendor'::text) AND (vendor_id = fr21_actor()) AND is_current_user_allowed()); fr17_product_delete_owner [DELETE] roles=authenticated USING ((fr21_role() = 'vendor'::text) AND (vendor_id = fr21_actor()) AND is_current_user_allowed()) CHECK None |
| public.review | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.reviews | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.rider_assignments | True | authenticated:SELECT | rider_assignments_insert [INSERT] roles=authenticated USING None CHECK true; rider_assignments_select [SELECT] roles=authenticated USING true CHECK None; rider_assignments_update [UPDATE] roles=authenticated USING true CHECK None; fr21_test_assignments_read [SELECT] roles=authenticated USING fr21_order_visible(orderid) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.riders | True | authenticated:SELECT | riders_insert [INSERT] roles=authenticated USING None CHECK true; riders_select [SELECT] roles=authenticated USING true CHECK None; riders_update [UPDATE] roles=authenticated USING true CHECK None; fr21_presence_owner [UPDATE] roles=authenticated USING ((userid = ( SELECT fr21_actor() AS fr21_actor)) AND (( SELECT fr21_role() AS fr21_role) = 'rider'::text)) CHECK ((userid = ( SELECT fr21_actor() AS fr21_actor)) AND (( SELECT fr21_role() AS fr21_role) = 'rider'::text)); fr21_presence_owner_guard [UPDATE] roles=authenticated USING ((userid = ( SELECT fr21_actor() AS fr21_actor)) AND (( SELECT fr21_role() AS fr21_role) = 'rider'::text)) CHECK ((userid = ( SELECT fr21_actor() AS fr21_actor)) AND (( SELECT fr21_role() AS fr21_role) = 'rider'::text)); fr21_presence_read [SELECT] roles=authenticated USING (userid = ( SELECT fr21_actor() AS fr21_actor)) CHECK None; fr21_test_riders_read [SELECT] roles=authenticated USING ((userid = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.security_audit_log | True | No anon/authenticated table grants | fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.stores | True | authenticated:SELECT | stores_insert [INSERT] roles=authenticated USING None CHECK true; stores_read [SELECT] roles=public USING true CHECK None; stores_select [SELECT] roles=authenticated USING true CHECK None; stores_update [UPDATE] roles=authenticated USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.tailoring_requests | True | authenticated:SELECT | tailoring_requests_insert [INSERT] roles=authenticated USING None CHECK true; tailoring_requests_select [SELECT] roles=authenticated USING true CHECK None; tailoring_requests_update [UPDATE] roles=authenticated USING true CHECK None; fr21_test_tailoring_read [SELECT] roles=authenticated USING ((customer_id = ( SELECT fr21_actor() AS fr21_actor)) OR (vendor_id = ( SELECT fr21_actor() AS fr21_actor)) OR (rider_id = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.users | True | authenticated:INSERT, authenticated:SELECT | Allow authenticated insert users [INSERT] roles=authenticated USING None CHECK true; Allow authenticated select users [SELECT] roles=authenticated USING true CHECK None; Allow authenticated update users [UPDATE] roles=authenticated USING true CHECK true; users_read [SELECT] roles=authenticated USING true CHECK None; fr21_profile_owner_guard [UPDATE] roles=authenticated USING ((id = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)) CHECK ((id = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)); fr21_test_users_signup [INSERT] roles=authenticated USING None CHECK ((email = ( SELECT (auth.jwt() ->> 'email'::text))) AND (role = ANY (ARRAY['customer'::text, 'vendor'::text, 'rider'::text]))); fr21_test_users_read [SELECT] roles=authenticated USING ((id = ( SELECT fr28_identity() AS fr28_identity)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)) CHECK None; fr28_users_write_guard [UPDATE] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed); fr28_users_delete_guard [DELETE] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK None |
| public.vendor_orders | True | authenticated:SELECT | vendor_orders_insert [INSERT] roles=authenticated USING None CHECK true; vendor_orders_select [SELECT] roles=authenticated USING true CHECK None; vendor_orders_update [UPDATE] roles=authenticated USING true CHECK None; fr21_vendor_owner_guard [UPDATE] roles=authenticated USING ((vendor_id = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)) CHECK ((vendor_id = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text)); fr21_test_vendor_orders_insert [INSERT] roles=authenticated USING None CHECK ((( SELECT fr21_role() AS fr21_role) = 'customer'::text) AND (EXISTS ( SELECT 1    FROM orders o   WHERE ((o.id = vendor_orders.order_id) AND (o.user_id = ( SELECT fr21_actor() AS fr21_actor)))))); fr21_test_vendor_orders_update [UPDATE] roles=authenticated USING ((vendor_id = ( SELECT fr21_actor() AS fr21_actor)) AND (( SELECT fr21_role() AS fr21_role) = 'vendor'::text)) CHECK ((vendor_id = ( SELECT fr21_actor() AS fr21_actor)) AND (status = ANY (ARRAY['accepted'::text, 'preparing'::text, 'cancelled'::text]))); fr21_test_vendor_orders_read [SELECT] roles=authenticated USING ((vendor_id = ( SELECT fr21_actor() AS fr21_actor)) OR (( SELECT fr21_role() AS fr21_role) = 'admin'::text) OR ((( SELECT fr21_role() AS fr21_role) = 'customer'::text) AND (EXISTS ( SELECT 1    FROM orders o   WHERE ((o.id = vendor_orders.order_id) AND (o.user_id = ( SELECT fr21_actor() AS fr21_actor)))))) OR ((( SELECT fr21_role() AS fr21_role) = 'rider'::text) AND fr21_order_visible(order_id))) CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| public.vendors | True | authenticated:SELECT | vendors_insert [INSERT] roles=authenticated USING None CHECK true; vendors_read [SELECT] roles=public USING true CHECK None; vendors_select [SELECT] roles=authenticated USING true CHECK None; vendors_update [UPDATE] roles=authenticated USING true CHECK None; fr21_test_vendors_read [SELECT] roles=authenticated USING true CHECK None; fr28_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed) |
| storage.buckets | True | authenticated:INSERT, authenticated:SELECT, authenticated:UPDATE, authenticated:DELETE, anon:INSERT, anon:SELECT, anon:UPDATE, anon:DELETE | None |
| storage.objects | True | authenticated:INSERT, authenticated:SELECT, authenticated:UPDATE, authenticated:DELETE, anon:INSERT, anon:SELECT, anon:UPDATE, anon:DELETE | fr04_cnic_direct_deny [ALL] roles=anon,authenticated USING (bucket_id <> 'rider-cnic'::text) CHECK (bucket_id <> 'rider-cnic'::text); fr25_evidence_direct_deny [ALL] roles=anon,authenticated USING (bucket_id <> 'dispute-evidence'::text) CHECK (bucket_id <> 'dispute-evidence'::text); fr28_storage_session_guard [ALL] roles=authenticated USING ( SELECT is_current_user_allowed() AS is_current_user_allowed) CHECK ( SELECT is_current_user_allowed() AS is_current_user_allowed); fr32_invoice_direct_deny [ALL] roles=anon,authenticated USING (bucket_id <> 'invoices'::text) CHECK (bucket_id <> 'invoices'::text) |

### Column write grants

| Table | Column | Role | Privilege |
|---|---|---|---|
| chat_messages | message | authenticated | INSERT |
| chat_messages | room_id | authenticated | INSERT |
| chat_messages | sender_id | authenticated | INSERT |
| notifications | is_read | authenticated | UPDATE |
| orders | order_status | authenticated | UPDATE |
| products | is_available | authenticated | UPDATE |
| riders | is_online | authenticated | UPDATE |
| riders | last_seen | authenticated | UPDATE |
| users | auth_user_id | authenticated | INSERT |
| users | cnic | authenticated | INSERT |
| users | cnic_image_digest | authenticated | INSERT |
| users | cnic_image_url | authenticated | INSERT |
| users | cnic_submission_status | authenticated | INSERT |
| users | cnic_submitted_at | authenticated | INSERT |
| users | cnic_upload_id | authenticated | INSERT |
| users | cnic_upload_started_at | authenticated | INSERT |
| users | created_at | authenticated | INSERT |
| users | email | authenticated | INSERT |
| users | id | authenticated | INSERT |
| users | is_blocked | authenticated | INSERT |
| users | name | authenticated | INSERT |
| users | name | authenticated | UPDATE |
| users | phone | authenticated | INSERT |
| users | phone | authenticated | UPDATE |
| users | profile_image | authenticated | INSERT |
| users | profile_image | authenticated | UPDATE |
| users | rejection_reason | authenticated | INSERT |
| users | rejection_reason | authenticated | UPDATE |
| users | role | authenticated | INSERT |
| users | verification_status | authenticated | INSERT |
| users | verification_status | authenticated | UPDATE |
| vendor_orders | status | authenticated | UPDATE |

### Storage

| Bucket | Public | Max bytes | MIME |
|---|---|---|---|
| rider-cnic | False | 5242880 | image/jpeg, image/png |
| dispute-evidence | False | 5242880 | image/jpeg, image/png |
| invoices | False | 5242880 | application/pdf |

Only these3 buckets exist in TEST. product-images, prescriptions, documents are absent. Existing protected CNIC/evidence/invoice APIs issue signed access.

### Function execution ledger

ACL =X means PUBLIC execution; NULL means default ACL, not automatic denial. Interpret with schema USAGE and body authorization. No functions invoked during audit. Full body-by-body/security-definer/schema-privilege proof and production definitions remain NOT INSPECTED.

| Function(signature) | SECURITY DEFINER | Settings | ACL |
|---|---|---|---|
| checklist_private.allowed(p_order bigint, p_rider bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| checklist_private.guard_assignment() | True | ['search_path=""'] | {postgres=X/postgres} |
| checklist_private.guard_delivery() | False | ['search_path=""'] | {postgres=X/postgres} |
| checklist_private.legacy(p_order bigint, p_rider bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr04_private.decrypt_cnic(p_value text) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr04_private.document_exists(p_user bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr04_private.encrypt_cnic(p_value text) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr04_private.guard_user() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr04_private.mask_cnic(p_value text) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr04_private.normalize_cnic(p_value text) | False | ['search_path=""'] | {postgres=X/postgres} |
| fr10_private.before_deadline(p_deadline timestamp with time zone, p_now timestamp with time zone) | False | ['search_path=""'] | {postgres=X/postgres} |
| fr10_private.cancel_batch(p_ids bigint[], p_reason text) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr10_private.cancel_locked(p_order bigint, p_reason text) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr10_private.guard_order() | False | ['search_path=""'] | {postgres=X/postgres} |
| fr10_private.guard_vendor() | False | ['search_path=""'] | {postgres=X/postgres} |
| fr10_private.timeline() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr13_private.cleanup() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr13_private.close_session() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr13_private.eligible(oid bigint, aid bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr14_private.allowed(oid bigint, actor bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr14_private.checkout_base(p_request_id uuid, p_items jsonb, p_delivery jsonb) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr14_private.cleanup() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr14_private.guard_destination() | False | ['search_path=""'] | {postgres=X/postgres} |
| fr14_private.invalidate() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr14_private.prepare_locked(p_order_id bigint, p_actor bigint, p_configured boolean) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr17_private.adjust(p_product bigint, p_quantity integer, p_mode text, p_reason text, p_request uuid, p_threshold integer, p_version bigint, p_payload jsonb) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr17_private.checkout_base(p_request_id uuid, p_items jsonb, p_delivery jsonb) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr17_private.lock_inventory(p_orders bigint[]) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr17_private.low_stock() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr17_private.payment_failed(p_order bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr17_private.protect_item() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr17_private.restore_cancelled() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr25_private.check_order(p_order_id bigint, p_actor bigint) | False | ['search_path=""'] | {postgres=X/postgres} |
| fr30_private.block_push() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr30_private.dispatch_push() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr30_private.queue_push() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.account_event(p_user bigint, p_kind text, p_source uuid) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.account_transition() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.block_transition() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.claim(p_limit integer, p_now timestamp with time zone) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.dispatch() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.enqueue(p_type text, p_user bigint, p_entity text, p_id text, p_key text, p_payload jsonb) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.order_finalized() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.payment_captured() | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.recipient(p_user bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.reserve_quota(p_kind text, p_key uuid, p_now timestamp with time zone) | True | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.server_only() | False | ['search_path=""'] | {postgres=X/postgres} |
| fr32_private.snapshot_order(p_order bigint) | True | ['search_path=""'] | {postgres=X/postgres} |
| public.admin_resolve_dispute(p_dispute_id bigint, p_decision text, p_note text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.admin_send_broadcast(p_request_id uuid, p_title text, p_message text, p_audience text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.admin_set_user_blocked(p_actor uuid, p_target bigint, p_blocked boolean, p_request uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.assign_available_rider() | False | none | {postgres=X/postgres,service_role=X/postgres} |
| public.cancel_timed_out_orders(p_limit integer) | True | ['search_path=""'] | {postgres=X/postgres} |
| public.create_dispute(p_order_id bigint, p_reason text, p_description text, p_evidence_paths text[], p_request_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.delivery_otp_status(p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr04_admin_riders(p_before bigint, p_limit integer, p_status text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr04_application_status() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr04_begin_upload(p_auth_uid uuid, p_request_id uuid, p_digest text, p_extension text, p_cnic text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr04_document_authority(p_user_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr04_finish_upload(p_auth_uid uuid, p_request_id uuid, p_path text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr04_order_rider_identity(p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr04_review_rider(p_user_id bigint, p_status text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr10_checkout(p_request_id uuid, p_items jsonb, p_delivery jsonb) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr10_vendor_transition(p_vendor_order_id bigint, p_status text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr13_can_read(p_assignment bigint) | True | ['search_path=""'] | {postgres=X/postgres,authenticated=X/postgres} |
| public.fr13_can_receive(p_topic text) | True | ['search_path=""'] | {postgres=X/postgres,authenticated=X/postgres} |
| public.fr13_submit_location(p_order_id bigint, p_lat double precision, p_lng double precision, p_accuracy double precision, p_device_at timestamp with time zone, p_request_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,authenticated=X/postgres} |
| public.fr13_tracking_context(p_order_id bigint, p_enable boolean) | True | ['search_path=""'] | {postgres=X/postgres,authenticated=X/postgres} |
| public.fr14_can_read(p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr14_finish(p_order_id bigint, p_actor bigint, p_lease uuid, p_route jsonb) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr14_prepare(p_order_id bigint, p_actor bigint, p_configured boolean) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr14_route_context(p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr17_save_product(p_request_id uuid, p_product_id bigint, p_data jsonb, p_stock integer, p_threshold integer, p_expected_version bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr20_assignment_status(p_vendor_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr20_guard_manual_flag() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_accept_order(p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_actor() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_approved_rider(p_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_begin_presence() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_complete_delivery(p_order_id bigint, p_otp text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_dashboard_stats() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_guard_assignment() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_guard_identity() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_guard_order_assignment() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_guard_rider() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_guard_vendor_order() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_guard_vendor_transition() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_order_contacts(p_order_ids bigint[]) | True | ['search_path=""'] | {=X/postgres,postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_order_visible(p_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_ready_and_assign(p_vendor_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_release_cancelled() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr21_role() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_set_presence(p_online boolean, p_epoch bigint, p_sequence bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr21_update_location(p_lat numeric, p_lng numeric) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_abandon(p_request_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_begin_evidence(p_auth_id uuid, p_request_id uuid, p_digest text, p_mime text, p_size integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr25_chat_list(p_before bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_chat_owned(p_room bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_delivery_timestamp() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr25_detail(p_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_eligible_orders(p_before bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_evidence_authority(p_dispute_id bigint, p_index integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_finish_upload(p_auth_id uuid, p_request_id uuid, p_digest text, p_mime text, p_size integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr25_history(p_before bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_options() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_order_history(p_before bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_prepare(p_request_id uuid, p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_request_status(p_request_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_support_chat() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr25_upload_authority(p_request_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr26_append_only() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr26_detail(p_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr26_final_immutable() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr26_options() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr26_queue(p_status text, p_before_at timestamp with time zone, p_before_id bigint, p_limit integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr26_vendors(p_id bigint, p_before bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr28_account_status() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr28_active_orders(p_target bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr28_finish(p_id uuid, p_failure text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr28_guard_identity() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr28_identity() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr28_pre_request() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres} |
| public.fr28_require_unblocked(p_uid uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr28_revoke_sessions(p_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr28_sync_context(p_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr28_token_live() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr28_user_list(p_search text, p_role text, p_blocked boolean, p_before_at timestamp with time zone, p_before_id bigint, p_limit integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr28_vendor_owns_order(p_order bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr28_vendor_visible(p_vendor bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres} |
| public.fr30_claim_push(p_limit integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr30_estimate(p_audience text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr30_finish_push(p_job uuid, p_lease uuid, p_outcome text, p_provider_message text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr30_push_eligible(p_job uuid, p_lease uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr30_register_push(p_installation uuid, p_token text, p_secret text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr30_resolve_push(p_installation uuid, p_secret text, p_broadcast uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,anon=X/postgres,authenticated=X/postgres} |
| public.fr30_unregister_push(p_installation uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr32_begin_email(p_id uuid, p_lease uuid, p_fingerprint text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr32_claim_email(p_limit integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr32_finish_email(p_id uuid, p_lease uuid, p_outcome text, p_provider text, p_retry_seconds integer, p_error text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr32_invoice_authority(p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.fr32_register_invoice_pdf(p_job uuid, p_lease uuid, p_sha256 text, p_bytes integer) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr32_test_allow_email(p_ids uuid[]) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr33_equal(a bytea, b bytea) | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr33_finish_send(p_id uuid, p_result text, p_provider_id text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr33_guard_client_order() | False | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr33_start_send(p_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.fr33_tag(p_order bigint, p_nonce text, p_code text) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.get_vendor_ratings(p_vendor_ids bigint[]) | False | none | {postgres=X/postgres,service_role=X/postgres} |
| public.is_admin() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.is_current_user_allowed() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.is_current_vendor(p_vendor_id bigint) | True | ['search_path=public'] | {postgres=X/postgres,service_role=X/postgres} |
| public.issue_delivery_otp(p_order_id bigint, p_request_id uuid, p_actor uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.notify_customer_on_order_status() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.notify_new_order() | False | none | {postgres=X/postgres,service_role=X/postgres} |
| public.notify_vendor_on_new_order() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.notify_vendor_on_status_change() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.pre_delivery_checklist(p_order_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,authenticated=X/postgres} |
| public.rls_auto_enable() | True | ['search_path=pg_catalog'] | {postgres=X/postgres,service_role=X/postgres} |
| public.start_checklisted_delivery(p_assignment_id bigint) | True | ['search_path=""'] | {postgres=X/postgres,authenticated=X/postgres} |
| public.submit_pre_delivery_checklist(p_assignment_id bigint, p_version integer, p_confirmations jsonb) | True | ['search_path=""'] | {postgres=X/postgres,authenticated=X/postgres} |
| public.sync_order_status_from_vendor_order() | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres} |
| public.update_timestamp() | False | none | {postgres=X/postgres,service_role=X/postgres} |
| public.vendor_adjust_stock(p_product_id bigint, p_quantity integer, p_mode text, p_reason text, p_request_id uuid, p_threshold integer, p_expected_version bigint) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |
| public.vendor_can_insert_product(p_vendor_id integer) | True | ['search_path=public'] | {postgres=X/postgres,service_role=X/postgres} |
| public.verify_delivery_otp(p_order_id bigint, p_otp text, p_request_id uuid) | True | ['search_path=""'] | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} |


## Recorded row counts

131 requirement/scenario/screen rows: DEVIATION-APPROVED=4, IMPLEMENTED-UNVERIFIED=8, MISSING=8, NOT TESTED=7, PARTIAL=74, VERIFIED=30. Overlapping rows are not distinct implemented features. Entire audit remains PARTIAL for limitations in FINAL-progress.md.

## Stage1 evidence addendum — 2026-10-22

Stage0 matrix/counts are historical, not a description of unchanged source after Stage1. Detailed current evidence: `docs/FINAL-security-audit.md`, `docs/evidence/FINAL-security-results.json`.

| Requirement/finding | Current Stage1 disposition | New code/evidence | Remaining scope |
|---|---|---|---|
| SEC-A01 HIGH / SEC04 / FR43 | Security remediation verified | AI client no credential lookup/provider HTTP; shopping-assistant authenticated/bounded/private server proxy deployed TEST;20Deno and Dart tests; actual app_settings/invalid Edge denials | No actual provider-use/account quota functionality accepted |
| SEC-A02 HIGH / S03 / SEC05 | False-payment-success remediation verified | PaymentScreen no card fields or success invocation; widget test including delayed3s | Gateway/callback/refund implementation remains missing Stage2, not marked compliant |
| SEC-A03 / FR05 | Dashboard-entry role check remediated | Fresh canonical RoleAccessGate; all dashboard entry sites gated; four-role/pending/blocked/revoked tests and actual session reads | All-screen rendered inventory remains incomplete |
| SEC-A05 / FR44/SEC07 | Vendor approval audit gap remediated; FR44 overall PARTIAL | final1_review_vendor and transactional trigger including legacy update; strict inputs/confirmed result/confirmation dialog;79SQL checks include one actual audit/no-op/owner/email-event preservation | Manual/configuration modules absent; universal error audit/full hosted lifecycle coverage pending |
| SEC-A06 / FR43/SEC10 | Filter-grammar risk remediated; overall PARTIAL | final1_search_products literal bounded invoker RPC; request/error/disposal handling; SQL/actual HTTP validation | Full catalogue/category UX and unimplemented writes remain Stage2 |
| SEC-A07 / FR42/SEC01 | RLS exception fixed; FR42 overall PARTIAL | New private limiter/RLS; existing fr30_private.limits RLS enabled;80table catalog/320operation matrix/170function index; no exposed private schemas;79SQL/86HTTP | Every legacy positive/negative operation not independently executed; no production claim |
| SEC-A09 / SEC04 | Current diagnostic source corrected | TEST-only configured ID reads, no embedded anon key/production target; bounded729file/953blob scan at recorded checkpoint | Public anon historical blobs and Firebase restrictions remain documented; no history rewrite/rotation |
| SEC02 | New TEST verification evidence | Synthetic password storage nonempty bcrypt-format aggregate; no hashes printed | Not independent audit of GoTrue implementation/all logs |
| SEC03 | PARTIAL with observed JWT3600s | Actual4role authenticated JWT lifetimes; existing session/block guard tests | Seven-day refresh expiry not established;40fixture sessions observed with no not_after; free alternative requires deviation approval |
| SEC06 | NOT VERIFIED globally | Assistant10/minute plus existing feature quotas | Not100/minute universal gateway/REST/Storage/Realtime/Auth coverage |
| SEC08/S05 / SEC-A04 | OPEN/CONTAINED |3private protected buckets; actual four-role direct listing denied; accepted signing/encryption retained | Missing product/prescription/document/photo secure media workflows deferred |
| SEC-A08 | OPEN/DEFERRED | No biometric policy change | Stage3/user fallback/enrollment decision, no physical biometric acceptance |
| FR18/24 / PhaseF | Fabricated analytics/reviews removed | Real empty/error/retry; delivered revenue; no sample review fallback; no fake saved instruments/rewards/instant assignment | Full earnings/rating writes still incomplete; checkout hardcoded multi-rider suggestions remain deferred |
| FR14 | NOT FUNCTIONALLY ACCEPTED, unchanged | Existing route authorization/Dart/Deno/read denials preserved | Physical road/progression/deviation and prior latency gates not resolved by Stage1 |

Only new security evidence above changes current dispositions; do not infer whole-SRDS or complete Stage1 acceptance. No Stage2–5 handoff approved.


## Completion pass — 2026-10-22, baseline553039d

Current static reconciliation and diagrams: UI-control-reconciliation.md and FINAL-stage-0-1-acceptance.md. Historical131-row status counts remain unchanged: they describe implementation acceptance, not audit effort. Stage1 fixes supersede stale historical descriptions for FR05/06/18/24/27/42/43/44, SEC04/07/08 and O01/05/08; see FINAL-security-audit.md. No blanket promotion to VERIFIED. FR14 remains NOT FUNCTIONALLY ACCEPTED.

Every existing requirement now has an explicit owner stage below. References identify the physical PDF page/section/scenario; implementation, evidence, gap and priority remain the seven columns of its original row plus dated security changes. Investigation is source/report based; unavailable runtime/configuration proofs remain open. No future-stage implementation acceptance is inferred.

| Requirement | Exact SRDS reference | Responsible stage | Current implementation status |
|---|---|---|---|
| FR-01 | 3.2 FR-01; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-02 | 3.2 FR-02; physical12–17 | Stage2 functional; Stage5 verification | IMPLEMENTED-UNVERIFIED |
| FR-03 | 3.2 FR-03; physical12–17 | Stage2 functional; Stage5 verification | IMPLEMENTED-UNVERIFIED |
| FR-04 | 3.2 FR-04; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-05 | 3.2 FR-05; physical12–17 | Stage1 security; Stage5 final coverage | PARTIAL |
| FR-06 | 3.2 FR-06; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-07 | 3.2 FR-07; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-08 | 3.2 FR-08; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-09 | 3.2 FR-09; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-10 | 3.2 FR-10; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-11 | 3.2 FR-11; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-12 | 3.2 FR-12; physical12–17 | Stage2 functional; Stage5 verification | IMPLEMENTED-UNVERIFIED |
| FR-13 | 3.2 FR-13; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-14 | 3.2 FR-14; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-15 | 3.2 FR-15; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-16 | 3.2 FR-16; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-17 | 3.2 FR-17; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-18 | 3.2 FR-18; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-19 | 3.2 FR-19; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-20 | 3.2 FR-20; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-21 | 3.2 FR-21; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-22 | 3.2 FR-22; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-23 | 3.2 FR-23; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-24 | 3.2 FR-24; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-25 | 3.2 FR-25; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-26 | 3.2 FR-26; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-27 | 3.2 FR-27; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-28 | 3.2 FR-28; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-29 | 3.2 FR-29; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-30 | 3.2 FR-30; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-31 | 3.2 FR-31; physical12–17 | Stage2 functional; Stage5 verification | PARTIAL |
| FR-32 | 3.2 FR-32; physical12–17 | Stage2 functional; Stage5 verification | VERIFIED |
| FR-33 | 3.2 FR-33; physical12–17 | Stage2 functional; Stage5 verification | DEVIATION-APPROVED |
| FR-42 | 3.2 FR-42; physical12–17 | Stage1 security; Stage5 final coverage | PARTIAL |
| FR-43 | 3.2 FR-43; physical12–17 | Stage1 security; Stage5 final coverage | PARTIAL |
| FR-44 | 3.2 FR-44; physical12–17 | Stage1 security; Stage5 final coverage | PARTIAL |
| UC-01 | 3.2 use-case UC-01; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| UC-02 | 3.2 use-case UC-02; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| UC-03 | 3.2 use-case UC-03; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| UC-04 | 3.2 use-case UC-04; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| UC-05 | 3.2 use-case UC-05; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| UC-06 | 3.2 use-case UC-06; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| UC-07 | 3.2 use-case UC-07; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| UC-08 | 3.2 use-case UC-08; physical18–22 | Stage2 functional; Stage5 verification | PARTIAL |
| S-01 | 4.2.1 S-01; physical31 | Stage1 security; Stage5 final coverage | PARTIAL |
| S-02 | 4.2.1 S-02; physical31 | Stage2 functional; Stage5 verification | VERIFIED |
| S-03 | 4.2.1 S-03; physical31 | Stage2 functional; Stage5 verification | MISSING |
| S-04 | 4.2.1 S-04; physical31 | Stage2 functional; Stage5 verification | VERIFIED |
| S-05 | 4.2.1 S-05; physical31 | Stage1 security; Stage5 final coverage | PARTIAL |
| S-06 | 4.2.1 S-06; physical31 | Stage2 functional; Stage5 verification | DEVIATION-APPROVED |
| SEC-01 | 4.2.2 SEC-01; physical31–32 | Stage1 security; Stage5 final coverage | PARTIAL |
| SEC-02 | 4.2.2 SEC-02; physical31–32 | Stage1 security; Stage5 final coverage | IMPLEMENTED-UNVERIFIED |
| SEC-03 | 4.2.2 SEC-03; physical31–32 | Stage1 security; Stage5 final coverage | NOT TESTED |
| SEC-04 | 4.2.2 SEC-04; physical31–32 | Stage1 security; Stage5 final coverage | PARTIAL |
| SEC-05 | 4.2.2 SEC-05; physical31–32 | Stage1 security; Stage5 final coverage | MISSING |
| SEC-06 | 4.2.2 SEC-06; physical31–32 | Stage1 security; Stage5 final coverage | NOT TESTED |
| SEC-07 | 4.2.2 SEC-07; physical31–32 | Stage1 security; Stage5 final coverage | PARTIAL |
| SEC-08 | 4.2.2 SEC-08; physical31–32 | Stage1 security; Stage5 final coverage | PARTIAL |
| SEC-09 | 4.2.2 SEC-09; physical31–32 | Stage1 security; Stage5 final coverage | VERIFIED |
| SEC-10 | 4.2.2 SEC-10; physical31–32 | Stage1 security; Stage5 final coverage | PARTIAL |
| T5.6-01 | 5.6 row01; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-02 | 5.6 row02; physical42–45 | Stage2 functional; Stage5 verification | NOT TESTED |
| T5.6-03 | 5.6 row03; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-04 | 5.6 row04; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-05 | 5.6 row05; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-06 | 5.6 row06; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-07 | 5.6 row07; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-08 | 5.6 row08; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-09 | 5.6 row09; physical42–45 | Stage2 functional; Stage5 verification | MISSING |
| T5.6-10 | 5.6 row10; physical42–45 | Stage2 functional; Stage5 verification | MISSING |
| T5.6-11 | 5.6 row11; physical42–45 | Stage2 functional; Stage5 verification | MISSING |
| T5.6-12 | 5.6 row12; physical42–45 | Stage2 functional; Stage5 verification | DEVIATION-APPROVED |
| T5.6-13 | 5.6 row13; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-14 | 5.6 row14; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-15 | 5.6 row15; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-16 | 5.6 row16; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-17 | 5.6 row17; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-18 | 5.6 row18; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-19 | 5.6 row19; physical42–45 | Stage2 functional; Stage5 verification | IMPLEMENTED-UNVERIFIED |
| T5.6-20 | 5.6 row20; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-21 | 5.6 row21; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-22 | 5.6 row22; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-23 | 5.6 row23; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-24 | 5.6 row24; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-25 | 5.6 row25; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-26 | 5.6 row26; physical42–45 | Stage2 functional; Stage5 verification | DEVIATION-APPROVED |
| T5.6-27 | 5.6 row27; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-28 | 5.6 row28; physical42–45 | Stage2 functional; Stage5 verification | PARTIAL |
| T5.6-29 | 5.6 row29; physical42–45 | Stage2 functional; Stage5 verification | VERIFIED |
| T5.6-30 | 5.6 row30; physical42–45 | Stage1 security; Stage5 final coverage | PARTIAL |
| UI-A | 3.3.1 screenA; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | IMPLEMENTED-UNVERIFIED |
| UI-B | 3.3.1 screenB; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | PARTIAL |
| UI-C | 3.3.1 screenC; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | PARTIAL |
| UI-D | 3.3.1 screenD; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | PARTIAL |
| UI-E | 3.3.1 screenE; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | PARTIAL |
| UI-F | 3.3.1 screenF; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | PARTIAL |
| UI-G | 3.3.1 screenG; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | VERIFIED |
| UI-H | 3.3.1 screenH; physical23–28 | Stage4 UI; Stage2 required services; Stage5 runtime | PARTIAL |
| O-01 | 2.3.1; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-02 | 2.3.2; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-03 | 1.3/2.3.3; see full requirement row and diagram map | Stage2 functional; Stage5 verification | VERIFIED |
| O-04 | 2.3.4; see full requirement row and diagram map | Stage2 functional; Stage5 verification | VERIFIED |
| O-05 | 2.3.4; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-06 | 2.3.5; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-07 | 2.3.5; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-08 | 2.3.6; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-09 | 2.3.6; see full requirement row and diagram map | Stage2 functional; Stage5 verification | MISSING |
| O-10 | 2.3.7; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-11 | 2.3.7; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-12 | 2.3.7; see full requirement row and diagram map | Stage2 functional; Stage5 verification | MISSING |
| O-13 | Table5.6-15; see full requirement row and diagram map | Stage2 functional; Stage5 verification | MISSING |
| O-14 | 2.3.8; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-15 | 2.4; see full requirement row and diagram map | Stage4 UI; Stage2 required services; Stage5 runtime | PARTIAL |
| O-16 | 2.4; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-17 | 2.5.1; see full requirement row and diagram map | Stage5 environment/performance/portability | NOT TESTED |
| O-18 | 2.5.2; see full requirement row and diagram map | Stage3 biometric/platform policy; Stage5 runtime | IMPLEMENTED-UNVERIFIED |
| O-19 | 2.5.2; see full requirement row and diagram map | Stage3 biometric/platform policy; Stage5 runtime | PARTIAL |
| O-20 | 2.5.2; see full requirement row and diagram map | Stage5 environment/performance/portability | PARTIAL |
| O-21 | 3.3.2; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-22 | 3.3.3; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-23 | 3.3.4; see full requirement row and diagram map | Stage2 functional; Stage5 verification | PARTIAL |
| O-24 | 4.1; see full requirement row and diagram map | Stage5 environment/performance/portability | NOT TESTED |
| O-25 | 4.3.1; see full requirement row and diagram map | Stage5 environment/performance/portability | PARTIAL |
| O-26 | 4.3.2; see full requirement row and diagram map | Stage4 UI; Stage2 required services; Stage5 runtime | NOT TESTED |
| O-27 | 4.3.3; see full requirement row and diagram map | Stage0 design decisions; Stage2–5 implementation/verification | PARTIAL |
| O-28 | 4.3.4; see full requirement row and diagram map | Stage5 environment/performance/portability | PARTIAL |
| O-29 | 4.3.5; see full requirement row and diagram map | Stage5 environment/performance/portability | NOT TESTED |
| O-30 | 4.3.6; see full requirement row and diagram map | Stage5 environment/performance/portability | PARTIAL |
| O-31 | 4.3.7; see full requirement row and diagram map | Stage0 design decisions; Stage2–5 implementation/verification | PARTIAL |
| O-32 | 4.3.8; see full requirement row and diagram map | Stage0 design decisions; Stage2–5 implementation/verification | IMPLEMENTED-UNVERIFIED |
| O-33 | 5; see full requirement row and diagram map | Stage0 design decisions; Stage2–5 implementation/verification | PARTIAL |

## FINAL02 current checkpoint — 2026-10-23 (Asia/Karachi)

Stage0 PARTIAL; Stage1 PARTIAL — SECURITY ACCEPTANCE PENDING; Stage2 readiness NO. This supersedes earlier pending-approval/device/activation labels while preserving their history. A/B/C approvals remain granted within their exact scopes.

Canonical inventory:56files,410source templates,295noncontrol references,707historical crosswalk rows. Corrects the earlier406/297checkpoint for three interactive maps/PageView; passive map preview remains composition. Source-template counts are not runtime pass counts. See [canonical controls](FINAL02-ui-canonical.md) and [rendered-state evidence](FINAL02-rendered-states.md).

TEST0004applied once after successful readiness/25rollback checks;25post checks passed. Current42versions/83RLS-enabled tables/174functions. Post-activation108four-role,13boundary,20targeted,5real signed-CNIC deadline,12own-profile Realtime,8rollback-only and10actual anonymous installation-capability,11physical/hosted lifecycle checks passed within their named scopes. Installed TEST APK/source hashes match; four-role routing/restoration, blocked/re-login and revoked/logout observations recorded individually. Marked customer confirmed active; phone logged out. Final affected18PASS; scoped analysis0issues. Historical290Flutter/2skips,175Deno and173hosted results are not new full-suite runs or additive totals.

See [current acceptance checkpoint](FINAL-stage-0-1-acceptance.md#final02-current-checkpoint--2026-10-23-asiakarachi), [policy/validation/Admin-audit matrix](FINAL02-security-matrix.md), [current evidence](evidence/FINAL02-acceptance.json) and [retained feature reconciliation](evidence/FINAL02-retained-features.json). Remaining evidence: full conditional rendering/handlers, other private Realtime topics/media paths, physical error/retry and secure-storage faults, independent retained-definer/legacy-operation proof. FR42/43/44 PARTIAL; FR14 NOT FUNCTIONALLY ACCEPTED. No Stage2–5 work, production modification, reset/replay, push or merge.


## FINAL03 final closure — 2026-10-23 (Asia/Karachi)

The131 audited requirement rows and their explicit stage ownership remain retained. Stage0 **COMPLETE (audit/classification)**; Stage1 **SECURITY ACCEPTED on isolated TEST**. This supersedes the preceding PARTIAL checkpoint for these stages only. It does not mark131 requirements functionally complete.

| Requirement / audit scope | Current status | Evidence / scope |
|---|---|---|
| Stage0 controls/conditions/handlers |Audit complete; focused named runtime evidence and future owners reconciled |FINAL03-ui-canonical.md; FINAL03-rendered-states.md;412templates/56files/295references/707historical rows;37new UI cases plus retained reports |
| FR02/03/05 active session/role boundary |Stage1 security accepted |10storage faults; canonical four-role gate; FINAL02 four-role physical; final-source customer login/restart/logout and Vendor switching retained |
| FR42 |Accepted for active access paths and deny-default deferred resources |FINAL03-security-matrix.md;84table/336operation metadata scope; real user policy, media, websocket and session tests |
| FR43 |Accepted for active trusted validation |Product media guard migration0001; retained transactional/byte validation; current74Flutter/17Deno and176hosted assertions |
| FR44 |Accepted for active critical Admin actions |Current audit4; retained rider/block/dispute/broadcast/assignment accounting; mutation/tamper denials |
| Retained FR04/10/13/17/20/21/25/26/28/30/32/33/checklist |Prior bounded acceptance preserved, affected integrations verified |14report hashes/ancestry revalidated including unacceptedFR14; current private-media/Realtimesecurity and lifecycle tests |
| FR14 |NOT FUNCTIONALLY ACCEPTED |Road-route/ETA/physical movement outstanding; no waiver, not a Stage0/1 security blocker |
| Later-stage implementation |Unchanged approved stage owners |A/B/C remain exact; no Stage2 or Stage3 biometric implementation begun |

No production/iOS/scale/provider acceptance inferred. Final signoff records actual levels and limitations.


## Stage2 cohort01–03 checkpoint — 2026-10-23

Baseline b19dc24 and Stage0/1 acceptance remain unchanged. Stage2 is in progress on feature/final-2-functional. S2-01 Vendor onboarding/review and S2-05 catalogue/search have bounded functional acceptance; see `FINAL-stage-2-acceptance.md`, `FINAL2-onboarding.md`, `FINAL2-catalogue.md`, `FINAL2-cart.md` and append-only evidence `evidence/FINAL2-01-results.json`, `evidence/FINAL2-02-results.json`, `evidence/FINAL2-03-native-results.json`. Cart persistence/restoration/account isolation passed; add-time reservation policy is pending and FR07 is not fully accepted. TEST48migrations/85RLS-enabled tables/183functions verified after004–006, each applied once after review. Onboarding19SQL cases/27HTTP-Realtime checks, catalogue8SQL cases/11HTTP checks, cart12SQL cases/12HTTP checks; candidate/post overlap. Flutter92PASS first cohort,79PASS affected cart cohort and30overlapping final unit cases;32PASS destructive-confirmation/UI cohort. Full analysis0errors/14inherited warnings/34infos. Native cohort28observations:18Android,10Auth/persistence/HTTP probes, explicitly separated. Fresh real-email Vendor signup/rejection/approval/notices/restart; actual two-Vendor cart/restart/account switching; category browsing and physical offline Retry recovery passed. Product deletion now verifies an affected row and suppresses pending repeats; vendor rejection now requires explicit whole-order cancellation confirmation (widget evidence). Existing RLS/session/quota/audit protections retained. New COD settlement work is in progress and is not accepted or deployed by this checkpoint. No new FR14 movement/ETA acceptance. No production modification, paid dependency, Docker, load test, push/merge or Stage3–5 work.

Stage2 follow-up04: guarded product deletion007 applied once (TEST49migrations); direct table DELETE stays denied.11SQL cases/6realHTTP-persistence checks and32Flutter cases verify owner/version/history/audit protection and confirmed handler effects. S2-17 accepted for current reachable destructive actions; full FR16/media and COD008 remain in progress. See `FINAL-stage-2-acceptance.md`, `FINAL2-confirmations.md`, `evidence/FINAL2-04-product-delete-results.json`.

Stage2 cash checkpoint05: TEST008 applied once;50migrations/86RLS tables/186functions verified. Append-only COD acknowledgements and manual refund results preserve original payment/action history;27SQL cases review/post and27real authenticated HTTP/persistence checks PASS,62affected Flutter PASS, scoped analyzer0issues. Exact role/ownership/gateway/audit/idempotency/privacy guards verified. Source includes Admin cash records, Customer payment/refund views and Rider receipt acknowledgement. Installed APK predates these additions; FR32 cash invoice integration and overall Stage2 acceptance remain pending. No real cash transfer or physical delivery claim. See `FINAL2-cod-ledger.md`, `evidence/FINAL2-05-cod-results.json`. Production untouched.
