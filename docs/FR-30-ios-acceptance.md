# FR-30 iOS/APNs verification — 2026-10-15

Base: `40ad2ca0851e7a3f203f173a1fc1d96b41a8d9d1`.

**iOS/APNs: NOT EXECUTED. Static readiness: FAIL.** Native iOS support is
incomplete. No iOS compilation, signing, APNs registration or iPhone delivery
has passed. Android acceptance in `FR-30-acceptance.md` remains historical and
unchanged. Machine-readable inspection: `evidence/FR-30-ios.json`.

## Checks performed

- **FAIL — Firebase iOS configuration absent.** No `GoogleService-Info.plist`
  under `ios`, no Firebase plist resource in `project.pbxproj`, and no
  `lib/firebase_options.dart`. The supplied external secret directory contains
  Android configuration and the existing server service account only. Neither
  substitutes for a registered Firebase iOS application.
- **FAIL — isolated iOS identity absent.** Runner has only Debug/Release/Profile
  configurations and the Runner scheme. Its bundle ID is
  `com.example.flutterApplication1`; there is no `fr21test` iOS scheme. An owned,
  explicit TEST bundle ID must be selected and matched across Apple and Firebase.
  The Android package must not be copied into iOS configuration by assumption.
- **FAIL — signing and push capability incomplete.** No `DEVELOPMENT_TEAM`,
  `CODE_SIGN_ENTITLEMENTS`, iOS entitlements file or Push Notifications capability
  is configured. Generic `iPhone Developer` settings do not establish valid
  signing. Actual certificates/profiles and their entitlements cannot be verified
  here.
- **FAIL — Background Modes absent.** `Runner/Info.plist` has no
  `UIBackgroundModes`. Firebase's setup calls for Background fetch and Remote
  notifications. These capabilities must be enabled for the isolated TEST target.
- **FAIL — native dependency integration incomplete.** No Podfile/Podfile.lock,
  Pods workspace reference or Flutter generated Swift package integration is
  present. Runner targets iOS 13.0, while the installed `firebase_core` 5.0.0 and
  `firebase_messaging` 17.0.0 podspecs each require iOS 15.0. Resolve this on the
  Mac using the installed Flutter toolchain; do not downgrade accepted Android
  dependencies. Raising the supported iOS minimum needs an explicit compatibility
  decision before claiming support for existing iOS 13/14 devices.
- **FAIL — iOS notification lifecycle not implemented.** `main.dart` registers
  only `AndroidBroadcastPushService`; its platform/flavor gate excludes iOS.
  Permission requests, registration refresh and logout cleanup in that service
  therefore never run on iOS. It initializes only Android local notifications.
  There is no iOS APNs-token readiness, Darwin notification setup or remote
  notification tap/cold-start route. The normal AppDelegate plugin registration
  is present, and method swizzling is not explicitly disabled; this alone does
  not prove native messaging works. No notification usage-description string
  should be invented: authorization is requested through the notification API.
- **FAIL — existing sender is not an iOS implementation.** `fcm.ts` emits only
  Android configuration, with the accepted Android package restriction. The
  private registration schema/RPC has no platform discriminator and uses the
  Android enable flag. APNs routing, environment/topic and iOS payload behavior
  have not been implemented or tested. Simply removing the client platform gate
  would enroll iOS into an unverified delivery path.
- **NOT EXECUTED — APNs key and console setup.** No `.p8` was found in `ios` or
  the supplied `C:\secrets\tez-rider` directory. No private-key contents were
  inspected. Apple/Firebase console access was not available for verification;
  absence locally does **not** prove a key is absent from Firebase. Team/Key ID,
  app registration, APNs upload validity and membership remain unverified.
- **NOT EXECUTED — native build/device tests.** Host is Windows; `xcodebuild`,
  `xcrun`, `pod` and `sw_vers` are unavailable. With SDK cache access, actual
  `flutter build ios` exited 1: `Could not find a subcommand named "ios" for
  "flutter build".` This is an environment limitation, not a compiler result.
  There is no usable Mac/Xcode/iPhone test connection in this session.
