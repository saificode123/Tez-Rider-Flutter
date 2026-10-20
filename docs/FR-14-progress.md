# FR-14 progress

Updated: 2026-10-20 (Asia/Karachi).

Status: **Implementation and verification in progress; not accepted.** Destination checkpoint approved by the user on 2026-10-19. Earlier inspection/checkpoint notes below are historical; the stage updates at the end describe current state.

## Git safety

- Branch: `feature/FR-14-route-and-eta`, created from `62d60ee` (accepted FR-13 plus iOS support).
- Verified with `git merge-base --is-ancestor`: FR21 `1173736`, FR04 `fd478a4`, FR25 `281c8a8`, FR26 `aabd6ca`, FR33 `ec1c63b`, FR28 `7e809fd`, FR20 `fa29b4c`, FR30 `40ad2ca`, FR10 `76960fa`, FR17 `57914e2`, FR32 `569e8c6`, checklist `7cf80fe`, FR13 `3408790` are all ancestors.
- Existing tracked deletions under `.kilo/worktrees/fluttering-derby/` preserved. No reset, push, merge or final implementation commit.
- No production or hosted TEST access or changes performed.

## Inspection findings (Stage A1)

1. Existing customer `map_screen.dart` uses FR13 `CustomerLocationFeed`, private Realtime and real rider markers; no delivery route/ETA integration.
2. `delivery_latest_locations` persists one trusted latest fix per assignment with RLS; FR13 guards active delivery, checklist, roles, blocked accounts and rider presence.
3. Existing `routing_service.dart` calls public OSRM demo directly; unsuitable as the requested authenticated, quota-managed routing backend.
4. Baseline orders already have nullable numeric `delivery_lat` / `delivery_lng`; FR10 validates and persists new checkout coordinates; FR17 wraps this checkout without replacing delivery data.
5. Checkout has map-tap selection and a My Location button, but also calls `_getCurrentLocation()` automatically in `initState`.
6. Address is read-only. No manual-address mismatch was found; the actual issue is automatic GPS selection without explicit destination confirmation.
7. Tracking-screen My Location only recenters the map; it is not an order destination and must remain separate.
8. Reuse GetX, flutter_map ^6.1.0, latlong2 ^0.9.1, FR13 feed/authorization and shared Edge helpers; assess FR32 atomic quota infrastructure after destination approval.
9. Proposed provider: OpenRouteService, provisional only; current plan redirects to HeiGIT account. Final terms, commercial eligibility and limits have not yet been established.
10. Main risks: unconfirmed destination, cross-order access, provider quota races, stale fixes and OSRM demo dependency. Routing implementation has not started.

## Delivery-coordinate checkpoint requiring approval

Evidence: `enhanced_checkout_screen.dart` initState calls `_getCurrentLocation`; that method sets `_currentLat` / `_currentLng` and reverse-geocodes. `_checkout.place` sends those values without an explicit destination-confirmed flag. Map taps and the My Location button can explicitly select coordinates, but existing persisted orders do not record which path produced the destination.

The missing data is **explicit order destination selection/confirmation provenance**, not absent coordinate columns. Coordinate range validation cannot establish that automatic device GPS is the delivery address intended by the customer. Actual hosted order completeness/provenance has not been audited; no blanket claim that all orders lack coordinates.

Smallest proposed change, pending approval:

- Stop automatically accepting GPS as a destination. Require the existing My Location action or a map-pin selection, with a clear confirmation of the selected destination before checkout.
- Retain existing coordinate columns and FR10/FR17 transactional checkout, stock and idempotency behavior.
- Consider a small nullable server-recorded destination-confirmation/source field for new orders, necessary if routing must distinguish historical unconfirmed destinations. Final migration design requires approval; none created.
- Preserve historical orders; do not backfill confirmation or coordinates. Old/missing/unconfirmed destinations should show ETA unavailable until a separately authorized confirmation workflow exists. That workflow has not been implemented or assumed.

Options: map-pin capture supports delivery somewhere other than the customer's device; explicitly confirmed device GPS supports delivery at the current location. Server geocoding adds ambiguity, privacy and service capacity constraints and still requires customer confirmation; it is not necessary to capture a map pin. No silent geocoding or historical backfill proposed.

