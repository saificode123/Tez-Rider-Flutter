# FR-13 acceptance report

Date: 2026-10-19. Branch: `feature/FR-13-rider-gps-streaming`.
Base: `7cf80fefdca3a54f5fd0dc5b70e9b77b1ebe3287`.
Environment: isolated Supabase TEST `igeisilhtmglgnqvllrx` only.
Production was untouched. No push or merge.

## Acceptance decisions

- Functional: **PASS — FR-13 FUNCTIONALLY ACCEPTED — Ready for the next FR.**
  Actual order 2241 completed through the existing private email OTP flow;
  synthetic cancellation and the timed battery observation also passed.
- Security: **PASS** for executed SQL, HTTP, private WebSocket, RLS, replay,
  assignment eligibility and actual-order second-customer denial checks.
- Realtime delivery: **PASS**, genuine Android fixes reached the authorized
  customer map and private receiver. Timing varies; a fresh fix every 2–3 seconds
  is not guaranteed. Hosted sub-800ms performance is not established.
- Android background: **PASS for observed foreground-service, locked-screen and
  background continuation**, including an untethered stable-Wi-Fi observation.
  Interrupted observations and limits are recorded separately below.
- Scale: **PASS for four LOCAL riders only**. 1,000 riders **NOT EXECUTED**;
  verified Free quotas cannot support 1,000 concurrent riders at this cadence.
- iOS: **NOT VERIFIED**. Rider sharing explicitly reports Android-only support.

## Implementation and security

`202610180001_fr13_live_gps.sql` was applied once to preserved LOCAL and isolated
TEST. TEST has 35 migration versions. Only `fr13-location` was deployed for FR-13.
The added `fr13-location-cleanup` job runs every 30 minutes; accepted FR-30,
FR-10 and FR-32 job schedules, active flags and command hashes were unchanged.
The 2026-10-19 resume audit confirmed migration history and jobs without replay.

An explicit foreground rider action opens an opaque order/assignment session.
The Edge endpoint validates the canonical user JWT through the existing FR-28
boundary, calls the user-authenticated submission RPC, rechecks eligibility and
publishes a private REST Broadcast using server-only credentials. Every accepted
update requires the exact assigned, approved, unblocked online rider, a valid
presence lease, completed immutable checklist and started delivery. Parent,
assignment, sorted user, rider and session locks serialize location mutations.

The SQL and Edge boundaries reject wrong roles/assignments, invalid or nonfinite
coordinates, accuracy outside 0–100 metres, stale/future/nonmonotonic device times,
extra fields, request replay and updates faster than the two-second server limit.
A failed publication returns an unconfirmed result; it never becomes simulated
success. A genuine device location is not cryptographic proof of physical presence;
there is no GPS-spoofing resistance guarantee.

Private channel reads require the canonical owning customer, assigned rider or
verified administrator and a currently eligible assignment. Anonymous users,
unrelated customers/riders/vendors and public-channel decoys fail the executed
privacy tests. A restrictive policy denies client-originated FR-13 publishing.
An unauthorized REST 202 acknowledgement is not proof of delivered content:
the actual receiver observed zero forged deliveries.

