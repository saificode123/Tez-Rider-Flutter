# GitHub portability and functional acceptance audit

2026-11-03, Asia/Karachi. Scope: authorized TEST `igeisilhtmglgnqvllrx`.
Production `arrqsvejrfdbacfwtpcc` was not accessed or modified. No messages,
routes, accounts, orders, CNIC approvals, cash acknowledgements or lifecycle
writes were created. Order 3180 was inspected read-only.

## A. Reproduced causes

1. A fresh GitHub clone has no `.env`. The requested build actually failed with
   `Did not find the file passed to "--dart-define-from-file". Path: .env`.
   This file should remain ignored; the fix is a tracked template and explicit
   secure provisioning, not committing local credentials.
2. The owner's existing `.env` contains `SUPABASE_PUBLISHABLE_KEY`, whereas the
   shared `main.dart` and push verifier read only `SUPABASE_ANON_KEY`. Thus even
   passing that file left the startup key empty. Both names now resolve through
   one shared function, with ambiguous values rejected and an actionable error.
3. Clean source declares `assets/videos/`, but Git had no file preserving that
   empty directory. The Android attempt emitted `unable to find directory entry
   in pubspec.yaml` for that path. A tracked `.gitkeep` restores the directory.
4. `pubspec.yaml` advertised Dart ^3.9.2, while its committed lockfile requires
   Dart >=3.13.0 / Flutter >=3.44.0. Manifest constraints now match the lockfile.
   Verified local SDK: Flutter 3.47.6 stable / Dart 3.13.5. No dependency upgrade.
5. The README was an unmodified Flutter starter and supplied no flavor,
   compile-time defines, JDK, Firebase or secure configuration instructions.

These are reproduced repository/configuration defects. The partner's actual
terminal log, installed tool versions, branch and laptop were not available;
her exact first failure cannot be independently attributed beyond these facts.
Adding `.env` and Firebase alone does not resolve an old SDK or incorrect command.

## B. Exact setup and toolchain

Use [PARTNER-WINDOWS-SETUP.md](../PARTNER-WINDOWS-SETUP.md) in order. It contains
installation, licenses, exact versions, configuration, run/build commands,
troubleshooting and independent acceptance checklist. Entrypoint `lib/main.dart`;
flavor `fr21test`; package `com.example.flutter_application_1.fr21test`.

Source: AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, desugaring 2.1.4; verified Flutter
defaults compileSdk/targetSdk 36, minSdk 24, NDK 28.2.13676358; AGP default Build
Tools 35.0.0. Build JDK 17; bytecode target 11. The local Android Studio bundle
contains JDK 25, but Flutter doctor confirms a separately configured Temurin 17.
No SDK paths were committed. Flutter regenerates local.properties and ignored
Gradle launchers/wrapper JAR on a Flutter build; missing tracked wrapper binaries
are not by themselves a verified Flutter-build blocker.

`.env` is compile-time input only. `FR21_ISOLATED_TEST=true` pins the TEST
boundary. `FR30_ANDROID_PUSH=true` enables Android TEST push; its Firebase
project is `tez-rider-fe12b`. Local flavor JSON matches the registered package.
The tracked root Firebase JSON is for legacy `tez-rider` / unsuffixed package;
it must not replace the flavor file. Supabase handles Auth, Storage, Realtime
and authenticated Edge functions. There is no client SMTP, Brevo or Geoapify key.
`SUPABASE_JWKS_URL` in the owner's local file is unused; the diagnostic warns.

No Firebase Console changes were necessary to correct the inspected package.
Maps use `flutter_map` with OpenStreetMap raster tiles; Geoapify road routing
is behind the authenticated Supabase Edge Function, not initialized with a
client provider key. Existing attribution and tile usage policy remain required.
Auth provider enablement, current sender configuration, SHA registration for
other sign-in products, current FCM server credentials and fresh receipt are
not verified by this package/configuration check.

## C. Exact Git comparison

