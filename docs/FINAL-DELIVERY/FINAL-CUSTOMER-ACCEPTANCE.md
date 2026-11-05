# Final Customer Acceptance — TezRider

2026-11-05, Asia/Karachi. **NOT READY FOR CUSTOMER ACCEPTANCE.**

The fixes below are implemented and published. This is not a claim that every SRDS requirement or physical journey has passed. Remaining gates are explicit; earlier historical evidence is not relabelled as current acceptance.

## Source and environment

- Branch: `feature/final-customer-delivery-fixes`.
- Application source: `0a70920d25f0d7e6e9db6a5c8de785659f7ec073`, pushed and independently cloned from GitHub.
- Base: `36f08e8f04ec9eb7569b212a779f27597cfc2d3c` premium UI branch, preserving the earlier portability/main history.
- Main remains `9e51e9d9fca4f1e63cfbf94742fd33c1eaca9485`. No merge, force push or history rewrite was performed in this stage. The earlier portability audit records the already-contained historical branches; they were not blindly replayed.
- Only Supabase TEST `igeisilhtmglgnqvllrx` was accessed. Protected project `arrqsvejrfdbacfwtpcc` was not accessed. The CLI labels TEST's primary database branch “production”; that label does not identify the protected production project.
- Flutter 3.47.6 / Dart 3.13.5; existing JDK 17, Android SDK and locked dependencies retained. No application dependency or mandatory paid service was added.
- Three additive/permission migrations were reviewed in rollback transactions, previewed individually, deployed only to TEST, and their regression SQL rerun after deployment. They retain existing orders, payment state, stock and legitimate identity approvals.

## Verification

- Root full suite: **812 PASS, 0 FAIL, 2 SKIP**. The skips are the existing credential-dependent hosted Rider cases; they were not silently enabled with another person's password.
- Fresh GitHub clone at the source above: `flutter pub get` passed with unchanged `pubspec.lock`; full suite **812 PASS, 0 FAIL, 2 SKIP**.
- Current presentation suite after the missing-photo correction: **12 PASS**, offline source-backed screen fixtures, not live backend acceptance.
- Deno 2.9.8: **240 PASS, 0 FAIL**. Test runtime network access was not granted; only fixture output directories were writable. These tests sent no email, push or routing request.
- SQL: `FINAL-customer-product-favorites.sql`, `FINAL-customer-saved-location.sql` and `FINAL-customer-related-favorites.sql` passed against TEST before and after their migrations. Test mutations rolled back; no additional order was created.
- Configuration guard: **11 PASS**. Windows preflight: **0 failures**, with the existing harmless unused `SUPABASE_JWKS_URL` warning in private configuration.
- Clean-clone analysis: **No issues found**. Android TEST arm64 debug APK built, signature verified and installed with existing app data retained. Customer session restoration to the dashboard was observed.
- APK SHA-256: `28f5cb9b4ed0a9c42409769d3b2df973b6764ca327441cd8965dd9b4ea0cf8ab`, 106,275,524 bytes; package `com.example.flutter_application_1.fr21test`, min SDK 24, target SDK 36. Poppins/Naskh/Material icons are bundled; no `.env` asset. It is a debug TEST artifact, not production signing.
- The recipient check was temporarily blocked by automatic approval review reaching a usage limit. Normal review resumed after its reset. The owner subsequently approved the TEST recipient correction and one existing invoice email. Recipient secret digest was verified against the approved inbox; order 2439's existing job reports **sent**, **one attempt**, no error. On 2026-11-05 the owner confirmed: “Received; PDF opens and total is PKR 600”. No new invoice, order, payment or cash event was created.
- Secret review: 1,375 deliverable text files scanned. The two inherited candidates are public Firebase client configuration and an explicitly non-secret rejection fixture. No new privileged credential was found. Private `.env`, TEST Firebase, server secrets, DPAPI state, tokens and device captures remain excluded from Git. History and files above the scanner's size limit were not rescanned.

- Final-source Chrome smoke: login rendered; empty submission displayed “Please fill in all fields”; selecting Rider changed the form to “Sign in as Rider”. No credentials or orders were submitted. Authenticated journeys and browser language-switch acceptance remain unverified.

## Reported issues

PASS in this table applies to the stated implementation or bounded check. BLOCKED means the full requested acceptance has an outstanding dependency; it does not erase passing component tests.