Current checkout already uses public Nominatim reverse geocoding. Its official policy requires an application-wide maximum of 1 request/second, identifying User-Agent/Referer, attribution, service switchability and caching where possible; autocomplete/systematic lookup is prohibited, and personal/confidential data must not be submitted. This is not an unlimited production dependency. Do not expand that usage; a selected coordinate remains usable without reverse geocoding.

Policy checked 2026-10-19: https://operations.osmfoundation.org/policies/nominatim/
Provider plan entry checked: https://openrouteservice.org/plans/ (redirects to https://account.heigit.org/info/plans).

## Authoritative sources and verification

- Read repository AGENTS.md, analysis report and acceptance findings for all requested FRs/checklist; reported historic PASS is not a fresh regression run.
- Extracted original SRDS: objective 1.3 (physical pages 4-5), 2.3.3 (7), 2.5.2 (11), FR14 (13), UC05 step 2 (21), tracking UI (26), Maps/Directions interface (29), S02 (31), SEC04/06/10 (32).
- FR14 wording: system shall provide live Rider tracking with route and ETA information. UC05 step 2 requires route and ETA updates. S02 specifies unavailable location after 30 seconds.
- Class-diagram members `GPSLocation.calculateETA`, `RiderAssignment.estimatedTime` and order ETA fields still require visual verification; not extractable by the text search performed. Full Stage A inspection remains incomplete at this checkpoint.
- System Python lacked pypdf; bundled Python successfully extracted relevant SRDS text. No package installation.
- Executed: Git status/branch/history/ancestry checks and source inspection only.
- SQL, Deno, Flutter, hosted, physical Android, previous-FR regressions and load tests: **NOT EXECUTED** for FR14.

## Deployment and remaining stages

- Migration IDs: none. Tables/functions/policies/grants/jobs/secrets changed: none.
- Edge Function: not implemented or deployed. Cache/quota/ETA persistence/fallback: not implemented.
- Provider quotas: no verified implementation limits; no provider calls or key required at this checkpoint.
- Planned secret after provider selection: `ROUTING_API_KEY` in ignored `supabase/functions/.env.test.local`, then server-side TEST secrets only. Never place a key in Flutter or tracked files.
- Stage B/C/D and final acceptance/commit remain pending. Production `arrqsvejrfdbacfwtpcc` untouched; authorized TEST `igeisilhtmglgnqvllrx` untouched.
- Next action: obtain approval for explicit checkout destination confirmation and historical-order compatibility before changing checkout/schema or implementing routing, per the user's A2 checkpoint.

## Stage A update - 2026-10-19

- User approved explicit destination confirmation, minimal server provenance, no inferred historical confirmation, immutable active destinations and isolated TEST deployment.
- New migration `202610190001_fr14_route_eta.sql`: confirmed timestamp/source, immutable destinations and authoritative ETA write guard, existing FR10/FR17 wrapper, RLS route cache, per-order 25-second lease, atomic provider credits/second/minute/concurrency reservations, cleanup cron. No historical provenance backfill or new historical destination-edit workflow.
- Preserved all 35 accepted migration versions. New migration applied once locally. Hosted rollback review passed **48 assertions**; deployment in progress, no production access.
- Local **8 independent concurrent SQL sessions** passed **6 assertions**: exactly one computation lease/reservation, seven BUSY responses, accepted result and subsequent cache reuse.
- Deno handler **29 tests passed**, with mocked provider, input/JWT/ownership gates, errors/redaction, cache, approximate fallback and simulated concurrency. Real SQL concurrency is separately recorded above.
- Provider changed to **Geoapify** after reading current live HeiGIT plan/terms assets: ORS Standard remains 2000/day and 40/min, commercial use permitted, but current terms prohibit transmitting personal data. Do not send live rider/home coordinates there. No ORS calls were made.
- Geoapify current official plan permits free commercial production: 3000 credits/day, 5 requests/second, attribution required. Route input uses lat,lng; response GeoJSON is lng,lat. A two-waypoint request has baseline credit cost plus possible long-distance surcharge. Server defaults: rolling 24-hour budget 2800 credits, rolling second cap 4, rolling minute cap 120, max 4 active requests. These are conservative application caps, not claimed provider minute quotas.
- Reserve 10 credits atomically before a call; accepted routes are limited to 1000km and settled conservatively to ceil(distance/500km)+1 credits. Unknown/error responses burn the remaining daily budget; a crashed unsettled lease blocks further calls after expiry. No refunds/retries for uncertain provider usage. Actual service-side limits and any other usage of the same account also apply. Dedicated account capacity is required; unrelated calls cannot be counted by this application's database.
- Geoapify key configured by user under existing ignored `ROUTING_API_KEY`; only that secret will be uploaded to TEST. No key printed or committed.
- Selected provider official sources checked 2026-10-19: https://www.geoapify.com/pricing/ ; https://apidocs.geoapify.com/docs/routing/ ; https://www.geoapify.com/terms-and-conditions/ ; https://www.geoapify.com/privacy-policy/ . Successful API request data is generally retained by the provider no longer than 24h; requests originate on the server and contain no account/order identifiers.