Fetched origin successfully; no blind merge or reset. Initial checkout:
`main`, HEAD `948f32402e0e256b3a162766ec0336c8728b4da4`, with existing edits.
Origin default HEAD also points to `main`. Authorized development ref was
**exactly** `2a059547a3054b35d34d6e81c181ef8879e2c19b` at inspection, with no
newer remote development commits. Both requested ancestor checks returned 0.
`bdeb72d` is included. Later destination, OTP-copy, handover and route-publication
fixes (`9e436a3`, `5981507`, `1f21078`, `21db8f7`, `e6d1fc0`) are also included.
Auth/checkout recovery source already exists; this audit did not invent it.

`main` has two additional merge commits but its tracked tree matched the shared
commit (`git diff --stat 2a05954 HEAD` empty). No missing later map/auth/checkout
feature was established. Local uncommitted lint edits are separate from GitHub.
The FR-21 feature ref is also listed as unmerged by ancestry; main's extra merge
records that history without changing the compared final source tree.
The partner's actual checkout is unverified. Portability fixes are an ordinary
forward update on `feature/final-2-functional`, not a rewrite of the shared SHA.

## D. Requirement traceability

Baseline: the owner supplied the exact 13-item FR Word contents in this chat.
The binary Word file was not inspected. The 45-page SRDS PDF was extracted
directly; FR-04 in its numbered table says CNIC number, while the owner's
priority text additionally requires document upload. Both scopes are audited.
The stale simulated/mock claims are checked against source, not accepted as facts.

Paths below are relative to the repository root. `test/` references are Flutter
unit/widget tests executed with mocks, not hosted acceptance. Matching
`supabase/tests/FR-xx.sql` and `tests/integration/FR-xx-*` are existing hosted/local
test definitions; their historical results are not fresh execution in this audit.
No row below is promoted to full end-to-end PASS solely from a passing unit test.

### FR-04 — PARTIAL

- Requirement: Rider CNIC number plus genuine document upload/review.
- Source/screens: `lib/services/cnic_document.dart`, `lib/controllers/cnic_document_controller.dart`, `lib/screens/cnic_document_screen.dart`, `lib/widgets/cnic_document_viewer.dart`.
- Backend: `fr04-cnic`, `fr04_begin_upload`, `fr04_finish_upload`, `fr04_application_status`, `users`, private `rider-cnic`; migration `202610120001_fr04_cnic_document.sql`.
- Tests/evidence: `test/cnic_document_test.dart`, `supabase/tests/FR-04.sql`, `docs/FR-04-acceptance.md`.
- Actual: validation, encryption/masking, upload admission and admin review code present; fresh bucket read confirms private. Fresh genuine upload/admin approve/reject/expiry and full current RLS journey NOT RUN. No synthetic document approved. Physical: retained historical evidence only. Fix commit: no FR workflow change; portability key resolution applies.

### FR-10 — PARTIAL

- Requirement: auto-cancel timed-out orders and trigger refunds.
- Source/screens: `lib/services/order_timeout_service.dart`, `lib/widgets/order_timeout_summary.dart`, Customer order details, Vendor transitions.
- Backend: `cancel_timed_out_orders`, `fr10_checkout`, `order_refund_actions`, timeline, stock-restoration wrapper; migrations `202610160001` / `202610160002`.
- Tests/evidence: `test/order_timeout_test.dart`, `supabase/tests/FR-10.sql`, `docs/FR-10-acceptance.md` (historical SQL/HTTP).
- Actual: scheduled/idempotent cancellation, inventory and role-notification code present; current mocked regressions included. New scheduler/hosted transaction journey NOT RUN. COD/manual refund is an approved deviation, not automatic provider settlement. Physical: no fresh timeout/refund test. Fix commit: no business change.

### FR-13 — FAIL (strict cadence); implementation present

- Requirement: real Rider GPS streaming every 2–3 seconds.
- Source/screens: `lib/services/delivery_location.dart`, `lib/services/delivery_location_platform.dart`, `lib/services/ios_rider_location_source.dart`, Rider sharing controls.
- Backend: `fr13-location`, latest-location/session state and private Customer broadcast.
- Tests/evidence: `test/delivery_location_test.dart`, `test/ios_delivery_location_test.dart`, `supabase/tests/FR-13.sql`, reports [24](24-Performance-and-GPS-Results.md) and [32](32-Delivery-Destination-Continuation.md).
- Actual: Geolocator real positions, requested Android interval currently 2 seconds; foreground service, permission/retry/stop logic present. Historical latest 300s native timestamp p50/p95 5268/6097ms, published-fix p50/p95 5.5165/6.097s. These fail the unwaived target. No simulated GPS accepted. Physical rerun unavailable; no sharing restarted. Fix commit: cadence not fixed by this portability work.

