# Rider authentication and controlled delivery continuation

2026-10-29, Asia/Karachi. TEST only (`igeisilhtmglgnqvllrx`); production untouched. This continues the dated evidence in report 29 without replacing historical results.

## Corrected diagnosis

The original three-r address had no TEST Auth account. The owner's corrected two-r address identifies existing Rider profile **999**, already email-confirmed. An earlier claim that this address belonged to the Customer was incorrect; canonical exact-account inspection supersedes that claim. No alias, duplicate account, manual email confirmation or verification resend was created. No new verification email delivery is claimed.

Read-only TEST configuration inspection found email confirmations enabled and custom SMTP disabled. This is a future sender-configuration limitation, not a demonstrated cause of missing mail for this already-confirmed account. No SMTP or remote Auth configuration was changed. The TEST flavor already contained the callback intent filter; its original manifest was restored unchanged after an incorrect initial assessment.

## Implemented repair

Implementation commit `a7fb0f9` adds explicit verification guidance, the normal signup-resend API with duplicate prevention and a 60-second cooldown, trusted TEST callback handling, safe expired-link handling, and completion of a missing canonical profile after verified authentication. Registration errors no longer classify every HTTP 422 as an existing account. UI wording distinguishes accepted requests from delivered email. Existing role and Admin authorization remain enforced.

The shared account settings now provide an obscured new-password/confirmation form with account-ownership checks and server-confirmed update, plus global sign-out. No previously exposed password is requested or reused; no password, callback token or private provider error is logged. The owner entered the replacement privately on the phone. The app confirmed the update; global sign-out was followed by a canonical **zero-session** inspection. The owner then signed in manually as Rider; a later inspection confirmed a new session and sign-in at `2026-10-29T08:38:18Z`. No agent password sign-in for this Rider occurred.

Runtime files: `lib/services/email_verification.dart`, `lib/screens/email_verification_screen.dart`, `lib/services/password_change.dart`, `lib/screens/password_change_screen.dart`, `lib/controllers/auth_controller.dart`, `lib/main.dart`, `lib/screens/{signup_screen,login_screen,splash_screen}.dart`, `lib/screens/customer/profile_screen.dart`, and the existing Urdu translation file. No new dependency, database migration or server deployment.

## Genuine Rider and installed build

Canonical Rider 999 is approved, unblocked and email-confirmed. The current private CNIC object exists; its submission at `2026-10-29T07:25:30Z` is followed by a canonical approval from an eligible Admin. Its digest differs from the known synthetic identity fixtures. This verifies the application's normal protected review workflow; model inspection does not establish government-document authenticity. The agent did not approve the Rider. Both seeded demo Riders remain pending.

The new DEBUG TEST APK was installed without clearing application data. Installed bytes independently matched `build/delivery/test/app-fr21test-debug.apk`, SHA-256 **8A0287B5B210980F8CEC7A486DC77B424B8BBFAB6E3F401D4094524E8D185E33**. The genuine Rider Dashboard and Online state were observed. At `09:01:48Z`, read-only inspection confirmed fresh online presence and matching location, one session and zero active orders. These are dated observations, not a claim that the device remains online after sign-out or disconnection.

## Verification and delivery state

Full Flutter regression: **725 PASS, zero FAIL, two SKIP**. Focused authentication/password tests: **46 PASS**, overlapping that suite. Analysis of 12 changed/relevant files: **no issues**. Historical server results remain historical on unchanged runtime server source; no fresh server test pass is inferred. Earlier failed/interrupted development runs are superseded only by the completed final run.

Read-only preflight and actual Customer browser UI confirmed the retained cart contains Chicken Biryani product 224, quantity one, stock 30, price PKR 350. Standard checkout displays delivery PKR 120 and total **PKR 470 COD**. No Place Order action was taken. The protected original-order checkpoint and account-scoped checkout recovery journal remain in place. Recipient configuration matches the verified owner inbox, and preflight found zero approved sendable email jobs. No OTP, confirmation or invoice has been sent in this stage.

The owner approved using the phone's current stationary position as Sana Foods' missing TEST pickup point. Saving through normal Vendor settings is in progress. The phone was signed out through normal controls for the Vendor switch. An action was subsequently blocked because automatic approval review could not complete due to usage availability; it was not executed. On continuation, the phone was disconnected, then reconnected by the owner. Current device/account state must be rechecked before proceeding.

Remaining before the one checkout: save and verify the confirmed pickup, confirm the physical customer destination and charge, match the current owner phone's push capability, refresh genuine Rider eligibility and reconcile the unique-order/message-budget checkpoint. Delivery, actual OTP receipt, proof, COD handover, earnings, reporting and terminal cleanup remain **NOT RUN**. Never promote these from preparation evidence.

Original GPS 2–3-second and routing 800ms targets remain unchanged. No new GPS/routing qualification was performed on this APK. Historical foreground median 3.016s/p95 5.922s and routing median 986.93ms/p95 3439.9ms remain insufficient. The 137-row inventory is not promoted: 76 historical PASS, 17 approved deviations, 43 PARTIAL, one BLOCKED. Production signing, iOS/APNs, capacity/SLA, portable recovery and production deployment acceptance remain open. Overall production readiness remains **NOT READY**.
