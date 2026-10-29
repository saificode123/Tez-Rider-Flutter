# Release execution ledger

Started 2026-10-28; continued 2026-10-29, Asia/Karachi. Baseline `ffce02b76125c14131939ccb1e67815a8bc588ed`, existing `feature/final-2-functional` branch and origin retained. No production operation, new demonstration account, repeated cleanup, fabricated delivery, identity approval, payment or earning.

The retained 137-row baseline remains 76 historical bounded PASS, 17 approved deviations, 43 PARTIAL and one BLOCKED. No whole requirement is promoted by the narrower results below. The 45-page PDF text was extracted and read; diagram-only pages are not treated as a new visual inspection. Original Word files remain unavailable after the existing request and renewed workspace/attachment search; supplied FR text remains the available priority list.

## FR-13: queued real fixes

**Root cause:** a genuine pending fix was discarded when a request completed before the 2300ms send window reopened. Waiting for another native callback could add another full provider interval.

**Files changed:** `lib/services/delivery_location.dart`, `delivery_location_platform.dart`, `lib/controllers/rider_controller.dart`; focused Android/iOS location tests. Android now requests 2000ms native updates. The existing 2300ms publication limit, freshness/accuracy checks, newest-fix-only queue, retry backoff, account/generation checks and consent remain enforced. A bounded timer flushes an existing real fix; it never requests or generates a position. Stop, account change and interrupted presence cancel pending work. Numeric diagnostics run only in DEBUG isolated TEST builds.

**Evidence:** prior committed service tested from an ignored copy: new queue test FAIL (expected 2 publications, actual 1); Stop variant PASS. Fixed focused location invocation: 60 PASS. Earlier fake-time test attempt hung and was interrupted; it is not the reproduction result. Source analysis: zero errors/warnings, three inherited brace-style infos. New TEST APK built and installed with source/hash checks; installed base.apk independently matched.

**Status:** implementation fix verified; strict physical cadence remains PARTIAL. Native/provider scheduling and customer receipt are distinct measurements.

**Remaining action:** strict timing decision or further measured optimization; full road progression/deviation, battery/device/iOS coverage and complete delivery lifecycle acceptance.

## FR-13: server publication

**Root cause:** each location request repeated a tracking-context RPC plus request-ticket round trip, although the subsequent live-topic lookup already rechecks sender session, consent/topic, lifecycle and recipients immediately before broadcast.

**Files changed:** `supabase/functions/fr13-location/{index,handler,handler_test}.ts`. Publication dependency explicitly requires live authorization. No shared/public broadcast or authorization cache introduced. Timings expose numeric submit/publication stages only.

**Evidence:** 24 GPS/shared-security tests PASS; combined GPS/routing/shared-security invocation 67 PASS. TEST deployment completed; source downloaded read-only and matched all seven deployed endpoint/shared dependency files. Initial deployment review rejected the `--no-verify-jwt` flag. Read-only version evidence established that both existing TEST functions already used `verify_jwt=false`; re-evaluation accepted preserving that existing setting. Application JWT/session/block/budget checks remain. No unresolved approval rejection or production deployment is implied.

**Status:** verified TEST change; no universal cadence guarantee.

## FR-14: redundant authorization network calls

**Root cause:** routing re-fetched Auth and initial order context after the request security wrapper had already verified the same JWT, live session and canonical profile. SQL prepare independently enforces current order/actor eligibility.

**Files changed:** `supabase/functions/get-delivery-route/{index,handler,handler_test}.ts`. Reuse is restricted to this request's verified scope. Missing/mismatched context falls back to live checks. SQL ownership checks, final live JWT/session/order revalidation, provider validation, quota/lease/cache handling and stale labels remain.

**Evidence:** combined 67 focused server tests PASS, TEST deployment, downloaded-source equality. Twelve actual sequential road requests over a reusable HTTPS connection: median 986.93ms, nearest-rank p95/worst 3439.9ms. Initial DNS probe 11.93ms and connect/TLS 362.75ms were separate. Initial provider stage 998.33ms. Warm cache requests ranged 723.16–1393.52ms. JSON decoding 0.18–0.70ms. This is HTTP timing, not Flutter rendering, impaired-network routing or a load percentile qualification.

