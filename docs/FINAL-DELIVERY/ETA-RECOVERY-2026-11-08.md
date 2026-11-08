# ETA diagnosis and recovery fix

Application source: `0b5a18aa072af289b9f48918eceb56a057e5db48`.

The isolated TEST read-only inspection found no active order created in the
preceding 14 days and zero live-location rows. The latest controlled order,
3180, is delivered; the following three orders are cancelled. An arrival estimate
cannot be verified from those records. The owner did not identify a particular
order or role screen. No order, destination, GPS fix or delivery was fabricated.

## Fixes

- An initially unconfirmed destination previously latched the route controller
  into its access-denied state. Confirming the pin could not recover ETA without
  reopening tracking. It now rechecks on the existing 60-second request schedule.
  Actual account/session/access denials still stop requests and clear private data.
- The Customer map explicitly shows No active delivery, Delivery completed or
  Order cancelled as appropriate, rather than treating an ended delivery as an
  ETA failure. Closed orders do not open a live feed or request a route.
- Missing/stale live location and server route failures now have explanatory
  notices. Missing GPS does not become an invented duration or road route.
- English/Urdu display and both regular/compact map headers are covered.

## Verification

43 focused route/map tests passed, including confirmed-pin recovery, moving and
stationary ETA, stale position handling, account revocation, offline failures,
compact/completed/empty map presentation and Urdu/narrow/large-text layout.
The complete single-worker suite passed: **850 passed, 0 failed, 2 existing
hosted-credential skips**. `dart analyze lib test` completed with No issues found.
The arm64 TEST APK build and signature verification passed. The earlier parallel
full-suite and analysis attempts failed from host memory exhaustion; neither is
counted as a pass. Retrying sequentially changed no assertions or skip rules.
Sanitized current evidence is `docs/evidence/ETA-RECOVERY-2026-11-08.json`.

No server code/schema was changed. No production access, new order, notification,
OTP, email, live GPS write or external routing request occurred. The pending
database reset remains unexecuted. The previous three-request external routing
cap was not renewed or bypassed, and the original 800 ms routing and GPS timing
acceptance gates remain open.

The phone was initially disconnected. After the owner reconnected it, the new
arm64 TEST APK was installed successfully while retaining app data. Its on-device
SHA-256 matches the verified build:
`9624bf825fb3b0465e9f5b47b24cdce281cc91f255814f394c3a6c3a7b9118e9`.
The APK is 106,892,601 bytes, signed with the existing Android Debug certificate.
After private Customer sign-in, the owner opened the affected screen. Read-only
native acceptance then passed 4 assertions: exact installed hash, only TEST app
visible, explicit No active delivery state, and no misleading ETA unavailable
message. The repeatable checkpoint is `eta-inactive` in
`tests/integration/FINAL-android-acceptance.py`.
Actual active-delivery ETA still requires a legitimate active order, fresh shared
GPS and authorization for the bounded live verification. Automated calculations
do not certify an arrival-time prediction on actual roads/traffic. No login
screenshot or credential data is included in published evidence.
