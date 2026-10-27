# Frontend UI/UX upgrade

2026-10-27 (Asia/Karachi). Baseline: `69197a6516422c37bf2b3900909aa06030081bd8`, existing `feature/final-2-functional` repository and origin preserved.

## Delivered changes

- Login: compact branded header, constrained responsive form, visible native-label English/اردو selector before authentication, persistent existing language preference, immediate label/RTL updates, retained typed inputs and role IDs, autofill and keyboard submission. Signup uses the shared palette and inherits the selected locale.
- Authentication controls: accessible 48px password-visibility button, disabled fields/role/signup/help during sign-in, reusable busy/disabled Material actions. Password reset validates email, prevents repeated submission, retains retryable localized errors, disposes its controller, and reports success only after Supabase confirms the request. Password and account-bound biometric authorization logic is preserved. Incomplete-registration back/Sign In now securely invalidates the current session and returns to Login instead of leaving a root-route dead end; a focused secure-storage/navigation test covers it.
- Design system: existing forest-green branding retained; stronger hint contrast, coherent restrained role colors, shared backgrounds/text/spacing/radii, reusable action buttons and statistics cards. Customer catalogue/cards and Customer/Vendor/Rider/Admin navigation retain actual controllers and backend values.
- Customer: shortened entrance/card motion; shared palette for search, product details, cart, checkout through the theme, history, profile, saved addresses/stores, notifications and Help/About. Removed a misleading dropdown arrow from the noninteractive location badge. About no longer invents five-minute delivery, app rating, rider counts or update status.
- Vendor: reusable statistics cards driven by the existing vendor controller/report; consistent product form/gallery, inventory and analytics colors. No product-image or destructive-action workflow replaced.
- Rider: consistent palette and a reusable, responsive availability card below the app bar. This resolves the physically observed cramped Urdu title; the switch has a full touch target, disables during pending/unknown state and labels unavailable state accurately. Requests never invent an online success. Motion respects OS preferences. Presence, GPS, proof, OTP, earnings and failure behavior remain backend-driven.
- Admin: shared statistics cards, grid adapts to enlarged text; three overlapping floating action buttons replaced by one labelled menu retaining Orders/monitoring, Broadcast notifications and Manage Users. Active-order text contrast improved.
- Payments: COD remains the existing checkout policy. Card/wallet/bank options are explicitly disabled with a localized explanation, instead of opening nonfunctional add/save flows. No payment integration or stored instrument is fabricated.
- Shared states: keyboard/screen-reader-friendly empty-state action buttons; reusable skeletons become static with reduced motion; order timeline stops decorative pulsing under reduced motion and after delivery.
- Motion: shared 160/240/320ms tokens and ease-out curve, subtle fade/slide routes via the native theme transition, no route animation under OS reduced-motion/accessibility preferences. Tab/scroll state now also survives successful same-account authorization rechecks. Retained content is offstage, non-focusable and has decorative tickers disabled while verification runs. Account/role changes, denial or errors discard it; server role checks remain mandatory. A fast failed read now returns the fail-closed retry panel rather than an unhandled future error. Login entrance does not replay on ordinary rebuilds.
- Accessibility: login scrolls at narrow/landscape sizes, email/password remain LTR within Urdu layouts, directional alignment, translated password tooltips, labels and disabled-state semantics. Removed the global 115% text-scale cap; tested login at 200%. This does not establish every legacy screen at every accessibility setting.
- Performance: no new dependency, animation network call or duplicate backend read added. Existing signed/private image lifetime and account cleanup retained. Metric values animate only when values change; hidden tabs retain existing ticker suppression.
- Environment: decorative TEST banner and unnecessary TEST wording in location notification removed. TEST app title/package/flavor, Firebase project checks, backend guard, isolation defines and build preflight remain intact.

## Control audit and limits

Fresh reproducible census: `tests/integration/FRONTEND-ui-audit.py`, `docs/FRONTEND-ui-canonical.md`, `docs/evidence/FRONTEND-ui-inventory.json`. All 707 historical references are retained and aligned to the prior checkpoint. Source templates are not unique rendered controls and are not device acceptance. All records keep `physical_verified=false`; named test/device checks provide narrower evidence.