### FR-14 — PARTIAL; 800ms performance gate FAIL

- Requirement: live Rider marker, road route, destination and ETA.
- Source/screens: `lib/screens/map_screen.dart`, `lib/services/delivery_route.dart`, delivery map widgets/metrics.
- Backend: `get-delivery-route`, route cache, destination revision and authenticated tracking context; FR14 migrations and destination amendments.
- Tests/evidence: `test/delivery_route_test.dart`, `test/delivery_map_view_test.dart`, `test/destination_amendment_test.dart`, `supabase/tests/FR-14.sql`, reports 31/32.
- Actual: real routing geometry/ETA and stale-response guards present, current mocked regressions included. Latest historical fresh RPC 3651.898ms; cached 1844/1390/1453ms, all over 800ms. Single decode/frame timings are not full render p95. No new provider call; prior three-request consent is not renewed. Physical: historical bounded map evidence only. Fix commit: no timing claim.

### FR-17 — PARTIAL

- Requirement: stock decrement on placement and restoration on cancellation.
- Source/screens: `lib/services/inventory_service.dart`, cart/checkout, Vendor stock adjustment.
- Backend: `fr10_checkout` inventory wrapper, row locks, `inventory_movements`; `202610160002_fr17_inventory.sql` and later ledger guards.
- Tests/evidence: `test/inventory_test.dart`, `test/checkout_recovery_test.dart`, `test/stock_adjustment_dialog_test.dart`, `supabase/tests/FR-17.sql`, `docs/FR-17-acceptance.md` (historical concurrency/race results).
- Actual: atomic/idempotent decrement/restoration and shortage handling present. Fresh read product 224 stock=29; no order mutation. New concurrent hosted checkout/restore NOT RUN. Carts reserve no stock under owner policy. Physical: no new checkout. Fix commit: lint-only verification cleanup; no inventory semantics changed.

### FR-20 — PARTIAL

- Requirement: expand search beyond initial 5km and notify Admin if none available.
- Source/screens: `lib/services/rider_assignment_service.dart`, `lib/controllers/rider_assignment_controller.dart`, Vendor pickup readiness and Rider assignment UI.
- Backend: `fr21_ready_and_assign`, `fr20_assignment_status`, eligibility/radius/retry logic; migrations `202610150001`–`003`.
- Tests/evidence: `test/rider_assignment_test.dart`, `supabase/tests/FR-20.sql`, `docs/FR-20-acceptance.md`, historical SQL/HTTP and race checks.
- Actual: bounded expansion, stale/ineligible exclusion and duplicate-assignment guards present; current unit regressions included. Fresh timed expansion/Admin receipt NOT RUN. Physical: retained historical only. Fix commit: no assignment change.

### FR-21 — PARTIAL

- Requirement: persisted real-time Rider online/offline status.
- Source/screens: `lib/services/rider_presence.dart`, `lib/controllers/rider_controller.dart`, Rider dashboard toggle.
- Backend: presence epoch/sequence RPCs, heartbeat, trusted assignment eligibility and stale-state handling.
- Tests/evidence: `test/rider_presence_test.dart`, `supabase/tests/FR-21.sql`, `docs/FR-21-acceptance.md`; report 32 records final Offline/zero tracking sessions.
- Actual: database RPC persistence and recovery code present; current mocked race regressions included. Fresh physical logout/restart/heartbeat expiry NOT RUN. No online/sharing action performed. Fix commit: lint-only test cleanup.

### FR-25 — PARTIAL

- Requirement: Customer dispute reason and evidence-image form.
- Source/screens: `lib/screens/customer/dispute_screen.dart`, `lib/controllers/dispute_controller.dart`, `lib/services/dispute_service.dart`.
- Backend: `disputes`, FR25 prepare/upload/submit APIs, private `dispute-evidence` and order ownership guards.
- Tests/evidence: `test/dispute_test.dart`, `supabase/tests/FR-25.sql`, `docs/FR-25-acceptance.md`.
- Actual: real form, validation and authorized storage code present; bucket freshly verified private. New hosted Customer upload/association/RLS test NOT RUN. Physical: historical only. Fix commit: none.

