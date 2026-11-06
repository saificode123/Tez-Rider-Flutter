# Final Customer / biometric / device acceptance

Updated 2026-11-06 UTC. This report supersedes the archived November 5 report. **Delivery remains partially accepted; not every mandatory gate has passed.**

## Published source and installed artifact

- Branch: `feature/final-customer-delivery-fixes`. Application source: `623d1c72bac1cff5c1ea6db66eb1c8c4c79f0335`. This verified source was subsequently consolidated into main with owner approval; see MAIN-CONSOLIDATION.md. No production deployment.
- APK: `tezrider-623d1c7-fr21test-arm64-debug.apk`, 106,892,601 bytes; SHA-256 `30200c6107be5976e8bf6c2d127ac0be8174f318393e1cd2ee1c0a85adcd5968`.
- Debug signer SHA-256: `8a34e66e44a7789737fd600989a927d7a0c1f2ed7fd50928317ae0a8378833fc`. APK installed with retained data on the connected OPPO Android 13 phone; installed APK hash independently matched. This is TEST/debug, not production signing or iOS acceptance.
- Protected production was not accessed. All backend changes and bounded operations target isolated TEST `igeisilhtmglgnqvllrx`.

## Executed checks

| Check | Status | Actual scope |
|---|---|---|
| Flutter regression | PASS | 846 passed, 0 failed, 2 existing hosted-credential skips; final source. |
| Dart analysis | PASS | Root and updated GitHub clone: No issues found. |
| Server Deno | PASS | 240 passed, 0 failed; isolated fixtures, no live provider traffic. |
| SQL/RLS | PASS | Four bounded rollback suites: product favorites, saved locations, related favorites, Rider quote preview. New migration tested before and after TEST deployment. No identity approval or new delivery. |
| Role login matrix | PASS | 32 password/biometric role combinations within automated tests, included in suite. |
| Android build/install | PASS | Final clone-built arm64 TEST APK, signature verified, install-r Success, exact on-device hash. |
| Native assertions | PASS | Final APK: Rider home and real PKR 113 earnings, 2 checkpoints / 6 assertions. Earlier bc38 APK: Customer home and saved-address present/absent, 3 checkpoints / 9 assertions. Read-only ADB integration, not Flutter integration_test runner. |
| Chrome | PASS bounded | Owner-assisted bc38 login rendering, empty-field validation and Rider role-label change with biometrics unavailable. Browser-control failures prevented agent-observed authenticated regression. Not full Chrome acceptance or final-source Rider proof. |
| Clean Windows clone | PASS bounded | Actual GitHub clone, private client configuration restored, unchanged dependency lock, successful build and analysis. Prior clone suite 834 passed; latest root suite 846. Another physical laptop remains untested. |

## Reported issues and physical acceptance