**Status:** substantial measured improvement; 800ms gate FAIL. No straight-line replacement or silent target change.

## Physical GPS conditions and bounded acceptance

Artifact: `build/delivery/test/app-fr21test-debug.apk`, SHA-256 `F5F18E26D1F863FFFD33DBB33BDBE7EEA6206C0DE7E88EB7DB3AD0DA5A910D04`. DEBUG TEST only; build metadata records baseline HEAD plus current file hashes; it was built before the runtime source commit. Those hashes still match the runtime now committed as ca295e7.

OPPO Android 13; precise location granted. Power saving was initially enabled. Owner explicitly disabled it and later moved to a safe outdoor stationary location. Native Android request inspection showed the requested 2-second interval and location foreground wake lock; no settings were silently overridden. Other apps' diagnostic entries are excluded from deliverable evidence.

- Power-saving window: 5 events; median interval 6.578s, worst 35.375s.
- Indoor, Power saving off: 11 events; median 5.516s, worst 6.781s; native fix median 5529.5ms, publication roundtrip median 1036ms, queue median 1ms.
- Outdoor transition: 21 events; median 2.430s, p95 4.156s, worst 5.797s; native median 2058ms.
- Subsequent outdoor foreground: 18 events; median 3.016s, p95/worst 5.922s; native median 2059.5ms, publication roundtrip median 1161ms.
- Same-process outdoor background: 24 events; median 2.360s, p95 3.594s, worst 4.594s; native median 2059ms, publication roundtrip median 1349ms.

Every listed feed window was approximately 60 seconds and had zero duplicate events. The observer and numeric pipeline windows are separate captures; counts are not directly paired request by request. Native callbacks, device timestamps, queue delays and HTTP roundtrips are measured separately. Uncertain cross-device clock differences and summed GPS path distances are not accepted movement or synchronized latency evidence. Report 24 remains historical for the preceding APK.

After the hour-long pause the rider was Offline. Initial sharing/network attempts correctly stopped at precondition guards before changing connectivity; they are not passes. Online was restored through the visible control, explicit sharing restarted, then the foreground service was confirmed before backgrounding. New 90.802-second offline check observed no default network, restored Wi-Fi/mobile settings, and retained the same TEST process; post-reconnection feed resumed without another Share/Retry: 23 events in 60.5 seconds, median 2.515s, p95 3.969s, worst 4.610s, zero duplicates. Native fix median 1965.5ms, callback median 2004ms, queue median 974ms and publication roundtrip median 1065ms. Server sharing was explicitly stopped during the pause.

## Recovery: actual secrets, bytes and authentication

**Root cause:** schema/data/count restoration alone did not establish runtime recovery. The ordinary CLI data dump also omitted service-owned Auth/Storage migration ledgers. The offline image's older ledgers caused incompatible migration replay against the restored newer schema.

**Files changed:** guarded runtime decryption/Storage/Auth recovery tools and `tool/test-runtime-ledgers.ps1`; existing backup/restore helpers now include explicit encrypted ledger export/restoration. No historical application migration was rewritten.

**Evidence:** owned network=none clone restored the existing encrypted post-seed snapshot. Five recovered Vault values decrypted and correctly masked five backed-up CNIC ciphertexts. All 259 objects / 8,001,146 bytes were uploaded and downloaded through a local Storage API with matching SHA-256, owner, MIME and object IDs. Initial newer Storage migration replay failed; API was pinned to the snapshot's recorded version for that byte-recovery test. Separately captured real TEST service ledgers contain 82 Auth and 74 Storage versions and were encrypted, hash checked and restored only in the offline clone. After ledger restoration, all seven backed-up credentials logged in, fetched their Auth user, refreshed tokens and passed canonical SQL actor/role checks. No external network/mail or hosted modification.

**Status:** bounded runtime recovery PASS. Source evidence: `RELEASE-{runtime-restore,runtime-secrets,storage-runtime,backup-ledgers,runtime-ledgers,auth-runtime}.json`.

**Remaining action:** remote Auth/Edge configuration parity, version-matched complete runtime/RLS/signed-URL recovery, protected portable/cross-machine key handover, full application smoke tests and production deployment/rollback rehearsal. Separate ledger capture is not retroactively an atomic snapshot.