### FR-26 — PARTIAL

- Requirement: Admin resolves/rejects actual disputes.
- Source/screens: `lib/screens/admin_disputes_screen.dart`, `lib/controllers/admin_dispute_state.dart`, `lib/services/admin_dispute_service.dart`.
- Backend: `fr26_queue`, `fr26_detail`, decision RPCs, immutable decisions/audit and notifications; `202610130006_fr26_admin_dispute_decisions.sql`.
- Tests/evidence: `test/admin_dispute_test.dart`, `supabase/tests/FR-26.sql`, `docs/FR-26-acceptance.md`.
- Actual: database-backed queue/detail/decision paths, no replacement mock backend in the production service. Current widget regressions included; fresh hosted resolve/reject/Customer receipt NOT RUN. Manual COD handling remains distinct from a provider refund. Physical: retained historical only. Fix commit: none.

### FR-28 — PARTIAL

- Requirement: Admin block/unblock, restrictions and recovery.
- Source/screens: `lib/screens/admin_users_screen.dart`, `lib/services/admin_users_service.dart`, `account_access.dart`, `account_session_service.dart`.
- Backend: `admin-user-status`, FR28 trusted blocking/RLS/access guards and audit; `202610140003_fr28_account_blocking.sql` plus later session guards.
- Tests/evidence: `test/admin_users_test.dart`, `test/account_access_test.dart`, `test/account_session_test.dart`, `supabase/tests/FR-28.sql`, `docs/FR-28-acceptance.md`.
- Actual: server-authorized state changes and session restrictions present, current mocked regressions included. Fresh role-authenticated hosted block/unblock NOT RUN; operator bucket reads are not RLS acceptance. Physical: historical only. Fix commit: reviewed braces only, no authorization weakened.

### FR-30 — PARTIAL

- Requirement: Admin broadcast to intended roles, in-app and Android push delivery.
- Source/screens: `lib/screens/admin_broadcasts_screen.dart`, `lib/controllers/admin_broadcast_controller.dart`, `lib/services/admin_broadcast_service.dart`, `android_broadcast_push_service.dart`, notification list.
- Backend: `admin_send_broadcast`, `fr30_estimate`, `admin_broadcasts`, per-user `notifications`, private push devices/deliveries, `fr30-dispatch-push`; `202610150004`–`006`.
- Tests/evidence: `test/admin_broadcast_test.dart`, `test/fr30_push_delivery_test.dart`, `supabase/tests/FR-30.sql`, `FR-30-push.sql`, `docs/FR-30-acceptance.md`, `docs/evidence/FR-30-push.json`.
- Actual: title/body validation, ALL/CUSTOMERS/VENDORS/RIDERS audiences, Admin guards, idempotency, immutable recipient snapshot, private per-user reads and durable push retry present. Fresh metadata finds 38 historical broadcasts; current unit/widget suite passes. History UI reports acceptance/recipient count, not proof of every device delivery; richer Admin failure reporting is not established. Fresh authorized recipient/foreground/background/retry delivery NOT RUN. No current mass/role send allowance verified, no broadcast sent. Physical: retained Android TEST evidence; final-device/iOS acceptance open. Fix commit: public-key alias now also used by authenticated push payload lookup.

### FR-32 — PARTIAL