| Issue | Verified cause and implementation | Verification / result | Remaining acceptance |
|---|---|---|---|
| Cross-role login | Dropdown choice was ignored; navigation already used the server profile, so protected Rider access was not established by the reported symptom. Password and biometric paths now compare a frozen selection with the authenticated server role, clear failed/mismatched sessions, bound requests and preserve generic credential errors. Errors are scrolled into view. | **PASS**: all 16 selected/server role combinations; secure logout/account-switch regressions; actual TEST role/status reads and role-restricted dispute endpoint checks. | Current-build physical four-role sign-in/restoration matrix remains separate from widget/network checks. Owner enters genuine Rider credentials privately. |
| CNIC upload FR-04 | Native `File(path)` and unguarded `Platform.isAndroid` broke browser selection/recovery. Both pickers now consume `XFile` bytes. CNIC safely resizes legitimate photos, strips metadata and retains 5 MB/signature/decoded-image limits. Private upload and same-request retries remain authoritative. | **PASS mechanics**: 18 real TEST checks on an existing pending synthetic Rider: upload, path/object confirmation, replay, authorized Admin private download, matching bytes, unrelated/anonymous denial, pending status retained. | **BLOCKED** genuine identity/physical camera-gallery/restart acceptance. The controlled checkerboard is not an identity document and no approval was fabricated. |
| Delivered disputes FR-25/26 | Existing server eligibility correctly requires owned delivery within 24 h and no conflicting open dispute. Latest observed delivered order 3180 is outside that window. Browser evidence selection/recovery had the same file-path defect and is fixed. | **PASS** bounded eligibility/image/controller/admin regressions; actual role-denial reads. Ineligible orders were not made selectable. | **BLOCKED** fresh eligible owned-order submission, private evidence review and Admin resolve/reject acceptance. No replacement order, timestamp reset or invented delivery was used. |
| Images | TEST inventory has 85 product rows without an image reference and one private reference; absence is data, not a failed URL. Existing authorized private rendering/expiry remains intact; legacy network-image errors now offer real cache-evicting retry. Product detail explicitly distinguishes missing photo and failed retrieval. | **PASS** byte/expiry/account-boundary/retry regressions; current UI fixtures. | **BLOCKED** complete actual-photo acceptance until correct approved product/store photos and exact mappings are supplied. No guessed restaurant imagery or public CNIC bucket was introduced. |
| Categories/icons | Recovered exact historical controls: All, Food, Grocery, Pharmacy, Thrift, Preloved, Tailoring. Live names/filtering remain; unavailable products are not fabricated. Category fallbacks use Material icons. | **PASS** source-backed render/filter tests and actual Android Customer dashboard observation. | Current full catalogue/category data remains subject to existing Vendor availability and ownership. |
| Instagram | No owner-verified destination was found. Removed the incorrect active link and show a truthful unavailable notice. | **PASS** source and UI verification. | Official URL can be enabled when supplied. Other unrelated existing links were not invented or changed. |
| Address/GPS | Checkout previously locked the address and replaced it with coordinates. Written house/street details remain editable and survive pin changes. Saved-address schema now retains validated optional coordinates and confirmation time; old text-only addresses/clients remain valid. Real GPS/map selection requires explicit confirmation. | **PASS** SQL persistence/replay/revision/ownership/coordinate checks; service fault tests; 3 offline checkout interaction tests, including clearing an old pin after selecting another address. | **BLOCKED** current APK's physical permission/GPS/save/cold-restart journey. No coordinates were invented or published. |
| Product Favorites | `favourite` had no authenticated table privileges despite broad inherited policies. Replaced broad policies with Customer-owner policies, retained live-session guard and added unique actor/product pairs after confirming no duplicates. Writes update UI after confirmation. | **PASS** SQL owner/foreign/Vendor/anonymous/duplicate checks, real Customer gateway read 200 with zero foreign rows, UI removal/retry tests. Physical empty state and Add to Favorites navigation observed. | Final current-APK save/remove/restart check remains to be bound to the final artifact. |
| Vendor/Rider Favorites | Owner approved the documented contract on 2026-11-05. Existing UUID table is used through Customer-only RPCs, actual Vendor order history and delivered-Rider relationships; idempotent save, paging and owner removal are implemented. Private contacts, CNIC and locations are not returned. Existing order details and Favorites view expose the controls. | **PASS** rollback and deployed SQL checks, lost-response/account-switch/wrong-receipt/busy/widget regressions. | Final current-APK owner journey remains pending. No production model or unrelated account directory was created. |
| “Couldn't be loaded” states | Added bounded profile reads, truthful permission/transport errors and retries; stale/uncertain changes do not become success. | **PASS** affected error/loading/empty/retry cohorts. | A failed future provider/network operation still surfaces an error; universal connectivity is not guaranteed. |
| Vendor Unavailable cancellation FR-10 | Orders 3181–3183 recorded only pending then cancelled, with `vendor_timeout` after the configured three-minute deadline. No accepted event was present. This matches SRDS's 2–3 minute default, rather than proving an erroneous cancellation. Vendor 998 is approved/active/unblocked but currently has no stored pickup coordinates. | **PASS** read-only cause/timing audit and existing transition regressions. Timeout, stock and refund guards were not relaxed. | **BLOCKED** fresh authorized Vendor accept/fulfilment journey and real pickup configuration. Do not auto-enable Vendors, invent a pickup or create another order without approval. |
| Delivery animation | Bundled cyclist runs only for actual order-level on-the-way events. Vendor pickup reservations cannot trigger it; reduced motion disables animation. | **PASS** five lifecycle/animation widget tests. | Physical moving-delivery presentation remains part of the unexecuted active-delivery journey. |
| Premium UI | Coral/cream shared theme, bundled typography and historical category/icon restoration retained; new internal address/Favorites/error controls follow existing components and Urdu translations. | **PASS** scoped actual Android Customer observation, 12 current offline screen renders, prior documented narrow/RTL checks and new interaction regressions. | **BLOCKED** complete current-build visual/accessibility acceptance across every role/screen. Independent external design evaluation was unavailable; no pixel-identical or whole-app visual certification is claimed. |
| Invoice/email FR-32 | Order 3180 has pending COD payment, no cash-collection event and no invoice. That is the expected eligibility rule, not a missing paid-invoice claim. Server PDF/private-storage/outbox/lease/idempotency code is retained. | **PASS** worker/PDF unit regressions and read-only eligibility audit. Existing synthetic invoice 2439 was privately downloaded through authenticated Admin access; its hash, length, one-page layout, order ID and PKR 600.00 total were verified. It is not an invoice for 3180 or proof of a new payment. | **PASS bounded send**: the owner-approved existing invoice 2439 reports sent, one attempt, after TEST recipient verification. **PASS owner receipt**: the owner confirmed the email arrived and its PDF opens with a PKR 600 total. This acceptance is limited to that single TEST invoice. No cash acknowledgement was fabricated to qualify 3180. |
| Admin broadcasts FR-30 | Existing Admin-only audience/estimate/confirmation/history/dispatch path retained; failures are not presented as delivered. | **PASS** existing Flutter and Deno permission/retry/idempotency cohorts. | **BLOCKED** bounded approved recipient/device send and receipt. No unrelated or mass broadcast was sent. Current role-wide audiences contain 39 Customers, 22 Vendors and 33 Riders, so a role-wide send would not be the requested one-device test. |
| Fresh Windows laptop | Guide/README now select the published delivery branch, public TEST `.env`, correct existing Firebase file and exact verified toolchain. Client configuration remains private and excluded from Git. | **PASS** actual fresh GitHub clone, dependency resolution, unchanged lock and full suite; final APK build/analysis recorded separately. | **BLOCKED** actual second-laptop execution; a fresh clone on this machine is not another laptop or iOS acceptance. |