## Stage B update - 2026-10-19 (verification ongoing)

- Checkout no longer acquires GPS on open. Existing My Location/map selection requires explicit confirmation and passes provenance to trusted checkout. Coordinates remain the confirmed delivery pin; no public reverse-geocoder call is needed or made. Map attribution and existing tile caching reused.
- `delivery_route.dart` validates GeoJSON, uses segment projection and actual polyline lengths for progress, tolerates noise/backward fixes, holds ETA while stationary, marks client adjustments approximate and throttles refresh to 60s with one request in flight.
- `map_screen.dart` reuses exactly one FR13 feed, draws only provider road geometry and displays ETA/fallback/loading/unavailable states; stale fixes hide road/ETA. No direct provider call in Flutter.
- Focused Flutter suite: **23 passed** before final provider-source rename; full suite first run: **265 passed, 2 skipped, 1 failed**. The failure was the accepted FR13 static assertion prohibiting any PolylineLayer before FR14 existed. It was updated to require server-derived route points while retaining no-simulation/no-legacy-GPS checks. Rerun pending.
- `flutter pub get` passed without dependency changes. Full `flutter analyze` executed: **85 pre-existing/new warnings and infos, no compile errors**; changed-source lint cleanup and final rerun pending. Existing checkout unused fields are not removed as unrelated cleanup.
- Android TEST build, hosted deployment, local HTTP load and final regressions remain in progress. No physical tests or iOS verification claimed.

## Stage B completion / Stage C update - 2026-10-20

- Full Flutter suite: **266 passed, 2 skipped**. Final focused route/FR13 suite: **52 passed**. Route/controller/map/model analyzer: **No issues found**. Existing unused checkout fields remain baseline warnings. Changed-file formatting and diff checks passed.
- Deno handler: **32 passed**, plus index type-check passed. Includes bounded request-body reading and disconnected/invalid geometry rejection. Geoapify returns MultiLineString; only the requested single leg is normalized into a LineString, with no fabricated bridge.
- New cleanup review found a lock-order risk if a busy parent were skipped and its cache subsequently deleted. Added **new** migration `202610190002_fr14_bounded_cleanup.sql`, without rewriting/replaying 001. Cleanup now locks at most 500 candidate parents with SKIP LOCKED, then removes only their cache/ETA. Local review **50 passed**; applied once locally and to TEST; deployed TEST SQL **50 passed**. All 35 prior accepted versions retained; total 37 versions.
- Deployed Edge `get-delivery-route` and only `ROUTING_API_KEY` on TEST. Hosted HTTP **12 passed**: actual provider road route, fresh authenticated FR13 publication, customer/rider/admin cache reuse, no additional provider reservations on hits, other customer/rider/vendor/anonymous denial, provenance/ETA persistence and FR28 blocked-customer denial.
- Hosted rollback regressions: FR17 **53**, FR32 **63**, checklist **56**, FR13 **55**, FR14 **48** before cleanup follow-up; final FR14 now **50**. Older raw SQL suites that directly seed transit/delivered states are incompatible with the already accepted checklist gate; their initial failures are not reclassified as passes. Existing checklist-aware HTTP regression harness is being run with only synthetic checkout-input confirmation adaptation. Interrupted-run transport failures are retained and selectively retried with fresh sessions.
- Original SRDS embedded class diagram visually inspected: GPS Location includes calculateETA(); Rider Assignment includes estimatedTime:int. Order diagram lists no estimated-delivery field, and existing migration search found none, supporting the single new order timestamp field.

