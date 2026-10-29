# Controlled delivery acceptance continuation

2026-10-29, Asia/Karachi. Started at `0972a61` on the existing feature branch, clean tree and expected remote verified. Owner's latest execution prompt and Rider decision are recorded in the policy addendum. Production remains untouched.

## Authorized scope and actual preflight

One COD order only: reviewed Chicken Biryani product 224, quantity one, PKR 350, existing delivery-charge calculation. Maximum two OTP emails, one confirmation and one invoice to the confirmed owner TEST inbox; order push only to the connected owner TEST phone. No SMS, online payment or unrelated broadcast. These permissions do not approve a synthetic identity or relax timing targets.

Read-only TEST preflight confirmed the actual Customer login/profile and canonical saved quantity one; product available at PKR 350 with stock 30; associated Vendor active, approved and unblocked. Owner recipient matches both confirmed Auth and the existing local configuration; the remote TEST recipient's SHA-256 metadata also matches. No plaintext address, credential or token is published. No approved pending/deferred/sending email jobs were found. Existing service-owned per-job email approval gates remain intact; no worker or email permission was activated.

All existing Customer orders and their items were checked: zero containing this product. An encrypted local checkpoint retains the original order inventory and authorized limits to identify an order created during a resumed session. No checkout, stock change, new order, OTP, email, push, proof, earning or status transition was submitted.

Vendor pickup coordinates are absent. Pickup and customer destination/charge must be confirmed through the actual workflow before checkout. Do not copy synthetic coordinates or an unrelated order's destination.

The retained approved Rider fixture had a synthetic NOT AN IDENTITY DOCUMENT upload. On clarification, the owner explicitly selected **“I will provide a genuinely verified Rider”**. That fixture is excluded; both seeded Riders remain pending. Genuine verification must occur through the normal protected CNIC/Admin process; no fabricated approval or eligibility bypass. Phone foreground inspection first failed; a later ADB read reported the phone disconnected. Physical execution is waiting for the genuine Rider and reconnected/unlocked TEST phone. No renewed notification permission is needed within the existing bounded authorization.

## Actual defect fixed while waiting

Checkout's request UUID lived only in `OrderCheckoutFlow` memory. A locally reproduced lost response after a committed request followed by screen recreation generated a different UUID: expected one server order, actual two. No hosted fixture orders were created for the reproduction.

Implementation commit `612c53b` stores the unresolved original request in the existing secure-storage package before any submission, verifies the write, and scopes it to the authenticated account that opened checkout. Recreated screens restore the original explicit destination and request UUID; no new GPS fix or automatic submission is generated. Changed cart/delivery details are rejected while the previous result is uncertain. Account switching, two competing screens, unavailable/corrupt storage and unconfirmed writes fail closed. The journal does not expire an ambiguous request. It is removed only after confirmed placement plus successful canonical cart clearing, or definitive stock/unavailability rejection. Recovery cleanup failure does not turn a confirmed order into an unconfirmed claim. English/Urdu recovery messages use the existing translation path.

Files: `lib/services/order_timeout_service.dart`, new `lib/services/checkout_request_store.dart`, `lib/screens/customer/enhanced_checkout_screen.dart`, `lib/core/stage2_ui_translations.dart`; focused recovery/storage tests and the existing checkout UI regression's storage adapter. No dependencies, database migration, server deployment or production signing changes.

Fresh full Flutter: **704 PASS, zero FAIL, two SKIP**. Related checkout/inventory/screen tests: **61 PASS**, overlapping the full suite. Final seven-file analysis: **no issues**. Initial full run found two failures from the checkout test's missing storage adapter and a following cascade; adapter added, assertions retained, then the full suite passed. Prior server 230 passes remain historical on unchanged source. Secure-storage tests use the platform adapter double; physical key-store/process-restart acceptance is still open.

Updated DEBUG TEST APK: `build/delivery/test/app-fr21test-debug.apk`, SHA-256 `8513DF0AA5AD848BDECB0E442C475EA43535BBCB89E7617491C93A369CDA06C9`. All 218 source hashes match implementation commit `612c53b`; existing Android tools verified its signature, Android Debug certificate and `com.example.flutter_application_1.fr21test` package. Installation/startup require the reconnected phone; no installed-build or production-signing claim. The previous APK/build manifest are retained under ignored `build/delivery/test/history-0972a61/` for historical GPS evidence.

## Remaining acceptance

Inventory remains 137 rows: 76 historical PASS, 17 approved deviations, 43 PARTIAL, one BLOCKED. No whole requirement promoted. Current inventory reproduction, preflight and build/test hashes are in `ACCEPT-{compliance,delivery-preflight,verification}.json`. Original Word files remain unavailable after the prior request and renewed repository/attachments search; prior PDF review is retained without claiming a new diagram inspection.

Delivery/OTP/invoice receipt, Rider earnings, Vendor/Admin reporting, real stock decrement/terminal cleanup and full cross-role acceptance are NOT RUN. No new GPS/routing measurement: prior foreground median 3.016s/p95 5.922s and routing median 986.93ms/p95 3439.9ms remain insufficient for the unchanged targets. No acceptance of proposed relaxed targets. No full accessibility/device/iOS acceptance, capacity/SLA certification, portable/runtime recovery completion, production signing or production inspection/deployment/rollback is inferred.

Next physical actions: owner completes genuine Rider review through the normal protected flow, identifies that TEST Rider by profile ID/name without sharing passwords/CNIC in chat, reconnects/unlocks the phone and opens TezRider TEST. Then verify pickup/destination and charge, current phone push capability, unique order guard and message budgets before the one checkout. Reconcile any ambiguous outcome before retrying. Production readiness remains **NOT READY**.