- Requirement: account/order emails and legitimate invoice generation/visibility/email.
- Source/screens: `lib/services/invoice_service.dart`, `lib/widgets/invoice_button.dart`, Customer order history/details; `_shared/fr32-invoice.ts`, `fr32-email-worker`, `fr32-invoice-url`.
- Backend: `email_outbox`, `invoices`, private immutable invoice snapshots, private `invoices` bucket, `fr32_invoice_authority`, leases/quota/idempotency/retries; `202610160003_fr32_email_outbox.sql` and COD ledger amendments.
- Tests/evidence: `test/fr32_invoice_test.dart`, `test/order_detail_test.dart`, `supabase/tests/FR-32.sql`, worker/URL Deno tests, `docs/FR-32-acceptance.md`, `evidence/FR-32-acceptance.json`.
- Actual: PDF validates item quantity/price arithmetic, subtotal/shared delivery/total/currency, invoice/order/Customer/Vendor IDs, paid date/status/reference. English/Arabic font assets are present; complete Urdu layout needs visual acceptance. No invented taxes/registration. UI opens a 900-second private signed PDF. Customer/Admin backend authority exists; Vendor invoice access and an Admin invoice-opening screen are not established by these Customer controls. Do not expose a multi-vendor Customer invoice to a Vendor without requirement/authorization review.
- Current TEST read: order 3180 delivered, **zero invoices**; its order-confirmation outbox status is `sent`. This is provider workflow state, not fresh inbox confirmation. Latest owner evidence says no cash collected; no invoice is expected until legitimate eligibility. Historical FR32 evidence records a different eligible order's native PDF and owner-confirmed invoice-email receipt. New provider submission, attachment opening and owner receipt NOT RUN; no extra email sent. Physical: historical only. Fix commit: configuration alias, no payment/invoice fabrication.

### FR-33 — PARTIAL; approved email substitution

- Requirement: original SRDS says SMS delivery OTP; owner approved secure email instead.
- Source/screens: `lib/services/delivery_otp_service.dart`, Rider OTP controls, `send-delivery-otp`.
- Backend: server HMAC/expiry/attempt/replay state, confirmed canonical Customer recipient and transactional completion proof; `202610140001_fr33_email_delivery_otp.sql` and later guards.
- Tests/evidence: `test/delivery_otp_test.dart`, `supabase/tests/FR-33.sql`, `send-delivery-otp/handler_test.ts`, `docs/FR-33-srds-deviation.md`, `docs/FR-33-acceptance.md`, report 32.
- Actual: Flutter receives no plaintext OTP, current local regressions included; historical order3180 used second approved OTP and delivered. Both allowed OTP sends are consumed; no resend executed. Fresh email receipt/attempt/expiry/replay/device journey NOT RUN. Literal SMS compliance is not claimed. Physical: historical owner-confirmed code entry only. Fix commit: no OTP behavior change.

All FR workflow fix fields above refer to this audit's scope; previous feature
implementation hashes/evidence remain in the linked original acceptance records.
Portability implementation commit: `c296faf`; main-history integration:
`448fdcab77fd524b07d783f74d68d3957272f654` (pushed to main and the feature branch).

## E. Invoice conclusion

Generation and private Customer viewing are implemented and historically tested
for eligible paid/manual-cash records. There is no legitimate invoice for order
3180 in the fresh TEST read. No fresh invoice email was submitted or received.
A `sent` confirmation row is not an invoice or inbox-delivery proof. Cash must
never be invented to qualify this order. Admin/Vendor UI coverage remains open.

## F. Broadcast conclusion

Real database-backed broadcasts and push dispatch exist. Fresh metadata and
mocked tests do not establish current receipt on a TEST device. No unapproved
audience was messaged. Next real check requires an explicitly approved bounded
audience/recipient, device connection and remaining allowance, followed by actual
foreground/background receipt and failure-state observation.

## G. Cross-role conclusion

Current Chrome execution: the owner entered credentials privately and signed
in as the existing Rider. The live dashboard rendered Offline. Earnings loaded
from TEST: one completed assignment, PKR113 for order3180, calculation parts and
the explicit notice that earnings are not payout confirmation. The Admin route
did not expose Admin content to this Rider; it rendered the access gate.
No cash-receipt control, Online toggle or sharing control was activated.
These are fresh bounded Chrome checks, not physical GPS/push acceptance or a
claim of complete Customer/Vendor/Admin execution. Normal owner Auth/session
bootstrap is distinct from an operator read-only metadata query.

- Customer: mocked auth/verification/browse/cart/checkout/tracking/invoice/dispute/notification regression coverage; no fresh physical full journey.
- Vendor: mocked catalog/stock/transition/reporting coverage; no fresh physical preparation/readiness journey.
- Rider: real GPS/CNIC/presence/assignment/OTP/proof/earnings paths present, mocked regressions and retained delivery evidence; no new genuine-device journey.
- Admin: approval/block/dispute/broadcast/monitoring service tests; no new role-authenticated hosted mutations or physical journey.