Realtime authorization is cached until rejoin/JWT refresh/expiry. The server
stops new eligible publication and rotates stopped-session topics; a message
already delivered or in flight cannot be recalled. This implementation does not
claim instantaneous global socket revocation. See official
[Realtime authorization](https://supabase.com/docs/guides/realtime/authorization).

## Persistence and retention

The user-approved design uses ephemeral REST Broadcast plus one durable latest
position per assignment. Rider/latest coordinates persist at most once per
15 seconds; a private UNLOGGED row stores only live timing and request metadata,
not coordinate history. Four LOCAL assignments produced four latest inserts and
four updates for 32 publications. Historical legacy GPS rows remain unchanged;
unsafe direct client writes to that legacy API are denied.

Completion, cancellation, reassignment, offline presence and account restriction
triggers remove session/latest/rate state. Bounded cleanup processes up to 100
parents with parent-first locks and SKIP LOCKED, including abandoned state older
than one day. There is no per-fix retained outbox or breadcrumb table. The REST
path avoids the retained-message writes of database `realtime.send`; see official
[Broadcast documentation](https://supabase.com/docs/guides/realtime/broadcast).

## Flutter and Android behavior

One owned Geolocator stream supplies genuine positions. Active delivery requests
2500ms high-accuracy fixes, with a 2300ms client minimum and two-second server
minimum. Idle online riders use a foreground-only once-a-minute stream. There is
no timer requesting GPS, simulated movement, fabricated gap fix or changed SRDS
cadence. During a slow send, only the newest pending genuine fix is retained and
revalidated; stop clears it. Error backoff begins when failure is observed.

The active Android stream uses an ongoing notification, location foreground
service and wake lock. The APK declares fine/coarse location, foreground service,
foreground-service location, wake lock and the existing notification permission.
No ACCESS_BACKGROUND_LOCATION permission was introduced. The service starts from
an explicit foreground action. Actual service registration and nonzero notification
ID were verified; the user confirmed the notification visible on the earlier APK,
whose notification configuration is unchanged in the corrected build.
References: [Android location foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#location),
[installed geolocator 12.0.0](https://pub.dev/packages/geolocator/versions/12.0.0).

FR-21 presence remains active while permitted delivery sharing runs in background.
A prolonged network interruption can make the rider offline and stop sharing.
Recovery therefore requires restoring Online and explicitly sharing again; the
customer map then recovers automatically. Automatic rider recovery is not claimed.

The customer subscribes to one exact owned assignment, validates event identity
and freshness, updates the marker without rebuilding unrelated content, and
removes the pin after more than 30 seconds without a fresh event. It displays
exactly `Rider location temporarily unavailable.` No fake route or ETA remains.
Account changes, logout, terminal events, resume and channel failures dispose or
refresh the appropriate resources. Existing FR-04 masked identity is retained.

Maps use the existing native HTTP cache, an explicit user agent, visible linked
OpenStreetMap attribution and normal browser caching. No bulk/offline download
feature was added. Reference: [OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles/).

## Executed automated verification

Raw logs are retained under ignored `.fr21-local/fr13/`. They are not deliverable
credentials or coordinate history; private runtime diagnostics must not be shared.

- Flutter dependency resolution: **PASS**, existing dependencies unchanged.
- Final full Flutter suite: **223 PASS, two inherited skips**
  (`flutter-full-newest-fix.log`), including sender queue/stop/backoff/freshness,
  channel lifecycle, stale state and recovery cases. The newest-fix regression
  failed before its implementation fix.
- Final changed-file analyzer: **PASS, no issues** (`dart-acceptance-analyze.log`). Earlier full
  analyzer: zero errors, 13 inherited warnings and 66 informational findings.
- SQL: **55 PASS** on LOCAL and hosted rollback/post-deployment checks.
- Deno: **12 PASS**; actual Edge index type-check **PASS**.
- LOCAL actual HTTP/private WebSocket checks: **25 PASS**.
- Hosted TEST HTTP: **26 PASS**; actual private Realtime: **24 PASS**.
- Physical order 2241 unrelated customer: **PASS**, forbidden context, zero latest
  rows and denied actual private WebSocket join (`physical-security.json`).
- Accepted FR regressions: **PASS** — FR-21 47, FR-04 49, FR-25 83, FR-33 39,
  FR-28 74, FR-20 70, FR-30 SQL 65/HTTP 25/Realtime 3, FR-10 24, FR-17 27,
  FR-32 63, checklist 56, FR-26 retry 95. The initial FR-26 concurrency failure
  is preserved; retry assertions were not weakened.
- Final TEST APK build/install: **PASS**, 113 Dart sources byte-match the build
  mirror; actual installed base.apk digest matches the scanned APK. Source/APK
  credential, endpoint and Android manifest scans **PASS**. No new dependency.

Corrected APK SHA256:
`c91d80603f2dc1e648df27fa647332497f92095ff39c2fe8e97203e4649d3341`.
Older APK `f5313d27…` observations are explicitly historical below.

## Physical Android evidence

Authorized device `AESWNRBAEUPNTGJZ`, package
`com.example.flutter_application_1.fr21test`. A separate marked TEST rider used
real GPS; rider coordinates were never seeded. Stocked COD checkout **2241** was
assigned through actual FR-20 matching. Actual phone login/Online, accept,
three-item checklist submission, guarded delivery start and explicit Share all
passed. The authenticated customer Flutter map displayed that assigned rider.
The user confirmed an outdoor walk with Internet retained while USB disconnected.
GPS drift is not treated as a measured walking distance.

- Corrected-build receiver: **660.7 seconds, 212 events, zero duplicates**.
  Device timestamp intervals: mean **3.118s**, median **3.035s**, p95 **3.674s**
  (`physical-observer-corrected-build.json`). Fresh-fix timing and network delivery
  vary; the request interval remains 2500ms. Later stable-Wi-Fi sampling had
  device intervals around 5–6s. No uniform three-second guarantee is made.
- Locked-screen/background on corrected APK: **PASS**. Controlled lock at
  09:40:54Z on 2026-10-19; Android Dozing, TEST app not foreground, location FGS
  running and network validated. Actual customer receiver: **180.2s, 33 events,
  zero duplicates**, final gap 1s (`physical-observer-resume-controlled-lock.json`).
- Untethered stable Wi-Fi lock/unlock: **observed continuation PASS**. The user
  unplugged USB, kept the phone beside the PC on working Wi-Fi, locked for about
  a minute and confirmed unlocking. A fresh private receiver had 23 events by
  127.3s, zero duplicates and latest gap 2.8s while the lock step was pending.
  Reconnection inspection found FGS active, presence age 8s and latest age 16s.
  The receiver later ended with a transport exception; it is not a successful
  completed 600-second receiver test (`physical-observer-untethered-wifi-retry.json`).
- Separate untethered interruption: **INCONCLUSIVE**, 16 events in 120.3s with
  final 59.9s gap; phone later offline, lease old and GPS session absent. Cause
  was not established. Another receiver lost its socket after 26.1s/5 events.
  These failures are retained; neither is relabelled an uninterrupted PASS.
- Explicit Home/background action on earlier APK: **PASS**, Android confirmed
  app not foreground/FGS active and receiver delivered 11 events in 60.2s.
  Current APK also passed the corrected locked/background observation above.
- Network off more than 30s: **PASS** actual customer DOM showed exact stale text,
  no rider pin or live status (`physical-map-stale.json`). Restore: **PASS with
  explicit Online/Share**, customer marker recovered without browser refresh
  (`physical-map-recovery.json`). Customer source is unchanged since those checks.
- GPS disabled: **PASS**, user manually disabled it; exact actionable message,
  FGS stopped and server session/latest absent. GPS was restored. Android rejected
  shell master-setting writes, so no shell success was assumed.
- Permission denial: **PASS**, actual rejected Android permission callback,
  actionable app message, no FGS/session/latest. Original precise while-in-use
  fine/coarse grants were restored and matched the saved baseline.
- Actual private email OTP completion: **PASS**, user entered the code privately.
  At 2026-10-19T10:06:16Z order **2241** was delivered, latest OTP state USED,
  exactly one protected delivery proof and one completion audit, GPS session/
  latest removed and actual foreground location service stopped. No OTP was read.
- Cancellation: **PASS** final synthetic lifecycle check on **2242**. This is
  a zero-capture COD legacy fixture marked `FR13 SYNTHETIC SECURITY TEST ONLY`,
  separate from completed checkout 2241. It tests GPS invalidation and native
  cleanup only, not a new in-transit business cancellation workflow or refund.
  Real phone sharing/latest state existed before cancellation; afterward the
  parent was cancelled, server session/latest absent, no refund created, and
  actual native location FGS stopped (2026-10-19T10:23:51Z).
- Battery diagnostic: **PASS, executed on the corrected APK**, 617.2 seconds,
  **25% before / 29% after**, USB charging at both readings. The accompanying
  private receiver completed **600.7s / 108 genuine events / zero duplicates**
  (`battery-diagnostic.json`, `physical-observer-final-battery.json`). This is a
  charging-confounded basic observation, not a battery-drain benchmark. Earlier
  APK observation was 60%/66% over ten minutes while charging; the corrected
  660.7s sample's 89%/later 100% readings were not synchronized to its end.
- Current APK fatal/unhandled/runtime-disposal error scan: **PASS**.

Phone/PC/server clocks differ. Sample server-clock estimates had half-RTT
uncertainties of 148.5–930ms. Raw two-clock latency must not be presented as
precise one-way delay; no sub-800ms hosted latency PASS is claimed. Earlier APK
raw p95 server-receipt-to-PC latency was 1854.9ms.

## LOCAL load and Free-tier capacity

Four authenticated LOCAL riders, authorized receivers, unauthorized joins,
reconnects and rate checks: **PASS**, 8 iterations, 16 sockets, 32 publications/
32 deliveries, **72/72 checks**, zero unexpected errors, duplicates or drops.
p95 **236.4ms**, maximum **307ms**, average **70.22ms**. This meets the measurable
local sub-800ms target, not hosted latency or large-scale qualification. Two
initial harness timing/drain failures were retained and corrected without changing
server security. LOCAL fixtures were closed and task services/Docker stopped;
no database volumes were reset. RAM reached 269MB free during build/load.
The optional 1,000-rider test was **NOT EXECUTED**.

Verified official Free limits: 200 concurrent connections, 100 messages/s,
100 joins/s, 100 channels/connection and 256KB Broadcast payload
([Realtime limits](https://supabase.com/docs/guides/realtime/limits)); 2M monthly
Realtime messages, with send and each receiver counted
([message accounting](https://supabase.com/docs/guides/platform/manage-your-usage/realtime-messages));
500MB database, 500MB RAM and 500k monthly Edge invocations
([pricing](https://supabase.com/pricing)). Edge memory/CPU/wall-time constraints
also apply ([Edge limits](https://supabase.com/docs/guides/functions/limits)).
All quotas are shared with existing FRs. This is not unlimited production usage.

At 1,000 riders: 2s cadence yields 500 ingress + at least 500 customer deliveries
per second; 3s yields about 333 + 333; 2.5s yields 400 + 400 = 800 counted
messages/s. Rider/customer connections approach 2,000 before administrators.
Durable rider/latest writes are separately capped around 67/s per table, while
volatile timing metadata still changes per accepted update.

A continuously reporting rider at 2.5s uses 1,440 Edge calls and at least 2,880
Realtime messages/hour. Gross monthly quota bounds are about 347 and 694
rider-hours respectively, before existing usage/additional recipients; these are
arithmetic ceilings, not demonstrated usable capacity. Free cannot support
1,000 concurrent riders at the required cadence. A possible later alternative is
adaptive observed-delivery updates plus concurrency admission within remaining
quotas; lowering the required cadence requires user approval and was not done.

## Limits and final integrity

GPS accuracy, fresh-fix availability, OS/manufacturer battery restrictions and
connectivity limit observed delivery. Force-stop, reboot survival, long background
JWT rotation and iOS were **NOT TESTED**. No guarantee is made for those cases.
Final physical integrity **PASS** at 2026-10-19T10:24:25Z: delivered order 2241
preserved, synthetic fixture 2242 cancelled, both GPS sessions/latest rows absent,
location FGS stopped, original precise location grants/GPS setting restored,
TEST rider offline, installed APK unchanged and runtime error scan clean.
No mandatory functional acceptance blocker remains. Scale and iOS qualification
remain separate. No production, paid service, route/ETA or dispatch expansion was
introduced. Only a local acceptance commit is authorized; no push or merge.

## Changed files

- `android/app/src/main/AndroidManifest.xml`
- `lib/controllers/rider_controller.dart`
- `lib/screens/customer/order_history_screen.dart`
- `lib/screens/map_screen.dart`
- `lib/screens/rider_dashboard.dart`
- `lib/services/delivery_location.dart`
- `lib/services/delivery_location_platform.dart`
- `lib/widgets/tez_map_tiles.dart`
- `supabase/config.toml`
- `supabase/functions/fr13-location/handler.ts`
- `supabase/functions/fr13-location/index.ts`
- `supabase/functions/fr13-location/handler_test.ts`
- `supabase/migrations/202610180001_fr13_live_gps.sql`
- `supabase/tests/FR-13.sql`
- `test/delivery_location_test.dart`
- `tests/integration/FR-13-artifact.py`
- `tests/integration/FR-13-browser.py`
- `tests/integration/FR-13-build.ps1`
- `tests/integration/FR-13-db.py`
- `tests/integration/FR-13-hosted.py`
- `tests/integration/FR-13-load.py`
- `tests/integration/FR-13-local-runtime.py`
- `tests/integration/FR-13-local-test.py`
- `tests/integration/FR-13-native.py`
- `tests/integration/FR-13-observe.py`
- `tests/integration/FR-13-physical-security.py`
- `tests/integration/FR-13-run.ps1`
- `tests/load/FR-13.js`
- `docs/analysis_report.md`
- `docs/FR-13-progress.md`
- `docs/FR-13-acceptance.md`
