# FR-13 progress

## Inspection — 2026-10-18
Branch feature/FR-13-rider-gps-streaming from clean7cf80fe; all12accepted
implementations verified as ancestors (FR28=7e809fd,FR20=fa29b4c).
SRDS inspected: FR13/2.3.3 require2–3seconds; UC05/pin; Table5.6rows16/26/27;
S02>30seconds; GPSLocation class visually reviewed on physicalPDF36 (lat/lng,
timestamp,rider/order IDs). User-approved persistence deviation replaces per-fix
GPS inserts. No FR14route/ETA or FR15identity expansion. Existing FR04masked
identity preserved. Authoritative stale wording fromTable5.6row27/user request.

Current customer map simulates movement and writes gps_locations every4seconds;
GPS table is keyed by rider text, not assignment. Rider gets one startup fix;
FR21heartbeat45–55seconds and FR20location freshness2minutes already exist.
FR21currently goes offline on pause; active permitted delivery session must retain
heartbeat while idle-background behavior remains. Existing Geolocator12.0.0 /
Android4.6.2 supports foreground notification settings; no paid SDK required.

Approved design implementation: protected Edge publish endpoint -> authenticated
RPC validation/rate reservation -> private REST Broadcast. Database realtime.send
would insert every message and retain3days, contrary to approved ephemeral goal;
REST avoids that history. No client Broadcast INSERT policy. Latest position per
assignment persisted at15seconds; bounded private unlogged timing state updates
each accepted fix for server rate limiting, not durable coordinate history.
No breadcrumbs. Authorization per accepted update; private channel SELECT only
for canonical owner/rider/verified admin during eligible active assignment.
Channel authorization caches until JWT refresh; ended-session publication stops,
clients dispose and authoritative lifecycle is refreshed after reconnect. Document
the finite in-flight server publication window rather than claim instantaneous
global socket revocation. No production/settings changes or extra secrets planned.

Free tier docs:200connections,100messages/sec,256KBbroadcast,2Mmessages/month;
1000riders at2–3s would exceed limits. Cadence unchanged; no1000userclaim.
Sources: https://supabase.com/docs/guides/realtime/broadcast
https://supabase.com/docs/guides/realtime/authorization
https://supabase.com/docs/guides/realtime/limits
https://pub.dev/packages/geolocator/versions/12.0.0
https://developer.android.com/develop/background-work/services/fgs/service-types#location

No FR13migration applied, no application change/deployment/test pass yet.
Next: actual schema/policy preflight, LOCAL backend/RLS/Realtime tests.

## Stage A — initial LOCAL verification
Migration202610180001draft reviewed with55actual rollback SQL assertions PASS,
then applied once to preserved LOCAL (35versions). Hosted remains34unchanged.
12Deno handler tests PASS; index typecheck PASS. Actual LOCAL HTTP/WebSocket
19checks PASS: rider/customer/admin join, other-customer/other-rider/vendor denied,
public-channel decoy receives no private GPS, protected Edge->REST publication
actually received, direct client publishes cannot reach customer, retry no duplicate,
stop prevents new publications even to cached subscriber and denies rejoin.
First localWebSocket503 was missing Docker DNSaliasrealtime-dev; corrected local
network alias, closed marked failed-run fixture, fresh actual rerun passed.
Existing Docker install/runtime reused; CLIstart reported existing DB and did not
start missing services. Cached official Realtime container added beside preserved
DB/REST/gateway; protected env suppressed and temporary env file removed.
No hosted migrations/functions/jobs/secrets changed. New cleanup job only LOCAL.
Active endpoint test session50418 at127.0.0.1:54328; stop after LOCAL verification.
Next StageB: single device stream/foreground delivery sharing, private customer
listener, stale guard, deterministic Flutter tests. Further hosted lifecycle and
Realtime reconnect/denial evidence remain, not inferred from these initial checks.

## Stage B — implementation and verification
Single owned GetX location service uses real Geolocator stream: idle foreground
60seconds/medium accuracy, active delivery2500ms/high accuracy/visible foreground
notification with wake lock. Reuses installedGeolocator12.0.0/Android4.6.2 and
existing notifications/cache packages. No new dependency/background permission.
Sharing explicitly starts in the existing active-order panel; stop available there.
FR21idle pause/offline unchanged; explicitly shared active delivery retains heartbeat
on pause/lock. Account/assignment/offline changes cancel stream; server validates
each fix. Missing/old/>100m fixes are not published. Retry backoff waits for actual
new fixes; no GPS polling/fake positions. FGS permissions added to mainmanifest.