83 source files / 45 screens; 491 templates (362 screen-connected, 96 shared, 33 unreachable legacy templates); 297 non-control references. No physical verification is inferred.

No literal empty callback or TODO handler was found by the bounded source search in lib. Resolved controls include login language selection, password visibility, password-reset validation/busy/retry, disabled unsupported payments, keyboard-capable empty-state actions and the Admin menu. Existing authorization, confirmed-result/error/retry and role-gate regressions were exercised. This is not a claim every dynamically generated control and backend action has passed a physical journey.

## Verification

- Final combined focused suite: **150 PASS, 0 FAIL**, seventeen files: frontend_upgrade, stage0_rendered_audit, auth_language, language_settings, app_navigation, biometric_security_policy, backend_config, vendor_dashboard_stats, closure_ui_states, closure_remaining_states, final_completion_security, order_detail, onboarding, onboarding_access, rider_presence, role_gate_state and account_session. Includes 16 new frontend tests plus 5 new access-view state/security tests. Earlier runs overlap and are not added to 150.
- Root-cause regression: the original same-account resume test failed because dashboard state reset. After the fix, all 5 new gate tests pass: hidden-state retention, denied-access disposal, actor-change disposal, safe read failure/retry, and blocked keyboard activation during checks. A focused 44-test security/control run also passed (overlaps the final 150).
- Initial test-only failures were corrected (including explicit disposal of the extra semantics handle): controller initialization in the widget-test async environment, exact existing Urdu wording, isolated language storage in the legacy login-render test. Final result above supersedes those runs.
- Format: changed Dart files formatted. `git diff --check` passed.
- Build-safety preflight: **11 PASS**; rejects production endpoint/identity misuse and privileged mobile keys.
- Secret scan: current tracked/unignored UTF-8 files <=2MB and reachable local/cached history scanned. Only existing public Firebase client configuration and an intentionally fake build-preflight secret fixture in current source; historical public anon tokens were also identified. No privileged credential detected in that scope. Actual credentials, private files, raw coordinates, signing keys and build artifacts stay ignored. Strengthened .gitignore and removed three accidental shell-command lines from it.
- Static analysis: lib plus the changed test files: **0 errors, 3 inherited warnings, 30 inherited infos** (33 findings), no new findings. Final seven-file focused analysis: **0 errors / 0 warnings**, with 2 inherited curly-brace style infos in rider_dashboard.dart. The earlier five-file focus had no findings. The earlier whole-repository analysis also included inherited test/root-script findings.
- Android: Final debug TEST APK built and installed on AESWNRBAEUPNTGJZ. Package com.example.flutter_application_1.fr21test retained. SHA-256 0F86C791697617D6CC3EE541DE0B9CA25FD946F133281BB60006B91BBF86B508; 138771324 bytes; 204 runtime-source hashes verified against current source; installed base.apk hash matches. English/Urdu login visually checked on the accessibility-fixed APK; language survives cold start. Screenshots and role checks retain their original artifact bindings below. Customer authenticated and real order 389 rendered without a mutation. Account-bound biometric sign-in passed on the preceding accessibility-fixed APK A4FEE40675683F730888988702D7910E273D9A8D12EF61656AFF0F171EE6684F (runtime commit 5dcf80a), before the final signup-return, Rider-header and access-view state fixes; Login/AuthController/credential/native-biometric sources are unchanged in the final APK: offline cold start retained the shortcut, exact network states were restored, the owner completed the fingerprint prompt and a server-refreshed Customer dashboard appeared. Ordinary session restoration is intentionally separate from the opt-in shortcut. Navigation-fixed APK Vendor dashboard/analytics confirmed real PKR 45.75 delivered sales; these Vendor sources are unchanged in the final Rider-layout APK. The older FR28 Vendor fixture correctly required registration; the accepted existing live-vendor fixture was used instead. No registration data was invented or submitted. Final Rider-layout APK: Admin session restored through the server gate, Urdu dashboard and all three labelled menu destinations observed; Rider authenticated in Urdu, corrected header and confirmed offline card visually checked. Final physical tab-resume/logout acceptance is INCOMPLETE: the controlled sequence lost a reliable visible TEST surface and was not promoted to PASS. Final APK installation and installed base.apk hash are verified. Earlier four-role/biometric results remain bound to their recorded artifacts and unchanged relevant source, not silently relabelled as final-artifact passes. Screenshots: ../evidence/FRONTEND-login-en.png and ../evidence/FRONTEND-login-ur.png.

