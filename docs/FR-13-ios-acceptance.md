# FR-13 iOS acceptance — 2026-10-19

**FR-13 iOS IMPLEMENTED — PHYSICAL VERIFICATION PENDING**

Base: `3408790d7c556665228d4c1cca371c4018a07cea`.
Branch: `feature/FR-13-ios-support`. Only isolated TEST
`igeisilhtmglgnqvllrx` is authorized. Production was untouched; no deployment,
migration, new job, endpoint, dependency upgrade, push or merge was introduced.

## Acceptance boundaries

- Safe Dart/configuration implementation: **COMPLETE**.
- Static configuration and Flutter unit tests: **PASS**, as recorded below.
- Native CocoaPods resolution/Ruby Podfile syntax/Xcode compilation: **NOT EXECUTED**.
- Apple signing/provisioning validation: **NOT EXECUTED**.
- Physical iPhone verification: **NOT EXECUTED**. No iPhone model, iOS version,
  native timing or battery result is available from this Windows environment.
- iOS functional acceptance: **NOT GRANTED**. Unit tests are not native evidence.
- Existing Android source/settings regressions: **PASS**. The previous physical
  acceptance remains historical; no fresh Android device test was run here.

## Inspection and implementation

Existing FR-13 already provided the assignment/checklist gate, trusted RPC/Edge
submission, private Broadcast, rate/freshness/quality guards, GetX single-stream
ownership, retries, stop/logout/terminal cleanup, customer map and stale handling.
The previous source explicitly rejected iOS. The iOS project lacked location
usage text, background location mode and a Podfile. AppDelegate already registers
Flutter plugins, so no custom native location code or background workaround is
needed. Existing Geolocator 12.0.0 / geolocator_apple 2.3.14 are reused unchanged.

`lib/services/ios_rider_location_source.dart` supplies Core Location through the
installed plugin. `delivery_location_platform.dart` selects it only on native
iOS. The Android source class is unchanged from the accepted base, confirmed by
static comparison; Android manifest and native configuration are unchanged.
`RiderController` selects the platform source; existing lifecycle/presence logic
continues to own authorization and tracking state.

`delivery_location.dart` adds optional iOS guidance/Settings support. Returning
from background rechecks iOS permission/service/accuracy without another prompt
or duplicate stream. Denial/restriction, disabled services and Settings-launch
failure provide actionable messages. `rider_dashboard.dart` exposes the iOS-only
Location settings link and the existing explicit Share/Stop controls. Android
uses the original messages and source behavior.

## Permissions, accuracy and background behavior

- **PASS, static/unit:** `Runner/Info.plist` explains foreground matching and
  active-delivery customer sharing, including a locked screen. It declares
  `NSLocationWhenInUseUsageDescription`; no Always or temporary-precision usage
  description is added. The Podfile sets
  `BYPASS_PERMISSION_LOCATION_ALWAYS=1` on the Geolocator Apple target.
- **PASS, source/unit:** Permission requests happen only from a foreground user
  action. The installed native handler requests When In Use when that plist key
  exists. Previously granted Always access is tolerated but is never requested.
- **PASS, unit:** The installed plugin maps native restricted/notDetermined to
  `denied` and denied to `deniedForever`; Dart cannot distinguish restriction
  from an unanswered request. Guidance therefore names Screen Time/device
  restrictions without claiming the user can override administrator policy.
- **PASS, unit:** Precise and reduced-accuracy status are handled. Reduced access
  is not silently upgraded. Genuine fixes still must meet the existing <=100m
  quality/time guards; wider approximate fixes are withheld with Settings advice.
  A reduced-authorized fix within the limit remains usable. No fabricated or
  relabelled coordinate and no relaxed backend accuracy policy was introduced.
- **PASS, static/unit:** `UIBackgroundModes` contains `location`; the Runner
  Background Modes capability is enabled. Only the active-delivery AppleSettings
  enable background updates and the visible system location indicator. High
  accuracy, distanceFilter 0 and automatic pause disabled retain opportunities
  for the existing ~2–3s publication target. AppleSettings has no interval API;
  iOS controls native fix timing. No exact background cadence is promised.
- **PASS, approved integration:** The user explicitly approved existing
  foreground-only matching updates after Go Online, because FR-20 requires a
  fix younger than two minutes before assignment. Idle settings use medium
  accuracy, automatic pause enabled and no background mode/indicator. The shared
  service throttles matching writes to once per minute; no polling timer or
  synthesized fix was added. Idle source stops when backgrounded.
- **PASS, unit:** Background/resume preserve a single active native subscription;
  revoked authorization/services stop it. Completion, logout, offline presence,
  blocked/ineligible responses and explicit Stop retain existing cleanup.

The minimum iOS version is now **15.0**, consistent across the Podfile, Xcode
project and AppFrameworkInfo.plist. The existing firebase_core 5.0.0 and
firebase_messaging 17.0.0 podspecs require 15.0; packages were not downgraded.
iOS 13/14 support is not claimed. Debug/Release xcconfigs include CocoaPods
settings; `pod install` and a native build remain required on macOS.

