# FR-10 progress — 2026-10-16

## Stage A inspection checkpoint

Branch `feature/FR-10-order-timeout-autocancel`, base
`fed835ffb27d7f163be33e89478a14a4af2943bf`. Starting tree clean.
All eight accepted commits are ancestors:1173736/fd478a4/281c8a8/aabd6ca/
ec1c63b/7e809fd/fa29b4c/40ad2ca. Branch created from the verified FR30 tip;
no assumption that those feature branches were merged into main. Existing iOS
inspection was already committed in the starting tip and is preserved.

### Inspection report (10 lines)

1. Checkout creates one pending parent with per-vendor child orders, not one parent/payment per vendor.
2. Current checkout is COD-only and creates no `payment`/`payments` record; inherited card screen simulates success and is not connected to this checkout.
3. Master amount combines items and delivery fees; children store item subtotals without financial allocation of those fees.
4. Vendor controller directly updates child status; no acceptance deadline or duplicate-tap guard exists.
5. Existing guard enforces approved vendor transitions but no expiry; child changes overwrite shared parent status.
6. TEST has no timeout function, deadline column, FR10 job or persisted timeline table; UI timeline is step-based.
7. Reuse owner notifications/unread state, canonical FR28 actor/session checks and existing parent-before-child assignment locks.
8. FR26 refund actions require a delivered dispute and verified full-order payment; their semantics cannot represent partial timeout refunds directly.
9. `payment` and `payments` coexist; canonical FR26 settlement requires one matching PAID/COMPLETED/SUCCEEDED payment, paid timestamp/reference and exact amount.
10. Blocking decision: a pending vendor can coexist with accepted/assigned siblings; cancellation scope and shared-payment/delivery-fee allocation are unspecified.

### Authoritative sources and provisional contract

Read AGENTS, analysis and relevant accepted FR21/04/25/26/33/28/20/30 evidence.
SRDS physical PDF pages8/13/21/31/42–44 reviewed, including visual state diagram
5.5. FR08 requires order/item/payment records; FR09 accept/reject; FR10 timeout
and refunds; FR11 complete timeline; SEC01 role/owner RLS. Section2.3.4 specifies
configurable timeout. UC06 specifies validated payment/refund records, without
multi-vendor allocation. State diagram places vendor waiting after successful
payment; it does not define partial cancellation.

S06 page31 gives 2–3 minutes; Table5.6 row12 page43 gives10 minutes; row13 page44
requires auto-cancellation/refund and `Order cancelled — vendor unavailable.`
No binding approved timeout exists in the inspected code/TEST configuration.
Provisional default **180 seconds**, as explicitly requested, has **not** been
deployed. Proposed trusted key `vendor_acceptance_timeout_seconds`, bounded
60–3600 seconds, with immutable per-eligible-vendor acceptance start/deadline.
At/after the deadline acceptance must return ORDER_EXPIRED independently of cron.
Prescription-waiting children are not yet awaiting acceptance. Current checkout
inserts the parent before children/items; parent `created_at` is not proof that
an individual vendor order is complete or eligible. A reliable server-side
checkout/finalization boundary is required before starting its deadline.

Configuration changes should affect future eligible orders only. Existing-order
backfill must not silently cancel historical orders or incomplete checkouts;
final backfill and parent/child deadline representation remain pending the
shared-order rule. No migration or backfill has been authored/applied.

### Actual checks and environment

- Read-only TEST inspection succeeded:30 source migrations exactly match hosted
  history, all seven relevant tables have RLS, pg_cron1.6.4 and pg_net0.20.4 exist.
- Only scheduled job found:existing FR30 Android push, id1, every minute, active.
  It was not changed. No FR10 job or migrations registered.
- Relevant server function definitions confirm direct vendor-transition guard
  lacks deadline enforcement and the status sync overwrites parent status.
- `001_tez_rider_gaps.sql` was not found among project tracked/normal source files;
  no timeout function exists among current applied migrations or in TEST.
- Local Docker engine29.8.2 responds. Local SQL stack/fixtures/load capacity not
  yet assessed; no load run or capacity claim. Existing CLI executable was missing;
  restored only from its existing local archive, no download/reinstallation.
- Source/evidence files are listed by `git status`; raw schema inspection is in
  ignored `.fr21-local/fr10/preflight.json`, sanitized summary in
  `docs/evidence/FR-10-preflight.json`. No credentials or personal records emitted.

### Financial decision required before implementation/deployment

Asked the user whether a single timed-out vendor cancels the entire shared
order (including accepted siblings) with full verified captured-payment refund,
or only that vendor portion, and how delivery fees are allocated for partial
refunds. Neither SRDS nor existing code resolves this. Entire-parent cancellation
also needs to reconcile the explicit requirement to preserve accepted/assigned
orders. The request's A7 says to stop and ask before changing payment records
when allocation requires an unresolved financial decision. No financial or
schema changes were made while this answer is pending.

Next: record the approved rule, finalize trusted checkout eligibility and
parent/child cancellation contract, implement migration/SQL races, then continue
Stages B/C/D. SQL behavior/security/concurrency tests, Flutter checks, hosted
mutations/regressions, physical Android and performance tests **NOT EXECUTED**.
Only the read-only inspection ran. No commit/push/merge or production access.

