# FR-17 acceptance — 2026-10-16

**FR-17 FUNCTIONALLY ACCEPTED — Ready for the next FR.**
Functional/security acceptance PASS on isolated TEST and the authorized Android
device. HTTP performance/1,000-buyer scale qualification NOT EXECUTED; no scale
capacity claim. No production deployment, push or merge.

Branch `feature/FR-17-stock-tracking`, base `76960fadf207f17156a2124b547f6cbe47d04b1f`.
Only isolated Supabase TEST `igeisilhtmglgnqvllrx` used. Production untouched.
No push, merge, paid infrastructure, new payment gateway or dependency upgrades.

## Requirements and backfill

SRDS FR-16/17 (PDF p14), UC-03 (p20), vendor dashboard (p26), SEC-01
(p31), and Table 5.6 inventory cases (pp43–44) inspected; class diagram
Product `stock:int`/`updateStock()` visually inspected on p36.
The explicit task resolves Table 5.6's reservation wording: cart additions
validate current stock but make no persistent reservation. Atomic checkout
alone decrements stock; a stale cart can receive a structured shortage.

Migration `202610160002_fr17_inventory.sql` applied ONCE after rollback review.
All 31 accepted versions retained; 32 total. Deployed SQL is frozen.
Products gain nonnegative integer `stock_qty`, threshold default5,
`stock_confirmed` defaultfalse and nonnegative bigint `stock_version`.
Three existing TEST products had no authoritative quantity: availability flags
were preserved and no quantity invented. Their zero/unconfirmed state means
UNKNOWN, displayed as stock confirmation required. Confirmed zero is out of
stock. Purchase requires confirmed positive stock AND existing availability.
Only explicitly synthetic fixtures received test quantities.

Production implications: this migration has NOT been run in production.
Existing real listings would require a coordinated vendor physical-count
confirmation before purchasing; do not silently label unknown inventory zero
or make listings purchasable using invented counts. Preserve legacy order and
payment records. Legacy orders with no recorded decrement never restore stock.

## Atomicity, ledger and cancellation

Authenticated `fr10_checkout` normalizes duplicate product IDs, locks products
in ascending ID order, checks real stock/vendor approval/block state, and
creates the accepted FR10 checkout and decrements/ledger in one transaction.
An insufficient item returns requested/available details with no partial order
or stock write. UUID retry returns the original order without another movement;
pre-FR17 payload replay is retained without inventing historical movements.

Existing-parent operations lock parents, sorted children, sorted union of
products, then payments. Checkout locks its actor/products and creates NEW
uncommitted parents, never acquiring an existing parent behind a product lock.
Vendor count locks actor `FOR NO KEY UPDATE`, then product. Absolute count
requires the observed version; a concurrent checkout causes STOCK_CHANGED
instead of overwriting a sale. Client retries retain UUID and immutable payload
after uncertain outcomes; changed payload cannot silently reuse that request.

Append-only `inventory_movements` records signed delta, before/after, product
and vendor snapshots, order/item, reason, actor, request/payload and timestamp.
Unique item/type prevents duplicate sale/restoration; vendor/request UUID
prevents repeated adjustments. Arithmetic and movement-type constraints apply.
Product snapshots survive deletion of unsold listings; recorded items cannot
be rewritten or deleted. No cascade erases inventory history.

Parent cancellation restores only its own recorded, unrestored decrements in
the same transaction. FR10 whole-shared-order policy is preserved: a timeout or
rejection cancels every vendor portion, including accepted siblings, restores
every consumed product, and emits one customer notice. Captured full payment
including fees produces one PENDING refund; never a completed refund without
provider confirmation. COD creates no monetary refund. Irreversible fulfillment
conflicts remain flagged for review. Repeated/concurrent cancellation restores once.

No payment gateway was introduced. A durable server-recorded single matching
FAILED non-COD payment with no capture timestamp can be compensated by the
existing minute worker after commit. The worker prelocks one bounded union of
expired and payment-failed parents before any products. No payment trigger
reverses parent/product locking. Precommit exceptions roll back all movements.

## Alerts and Flutter

One owner notice on confirmed stock crossing `old > threshold && new <= threshold`:
`Low stock alert: [name].` Restocking above threshold rearms; purchases remaining
below do not spam. Threshold changes alone, or combined with that adjustment,
do not emit immediately; subsequent quantity changes use the new threshold.
Product/version uniqueness and the accepted FR30 event UUID pipeline deduplicate.
No new cron, native Android/Firebase configuration, push sender or realtime
product subscription. Existing inbox/unread/read behavior retained.

Vendor create/edit saves metadata and confirmed stock atomically via RPC;
quick count requires a reason and snapshot version. Unknown stock requires an
explicit count. Loading/error/retry states retain form values and image.
Customer catalog/detail/cart show actual stock; all six add entrypoints await
server validation and show success only on success. Stock zero disables buying
with `This product is currently out of stock.` Catalog/vendor queries paginate.
Cart refresh preserves choices; checkout shortages show requested/available and
offer explicit adjustment of affected items while preserving valid items.
No mock catalog, fabricated fallback or optimistic backend success.

