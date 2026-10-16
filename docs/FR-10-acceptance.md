# FR-10 acceptance — 2026-10-16

**FR-10 FUNCTIONALLY ACCEPTED on isolated TEST.** Security and refund-initiation checks passed. Optional 1,000-VU qualification NOT EXECUTED. No push or merge.

Branch `feature/FR-10-order-timeout-autocancel`, base `fed835ffb27d7f163be33e89478a14a4af2943bf`. Only isolated Supabase TEST `igeisilhtmglgnqvllrx` used. No production changes, push or merge.

## Approved policy

The user approved atomic shared-order cancellation: any required vendor timeout cancels the parent and all portions, including accepted siblings. No partial refunds or delivery-fee allocation. Preparing, ready, assigned, delivery and other irreversible fulfillment conflicts require review instead of forced cancellation.

Default private `vendor_acceptance_timeout_seconds` is **180**, constrained to 60–3600. SRDS S-06 says 2–3 minutes, Table 5.6 row 12 says 10 minutes; the task explicitly chooses 180. Immutable per-vendor `acceptance_started_at`/`acceptance_deadline_at` start when atomic checkout becomes eligible; prescriptions start when released to pending. The indexed parent deadline is the next pending portion deadline. Config changes affect newly eligible portions only. Legacy fragmented checkouts are not backfilled with guessed readiness or cancelled retrospectively.

Parent-first locks serialize acceptance/cancellation/transitions; children lock in ID order. Acceptance rechecks owner/approval/block/state/database clock after locking and expires at the exact deadline, independently of cron. Bounded oldest-expired batches use `SKIP LOCKED` and set-based cancellation. Rejected managed portions share the same whole-order transaction.

## Functional acceptance

- **PASS — deployment:** only `202610160001_fr10_order_timeout.sql` applied once; 30 accepted versions retained, 31 total. No replay/reset. Active cron `fr10-order-timeout`, job **4**, every minute; existing FR30 push job remains ID 1. Actual successful run history verified. Autonomous fixture cancelled without manual worker invocation, with one notice, pending refund and event (`autonomous-cron.json`).
- **PASS — SQL:** 67 rollback assertions locally, 67 hosted predeployment, 67 deployed TEST. Exact boundary, immutable snapshots, accepted sibling, fulfillment conflict, financial variants/history, checkout/replay/rollback, role/blocked/ownership and forgery covered.
- **PASS — races:** actual separate sessions exercised acceptance-first over expiry, worker-first then waiting acceptance denied, overlapping workers and deduplication. Hosted concurrent accepts produced one acceptance and one replay.
- **PASS — hosted HTTP:** 24 checks: authenticated atomic checkout/retry/canonical totals, concurrency, deadline enforcement before cron, COD/captured/authorized outcomes, owner history, RLS/forgery.
- **PASS — Flutter:** pub get succeeded, no new dependency. Final suite **150 PASS / 2 inherited conditional skips**, including 15 FR10 tests. Analysis **0 errors / 14 inherited warnings / 87 style notices**; one new braces style notice remains in the customer refresh error handler. No warning-free claim.
- **PASS — integration:** stable checkout retry UUID/payload, canonical server prices, actual location, one atomic parent/children/items/COD-payment transaction. Vendor waits for authoritative results and blocks duplicate submissions. Customer refresh reuses notifications, shows actual cancellation/refund/timeline and visible network errors. Existing timeline remains compatible.
- **PASS — physical Android:** fresh scanned APK installed successfully on `AESWNRBAEUPNTGJZ`, package `com.example.flutter_application_1.fr21test`. Actual customer searched/added the synthetic product, checked out COD for PKR200, and saw confirmation. Parent1577 had a real60-second deadline and autonomously cancelled; phone showed exact reason and server-timestamped timeline. Captured synthetic parent1578 showed pending-refund label on dashboard and existing history. OS received exact timeout notice; inbox retained old broadcasts; mark-all-read changed unread3→0. Vendor accepted parent1579/child1184 before deadline; after parent1580/child1185 expired, actual tap showed “This order has expired and can no longer be accepted.” Cron subsequently cancelled it, and vendor history showed CANCELLED. Default180 restored and independently verified. Final database checks: three cancelled parents/all children, one notice/event each, exactly one full pending refund for1578, none for COD, zero rider assignments; accepted1579 remained accepted. Existing broadcast subsequently reached vendor Android OS with exact title/message. TEST process scan: zero fatal/unhandled exceptions, zero Flutter error lines.

## Security acceptance

