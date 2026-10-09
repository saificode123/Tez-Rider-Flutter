# FR-21 verification and deployment

Scope: rider presence and its use in existing assignment. Nothing has been
deployed. Migration: `supabase/migrations/202610090001_fr21_presence.sql`.

## Database prerequisites and risks

- Test against a clone of the actual schema first. The checked-in SQL files are
  destructive bootstrap scripts, not a trustworthy ordered migration history;
  **do not run them against an existing project**.
- The migration reuses presence columns if present; new `is_verified` is
  backfilled only from approved rider profiles. Later admin approval updates
  synchronize it. Existing verification values are preserved.
- Legacy identity uses `users.id` (bigint) and confirmed Auth email. The actor is
  resolved server-side against `auth.users`, never a client-supplied rider ID.
  Unconfirmed or unmatched accounts are rejected. Confirm email/ID mappings in
  the clone before deployment.
- A unique index on `riders.userid` deliberately fails on duplicate profiles;
  resolve duplicates manually after reviewing their relationships. No data is
  dropped or silently deduplicated.
- Presence RLS combines an owner policy, a restrictive owner guard, column
  privileges, and a trigger. Clients cannot change other rider fields, insert
  replacement profiles, or delete profiles. Provisioning and location updates
  require existing authorized server operations; this migration adds none.
- Existing policies are preserved. RLS is enabled on tables used by the RPCs,
  with scoped read policies added. On the clone, verify existing customer order
  writes and admin/profile operations still have their required policies; do not
  compensate with `USING(true)`. The checked-in schema has no complete policies
  for those workflows, so full live policy compatibility is **unverified**.
- Role/email/approval fields are protected from client escalation. Rider/vendor
  signup remains pending until admin approval; existing account profile fields
  remain governed by their policies. No client service-role key is introduced.
- Missing vendor coordinates produce a confirmed ready status plus a truthful
  no-location message. Existing coordinates are reused without adding columns.
- Apply the migration before releasing the client. Keep the migration and RPCs
  together; mismatched versions fail visibly. Existing Realtime publication must
  include `orders` and `tailoring_requests` for dashboard events.
- The stored `is_online` flag is intent. Effective availability also requires
  `last_seen >= server_time - 2 minutes`; stale flags are never eligible for
  assignment. No scheduled stale-row cleanup is required.
- One app session per rider: startup rotates its epoch. Older sessions cannot
  heartbeat over the newer session; sequence numbers reject late requests.
  Retries reuse the same sequence and do not repeatedly extend a lease.
- Backgrounding sets offline best-effort. Returning to foreground restores the
  server state; toggle online again when needed. Abrupt process death cannot
  guarantee a final network request; expiry bounds stale eligibility to 2 minutes.

## Capacity and zero-cost limits (checked 2026-10-09)