Customer map removes simulation, legacy GPS writes, unrelated nearest-rider pins
and fabricated route/ETA. Retains FR04masked identity/fare; order-history action
opens exact owned order. Private topic listener, monotonic30seconds stale state,
authoritative reconnect refresh, bounded backoff and one subscription; dispose on
logout/account/order switch. Latest already-stale snapshot never shows as live.
Cached native tiles use existing cache package, explicit app identifier; browser
HTTP cache/Referer retained. Visible linked OSM attribution; no bulk/offline fetch.

22focused deterministic tests PASS;216fullPASS/2inherited skips. Initial fake-async
stream-close test hung; corrected fixture cleanup and asynchronous test callbacks,
fresh bounded rerun passed. Initial new brace notices corrected. Full analyze79
inherited findings (0errors,13warnings,66notices), no new FR13diagnostic. PubgetPASS,
no dependency version change. Account-switch and start-error cleanup hardened.
Cleanup draft reviewed for lock ordering: bounded100parent-firstSKIPLOCKED batch;
55LOCAL rollback assertions passed; only this unreleased function corrected locally,
no migration replay. Hosted rollback final55PASS; hosted still34versions.
Additional actual LOCAL private REST testsPASS: rider/customer/other-customer REST
requests return202 but deliver0forgedevents (acknowledgement is not authorization).
Initial status-only test wrongly expectedHTTP403; corrected to test actual delivery.
22LOCAL Realtime checks nowPASS. Fresh Android build helper syncing manifest;
first attempt rejected stale map mirror due old checklist allowlist; updating only
reviewed FR13source allowlist. No APK success/device/hosted deployment claimed yet.

## Stage C — deployed TEST verification
Only migration202610180001 applied once to TEST;35versions. Protected fr13-location
deployed, no new credentials. Accepted FR10/30/32job settings/hashes unchanged;
new fr13-location-cleanup runs every30minutes. HostedFR13SQL55PASS and checklist
SQL56PASS. First checklist report parser assumed aliasresults; actual JSON aggregate
column name corrected, rerunPASS. HostedHTTP26PASS (read actual summary for count):
ownership/role/anonymous/validation/skew/idempotency/rate/direct-write/RLS checks.
Initial sequential rate assertion failed because network round trips exceeded2s;
real concurrent requests produced PUBLISHED+RATE_LIMIT. No server guard weakened.
Actual hostedRealtime24PASS: all authorized roles receive one trusted event;
wrong roles/anonymous denied, public decoy empty, direct WS/RESTclient forgeries
not delivered, reconnect one event, cancellation/completion stop publication and
deny rejoin. Completion here is explicit privileged synthetic fixture history,
not realOTP/device proof. Previous-FR regressions ongoing separately inFR13output.

LOCAL private-channel self=true/false variants25PASS. Latest k6four-rider run:
8iterations/16WebSocket sessions,32accepted publications/32deliveries,72/72checks,
0unexpected errors,0duplicates,0drops; p95=236.4ms,max307ms.4latest inserts+4updates,
not32coordinate rows. Four marked fixtures closed/tokenfiles removed each run;
remaining LOCAL fixture closed and4local services stopped; endpoint50418stopped.
Initial two failed load attempts retained. First had808msp95/timeout and retry
accounting defects; second had socket-close timer racing its last send. Fixed
harness deadlines, expected rate/replay accounting and3smessage drain; unchanged
server code passed actual rerun. No hosted load;1000usersNOTEXECUTED.

Initial Android build624.4sPASS but later customer first-fix centering/auth cleanup
changes require final rebuild; no stale APK source claim. Memory269MBfree during
build/local load,624MBafterlocalshutdown. BrowserCLI recovered via free npxutility;
itscore/auth guidance read. Built-in CUA initialization failed missing assets; using
isolated named browser sessionfr13-60194cb55fe7 with installedChrome instead.
No personal browser state will be used. Mandatory physical checks not yet executed.
No commit/push/merge; production untouched. Next finalbuild/scan, customerUI and
physicalGPS/stale/background/permission/battery/OTP/cancellation acceptance.