The fresh TEST read uses operator metadata access only, not user-role tokens;
it must not be cited as proof of RLS or role restrictions. Do not run old fixture
integration runners blindly: some create accounts, orders and real messages.

## H. Verification ledger

Raw diagnostics remain ignored in `.fr21-local/portability/`; sanitized delivery
evidence is published alongside this audit. Baseline clean-clone dependency
resolution passed; baseline build failed on missing `.env`, and the configured
attempt exposed the missing asset directory. Baseline analysis returned 45
findings (including duplicated lines), not a clean result.

Final corrected-source full Flutter suite: **763 PASS, 2 SKIP, 0 FAIL**;
`flutter analyze --no-pub`: **no issues**, exit 0. Whole-project
`dart analyze --fatal-infos` and focused semantics analysis also passed.
The analyzer cleanup includes reviewed existing brace/import corrections,
current semantics API use, removal of write-only cart bookkeeping and an
unreferenced private card helper; active UI/business flows were preserved.

Deno 2.5.6 was obtained as an isolated temporary npm test tool, not a global
installation. **240 PASS, 0 FAIL** across the existing Edge Function tests.
Runtime network permission was withheld throughout; test dependencies were
downloaded separately. The first constrained attempts exposed PDF output-folder
permissions/assumptions. Tests now create their two output directories themselves.
Final executed command (via the temporary Deno tool):

```powershell
deno test --allow-read --allow-env --allow-write=.fr21-local/fr32,.fr21-local/final2 --no-prompt supabase/functions
```

The existing Supabase package is declared directly for standalone Dart diagnostics,
with no resolved version change. All three diagnostics compiled as plain Dart
kernels, and whole-project analysis passed again.
The generated synthetic invoice was parsed: one page, expected invoice identifier
and PKR440.00 total. This is a local test fixture, not an invoice issued to a real
Customer; no new visual PDF-layout or in-app viewing acceptance is claimed.
The read-only Windows setup check with `-SkipDeviceCheck` passed with 0 failures;
this was before the build filled the drive. A disk-space check was subsequently
added; the current nearly full owner drive is expected to fail that new check.
Seven positive/negative builder-preflight cases passed. With no Android device,
the full device check correctly remains an external acceptance dependency.

Python tracking-timing helper: **4 PASS**. Complete SRDS inventory validator:
**137 rows**, 77 retained/bounded passes, 17 approved deviations, 42 PARTIAL,
1 BLOCKED. That check validates an inventory, not 137 executed E2E workflows.
This audit does not promote a new whole requirement.

The compressed temporary-output arm64 build **passed** on Windows (596.7s).
Package `com.example.flutter_application_1.fr21test`, min/target SDK 24/36,
debug signature verified. SHA-256:
`E7E7677B05E14297CFB4A085706F7D8ED4A6CF73EA9FAF813CC2F57AA28E514C`.
The retained APK contains the arm64 Flutter engine; scanning found no protected
production project reference. It is not an x86_64 emulator APK.
After the owner freed space, the universal retry reached packaging but failed
to hash its output while the drive again ran out of space. No universal APK is
accepted. The verified phone APK is retained apart from failed outputs. Independent
second-PC, Android installation/startup/login/maps/push/PDF acceptance NOT RUN:
`adb devices` returned no connected device. iOS NOT RUN. SQL/local database
integration NOT RUN: no usable psql/local PostgreSQL/Docker test runtime was
available in this session. Hosted mutation/role-token integration NOT RUN;
only the explicitly bounded read-only TEST metadata snapshot was executed.
The universal Android attempt reached native library merging, then failed
extracting armeabi-v7a/x86_64 Flutter libraries with **There is not enough space
on the disk**. Only this audit's npm/Deno download caches were removed. The
subsequent arm64-only retry is reported separately; no universal/second-PC
acceptance is inferred from it. SDK/Pub/Gradle dependency caches are shared with
the installed host toolchain; no project build files or ignored configuration
were copied from the original working tree into the clean clone beyond the two
explicitly provisioned public TEST client configuration files.