| Issue | Status | Evidence and remaining limit |
|---|---|---|
| Biometric sign-in | PASS bounded | Genuine explicit opt-in, native prompt, cancellation remains on login, cold-start lock, genuine successful unlock. Button moved above credentials; unsupported Chrome unavailable. Secure protected tokens, logout revocation and account/role checks covered by tests. Final-source APK installed; biometric physical success was on preceding bc38 APK. OS lockout not forced on owner hardware. |
| Cross-role security | PASS automated / BLOCKED physical negative | Server role gates and 32 test combinations pass. Genuine Rider login physically observed. During attempted Customer-to-Rider biometric negative check, owner entered genuine Rider credentials; that attempt is inconclusive, never a negative-test pass. |
| CNIC / private Storage | BLOCKED full acceptance | 18 controlled synthetic upload mechanics checks and private-bucket/policy coverage passed. Genuine camera/gallery identity-document journey not certified; no fabricated identity approval. |
| Delivered-order dispute | BLOCKED full acceptance | Picker bytes, form/eligibility and server regressions retained. Existing delivered order 3180 is outside the 24-hour window; no new authorized eligible delivery was created. |
| Product/Vendor/category images | BLOCKED data | Missing and failed-photo states and real retry fixed; 85/86 inspected TEST products lacked image references. Correct approved photos/mappings still required. No guessed business images. |
| Original categories/icons | PASS bounded | All, Food, Grocery, Pharmacy, Thrift, Preloved, Tailoring restored in source with icons and live filtering. Actual dashboard/category controls observed; live TEST fixture categories retained. This does not certify missing photos. |
| Instagram | BLOCKED URL | Incorrect active link removed; truthful unavailable state. Official owner URL still required. |
| GPS / pin / house / street / addresses | PASS bounded | Actual GPS pin confirmed by owner. Explicitly approved one TEST address saved with synthetic house/street preserved; backend read and post-restart native check passed; only approved test address deleted, count zero confirmed. No coordinates published; normal server audit/idempotency receipts retained. |
| Product favorites | PASS bounded | Actual add and backend-confirmed UI success, saved list and remove-to-empty observed on bc38 APK. Original empty state restored; no cart/order changes. Owner/foreign/idempotency SQL and retry tests pass. |
| Eligible Vendor/Rider favorites | BLOCKED physical acceptance | Approved TEST implementation uses actual Customer order history / completed Rider delivery, owner-only RPCs and public fields. SQL and Flutter checks pass; actual eligible phone add/remove journey not completed. |
| Loading errors | PASS scoped | Profile bounds, truthful failures/retries, image failures and quote error handling fixed and tested. Universal network/service availability is not claimed. |
| Vendor Unavailable cancellation | PASS audit / BLOCKED new journey | Prior orders timed out pending at configured deadline; no accepted event existed. No false timeout bypass added. Fresh actual Vendor fulfilment not performed; pickup configuration missing. |
| Rider estimate / availability race | PASS bounded | Server now permits authorized pre-acceptance preview only for fresh Online approved available Rider and eligible unassigned accepted/ready orders, preserving frozen assignment/history rules. No financial mutation. Client waits for confirmed presence and filters invalid offers. Actual final APK Online check displayed truthful missing Vendor pickup guidance, no generic estimate error, then Offline after 26.27 seconds; backend Offline confirmed. Numeric quote remains blocked by missing pickup data. |
| Delivery cyclist | PASS tests / BLOCKED moving device | Actual on-the-way lifecycle and reduced-motion tests pass. No new active moving-delivery acceptance. |
| Premium UI every role/screen | BLOCKED full acceptance | Shared coral/cream UI and scoped internal-screen fixes; 12 offline render fixtures and 42 focused checks. Inventory covers 48 screen source files, not 48 physically accepted screens or pixel-identical certification. External design evaluation unavailable. |
| Invoice PDF / email | PASS bounded | Existing authorized synthetic order 2439 PDF verified; one email sent, one attempt; owner confirmed receipt and PDF PKR 600 total. No new payment or invoice fabricated. Fresh in-app generation/viewing whole journey remains unverified. |
| Admin broadcast | PASS bounded receipt | One approved Customer broadcast created through authenticated synthetic Admin gateway, 39 in-app notices / 2 existing installations. One provider accepted; one failed INVALID_TOKEN. Owner confirmed Android notification receipt. Native Admin creation screen not physically certified; no second broadcast. |

## All 13 priority FRs

Status applies to the whole requested acceptance, not merely source existence. PASS bounded never means every role journey was freshly executed.