## Stage D — final build and device connection checkpoint
Final Android build PASS (76.4s); installed successfully on authorized Android
AESWNRBAEUPNTGJZ. APK SHA256 f5313d27a5184a7865b75bd29402e33a6f75699c28b665001248cb3f28961fd5;
113 source files match; credential scan PASS; production endpoint absent;
required foreground-location permissions/service present; no background-location
permission. Changed-file analyzer PASS with no issues after final brace correction.
Full Flutter suite remains 219 PASS / 2 inherited skips. FR26 retry 95 PASS / 0 FAIL;
original failed concurrency attempt retained. All prior FR regression suites now
have passing completed runs. Physical real-GPS checks remain pending; no acceptance
or local commit yet. Existing repository web files restored only to temporary
build mirror after initial web-build preflight reported missing configuration.

Actual physical order2241: dedicated GPS rider login/online/fresh idle fix PASS;
stocked checkout/FR20 exact assignment, UI acceptance/checklist/start/Share PASS.
Real customer Flutter web build PASS; isolated browser actual protected login/map
shows live rider. Browser vault synthetic fill discarded by Flutter; trusted
keyboard entry solved verification-tool input without product changes or secret
output. Phone walking and lock/unlock confirmed by user; Android observed Dozing
with Geolocator foreground service active while real receiver continued events.
660.4s actual private WebSocket:201events,0duplicates,mean3.238s/p95gap5.828s,
p95server-receipt-to-observer1854.9ms (two clocks/network); no uniform2–3s guarantee
or sub800ms hosted claim. Battery60->66%,USBcharging,diagnostic only. Actual order
second customer denied context,latest SELECT and actual private WebSocket join.
Acceptance report created honestly with pending criteria and Free capacity math.
User asked to turn off phone WiFi/mobiledata and reply offline; awaiting reply.
No OTP requested yet for2241; no terminal physical result, acceptance or commit.

Network-off user confirmation received. Actual customer DOM after >30s confirms
exact stale text, no live rider marker and no live status; sanitized evidence
physical-map-stale.json saved. User restored network; customer remains stale.
TEST UI currently covered (foreground guard correctly refused unrelated-screen
inspection/taps). Asked user to unlock/open TEST delivery screen and reply ready.
Recovery is not passed; FR21 lease may require explicit online/share restoration.

User reopened TEST. Outage had left rider offline/sharing off as existing FR21
requires. Restored observed Online and explicit Share controls. Actual customer
map recovered automatically without refresh (physical-map-recovery.json).
Asked user Home-button/background-for-minute action; confirmation still pending.
Background-state checks15:16:50Z,15:18:21Z,15:21:24Z show TESTstillforeground and
locationFGSactive: no explicit background PASS claimed. Additional receiver
sample120s/20events/0duplicates was foreground, despite filenamebackground.
Later sample of received genuine device fixes averages~5.5s, cadence unresolved.
Three clock/RTT observations saved; raw one-way latency has clock uncertainty.
Permission/GPSdisabled/notification/completion/cancellation remain pending.

User confirmed explicit Home/background action. OS recorded TESTnotforeground,
locationFGSactive at15:25:29Z. New actual-background receiver60.2s/11events/
0duplicates: explicit background continuation PASS for pre-correction APK. Asked
user to confirm visible ongoing notification; reply pending.
Cadence investigation reproduced a client issue with a slow pending publication:
fresh fixes arriving meanwhile were dropped. Meaningful regression failed before
fix (expected2sends,actual1). Sender now holds exactly one newest genuine fix,
revalidates generation/freshness/throttle/backoff when previous request finishes;
stop clears it. No synthesized coordinates, history backlog, new timer or cadence
change.27focused Flutter testsPASS including stopped/inflight cases; full suite,
analysis, fresh build and actual corrected-APK checks pending. Existing installed
APK f5313d27 remains prior source; do not claim source-match after this code edit.