## I. Files, Git and security

Changes: public-key alias/error handling shared by main/diagnostics/push;
configuration template; honest SDK constraints; missing asset-directory marker;
read-only Windows preflight; existing guarded builder accepts .env and validates
TEST Firebase; beginner setup/README; manual Android TEST CI; analyzer cleanup
and reproducible Deno PDF fixture directories without business changes.
Previously dirty brace/import test corrections were
reviewed and preserved. Generated plugin edits and the owner's `.gitignore`
were not swept into the portability commit.

CI is manual (`workflow_dispatch`), not executed in this audit. The subsequent
owner-authorized main update includes this workflow on the default branch;
protected TEST environment secrets must still be configured before dispatch.
See [GitHub dispatch requirements](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch).
Owner setup: create protected GitHub environment `test`, allow the authorized branch, add
`TEZRIDER_TEST_SUPABASE_PUBLIC_KEY` and `TEZRIDER_TEST_FIREBASE_CONFIG`. Values
are never echoed; no APK/configuration artifact is uploaded. Owner must review
GitHub runner availability/allowance; no paid runner or service is required.

`.env` and flavor Firebase JSON were untracked and have no path history in the
inspected repository. The tracked legacy Firebase JSON is public client
configuration, not an FCM service account. Never rotate a public client key as
a substitute for RLS. Any real privileged credential exposure requires owner
rotation; no credential value is printed or written into this report.
The current-tree pattern scan inspected 1,345 tracked text files. Its two private
key-marker candidates were manually classified as generated synthetic test-key
code and private-file validation, not embedded private credentials. Ninety-four
files contain machine paths, predominantly historical tools/test runners/docs;
no such path was found in the audited Android/lib source. This is a bounded
pattern scan, not a guarantee about every historical Git blob. Historical
machine-specific `tool/` and `tests/integration/` scripts exist and are not
portable partner setup dependencies. Their private DPAPI fixtures are bound to
the original Windows identity and should not be copied as partner credentials.

The owner subsequently explicitly authorized testing Chrome and updating main.
All remote feature refs were already ancestors of `origin/main`; no blind bulk
merge was needed. Reviewed portability implementation is `c296faf`; merge
`448fdca` also preserves the existing main history without a source conflict.
The final handover records the resulting pushed main hash. No force push or
history rewrite. Use `git pull --ff-only`; preserve local work. The isolated clone avoids changing
the dirty root checkout's branch/index.

## J. Partner handover

After tool installation and configuration from the guide:

```powershell
git fetch origin --prune
git switch main
git pull --ff-only origin main
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-windows-setup.ps1
flutter analyze
flutter test
flutter devices
flutter run --debug --flavor fr21test -t lib/main.dart --dart-define-from-file=.env
flutter build apk --debug --flavor fr21test -t lib/main.dart --target-platform android-arm64 --dart-define-from-file=.env
```

Record branch/SHA, SDK/JDK, checks, APK hash, installation, startup and explicit
device results. `build/app/outputs/flutter-apk/app-fr21test-debug.apk` is the
direct-command output. A source clone on this machine is not a second laptop.

## K. Remaining acceptance and zero-cost limits

Partner execution/logs and a connected Android device are still required.
Complete current backend role/RLS journeys, real authorized push/eligible invoice
receipt, cadence/800ms performance, iOS/APNs and production release remain open.
The owner did not waive timing requirements. No production readiness claim.
The universal build's storage failure is a host limitation. Automatic approval
review rejected cleanup of the failed output folder and then its single failed
APK file with only "blocked by policy"; the owner was asked to remove that
generated folder manually. The separately retained verified arm64 APK must be
kept. No unrelated source/configuration/user files were deleted.

Official limits checked 2026-11-03: [Geoapify Free](https://www.geoapify.com/pricing/)
3,000 credits/day, up to 5 requests/s; [Brevo Free](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan)
300 emails/day, no rollover; [Supabase Free](https://supabase.com/pricing)
500MB database, 1GB Storage and inactivity pausing. These finite shared limits
do not establish production capacity. This audit consumed **zero** route,
email or push sends. Runtime remaining provider quotas were not queried.