## Stage D update - 2026-10-20 (in progress)

- Fresh Android arm64 TEST APK built successfully; final build mirror hashes match all four modified/new application sources. Package identity verified as `com.example.flutter_application_1.fr21test`; installed successfully on `AESWNRBAEUPNTGJZ` after the user connected it. No installation to production package.
- Physical customer destination selection/confirmation, real rider walk/deviation, stale/recovery, provider fallback UI and OTP completion still **NOT TESTED**. User actions will be requested one at a time. Dedicated physical rider and existing authorized verified TEST customer inbox prepared; no new rider GPS coordinates seeded.
- Local HTTP load uses Node built-ins (open source equivalent runner) at `tests/load/FR-14.js`, actual LOCAL Supabase Auth/PostgREST/RLS and a mocked provider. No hosted load or real provider load.
- Normal load: **10 VUs, 50 requests, 40 authorized responses, 10 denials, zero unexpected errors, zero unauthorized disclosures, one provider invocation**; 9 initial BUSY/fallback responses, 31 road-cache responses. **p95 4219.55ms: FAIL** against 800ms target.
- Provider-failure/quota fallback load: **2 VUs, 10 requests, 8 approximate responses, 2 denials, zero unexpected errors/disclosures, one mocked provider invocation**. **p95 1318.08ms: FAIL**. Mock-only reservation removed only for that local fixture during teardown; hosted/real quota reservations are never refunded.
- Earlier load setup failures involved incomplete synthetic Auth fields and stale GPS during setup. Fixed fixtures populate normal GoTrue fields and continuously submit fresh synthetic FR13 fixes during the local run. Initial failed diagnostic results are not acceptance passes.
- Host had approximately 700MB free of 8GB RAM during build/load; the run also crossed a workstation interruption. This is a limitation, not proof of target performance. 1000 VUs **NOT EXECUTED**. No scale acceptance.
- Free-tier capacity analysis is in `FR-14-acceptance.md`. Final commit, full regression acceptance and physical acceptance pending; no push/merge.

### Stage D continuation - 2026-10-20