Visible ongoing notification confirmed by user. Newest-fix hardening includes
expiry rejection and retry delay measured from failure completion (not request
start). Final full Flutter run223PASS/2inheritedskips.29focusedGPS cases included.
Fresh corrected Android build started; not installed yet. No backend change or
migration replay. All physical evidence to this checkpoint belongs to prior APK.

Corrected build46.3sPASS, installed successfully. APK SHA256
c91d80603f2dc1e648df27fa647332497f92095ff39c2fe8e97203e4649d3341;
113sources match, credential/endpoint/permissions scansPASS; sender/test analyzer
noissues. Fullsuite223PASS/2skips. Corrected-APK physical checks now starting.

Installed package hash directly verified=c91d8060. TEST process force-stopped and
restarted to ensure new code. UI helper inherited a fixed filename and could read
stale XML when uiautomator failed; FR13-only helper now uses a fresh UUID path,
requires successful dump, filters TEST package and removes temporary XML. Post-
restart old sharing snapshots are invalid and are not acceptance evidence. No
taps based on those snapshots were performed. A system overlay covered diagnostic
capture; saved frame removed and frame action removed. User asked to close shade
and reopen TEST delivery screen. Real corrected-source GPS checks await that.

Fresh UI capture succeeded after user closed shade. Corrected APK online/active
delivery restored; explicit Share tapped. New660.7s actual receiver completed:
212events,0duplicates,device timestamp intervals mean3.118s/median3.035s/
p95=3.674s. Evidencephysical-observer-corrected-build.json. Actual sender runtime
fatal/unhandled scanPASS. Batterybaseline89%,USBpowered; aftervaluepending.
User noted walking disconnectsUSB. Explained GPSusesInternet,notUSB; asked user
to unplug,keepWiFi/mobiledataon,walksafelyoutdoors~1minandreplywalked. Confirmation
pending; no untethered movement PASS assumed. Customerbrowser remains available
to observe actual updates. Need correctedbuildlock/background,permissions/GPSoff,
OTPcompletion and cancellationlifecycle before finalacceptance/commit.
Prepared guarded zero-capture legacy synthetic cancellation fixture helper, gated
on actual managed checkout's OTPcompletion. It never force-cancels an irreversible
managed FR10 checkout. New cancellation helper NOT EXECUTED yet.

User confirmed untethered walk. Requested corrected-build lock/unlock for~1min.
120.3s private receiver sample16events/0duplicates, but its final59.9s had no event:
untethered locked-screen continuation NOT PASSED. Earlier commentary that updates
were still arriving was based on preceding live observations; final sample reveals
interruption. Need inspect phone network/presence/GPS service after user unlocks
and reconnects USB. No corrected locked-screen PASS or cadence guarantee claimed.

2026-10-19 resume: deviceconnected,c91d8060installedhashPASS,networkvalidated.
Original interruption showed is_online=false,heartbeat~6minold,GPSsession0,no
appcrash; causeoflostheartbeatnotestablished. Restored Online/Share. Controlled
lock09:40:54Z: actualDozing,TESTnotforeground,GPSFGSactive,validatednetwork at
09:42:17Z. Actualreceiver20eventsby109.6s/0duplicates,latestgap2.9s;serveronline,
presenceage35s/latest15s. Powered controlled lock/background continuationPASS;
untethered interruption remains separate/inconclusive.
Androidshell rejectedGPSmastertoggle; settingconfirmedunchangedtrue. User manually
disabledGPS; fresh TEST UI exactdisabledGPSmessage,FGSstopped,session/latest0:
physicaldisabledGPSPASS. User restoredGPS. Baselinefine/coarsepermissionbothtrue
saved; ownTESTAppSettings opened; asked user Permissions/Location/Don'tallow,
replydenied. Permissiondenial/restore,OTPcompletion,cancellationpending.

Controlled lock receiver completed180.2s/33events/0duplicates,finalgap1s.
ResumeauditPASS:35versionsmatchrepo,acceptedjobhashes/schedules/activeunchanged;
no migration replay orproductionoperation. Permissionfine/coarsedeniedconfirmed
afteruseraction. InitialdenialcheckhitOfflineprerequisite (nolocationrequestyet),
soOnlineexplicitlytapped. ActualAndroidpermissioncontrollerpromptnowforeground;
requesteduserDon'tallow/replydeniedagain. No permissionPASSclaimeduntilcallback.