Apple permits an already running, background-enabled When In Use session to
continue when the app backgrounds. It does not relaunch a terminated When In Use
app for location. Force-quit, OS termination, Low Power Mode, disabled services,
network loss and scheduling restrictions can interrupt updates. The existing
FR-21 lease can expire during an interruption; restore Online and explicitly
Share again if needed. No workaround or relaunch guarantee is provided.
References checked before choosing the configuration:
[Apple authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services),
[background location updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates),
[restricted access](https://developer.apple.com/documentation/corelocation/clauthorizationstatus/restricted),
[Geolocator 12.0.0](https://pub.dev/packages/geolocator/versions/12.0.0).
The plugin README's generic background/Always advice was checked against its
installed native permission handler and Apple's supported When In Use model;
physical validation is still pending.

Battery: foreground matching uses lower accuracy, delivery tracking is explicit
and ends with eligibility/sharing. High-accuracy distanceFilter 0 background
tracking consumes power. Actual iPhone consumption and locked-screen scheduling
are **NOT TESTED**; record before/after percentage in a timed device session and
note charging, network and Low Power Mode. No Android battery result is reused
as iOS evidence.

## Security and customer tracking

**PASS, source/static and shared TEST checks:** the same user-authenticated
`fr13_tracking_context`/`fr13_submit_location`, FR-28 account boundary and
`fr13-location` publisher are reused. Authentication, assigned rider, active
assignment, immutable completed checklist, started delivery, approval/block state
and online lease remain server enforced. RLS, opaque private topics, no-client
publishing policy, server throttle, latest-state retention and trusted server
publication are unchanged. No client secrets or separate iOS endpoint exist.

**PASS, common Flutter tests/source comparison:** customer feed/map lifecycle,
assignment identity, stale pin removal after >30s, exact message
`Rider location temporarily unavailable.`, reconnect/recovery and disposal are
unchanged. The native tile cache and linked OSM attribution remain; only iOS's
HTTP user agent is identified as iOS instead of Android. Actual iPhone tile
rendering, native customer subscriptions and marker movement are **NOT EXECUTED**.
No FR-14 route/ETA functionality was added. Existing FR-13 Free-tier quotas
remain shared across platforms; no new scale qualification or cadence reduction
is claimed.

GPS support does not require an APNs key or Firebase iOS registration. Existing
FR-30 iOS/APNs limitations remain a separate feature; this work does not claim
push notifications are accepted or enroll iOS into the Android-only push path.

## Tests executed in this environment

Evidence: ignored `.fr21-local/fr13-ios/` logs and tracked
`docs/evidence/FR-13-ios-static.json`. Test positions are explicit unit/synthetic
fixtures; they are never represented as real iPhone GPS.

- `flutter pub get`: **PASS**; pubspec/lock unchanged.
- `dart format` on seven changed Dart files: **PASS**.
- Full `flutter test`: **243 PASS, two inherited skips**. Twenty new iOS/platform
  tests cover permissions, restricted mapping, GPS off, both accuracy modes,
  foreground/background settings, duplicate prevention, authorization/checklist
  gate, terminal/logout cleanup, network recovery and Settings resume changes.
  Existing shared customer stale/reconnect and earlier-FR tests also passed.
- Initial focused suite: **46 PASS**, before three added resume cases.
  Final focused suite: **49 PASS** after all three resume cases and style fixes.
- Final changed-file analysis: **PASS, no issues**. Full `flutter analyze` ran:
  **0 errors, 13 inherited warnings, 66 informational findings** (79 total,
  nonzero exit). Four newly introduced style notices were fixed; the original
  and final logs are retained. This is not a claim that full analysis is clean.
- Python helper syntax: **PASS**. macOS script `bash -n`: **PASS**. Windows sandbox
  initially prevented Git Bash startup; the same syntax-only check succeeded
  with runtime access. No macOS command was executed by that syntax check.
- Static native configuration: **PASS** plist parsing, iOS minimum consistency,
  When In Use/background settings and accepted Android/backend comparison.
  This does not validate Ruby/CocoaPods/Xcode compilation.
- TEST audit: **PASS**, 35 migration versions, no migration replay and accepted
  jobs unchanged. Initial audit wrapper lacked its original baseline file;
  corrected harness reads the accepted baseline, retained failed log, retry PASS.
- Hosted TEST SQL **55 PASS**, checklist regression **56 PASS**.
- Hosted HTTP **26 PASS**, actual private Realtime **24 PASS**, including roles,
  publication privacy, replay/rate limits, terminal state and unauthorized joins.
  These verify the shared backend, not a native iOS client.
- Previous-FR hosted regressions: **PASS** — FR-21 47, FR-04 49, FR-25 83,
  FR-26 95, FR-28 74, FR-20 70, FR-30 SQL 65/HTTP 25/Realtime 3, FR-10 24,
  FR-17 27, FR-32 63 and FR-33 retry 39. Initial FR-33 failed with a transport
  TimeoutError after its lockout checks; original log and failed all-suite summary
  are preserved. The isolated retry used unchanged assertions and passed. No
  backend or timeout change was made to obtain the retry result.
- Final credential/artifact candidate scan: **PASS**, 20 iOS-related files; no
  signing material, server keys, test passwords or build artifacts included.
  PowerShell wrapper syntax also passed. The final read-only TEST audit retained
  35 migration versions and unchanged accepted jobs.

## Exact native blockers and next setup step

Current host is Windows. `xcodebuild`, `xcrun`, `sw_vers`, CocoaPods `pod` and Ruby
are unavailable. No macOS executor or physical iPhone is connected to this task.
The repository has no selected DEVELOPMENT_TEAM or dedicated signed iOS TEST
identity; the current bundle ID is `com.example.flutterApplication1`. Apple
account/provisioning validity cannot be verified here. No signing material was
requested, inspected or printed.

**Next step:** open this branch on a Mac with Xcode and the matching Flutter
3.47.6 / Dart 3.13.5 toolchain, supply only the existing public TEST client defines
privately, and connect an unlocked iPhone running iOS 15 or newer. Then:

1. Check Xcode command-line tools and CocoaPods availability. Keep Apple sign-in
   inside Xcode; never paste credentials/certificates/profiles into chat or Git.
2. Run the reproducible unsigned-build helper from the repository root:
   `bash tests/integration/FR-13-ios-macos.sh /absolute/path/to/public-TEST-defines.json`.
   It validates the TEST endpoint/flag and public client key without printing
   values, runs pub get, Ruby syntax/CocoaPods resolution and an unsigned iOS
   debug build. It refuses non-macOS hosts and does not install/sign an app.
3. Open `ios/Runner.xcworkspace`, select a signing team available to the user and
   an owned explicit TEST bundle ID. Confirm the Location Updates background
   capability and iOS 15 minimum. No paid location service is needed. Do not add
   Push Notifications/APNs capability merely for GPS.
4. Build and run the signed TEST app in Profile mode on the real iPhone with the
   same public TEST defines. There is no existing iOS `fr21test` scheme; do not
   reuse Android flavor commands. Record any build/signing error honestly.
5. Record actual device model, iOS/Xcode/Flutter versions, bundle ID, build hash,
   permission choices, network/power conditions and observed timing. Store only
   sanitized evidence; keep OTPs, coordinates and credentials private.

## Required physical iPhone verification — all NOT EXECUTED

Ask the user for **one physical action at a time**, wait for confirmation, and
verify actual backend/customer state rather than treating a tap as success.

1. Rider logs in, explicitly goes Online, grants While Using access and has a
   genuine foreground matching fix; idle background does not collect location.
2. Accept valid assignment; complete checklist; start delivery; explicitly Share.
   Confirm unauthorized/unstarted/checklist-incomplete attempts remain blocked.
3. Authorized customer on iOS sees the real moving rider and rendered tiles.
   Walk safely outdoors; measure actual fresh-fix/publication intervals without
   manufacturing updates or treating drift as a measured walking distance.
4. Lock the iPhone for several minutes; inspect background indicator and actual
   customer/server updates. Background to another app and repeat. Do not infer
   force-quit survival from success here.
5. Disable network >30s; customer loses stale pin and sees exact required text.
   Restore network; verify retry/customer recovery. If FR-21 expired the lease,
   explicitly restore Online/Share and document that manual step.
6. Test denied/restricted access where possible, disabled Location Services and
   precise/reduced choices. Verify Settings recovery, quality withholding and no
   duplicate stream. Restore original user settings afterward.
7. Complete real delivery with emailed OTP entered privately by the user. Verify
   USED state, one proof/audit and stopped background GPS/session/latest state.
8. Use only a guarded synthetic zero-capture fixture for cancellation lifecycle;
   do not force-cancel an irreversible managed checkout. Verify native GPS stop.
9. An unrelated second customer must have forbidden context, no latest row and a
   rejected actual private channel join. Verify logout/block/ineligibility stop.
10. Record a timed ten-minute iPhone battery diagnostic; qualify charging and OS
    effects. Leave the TEST rider offline and tracking stopped after cleanup.

Only after a successful native build, security checks and these physical tests
may the status become **FR-13 iOS FUNCTIONALLY ACCEPTED**.

## Changed files

- `docs/FR-13-ios-acceptance.md`
- `docs/FR-13-ios-progress.md`
- `docs/evidence/FR-13-ios-static.json`
- `ios/Flutter/AppFrameworkInfo.plist`
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`
- `ios/Podfile`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner/Info.plist`
- `lib/controllers/rider_controller.dart`
- `lib/screens/rider_dashboard.dart`
- `lib/services/delivery_location.dart`
- `lib/services/delivery_location_platform.dart`
- `lib/services/ios_rider_location_source.dart`
- `lib/widgets/tez_map_tiles.dart`
- `test/ios_delivery_location_test.dart`
- `tests/integration/FR-13-ios-macos.sh`
- `tests/integration/FR-13-ios-run.ps1`
- `tests/integration/FR-13-ios-static.py`
- `tests/integration/FR-13-ios-verify.py`