- Accepted regression reruns completed: FR21 47, FR26 96, FR20 70, FR30 SQL 65/HTTP 25, FR17 HTTP 27 passed. Earlier valid runs: FR04 49, FR25 83, FR33 39, FR28 74, FR30 Realtime 3, FR10 24. FR32 SQL 63, checklist 56 and FR13 SQL 55 passed. FR17 captured-payment fixture now seeds capture and expiry atomically, preventing the existing expiration worker from observing a half-prepared synthetic test.
- User replied connected; fresh authorized adb check still reports no device. Requested unlock, data cable and USB-debugging authorization. Physical checks remain pending. No actual customer destination or physical route is claimed.
- Corrected the analysis report from the old destination-approval checkpoint to implemented/pending physical acceptance. FR-14 remains NOT FUNCTIONALLY ACCEPTED; performance results remain FAIL.
- After the user's reconnected/ready replies, adb still lists no devices. Windows present-device inspection also finds no Android/ADB/MTP/portable device; the SDK adb process is running. Requested a different data cable/port and File transfer USB mode. This is an unresolved physical connection blocker, not a failed application test.
- Final review checkpoint: eight Python helpers parse successfully; changed-file diff whitespace check passes; basic embedded private-key/token pattern scan of the 29-file manifest reports zero matching files. This pattern scan is not a comprehensive secret audit. Runtime/provider/cleanup and the FR17 fixture diff reviewed. No additional source modification or deployment this continuation.
- Device connection recovered after cable/port troubleshooting: authorized serial AESWNRBAEUPNTGJZ reports device. Opened installed TEST package, signed into prepared customer through actual UI, searched the dedicated physical product and added exactly one item. Cart contained only that item. Checkout opened with explicit My Location/Choose delivery pin controls; no automatic confirmation claimed. Asked the user to select/confirm the real walk-test destination and leave the order unplaced.
- Added guarded physical-test preparation helpers: actual vendor acceptance only for one recent confirmed checkout containing the dedicated product/customer; assignment only with a fresh real phone idle fix. They never manufacture destination confirmation or rider fixes. Python syntax passed; these new backend preparation actions have not yet executed.
- Physical continuation: user explicitly confirmed destination; native UI showed Confirmed delivery pin. First submission correctly stopped on the existing blank contact-phone validation; entered noncontactable synthetic TEST number, then actual checkout succeeded and emptied the cart. Actual order #2385 accepted by its fixture vendor, assigned through FR20 to exact physical rider after real fresh idle GPS, accepted on phone, checklist submitted and Start Delivery enabled. Started delivery and explicitly enabled FR13 sharing in native UI.
- Database observation: destination provenance `my_location` with server confirmation timestamp, authoritative ETA persisted, fresh accurate physical GPS. The selected point coincides with the initial rider position, so first real Geoapify route is 0m/0.125s and customer browser displays Arriving in 1 min. No nonzero route/walking claim yet. User asked to walk 150–200m away safely with data/GPS/app active; pending.
- Actual physical-order security: second customer denied FR13 context and Edge route, and receives zero latest-location/cache rows (4 checks passed). Destination remains immutable; only synthetic pickup follows the real idle rider position for test assignment. No production mutation.
- User reported walked. On observation, latest GPS was stale and customer UI showed ETA unavailable with no Geoapify road attribution/visible route state. Native app was not foreground; reopening showed a restarted rider dashboard offline. Restored online presence, reopened active delivery and explicitly resumed sharing. Fresh accurate GPS returned and browser showed Approximately 1 min. This verifies stale/fallback recovery, but the walk itself was not captured; no progression/deviation pass.
- Routing infrastructure blocker: aggregate TEST quota review shows 17 reserved credits and one unsettled request from 2026-10-20 09:36:32.769902 UTC (14:36 PKT). The conservative safeguard refuses further provider calls while an expired unsettled reservation remains in the rolling 24h window. No reservation removed or artificially settled; actual provider usage is unknown. Earliest automatic age-out is 2026-10-21 after 14:36:33 PKT, subject to other account/request limits. No scheduled follow-up created. Nonzero physical road-route verification remains pending. Requested return to confirmed destination for arrival/email-code completion testing.
- User returned ready to finish. Native Arrived opened the email verification sheet; request accepted. User entered/submitted the code directly on phone. Backend terminal checks **3 passed**: actual delivered status, no route/ETA/latest GPS/session/lease and completed-order route denied. Browser ETA unavailable. USB disconnected before rider post-completion capture; no success screenshot claimed.
- Stage D remains **INCOMPLETE / NOT FUNCTIONALLY ACCEPTED**. Outstanding: physical map-pin confirmation, nonzero road-route/progression/deviation, controlled network-only loss/recovery and latency qualification. 1000 VUs not executed. Source changes are ready for the requested implementation commit with these gaps recorded; no push/merge. Provider quota records remain intact, including the unresolved reservation.

## Follow-up from 7313a6f - 2026-10-20