- **PASS — existing FR-30 regressions, current checkout.** Ran `flutter test
  --no-pub --concurrency=1 --reporter expanded test/fr30_push_delivery_test.dart
  test/admin_broadcast_test.dart`: 23 passed, exit0. These cover delivery/session
  races and broadcast behavior; they do not exercise iOS native messaging.
  Git diff confirms `android`, `lib`, `supabase`, `pubspec.yaml` and
  `pubspec.lock` match base40ad2ca. Ignore probes for Firebase plist, `.p8`, `.p12`
  and provisioning files passed; `git diff --check` passed. SQL/Deno/hosted
  regressions were not rerun because no backend or runtime code changed.

## Next setup step

Provide access to a Mac with Xcode and a physical iPhone, together with an
existing authorized Apple Developer team (or an eligible institutional fee
waiver). Confirm the team's owned **iOS TEST bundle ID**. No Apple purchase or
paid service has been authorized or introduced.

Then complete these steps on that Mac before native acceptance:

1. Register that exact TEST identifier with Push Notifications in Apple, and
   register the same iOS app in the existing Firebase TEST project
   `tez-rider-fe12b`. Save its `GoogleService-Info.plist` outside Git; supply only
   its path, never private-key contents. Add it only to the TEST target resources.
2. Upload an appropriate APNs authentication `.p8` directly to that Firebase iOS
   app's Cloud Messaging configuration with its Key ID and Team ID. Keep the key
   outside the repository and Flutter app; it is not a client asset or a new
   Supabase client secret. Verify access and APNs environment in the consoles.
3. Configure a TEST scheme/configuration, signing team and matching provisioning
   profile; enable Push Notifications and Background Modes. Verify the signed
   application's `aps-environment` entitlement rather than guessing its value.
   Resolve native dependencies and the iOS 15 minimum with Xcode/Flutter.
4. Implement a separately gated iOS TEST path preserving Android behavior. Wait
   for APNs registration before FCM calls; use the installed registration API,
   secure owner/session-bound storage, refresh/rebinding, permission states,
   logout/block cleanup and tap handling. Add platform-aware TEST-only server
   registration/dispatch through additive migrations; never replay migration006
   or modify production `arrqsvejrfdbacfwtpcc`.
5. Verify an iOS delivery design before rollout. The Android data-only hint and
   authenticated resolution approach cannot promise reliable iOS terminated
   delivery. Background execution is constrained; a user swipe-away stops
   background handling until reopening. Assess OS-presented alerts and their
   privacy/logout implications; do not send confidential text or silently relax
   session/block guarantees. Distinguish normal termination from force-quit.
6. Build and sign on the Mac, inspect the embedded TEST Firebase identity and
   entitlements, and test a real iPhone: denial/allow/settings changes, APNs/FCM
   registration and refresh, foreground/background/normal termination,
   force-quit limitation, tap/cold-start navigation, unread/read badges,
   logout/relogin/rebinding, blocked user and invalid registration cleanup.
   Record actual OS/device and provider evidence; provider acceptance alone is
   not device delivery. Rerun affected Flutter/SQL/Deno/TEST regressions and
   accepted Android lifecycle checks before an iOS acceptance commit.

Only Supabase TEST `igeisilhtmglgnqvllrx` is authorized. No backend, native runtime,
Android implementation or accepted FR was modified during this inspection.
`ios/.gitignore` now excludes Firebase iOS config and common Apple signing files.
The pre-existing root `.gitignore` modification was preserved. No commit,
push or merge was performed.

## Official references checked

- [Firebase Flutter FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started):
  Apple capabilities, APNs upload, swizzling and APNs-token readiness.
- [Firebase Flutter receive behavior](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages):
  permission, foreground presentation and iOS swipe-away limitations.
- [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup):
  macOS/Xcode, signing and physical device setup.
- [Apple membership](https://developer.apple.com/programs/whats-included/) normally
  costs USD99/year; [eligible organizations can request a fee waiver](https://developer.apple.com/help/account/membership/fee-waivers).
  Without an existing eligible team/waiver, native APNs conflicts with the strict
  zero-cost requirement. Existing in-app notifications remain the available
  free-compatible alternative; they do not satisfy background APNs delivery.