## Security change inventory

- RLS: new `fr17_ledger_read` permits allowed owning vendor/admin reads only;
  restrictive `fr17_product_update_owner` and `fr17_product_delete_owner`
  enforce role/ownership/block checks. Existing SELECT and FR28 guards retained.
- Grants: revoke ordinary product INSERT/UPDATE; authenticated can update only
  `is_available` directly. Metadata/count changes use approved-owner RPCs.
  Ledger ordinary writes denied; authenticated scoped SELECT; service SELECT/
  INSERT and sequence usage/select only. No ordinary ledger UPDATE/DELETE.
- All `fr17_private` function EXECUTE revoked from PUBLIC/anon/auth/service.
  PUBLIC/anon cannot execute the three public checkout/stock/save RPCs;
  authenticated EXECUTE granted, with server checks. Existing worker grants
  retained; ordinary clients/service cannot invoke privileged cancellation.
- New SECURITY DEFINER functions, all fixed empty search_path:
  `fr17_private.low_stock`, `adjust`, `lock_inventory`, `restore_cancelled`,
  `protect_item`, `payment_failed`; public `vendor_adjust_stock`,
  `fr17_save_product`, replacement `fr10_checkout` and `cancel_timed_out_orders`.
  Existing `fr10_checkout` moved to private `checkout_base`; existing
  `fr10_private.cancel_batch` gains sorted product-union prelocking.
- Triggers: `fr17_low_stock`, `fr17_restore_cancelled`, `fr17_protect_item`,
  `fr17_ledger_immutable` (reuses accepted `fr26_append_only`).
- Indexes: item/type and vendor/request uniqueness; product/order ledger
  lookups; vendor inventory pagination; low notice uniqueness; bounded open
  inventory-order worker index. Existing indexes retained.

## Executed automated evidence

- PASS: LOCAL53 rollback SQL; hosted predeployment rollback53; deployed TEST53.
- PASS: 15 independent-session local concurrency checks. Two last-unit buyers:
  one sale, one shortage. 200 valid attempts across ten sessions with opening100:
  exactly100 purchases, stock0, no oversell, one crossing notice. Opposite
  multi-product lock order, stale vendor adjustment behind checkout, concurrent
  cancellation, checkout/cancellation and full ledger reconciliation passed.
- PASS: hosted real HTTP27, including simultaneous last-unit buyers, no partial
  shortage, shared accepted-sibling timeout restoration/full600 PENDING refund,
  rejection, rearm and role/ownership/block/direct-write denials.
- PASS: independent deployed history/RLS/grant/index/negative-stock verification.
  Same two active minute jobs: FR30 ID1, FR10 ID4. Default timeout180 retained.
- PASS: Flutter initial focused38/full173; after the physical dialog fix,
  focused41 and full176 with2 inherited conditional skips. Final analysis
  zero errors,13 inherited warnings,66 notices (including2 new brace-style
  notices). Analysis exits1 with these findings; it is not a clean lint pass.
  Pub get completed; versions
  unchanged. First full-suite compiler failed on missing temporary output.dill;
  counted as failed attempt, then clean serial rerun passed.
- PASS: accepted regressions FR21=47, FR04=49, FR25=83, FR26=96, FR33=39,
  FR28=74, FR20=70, FR30 SQL65/HTTP25/realtime3, FR10 SQL67/HTTP24.
  All assertions retained. FR10 fixture-only integration now confirms synthetic
  product stock via the owning vendor RPC. No real email or money movement.

The first post-fix full run stalled during loading at19; only its owned process
tree was stopped. A fresh workspace-local TEMP retry passed176. Neither stalled
attempt nor the earlier temporary-output compiler failure is counted as a pass.
Raw credentials/private fixtures/build outputs remain ignored. Portable,
sanitized evidence: `evidence/FR-17-acceptance.json`.

## Performance and free-tier limits

Full1,000-VU k6 NOT EXECUTED: memory preflight469,442,560 bytes (<1GiB).
Smaller k6 NOT EXECUTED: after starting existing Docker, only75,042,816 bytes
available (<350MiB); stopped Docker to reclaim memory. No hosted load fallback.
The executed ten-session/200-attempt SQL race is correctness evidence, not an
HTTP latency measurement or a 1,000-user capacity claim. Checkout p95<800ms
and unexpected-error<1% qualification remain NOT EXECUTED in this environment.
Rerun local-only `tests/load/FR-17-local.py small` then `full` with sufficient RAM.
Multi-product contention and double-restoration correctness were executed in
independent local sessions; their large-scale latency remains unqualified.

