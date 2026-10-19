# FR-13 iOS progress

## Stage A — inspection complete, 2026-10-19

Branch `feature/FR-13-ios-support` created from clean accepted FR-13
`3408790d7c556665228d4c1cca371c4018a07cea`; earlier accepted FR commits and
checklist are ancestors. No unrelated changes. Production untouched.

Existing shared validation/Broadcast, assignment/checklist gate, GetX lifecycle,
customer map/freshness/reconnect and cleanup are reusable. Geolocator12.0.0,
geolocator_apple2.3.14 already installed. Android source remains separate.
iOS lacks usage descriptions/background mode/Podfile; deployment13.0 is below
existing Firebase5/17 podspec minimum15.0. No team/TESTscheme configured.
Windows has no Xcode/macOS/iPhone build capability; native tests NOT EXECUTED.

Chosen design: foreground-started When In Use Core Location, location background
mode/visible indicator, no Always request, no relaunch/force-quit workaround.
Installed plugin permission handler requests When In Use when that plist key
exists; BYPASS_PERMISSION_LOCATION_ALWAYS=1 removes unused Always branch.
Apple's authorization documentation supports continuing an already active
background-enabled When In Use session. Native behavior still requires iPhone.

User explicitly approved existing foreground-only once-per-minute matching
updates after Go Online, resolving FR-20 fresh-location prerequisite. Delivery
background starts only after checklist/start/server authorization. Reduced
accuracy remains usable only when actual fix meets existing <=100m validation;
otherwise withhold coordinates and provide Settings guidance. No quality bypass.

Next: iOS source/settings, native configuration and automated tests. No backend
schema/function/job changes, no push/merge; local commit after available checks.

## Stage B — implementation and initial tests

Added separate iOS Core Location source and platform selection; Android source
class remains byte-for-byte equivalent to the accepted commit. iOS When In Use
permission, denied/restricted/disabled guidance, precise/reduced metadata and
Settings link reuse the existing single-stream service. Approximate fixes are
never relabelled precise or accepted above100m. Resume rechecks iOS Settings
without prompting or duplicating subscriptions. Background location/indicator
only enabled for delivery; idle matching is foreground-only as approved.
Podfile/xcconfig integration, background capability/plist and iOS15 minimum
prepared against existing SDK dependencies; no package upgrades/AppDelegate hack.

Initial focused tests46PASS before adding three resume cases; final full tests
and analysis running. No native claims. TEST audit35versions/acceptedjobsPASS,
SQL55/checklist56PASS. Initial audit wrapper lacked original accepted baseline;
fixed harness to read that unchanged baseline, retained failed log, retryPASS.
HTTP/Realtime/prior-FR regressions running with separate ignored iOS evidence.
Static checkPASS: native tools absent, Android manifest/source unchanged,
shared backend/customer feed unchanged. No deployments/migrations/production.

## Stage B complete / Stage C in progress

FullFlutter243PASS/2inheritedskips; finalfocused49PASS (20newiOSplatform cases +
29existingFR13cases). Final changed-file analyzer noissues. Full Flutter analyzer
executed with79inheritedfindings:0errors/13warnings/66infos. Fourinitialnewstyle
noticesfixed; original/final logs retained. Format7changedDartfilesPASS.
PythonhelperssyntaxPASS; macOShelper bash -nPASS (initial sandbox MSYSstartup
blocked, same syntax-only checkpassedwithruntimeaccess). NativeRuby/Pods/Xcode
NOTEXECUTED. iOSminimum15/background/WhenInUse/pliststaticPASS.
HostedTESTaudit35versions/unchangedacceptedjobs, SQL55/checklist56,
HTTP26/actualprivateRealtime24PASS. Prior-FRregressionsstillrunning sequentially.
Mac buildscript validates public TESTdefines and refuses nonmacOS/serverkeys;
no credentials/signing material needed or printed. Acceptance report created with
allnative/iPhonechecks explicitlyNOTEXECUTED and reproducible physicaltestplan.
Androidsource/manifest, sharedbackend/customerfeed anddependenciesunchanged.

StageCregressioncheckpoint:FR21(47),FR04(49),FR25(83),FR26(95)PASS.
FR33 encountered TimeoutError after its lockout checks; original failed log
preserved. Other suites continue; do not claim allregressionsPASS. Added guarded
single-suite rerun option for existing unchanged assertions. RetryFR33 only after
sequentialall-suite run finishes, to avoid concurrent fixture mutations.

StageC sequential run finished: FR21(47),FR04(49),FR25(83),FR26(95),FR28(74),
FR20(70),FR30 SQL65/HTTP25/Realtime3,FR10(24),FR17(27),FR32(63)PASS.
FR33initial transport TimeoutError retained in regression-FR33-initial-timeout.log
and regressions-all.json. Its unchanged single-suite retry nowrunning; no
assertions, backend code or timeouts weakened. No concurrent fixture mutations.
Native iPhone/Xcode checks remainNOTEXECUTED; finalcommitawaitsavailablechecks.


## Stages C/D — available verification complete, 2026-10-19

FR33 unchanged retry39PASS; initial transport TimeoutError retained. All other
hosted FR regressions passed (counts in acceptance report). Final TEST audit
35versions/acceptedjobsunchangedPASS. No schema, function or job deployment.
FullFlutter243PASS/2inheritedskips, finalfocused49PASS; changedanalyzernoissues;
fullanalysis79inheritedfindings(0errors/13warnings/66info). Nativeconfigstatic,
Python/PowerShell/bashsyntax andcredential/artifact scansPASS. Androidsource/
manifest/backend/customerfeed/dependency preservation verified against3408790.

Status: FR-13 iOS IMPLEMENTED — PHYSICAL VERIFICATION PENDING.
NativeRuby/Pods/Xcodebuild/signing/iPhonetestsNOTEXECUTED: Windows host, noMac/
Xcode/CocoaPods/Ruby or iPhoneavailable. NoiOSfunctionalacceptanceclaimed.
Nextsetup: Mac with matchingFlutter3.47.6/Xcode, publicTESTdefines, ownedTEST
identity/signing and iPhone running iOS15+; run documented macOShelper thenphysicalplan, one
actionatatime. NoApplecredentialsrequested/exposed. Nativebattery/cadence/
map/OTP/lockedbackgroundverificationmustbeactualdeviceevidence.

Review/stage only20iOSrelatedfiles; authorizedlocalcommit message
feat(FR-13): add iOS rider GPS support. Branchfeature/FR-13-ios-support.
No production/push/merge/force. Acceptance report and static evidence included.