## Delivery and release dependencies

The new end-to-end order/proof/OTP/earnings journey has not been accepted. The two seeded Riders remain pending genuine CNIC verification. Existing unrelated orders are preserved. Real external OTP/notification dispatch, approved production identity/signing, Mac/Xcode/Apple device/APNs access, production inspection/deployment authorization and SLA/capacity decisions remain explicit gates. Safe implementation and verification work continues; this ledger is not a final readiness certificate.

## Legacy Customer registration: actual cart and reviews restored

**Root cause:** the original registration API created new Customers as approved but left confirmed legacy Customers at the generic pending default. The physical Customer could sign in but canonical cart and ratings guards correctly rejected its pending profile. The first earlier Add tap did not persist and is not a passing cart result.

**Implementation:** `202610290001_release_customer_registration_repair.sql` replaces only authenticated registration completion. A confirmed, unblocked, pending Customer with valid name/phone completes automatically; missing fields return PROFILE_REQUIRED through the existing form. Existing role wins over client input. Rejected/suspended Customers and pending Vendors/Riders remain unchanged. Feature permissions, CNIC approval and all four feedback definitions/owners/grants remain unchanged. No bulk backfill or invented server-side contact details.

**Verification:** actual encrypted definition checkpoint, successful offline restore of the original failure, repair reapplication and nine rollback-only Auth/SQL checks. TEST dry-run listed only this migration; apply completed and read-only definition/grant comparison passed. The phone then reached Complete Registration, retained its existing name/email, received the explicitly synthetic non-contactable TEST phone `0000000000`, completed, signed in and showed No reviews yet. One actual Add to Cart action persisted quantity 1 for reviewed product 224; authenticated reads confirmed stock stayed 30 and ratings returned OK. No checkout, new order, payment, earning or Vendor/Rider approval. Local checks additionally asserted one audit, idempotent completion and no queued external messages. The unused feedback-permission prototype was never applied to TEST and is excluded from delivery.

Evidence: `RELEASE-registration-{local,rollback,deployed}.json`, `RELEASE-customer-runtime.json`.

## Current regression and evidence binding

Fresh full Flutter invocation: **691 PASS, 0 FAIL, 2 SKIP**. Fresh full Deno invocation: **230 PASS, 0 FAIL**. Initial Deno commands omitted required invoice-font read/sample-PDF write permissions and produced 227 passes/three permission failures each; the successful invocation grants only the bundled font path and two ignored sample directories, with no network permission. Focused GPS/route/shared server invocation: 67 PASS. Seven PowerShell helpers parsed; current Python helpers compiled. Focused source analysis remains zero errors/warnings and three inherited brace-style infos.

All 217 APK source hashes still match. Read-only downloaded final TEST bundles match all seven endpoint/shared files, including the final 2048-byte streaming parser with malformed UTF-8/JSON rejection and oversized-stream cancellation. Physical GPS captures preceded that parser-only patch; no fresh physical parser-build claim. `RELEASE-performance.json` excludes raw coordinates, jitter path distance and unqualified cross-device latency. `RELEASE-verification.json` binds passing raw-log hashes. The secret scan found only the existing public Firebase client configuration and intentional fake-key test fixture; no private candidate is accepted for Git.

Three labelled owned offline recovery containers/ephemeral volumes were removed after their checks. Four canonical local services retained the same identity/running state; encrypted backups were retained. Full cross-service Auth/Storage RLS and signed-media recovery are still open; the bounded independent Auth/Storage checks do not establish them.

The phone is left on the Customer product detail with one saved TEST cart item. GPS sharing is stopped and the old physical Rider is Offline. Wi-Fi/mobile settings were restored by the earlier recovery test. No repeated connection interruption was run against the Customer screen after the latest Ready reply.

## Git delivery

Logical implementation commits on the preserved `feature/final-2-functional` branch: `ca295e7` GPS/routing, `cc566c5` Customer registration, `1d1c152` offline recovery. Their evidence and current dependencies are delivered in the subsequent evidence commit. The APK's embedded baseline HEAD remains historical; its 217 source hashes match the committed runtime. No force push, main merge or production operation is authorized by these commits.