Actualpermissioncallbackdenied:physicaldenialPASS (actionableUI,noservice/session/
latest). Userrestoredwhile-in-use+precise; originalfine/coarsegrantsmatchedPASS.
RestoredOnline/Shareandactualforegroundservice. Baselinebattery23%,USBpowered.
New1200scontinuousprivateobserveruntethered-stable-wifi started. Userconfirmed
USBunplugged,phonebesidePC/sameWiFi; sample26.1s/5events/latestgap0.1s. Requested
lock1minthenunlock/replyunlocked. This timed untethered trial is stillpending.

Observeruntethered-stable-wifi stoppedat26.1s/5events dueactual WebSocket
ConnectionClosedError(no close frame),not an inferredphonefailure. Preserved raw
sample andcompanionfailureJSON. Observer now writesUTC/status andexplicitFAILED
metadataonexceptions; inspectfileagebeforereportingliveupdates. New authorized
untethered-wifi-retry receiverconnectedtosameactivesharing:64.2s/12events/
0duplicates/latestgap0.6s,freshreportage2.2s. PCdefaultnetworkWiFi,notUSBtether.
User'slock/unlockconfirmationstillpending; nofinaluntetheredlockPASSyet.

## Final-stage checkpoint — 2026-10-19
Actual private OTP delivery2241 PASS at10:06:16Z: USED OTP, delivered parent,
one protected proof/one audit, GPS session/latest removed and actual Android
location FGS stopped. User entered code privately; no OTP read or printed.
Permission denial/GPS-disabled tests PASS and original settings restored.
Corrected powered locked/background test PASS180.2s/33events/0duplicates.
Untethered stable-WiFi lock/unlock had observed continuation; receiver later
failed transport after420.8s/60events. Separate initial26.1s socket failure and
prior120.3s interruption retained; no uninterrupted600s claim for these runs.
Actual customer stale text/pin removal and explicit Online/Share recovery PASS;
actual order second-customer context/latest/WS denial PASS. Current223FlutterPASS,
2inheritedskips; final changed-file analyzer PASS/noissues. No app source changed
since installedc91d8060; helper Python syntaxPASS. Rewritten acceptance report
separates final evidence, older-build observations, failures and scale limits.
Syntheticzero-captureCODfixture2242 prepared, phone checklist/start/Share executed.
Ten-minute battery/realreceiver observation started10:12:40Z at25%USBcharging;
finish and cancellation stillpending. No acceptance commit/push/merge yet.

## Stage D complete — 2026-10-19
FR-13 FUNCTIONALLY ACCEPTED — Ready for the next FR.
Final corrected APKc91d8060: timed617.2s battery25%->29%USBcharging; accompanying
receiver600.7s/108genuineevents/0duplicates. Diagnostic only, not batterybenchmark.
Syntheticzero-capturefixture2242 realphoneGPSactivebeforecancellation; aftercancel
serverGPSstateabsent/no refund andnativeFGSstoppedPASS10:23:51Z. Actualdelivered
2241preserved. FinalintegrityPASS10:24:25Z: originalGPS/precisefine/coarsegrants
restored, bothordersGPSstateabsent, ownTESTrideroffline, actualinstalledAPKmatch,
runtimeclean. Finalchanged-fileanalyzer noissues; PythonhelperssyntaxPASS.
FullFlutter223PASS/2inheritedskips; Deno12, SQL55, hostedHTTP26/Realtime24,
all12acceptedFRregressions pluschecklistPASS. FourLOCALriderload72checksPASS,
32/32deliveries,p95236.4ms. Earlierfailedattemptsretained; nohostedlatencyguarantee.
iOSNOTVERIFIED; optional1000ridersNOTEXECUTED/Freequotainsufficient; no cadence
change. Fullcoherentevidence/limits/filelist: docs/FR-13-acceptance.md.
Branchfeature/FR-13-rider-gps-streaming; migration202610180001appliedonce;
fr13-locationonlynewEdge, fr13-location-cleanup30minjob;35versions/acceptedjobs
unchanged. No production/paiddependency/push/merge. Finalallowlist/credentialscan,
stagingreview andauthorizedlocalacceptancecommit follow. No required user action.