- **PASS:** fixed empty privileged search paths; server owner/role/block checks; private config/checkout payload; RLS on new tables. New policies `fr10_refund_read`/`fr10_timeline_read` restrict readers. Ordinary writes cannot forge obligations/events.
- **PASS — grants:** scheduler execute revoked from PUBLIC/anon/authenticated/service_role; cron runs postgres. Direct authenticated INSERT revoked on orders/vendor_orders/order_items. Existing legacy vendor status grants retained with managed-order RPC guard and existing ownership RLS.
- **PASS — preservation:** all eight accepted commits remain ancestors; no accepted policy removal, financial history rewrite, production access, paid dependency, real email or payment-provider action.
- **PASS — artifact/source secret scan:** actual fresh APK TEST package/endpoint/FR10 code confirmed,103 Dart sources byte-matched, protected credentials and production endpoint absent. APK206318163bytes, SHA256 `e7f146d1c117c755cef2b323fec0362d60ec8466e02481b42d867139be1dc4e6`. No client/native FCM configuration or sender modification.

## Refund initiation acceptance

**PASS SQL/hosted/physical display.** Exactly one canonical verified captured payment matching complete amount, owner and method creates one append-only full `order_refund_actions` **PENDING**, including collected delivery fees. Payment history unchanged; no duplicate FR26 obligation. COD creates none. Authorized/uncaptured/pending/failed/voided payment states remain unchanged. Unverified/mismatched/ambiguous capture flags financial review without fabricated refund. Physical prepaid fixture was explicitly synthetic: no real funds collected or refunded.

**Refund initiation records a pending financial obligation. It does not prove money was returned.** Completion requires verified provider confirmation; this feature never records it.

## Notifications and timeline

**PASS SQL/HTTP/physical receipt.** Exact owner notice: **Order cancelled — vendor unavailable.** Unique order/event IDs deduplicate notice and cancellation timeline. Generic/child duplicate notices suppressed for managed cancellation. Existing FR30 durable Android queue/resolver handles timeout UUIDs without native/Edge sender changes. Broadcast, unread and mark-as-read remain. Events use persisted server timestamps. `fr10_private.timeline` is the trusted FR17 integration point; no stock workflow invented. Initial standalone UI assertion raced with live list refresh; the actual expanded COD timeline was re-observed and passed. Expiry response was observed immediately after the actual tap; a delayed separate assertion missed its transient message. These probe timing failures are not represented as passing assertions.

## Accepted feature regressions

Actual TEST reruns: FR21 **47**, FR04 **49**, FR25 **83**, FR26 **95**, FR33 **39** (zero real emails), FR28 **74**, FR20 **70**; FR30 **65 SQL / 25 HTTP / 3 Realtime**. Existing Deno sender check succeeded, **4 tests PASS**. FR21 used the accepted FR30 compatibility runner refreshing synthetic GPS during its long sequence. An earlier old direct FR21 run stopped at 40 PASS/1 FAIL on reassignment with stale synthetic location; no app rules were weakened.

## Performance and free limits

- **PASS — local bulk:** 5,000 synthetic captured orders, bounded500 batches and overlapping workers: exactly5,000 cancellations/refunds/notices/events, zero duplicates. 80.47 seconds including setup; nonempty concurrent batch calls578–30,734ms under memory pressure. Batch throughput is separate from interactive latency.
- **PASS — local HTTP:** k6 2 VUs /15sec /197 checks/requests, zero unexpected errors, acceptance p95 **146.63858ms**, exit0. Samples include initial accept and replay. Minimum available RAM321,523,712bytes.
- **NOT EXECUTED — optional1,000 VUs:** preflight443,621,376bytes below1GiB gate. No1,000-user readiness claim; no large hosted load. Local containers stopped, volumes preserved.
- [Supabase Cron](https://supabase.com/docs/guides/cron): pg_cron, job definitions/history in `cron.job`/`cron.job_run_details`; official guidance <=8 concurrent jobs, <10 minutes. Minute scheduling may cancel after expiry; acceptance expires immediately.
- [Free pricing](https://supabase.com/pricing):500MB database. [Compute connections](https://supabase.com/docs/guides/platform/compute-and-disk): Nano60 direct/200 pooler. Free service is bounded. Indexed bounded batches, pooling, modest concurrency and monitoring mitigate pressure; growing history needs capacity review. No paid infrastructure.

## Evidence and remaining work

Sanitized inspection `docs/evidence/FR-10-preflight.json`; reproducible SQL/Flutter/integration/load runners in changed-file manifest. Ignored actual results `.fr21-local/fr10/`: SQL, concurrency, autonomous cron, HTTP, analysis, Flutter, k6 and build. Credentials remain protected outside Git.

Final sanitized results: `docs/evidence/FR-10-acceptance.json`; changed/new paths: `docs/FR-10-files.txt`. Final scan/review precede the feature-only commit. No mandatory functional blocker remains. Optional1,000-VU qualification and iOS physical tests are not claimed. iOS/APNs remains the separate previously reported platform dependency; no iOS configuration changed in FR10.