Supabase Free includes 200 peak Realtime connections, 2 million Realtime messages
per month, 500 MB database size per project, and 500,000 Edge Function invocations
per month. Source: [official billing quotas](https://supabase.com/docs/guides/platform/billing-on-supabase).
It also limits Realtime to 100 messages/second and 100 channel joins/second:
[official Realtime limits](https://supabase.com/docs/guides/realtime/limits).

**1,000 simultaneously connected app users do not fit hosted Free.** The first
known hard limit is 200 Realtime connections (join/message bursts could fail
earlier). One channel per rider screen reduces subscriptions, not connection
count. No paid dependency or upgrade is introduced.

Free mitigation: cap simultaneously connected users at 200, stagger connections,
or self-host the open-source Supabase stack on existing hardware. Self-hosting
does not remove compute/network/resource costs. **Assumption:** hardware capable
of meeting the 1,000-user latency target is available; this has not been measured.
There is no promise of a free hosted 1,000-user deployment.

Heartbeats are jittered every 45–55 seconds, online only: at 1,000 continuously
online riders, about 18.2–22.2 writes/second, 1.57–1.92 million writes/day, or
47.1–57.6 million writes/30 days (mean interval 50s: 51.84 million/month). They
update existing rows rather than append history. Vacuum, write I/O, egress, and
indexes still need measurement. FR-21 has no `riders` heartbeat subscription,
avoiding a new per-heartbeat Realtime fan-out; other existing subscribers may
still receive updates. RPCs use PostgREST and consume **zero Edge Function
invocations**. Existing earnings/history modules are outside this change;
application-wide scale is not claimed.

## Isolated backend tests

Supabase CLI, Docker, psql, and k6 were not available during implementation;
database and load tests were **Not executed**.

Use an existing isolated schema clone. For local testing, run `supabase init`
once if no local config exists, then `supabase start`; import the verified schema
into that disposable local database and apply the FR-21 migration. Never run a
reset or the legacy destructive SQL against the live project.

Run SQL using an isolated database DSN:

```text
psql "$TEST_DB_URL" -v ON_ERROR_STOP=1 -v FR21_ISOLATED_TEST=true -f supabase/tests/FR-21.sql
```

The main tests create disposable negative-ID fixtures in one transaction and
roll back. They check all five roles, both riders, forged timestamps, protected
fields, stale/unverified exclusion, duplicate writes, superseded epochs,
out-of-order online/offline writes, and assignment idempotency. Failures raise
exceptions. Optional dblink cases require two disposable committed vendor orders,
one fresh verified available rider, and no other eligible riders. Supply
`FR21_RACE_DSN`, `FR21_RACE_VENDOR_UUID`, `FR21_RACE_ORDER_A`,
`FR21_RACE_ORDER_B`, `FR21_RACE_RIDER_ID` as psql variables. These cases hold a
transaction open, verify another order skips its reserved rider, then verify a
duplicate waits and creates exactly one assignment. They mutate only those
committed test fixtures; recreate the disposable project afterward. The
`dblink` extension is test-only, not a production dependency.

For k6, prepare a **private, untracked** JSON array of 1,000 test fixtures with
distinct approved riders, confirmed Auth accounts, rider rows/coordinates,
vendor rows/coordinates, and disposable orders. Each entry contains
`rider_token`, `vendor_token`, `vendor_order_id`. Tokens must remain valid for
the whole run. Supply their path with `FR21_FIXTURES`; do not commit credentials.

```text
k6 run tests/load/FR-21.js
```

Environment: `FR21_URL=http://127.0.0.1:54321`, `FR21_ANON_KEY` from the local
instance, and `FR21_FIXTURES`. A remote clone additionally requires
`FR21_ISOLATED_TEST=true`, `FR21_TEST_PROJECT_REF`, and the distinct
`FR21_LIVE_PROJECT_REF` so the live target is rejected. The script ramps to
1,000 VUs, calls heartbeat and assignment RPCs, and requires p95 <800ms,
HTTP failures <1%, and successful checks >99%. It tests HTTP database operations;
it does not bypass or test 1,000 Realtime connections on hosted Free.

## Device checklist

1. Approved rider login: toggle restores DB status; no default online flash.
2. Toggle online: confirmed DB `is_online=true` and server `last_seen`; rapid taps
   cause one intent write and the switch stays disabled during the request.
3. Wait 55 seconds online: `last_seen` advances without overlapping requests.
4. Disable network and toggle: UI reverts, error appears, no simulated success.
5. Reconnect and Retry: confirmed state restores; online can be requested again.
6. Vendor marks ready: only a fresh, verified, available online rider is assigned;
   repeat the action and confirm one assignment/notification.
7. Use two vendors/orders concurrently with one eligible rider: only one order
   reserves it; the other gets a confirmed no-rider result.
8. Background/close or logout normally: offline writes occur best-effort before
   signout; returning restores the DB state.
9. Force-kill an online rider app: after >120 seconds assignment excludes it;
   relaunch restores offline.
10. Attempt another rider's presence/protected fields with test credentials:
    no foreign row changes; verification/availability/ownership writes are denied.

## Local checks

The Flutter batch launcher stalled. Checks were run through the existing Flutter
tool snapshot with the existing Dart SDK, without reinstalling/changing the SDK.
`flutter pub get` completed: `Got dependencies!` (46 newer constrained versions
reported; no dependencies changed). `dart format .` was attempted and failed
while traversing an existing missing build/intermediate path; unrelated formatting
was restored, then changed Dart files were formatted directly.

Final full analysis: exit 1, `98 issues found. (ran in 93.4s)`; no diagnostics in
the FR-21 changed files. Final full tests: exit 1, `00:26 +6 -1: Some tests failed.`
All six FR-21 tests passed; the existing splash-screen test omits GetX
AuthController setup and fails independently. It was left outside this scope.
The targeted FR-21 test run reported `00:03 +6: All tests passed!`.
Changed Dart files formatted successfully; k6 JavaScript syntax checked with
Node. SQL, dblink races, Supabase/local startup, k6 load, and device checks:
**Not executed**. No claim is made that the migration has run or p95 is <800ms.