### Free-tier references checked 2026-10-16

[Supabase Cron](https://supabase.com/docs/guides/cron) uses pg_cron, records jobs
and runs in `cron.job`/`cron.job_run_details`, and recommends at most8 concurrent
jobs with each under10 minutes. Proposed FR10 schedule once/minute, batch500,
partial expiry index and parent-before-child deterministic locks remain design
choices, not implemented/tested behavior. Monitor history growth and query plans.
[Free database quota](https://supabase.com/docs/guides/platform/database-size)
is500MB; [Nano connection defaults](https://supabase.com/docs/guides/troubleshooting/how-to-change-max-database-connections-_BQ8P5)
are60 direct/200 pooled. Bounded jobs and pooled interactive calls help within
these limits; no 1,000-user capacity qualification is claimed.


## Approved policy and implementation checkpoint — 2026-10-16

The user's allocation answer supersedes the earlier financial blocker. One
shared order is atomic: any required vendor timeout cancels every portion,
including accepted siblings; no partial allocation/refunds. COD creates no
monetary refund; verified captured full-order payment becomes one immutable
PENDING obligation including fare. Authorized/unpaid records remain unchanged.
Preparing/ready/in-transit/delivered portions, a rider reservation, or an assigned
parent produce fulfillment_conflict review instead of automatic cancellation.
No actual money movement or completed refund is implemented.

Draft migration202610160001 adds private bounded180-second configuration,
immutable per-vendor deadlines, indexed parent next-expiry, atomic trusted COD
checkout, server vendor transitions, shared cancellation and pending-refund/event
storage. Deadline starts only after atomic checkout finalization; prescription
waiting starts its own deadline when released to pending. Parent next-expiry is
derived from pending children and is not the immutable snapshot. Configuration
changes affect new eligibility only. Legacy fragmented checkouts are preserved
without guessed historical readiness/backfilled deadlines; new client checkout
uses the trusted atomic RPC. This deliberate legacy behavior must be explicit
in acceptance; no historical order is silently expired.

Worker locks parent rows oldest-deadline-first with SKIP LOCKED, then all child
rows in parent/id order. Batched payment locks, refund insert, parent/child
cancellation and exactly-one owner notification share the transaction. The
existing durable FR30 queue resolves either broadcast UUID or timeout notice
UUID through the same scoped device capability; no new push provider/service.
No stock work. FR17 extension boundary is the persisted vendor_timeout event.

Local accepted FR30 migration006 was previously absent and applied once to the
existing local stack; all30 accepted migrations now present locally. New FR10
migration applied locally only, then evolving draft functions revised in place.
No accepted migration replay, hosted schema change or production access. Local
rollback assertions passed for boundaries, checkout/payment atomicity,
configuration, owner role/permissions, approved shared-order policy, full pending
refund, uncaptured/COD exclusion, irreversible conflicts and injected rollback.
Separate-session races, full suites and hosted review remain underway.

Flutter integration now uses server vendor transitions, per-order busy state,
authoritative status refresh on uncertainty and atomic checkout with stable retry
UUID. Existing order cards/history expose trusted cancellation/refund/timeline;
existing notification refresh drives customer order refresh. No Flutter timeout
cancellation timer. Existing checkout-only simulated tracking loop became dead
when the old fragmented finalizer was replaced and was removed; no GPS/ETA
implementation was added. Dependency resolution succeeded with no new package.
Current branch feature/FR-10-order-timeout-autocancel, basefed835f; no commit.


## Stages A/B checkpoint — 2026-10-16

Final draft passed67 rollback SQL assertions locally and67 in the hosted TEST
review transaction. Separate local sessions proved pre-deadline acceptance wins,
timeout-first acceptance denial and duplicate worker idempotency. Local5000
captured synthetic orders drained across bounded overlapping batches with exactly
5000 cancellations, notices, pending refunds and cancellation events (zero
duplicates); total80.47seconds including fixture creation. Individual500-order
worker calls ranged578–30734ms for nonempty overlap calls; this is scheduler
throughput, not interactive latency. No hosted load. JSON:local-races-bulk.json.

Flutter pub get succeeded,15 new tests passed; full suite150 passed/2 inherited
conditional skips. First analysis found0errors; inherited findings plus one new
unused COD field and a braces info were identified and corrected; final analysis
still pending. Schema review moved checkout payload into private storage to
preserve multi-vendor privacy. Existing vendor status grants remain for legacy
orders; managed-order BEFORE guard rejects direct updates and requires the RPC.
No Android Firebase client/service changes.

Hosted final migration dry-run/deployment initiated after these checks. Only
202610160001 is eligible; source/history guard prevents replay. Physical Android
currently undetected; a single reconnect request is pending while build and TEST
verification continue. No mandatory acceptance claim or feature commit yet.


## Stage C deployment/verification checkpoint — 2026-10-16

Applied only202610160001_fr10_order_timeout.sql to TEST, via guarded dry-run;
31 migration versions now match source. No production connection or accepted
migration replay. Deployed SQL67 PASS, hosted HTTP24 PASS (atomic checkout,
concurrent accepts, deadline denial, canonical full refund/COD/uncaptured,
notification/timeline and RLS). Actual cron job is active once/minute with
successful run history and default180 verified. Autonomous expired captured
fixture seeded without manually invoking the worker; result verification pending.

Regression results so far:FR04=49,FR25=83,FR26=95,FR33=39 (zero real emails).
Old direct FR21 run stopped40 PASS/1FAIL at released-rider reassignment; using
previously accepted FR30 regression21 wrapper which refreshes synthetic GPS
before presence changes. Its final result and FR28/FR20/FR30/Deno still pending.

Local HTTP k6 two VUs:197 checks/requests, zero unexpected errors,
acceptance p95=146.63858ms, minimum available RAM321523712bytes, exit0. Full1000
preflight NOT EXECUTED with443621376bytes available. Local5000-order dedup/batch
result remains separate. Local stack stopped cleanly with volumes preserved to
free memory for APK building. No hosted load.

First APK invocation used main checkout accidentally and was stopped; corrected
build runs in the prepared mirror with1GiB Gradle heap, preserving repository
Android configuration. Accepted Gradle/Kotlin deprecation warnings inherited;
no version upgrade or skip-validation workaround. Fresh APK result pending.
USB request remains pending; device absent on actual ADB check. No physical
acceptance or feature commit claimed. No push/merge.

## Stage D fresh artifact checkpoint — 2026-10-16

Device now positively detected (AESWNRBAEUPNTGJZ/CPH2285); TEST sign-in UI
observed. Android operations require sandbox escalation; a restricted-daemon
failure is not evidence that the phone is disconnected.

All hosted regressions finished: FR21=47 using accepted FR30 GPS-refresh runner,
FR04=49, FR25=83, FR26=95, FR33=39/no emails, FR28=74, FR20=70,
FR30 SQL65/HTTP25/Realtime3. Deno sender check and4 tests passed. Autonomous
cron independently cancelled its released fixture with one notice/refund/event.
Actual job4 runs each minute, config180, no ordinary/service worker execute.

Final Flutter suite150 PASS/2 conditional skips. Analysis0 errors/14 inherited
warnings/87 style notices (one new braces notice in refresh error handler).

Fresh mirror APK built successfully in380.7sec after restoring the actual empty
declared assets/videos directory. Native Android/Firebase configuration retained.
Artifact scan PASS:103 byte-matched Dart sources, exact TEST package/endpoint,
FR10 code present, protected credentials and production endpoint absent.
SHA256 e7f146d1c117c755cef2b323fec0362d60ec8466e02481b42d867139be1dc4e6,
206318163bytes. Install initiated; physical checks still pending.

Branch remains feature/FR-10-order-timeout-autocancel at base fed835f.
Only migration202610160001 deployed once. No feature commit/push/merge.

## Stage D complete — 2026-10-16

FR-10 FUNCTIONALLY ACCEPTED on TEST. Fresh APK scanned and installed (Success).
Physical customer UI search/add/cart/COD checkout confirmed parent1577 with
60-second snapshot; autonomous cron cancelled it. Phone showed exact reason and
persisted server timeline. Explicit synthetic captured parent1578 displayed full
pending-refund label in dashboard and existing history. COD had no refund.
Timeout received in actual Android OS; inbox retained prior broadcasts. Actual
Mark-all-read changed unread3→0. Vendor before-deadline acceptance persisted
(parent1579/child1184). After parent1580/child1185 deadline06:26:52.754478UTC,
physical Accept Order displayed “This order has expired and can no longer be
accepted.” Later cron cancelled it and vendor history showed CANCELLED.

Final integrity: three cancelled parents/all portions, one notice/event each,
one PENDING full200 refund only for synthetic capture, no rider assignments,
accepted1579 still accepted. Default180 restored then independently verified;
one active cron4 and successful runs retained. Existing FR30 broadcast reached
vendor Android OS with exact title/message. TEST log scan0 fatal/unhandled,
0 Flutter error lines. No native Android/FCM/Edge configuration changed.

Probe timing notes: an initial timeline assertion raced with a live refresh;
re-observed expanded timeline assertion passed. Actual expiry message appeared
immediately after the tap; delayed standalone assertion missed its transient
refreshed card. Failed standalone assertions are not counted as passing tests.
An old broadcast admin had no accepted send; dedicated synthetic native-admin
sent successfully without modifying existing rate limits.

Final report docs/FR-10-acceptance.md, sanitized evidence
docs/evidence/FR-10-acceptance.json and exact paths docs/FR-10-files.txt.
All mandatory SQL/Flutter/hosted/regression/physical checks complete.
Local5000 and2VU p95146.63858ms passed; optional1000VUs NOT EXECUTED due RAM.
Refund initiation records a pending obligation, not returned money.

Feature-only commit is next after final source/secret/whitespace review.
Current branch feature/FR-10-order-timeout-autocancel, precommit HEAD fed835f.
No production access, accepted migration replay, paid service, push or merge.