- Preserved branch and accepted migrations. New migration `202610200001_fr14_cache_read_path.sql` applied once to isolated TEST only (38 versions); 54 rollback review/deployed SQL assertions passed. Old prepare implementation is retained as a private, non-service-callable locked helper. Authorized fresh cache hits avoid parent-order write locks while retaining per-actor limits, location freshness/accuracy, destination match, eligibility and route proximity checks. Every miss/recompute uses the original lock/lease/quota path. Edge still rechecks current caller/order access before returning geometry.
- Live Auth and FR28 checks overlap without caching their results or starting order work until both complete. Added denial/unavailable/concurrency tests; **35 Deno tests passed**, index check passed. TEST Edge redeployed; no real quota reservation reset or refund.
- Local profile baseline: 10 VUs/50 requests p95 **2993.39ms FAIL**. Dependency p95: Auth 967.01ms, preparation 2160.26ms, account boundary 199.07ms, context 188.39ms; one finish 822.57ms. Rollback-only local SQL preparation measured 68.24ms in one session; concurrent preparations queue behind the parent write lock. Host free RAM approximately 954MiB of 8GiB. These observations identify Auth/resource pressure and serialized preparation costs, not a complete production profile.
- Updated local harness consumes Auth response bodies like deployment, reports per-stage timings, labels sequential/overlap authentication and whether the database cache-read migration is installed. Overlap-only reruns on unchanged LOCAL schema: 10 VUs p95 **4776.03ms FAIL**, 2-VU provider-failure p95 **1686.32ms FAIL**. Both had zero unexpected errors/disclosures and one mock provider call. No latency improvement claimed. Optimized TEST database path has NOT been end-to-end load-qualified locally; local database schema was not changed.
- Automatic approval review rejected LOCAL migration application, interpreting TEST-only scope as excluding LOCAL schema mutation. User answered TEST; continued TEST-only deployment and left LOCAL schema unchanged. New local parent-lock contention assertion was added but NOT EXECUTED without that migration. No bypass attempted.
- Relevant reruns: Flutter route/FR13 **52 passed**; deployed rollback FR17 **53**, FR32 **63**, checklist **56**, FR13 **55**, FR14 **54**; accepted HTTP FR28 **74**, FR33 **39**, FR20 **70**, FR10 **24**, FR17 **27** passed.
- Physical map-pin selection **PASS**: opened Select Delivery Location, user tapped a real destination; observed separate Confirm delivery destination/Deliver to this map pin?/Cancel/Confirm destination dialog. User explicitly confirmed. Actual TEST checkout #2418 persisted `map_pin` and server provenance; fixture vendor accepted, FR20 assigned exact physical rider using a fresh real idle fix, native checklist completed. Previous completed physical order #2385 retained in encrypted fixture history. Controlled network-only test in preparation; nonzero road walk still blocked until legitimate budget is available after the unresolved reservation ages out.
- Controlled network-only test on original APK **FAIL for automatic recovery / PASS for stale handling**: baseline process 22544/default network present at 10:34:43 UTC, network absent and same process/foreground at 10:38:24, network restored with same process at 10:40:18. User left GPS/app/screen active. Customer ETA unavailable after stale GPS; restoration did not resume sharing. Real location rows were eventually cleared by existing presence expiry. No Retry/Share/online switch was used during recovery observation.
- Root cause: presence heartbeat failure set online=false/ready=false, cancelling delivery sharing and its consent. Added opt-in same-epoch heartbeat recovery only while an already-consented active delivery remains current; no new epoch/session takeover, and permanent authorization/epoch failures do not retry. Location publishing stays suspended until server presence, permission and delivery context revalidate; then reuses its existing GPS stream and enables the authorized delivery context. Explicit Stop/offline/logout/account/order changes still cancel consent. A consent-withdrawal-in-flight test exposed a race; a newer offline sequence now supersedes the pending online renewal.
- Recovery fix verification: focused presence/GPS/route **70 passed**; full Flutter **275 passed, 2 skipped**; changed source analyzer passed before final small race guard. Fresh TEST APK build running; physical recovery retest remains NOT TESTED until installed. No provider budget reset.
- Final recovery-source analyzer **No issues found**; accepted FR21 HTTP regression **47 passed**. TEST APK remains in build at this checkpoint; installed physical binary still old, so no fixed-network-recovery result claimed.
- Build completed successfully (`assembleFr21testDebug`, 183.2s); verified TEST package identity, fresh APK newer than full-suite log, and all three modified recovery-source hashes against the build mirror. Installed with existing data preserved. After resuming the interrupted turn, restored explicit sharing on the new binary: process 20050, presence epoch 9, fresh accurate real GPS and customer labeled approximate ETA. Network retest requested; waiting for the user to disable internet. No automatic recovery result claimed yet.