| FR | Status | Scope / remaining gate |
|---|---|---|
| FR-04 CNIC | BLOCKED | Secure implementation/mechanics pass; genuine camera/gallery and identity acceptance outstanding. |
| FR-10 timeout/refund | PASS bounded | Existing atomic regressions and real timeout-cause audit; no new financial scenario or Vendor fulfilment. |
| FR-13 streaming | FAIL timing | Historical real foreground/background/recovery medians 3.946/5.422/5.218 s exceed original 2–3 s target. Current 26-second idle Online check is not an active-delivery cadence measurement. |
| FR-14 route/ETA | FAIL timing | Historical routing 4265/3047/2484 ms exceeds 800 ms gate. No new external routing calls; earlier 3-request budget not reset. |
| FR-17 inventory | PASS bounded | Existing atomic decrement/restore and controlled history retained; no new order/stock mutation this check. |
| FR-20 radius/admin escalation | PASS bounded | Existing scoped regressions; no new live dispatch journey claimed. |
| FR-21 Online/offline | PASS bounded | Final APK Online then Offline physically observed; backend Offline confirmed; new delayed-response race tests pass. |
| FR-25 dispute submission | BLOCKED | Implementation/tests pass; no current eligible delivered-order physical submission. |
| FR-26 resolve/reject | PASS bounded | Existing server-backed permission/transaction regressions; no new real Admin resolution. |
| FR-28 block/unblock | PASS bounded | Existing server role and blocking regressions; no new genuine account mutation. |
| FR-30 broadcast | PASS bounded | Approved actual in-app/provider dispatch and owner Android receipt; one obsolete installation failed, not silently counted delivered. |
| FR-32 invoices/email | PASS bounded | Authorized existing invoice email and PDF owner receipt; fresh paid-order in-app journey not executed. |
| FR-33 OTP | BLOCKED strict SMS / approved email deviation | Previously approved secure email alternative retained, no new OTP sends. Not an SMS-gateway PASS. |

The retained 137-row SRDS matrix remains 77 bounded historical PASS, 17 approved deviations, 42 partial, 1 blocked. It has not been relabeled as 137 current passes. The available SRDS and owner's supplied FR text were used; original binary FR Word file was unavailable.

## Partner setup and biometric use

Follow `docs/PARTNER-WINDOWS-SETUP.md`: install the documented Flutter/Dart, JDK and Android SDK; clone and select `main`, supply private TEST `.env` and matching TEST Firebase configuration, then run the documented analysis/test/flavor commands. `.env` alone is not a substitute for the toolchain and Firebase configuration. No secrets, APK, raw UI, coordinates or private PDFs are committed.

Biometrics: sign in normally with the correct role, explicitly enable Biometric sign-in under Me/Profile and complete the genuine OS prompt. Use Lock and sign in or restart to exercise protected entry. Sign out revokes the protected credentials; use normal login and explicit opt-in again. No automatic enrollment or password storage.

Remaining mandatory gates: original timing failures; valid dispute and genuine CNIC device journeys; missing approved image data and Instagram URL; eligible related-favorites phone journey; current physical negative cross-role test; complete four-role UI/navigation/accessibility and invoice in-app acceptance; actual partner laptop, iOS and release signing. No blanket complete-success claim.

## Evidence and files

Current sanitized evidence: `docs/evidence/FINAL-DEVICE-2026-11-06.json`. Historical evidence remains date/source scoped. See archived `FINAL-CUSTOMER-ACCEPTANCE-2026-11-05.md` for earlier source fixes and evidence.

Files changed since the earlier published customer report:

```
android/app/src/main/res/values-night/styles.xml
android/app/src/main/res/values/styles.xml
docs/POLICY-DECISIONS.md
lib/controllers/auth_controller.dart
lib/controllers/rider_controller.dart
lib/core/final_customer_translations.dart
lib/middleware/auth_middleware.dart
lib/screens/ai_assistant_screen.dart
lib/screens/chat_screen.dart
lib/screens/customer/saved_addresses_screen.dart
lib/screens/customer/saved_stores_screen.dart
lib/screens/customer_dashboard.dart
lib/screens/login_screen.dart
lib/screens/product_detail_screen.dart
lib/screens/rider_dashboard.dart
lib/screens/splash_screen.dart
lib/screens/vendor/prescription_review_screen.dart
lib/services/rider_earnings_service.dart
lib/services/rider_presence.dart
lib/services/session_credentials.dart
lib/widgets/app_drawer.dart
lib/widgets/biometric_settings_tile.dart
lib/widgets/rider_earnings_panel.dart
lib/widgets/role_access_gate.dart
supabase/migrations/202611060001_final_rider_quote_preview.sql
supabase/tests/FINAL-rider-quote-preview.sql
test/account_session_test.dart
test/biometric_session_entry_test.dart
test/login_role_matrix_test.dart
test/onboarding_access_test.dart
test/rider_presence_test.dart
test/rider_quote_preview_test.dart
test/role_gate_state_test.dart
test/vendor_dashboard_stats_test.dart
tests/integration/FINAL-android-acceptance.py
```