## Priority FR and full SRDS status

FR-04/10/13/14/17/20/21/25/26/28/30/32/33 remain individually scoped in the existing compliance matrix and the evidence above. Passing a changed widget/service does not promote the whole requirement.

- FR-13 uses genuine positions; current Android requests two-second fixes and the publication gate is 2,300 ms. Historical measured foreground/background/recovery medians were 3.946/5.422/5.218 s, failing the original 2–3 s target. No current active-order cadence was measured and the target was not waived.
- FR-14 has real server routing/ETA, but historical total requests of 4,265/3,047/2,484 ms failed the unwaived 800 ms gate. This stage made zero routing-provider requests and did not reset the earlier three-request approval budget.
- FR-17 transactional stock, FR-20 radius/escalation, FR-21 persistence and FR-28 blocking implementations/regressions are retained. New full hosted business journeys were not inferred from file existence.
- FR-33 retains the previously owner-approved secure email alternative to paid SMS. It is an approved deviation, not an ordinary SMS PASS. This stage sent no OTP; the separately approved synthetic invoice email is recorded above.
- The retained full matrix has 137 rows: 77 bounded historical PASS, 17 approved deviations, 42 partial and 1 blocked. It was not rewritten to claim 137 fresh current-build acceptances. See `15-SRDS-Complete-Test-Matrix.md`, `20-FR-Document-Verification.md`, `24-Performance-and-GPS-Results.md` and `FR-GITHUB-PORTABILITY-AUDIT.md`.
- The SRDS PDF and owner-supplied FR text are available; the original binary FR Word file was not inspected. Finite free-tier capacity, SLA, iOS/APNs/signing and production deployment gates remain unchanged.