## Delivery and remaining acceptance

TEST Supabase remains `igeisilhtmglgnqvllrx`. No SQL, migrations, Edge Functions, backend grants or production (`arrqsvejrfdbacfwtpcc`) data/configuration changed. No new service or paid dependency introduced.

Runtime changes are committed in `29f5ab81c6adc09eed7705bad95c2d0b82cc747d` on `feature/final-2-functional`, using the existing origin. Delivery documentation/evidence is a separate commit. Normal feature-branch push verification is reported in the final chat; no force-push or main/master push is authorized or used.

Full frontend acceptance remains subject to actual device checks and every required rendered control. Whole-application production readiness remains **NO**: the backend/tracking latency/background location, iOS/APNs, signing, routing, end-to-end proof/OTP, production deployment and capacity gates in 11-Known-Issues-and-Limitations.md and 12-Final-Handover-Report.md remain separate. A debug TEST APK is not production acceptance. No performance, battery, SLA, complete screen-reader/contrast or every-density certification is inferred from widget tests.

## Files changed

- `.gitignore`
- `lib/core/app_translations.dart`
- `lib/core/stage2_ui_translations.dart`
- `lib/main.dart`
- `lib/routes/app_routes.dart`
- `lib/screens/admin_dashboard.dart`
- `lib/screens/customer/about_tezrider_screen.dart`
- `lib/screens/customer/cart_screen.dart`
- `lib/screens/customer/help_center_screen.dart`
- `lib/screens/customer/notifications_screen.dart`
- `lib/screens/customer/order_history_screen.dart`
- `lib/screens/customer/payment_methods_screen.dart`
- `lib/screens/customer/profile_screen.dart`
- `lib/screens/customer/saved_addresses_screen.dart`
- `lib/screens/customer/saved_stores_screen.dart`
- `lib/screens/customer_dashboard.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/product_detail_screen.dart`
- `lib/screens/rider_dashboard.dart`
- `lib/screens/search_screen.dart`
- `lib/screens/signup_screen.dart`
- `lib/screens/vendor/prescription_review_screen.dart`
- `lib/screens/vendor/product_form_screen.dart`
- `lib/screens/vendor/vendor_analytics_screen.dart`
- `lib/screens/vendor/vendor_products_screen.dart`
- `lib/screens/vendor_dashboard.dart`
- `lib/services/delivery_location_platform.dart`
- `lib/theme/app_motion.dart`
- `lib/theme/app_theme.dart`
- `lib/widgets/app_action_button.dart`
- `lib/widgets/app_language_selector.dart`
- `lib/widgets/app_stat_card.dart`
- `lib/widgets/empty_state.dart`
- `lib/widgets/order_timeline.dart`
- `lib/widgets/password_reset_dialog.dart`
- `lib/widgets/shimmer_cards.dart`
- `test/frontend_upgrade_test.dart`
- `test/stage0_rendered_audit_test.dart`
- `tests/integration/FRONTEND-native.py`
- `tests/integration/FRONTEND-ui-audit.py`

New shared availability component: `lib/widgets/rider_availability_control.dart`.

Access-view fix: `lib/widgets/role_access_gate.dart`, `test/role_gate_state_test.dart`. Final whole-lib analysis remains 0 errors / 3 inherited warnings / 30 inherited infos (exit 2 due to warnings). No whole-application production acceptance is inferred.

Final acceptance: frontend implementation and automated regression delivery are recorded; exhaustive frontend/device acceptance is **PARTIAL**, not COMPLETE. The final APK is installed and hash-verified, but a completed controlled final resume/logout run is still required. Device helper-owned temporary XML files were cleaned. No production readiness or full physical every-control pass is claimed.