Official [Supabase database-size limits](https://supabase.com/docs/guides/platform/database-size)
state Free500MB, with read-only restrictions beyond the limit. Official
[compute/connection limits](https://supabase.com/docs/guides/platform/compute-and-disk)
list Nano60 direct connections/200 pooler connections. These are limits, not a
promise of sustainable checkout concurrency. Use bounded pooler-backed work;
do not map1,000 buyers to1,000 direct PostgreSQL connections. Free quotas are
finite; append-only inventory, accepted audit/outbox and notifications share
the database allowance. No paid capacity was added.

Actual small TEST sample:25 ledger rows, mean physical tuple207 bytes,
table49152 bytes and indexes81920 bytes. Fixed page allocation dominates this
tiny sample, so dividing81920 by25 is not a reliable per-row index estimate.
**Assumption:** at207 tuple bytes plus estimated150–300 bytes for the primary/
secondary/partial indexes,1million movements would occupy roughly357–507MB
before additional page slack, larger reasons/payloads, TOAST and vacuum effects.
One sale item adds one row; cancellation adds another; each manual adjustment
adds one. This is a planning estimate, not a measured million-row benchmark.
Monitor actual relation/index sizes; do not delete append-only audit records
or promise unlimited retention within the shared Free500MB database.

## Physical Android acceptance

Device `AESWNRBAEUPNTGJZ`, package `com.example.flutter_application_1.fr21test`.
Corrected fresh TEST APK build/install PASS (130.6s build). All106 Dart source
files match the mirror. Actual APK206344554 bytes, SHA256
`91a475b1ffc5d0ae8fa9b4ef37096e52f3f9f76ed09b02163827470405314694`.
TEST application ID and endpoint verified; protected credentials and production
endpoint absent;38 changed/new files scanned at this checkpoint. Installation
returned Success. Existing native Android/Firebase configuration preserved.

- PASS vendor creation: actual phone form created product34 with12 confirmed
  units/threshold5; matching persisted row and vendor indicator observed.
- PASS adjustment: corrected phone dialog saved16/version3 and returned to
  the inventory list without assertion. Low-stock fixture later restocked7
  using the same actual UI. In-stock, low4 and zero indicators observed.
- PASS customer catalog/detail/cart: available16 shown; zero product displayed
  exact SRDS message and a disabled Add to Cart button. Real available-item
  add succeeded, and cart showed the chosen quantity/current stock.
- PASS UI checkout: actual COD order1671 created one item/decrement, stock16->15.
  Temporary eligibility3600 allowed deliberate rejection; default restored180.
  Saved child deadline remained the original3600 snapshot.
- PASS shortage: two-item cart, synthetic stock changed to0 after checkout
  opened; actual dialog requested1/available0. No extra order, no partial valid
  stock decrement. Explicit Adjust quantities removed only the affected item
  and retained valid quantity1. Synthetic available count restored15 afterward.
- PASS actual shared checkout: existing multi-vendor confirmation completed;
  order1672 contained products30/32 from two vendors, amount360, two decrements,
  both20->19. Temporary60 default restored180 in finally. The minute worker
  cancelled both portions automatically before any manual retry; both stocks
  returned20, two restores, one customer notice, no COD refund. Customer history
  displayed Cancelled and the exact message for order1672. Worker retry retained
  exactly two restoration rows.
- PASS vendor rejection: actual phone Reject on child1271 cancelled parent1671
  with `vendor_rejected`, restored15->16 exactly once, no live portion/refund.
  FR10 emits its dedicated notice only for vendor_timeout; the probe was
  corrected to expect zero dedicated timeout notices for rejection. No business
  behavior changed to satisfy a test assumption.
- PASS first crossing: real synthetic customer HTTP purchases7->5->4 while
  vendor app foreground; exactly one product33 notice and actual matching
  Android OS notification. Below-threshold purchase did not spam.
- PASS rearm: actual vendor UI restock7, then real synthetic HTTP purchase2;
  exactly two crossing notices total and a second matching Android notification.
  These customer purchases were HTTP fixture triggers, not claimed phone checkouts.
- PASS existing notifications: both low-stock notices and existing new-order
  notices visible in phone inbox; actual Mark all as read persisted unread0.
- PASS final physical integrity: six own synthetic products reconcile from
  ledger opening0, zero negative/unreconciled products, duplicate movements or
  missing cancellation restores. Final visible TEST UI/log scan passed, no fatal,
  unhandled or Flutter error lines. Fresh hosted recheck confirms same32 versions,
  protected-write denials, default180 and original two active scheduler jobs.

The first APK did expose a real dialog-close `_dependents.isEmpty` assertion
after saving14. It was counted FAIL, fixed with State-owned controller lifetime,
covered by three new widget tests, rebuilt and repeated successfully on-device.
The earlier severity-only log check missed the red screen; the final probe also
rejects assertion patterns and empty TEST UI. An early shared-order probe saw
the old order while the app awaited confirmation; that lookup was discarded,
and the helper now requires both expected products/new order before recording.
No test result was fabricated. No remaining mandatory functional/security blocker.

## Git and recovery

Exact changed/new paths: `FR-17-changed-files.txt` (38 files). Sanitized executed
evidence: `evidence/FR-17-acceptance.json`. Resume from `FR-17-progress.md` and
the existing deployed history; never replay migration202610160002.
Feature-only commit message: `feat(FR-17): stock quantity tracking`.
Commit identity/working-tree status are recorded in Git history and the final
handoff, avoiding a self-referential commit hash in this file. No push or merge.
Requested safe push command, for user use after that commit:
`git push -u origin feature/FR-17-stock-tracking`. Not executed.