## Configuration and release decision

Follow `docs/PARTNER-WINDOWS-SETUP.md` and the current branch/commit above. Backend migrations are already applied to the authorized TEST project. They are not permission to deploy to production. Private SMTP/provider/service-role/database/FCM credentials never belong in Flutter or Git.

Order 3180 was preserved: delivered, one earning record, no collected-cash claim, no paid invoice. Final stock/payment readback is recorded in sanitized evidence. No additional order, fabricated GPS, fake identity approval, new payment, refund settlement, push/route send or production change was made by this stage.

Release recommendation: **NOT READY FOR CUSTOMER ACCEPTANCE** until the explicit physical, timing, imagery, bounded notification/invoice and partner-machine gates are completed. The published bug fixes and portable source can be reviewed and run without representing those gates as passed.

## Changed source files

Implementation commit contains 39 changed/new files. The exact list follows; final acceptance/evidence documentation is a separate publication-only commit.

```text
README.md
docs/FINAL-DELIVERY/FAVORITE-RELATIONSHIPS-PROPOSAL.md
docs/PARTNER-WINDOWS-SETUP.md
docs/POLICY-DECISIONS.md
docs/evidence/FINAL-CUSTOMER-secret-review.json
lib/core/app_translations.dart
lib/core/final_customer_translations.dart
lib/screens/customer/about_tezrider_screen.dart
lib/screens/customer/enhanced_checkout_screen.dart
lib/screens/customer/order_detail_screen.dart
lib/screens/customer/saved_addresses_screen.dart
lib/screens/customer/saved_stores_screen.dart
lib/screens/customer_dashboard.dart
lib/screens/login_screen.dart
lib/screens/product_detail_screen.dart
lib/services/cnic_document.dart
lib/services/dispute_service.dart
lib/services/related_favorites_service.dart
lib/services/saved_addresses_service.dart
lib/widgets/order_timeline.dart
lib/widgets/order_timeout_summary.dart
lib/widgets/product_image.dart
lib/widgets/related_favorites.dart
scripts/check-windows-setup.ps1
supabase/migrations/202611040001_final_customer_product_favorites.sql
supabase/migrations/202611050001_final_customer_saved_location.sql
supabase/migrations/202611050002_final_customer_related_favorites.sql
supabase/tests/FINAL-customer-product-favorites.sql
supabase/tests/FINAL-customer-related-favorites.sql
supabase/tests/FINAL-customer-saved-location.sql
test/auth_language_test.dart
test/closure_ui_states_test.dart
test/cnic_document_test.dart
test/delivery_timeline_restoration_test.dart
test/final_domain_images_test.dart
test/login_role_matrix_test.dart
test/related_favorites_test.dart
test/saved_address_checkout_ui_test.dart
test/saved_addresses_test.dart
```

## Acceptance evidence published separately

- `docs/evidence/FINAL-CUSTOMER-verification.json`
- `docs/evidence/FINAL-CUSTOMER-apk.json`
- `docs/evidence/FINAL-CUSTOMER-cnic-mechanics.json`
- `docs/evidence/FINAL-CUSTOMER-role-reads.json`
- `docs/evidence/FINAL-CUSTOMER-cancellation-audit.json`
- `docs/evidence/FINAL-CUSTOMER-invoice-review.json`

Device captures, private signed links, the prepared invoice PDF and all operator configuration stay local. The original unwaived gates remain open.

Single-email consent/result: `docs/evidence/FINAL-CUSTOMER-invoice-send.json`. No recipient address, provider identifier, signed URL or private PDF is published in that evidence.
