# FR-30 acceptance — 2026-10-15

**FR-30 PARTIALLY IMPLEMENTED — Native push approval or verification pending.**

In-app functionality/security passed the executed TEST and physical checks below. SRDS §2.3.8 also
requires native push; it has not been waived or implemented. Full 1,000-user
performance qualification remains separate and unverified. Production untouched;
no TEST reset, migration replay, push or merge.

Evidence prefix: `docs/evidence/FR-30-`. Raw logs, screenshots, build and local
fixtures remain ignored in `.fr21-local/fr30/`; credentials remain DPAPI-protected.
Exact changed-file manifest: `FR-30-files.txt`.

## In-app functional and security criteria

- **PASS — SRDS/source inspection and architecture.** Locations: `FR-30-progress.md`,
  `FR-30-push-decision.md`. Checked FR30/31, §2.3.7/8, UC08 step4, composer, FR44,
  SEC01/07 and S01; visually reviewed the Manage Notifications use-case diagram.
  Selected transactional per-user fan-out to preserve existing owner RLS, read state,
  bigint pagination and unread queries. Shared broadcasts would still need mappings
  and would alter FR31 query/authorization behavior. Trade-off: N duplicated payloads.
- **PASS — canonical approved admin, blocked/session guards.** Locations: migration
  `202610150004`, `admin_send_broadcast`, `fr30_estimate`. SQL/hosted role-denial,
  blocked/unapproved admin, anonymous and forged-write probes passed. Evidence:
  `sql.json`, `hosted.json`, `verification.json`. FR28 pre-request denial retained.
- **PASS — trusted audience and immutable eligibility snapshot.** Location: set-based
  notification insert plus UUID FK/unique `(broadcast_id,user_id)`. ALL/CUSTOMERS/
  VENDORS/RIDERS, blocked exclusion, role changes, zero recipients tested in rolled-back
  SQL. Hosted customer/vendor sends, later new user exclusion, offline retrieval passed.
  Existing send-time recipients retain their own notice after role change; new role
  joiners get no historical notice. Block/unblock never creates new deliveries.
  ALL/RIDERS committed hosted sends deliberately not executed: one unrelated rider
  exists. Genuine simultaneous ALL sends were executed locally with synthetic users.
- **PASS — input validation and plain text.** Locations: RPC constraints/trim/limits,
  controller and Text widgets. SQL covers whitespace, empty/oversized/null/invalid
  audience and literal HTML-like content. Client rune-length validation and field
  limits; widgets render text without HTML/Markdown execution. Evidence: `sql.json`,
  `hosted.json`, `flutter.json`.
- **PASS — idempotency, transactionality, abuse limits, audit.** UUID is bound to
  actor+trimmed payload+audience; replay precedes limits. Same-key changed payload or
  actor conflicts. Real hosted four-way HTTP race: one SENT/three ALREADY_SENT;
  two different-key requests: one SENT/one COOLDOWN. Local simultaneous ALL sends
  by two admins both SENT. Migration `202610150005` uses NO KEY UPDATE sender lock
  compatible with recipient foreign keys. Default 60s cooldown/10 per rolling24h;
  private operator-configurable settings. SQL validates daily limit/replay/count/audit.
  Final audit confirms zero duplicates/count mismatches and one SEND_BROADCAST audit
  per broadcast. Evidence: `hosted.json`, `local-admin-races.json`, `verification.json`.
- **PASS — UUID broadcast audit relationship.** Existing generic audit `target_id`
  is bigint and remains intact. Each UUID broadcast has a unique internal bigint
  `audit_number`; audit stores it plus a UUID `broadcast_id` FK. Actor, action,
  target type, time and immutable audience/count are joinable without client identity
  inputs. Existing append-only audit trigger/grants preserved.
- **PASS — least privilege, own read isolation and history privacy.** SQL/HTTP test
  ordinary users cannot enumerate history, insert broadcasts/notices/audits, or update
  other users' read state. Admin history is approved-admin-only; blocked protected
  reads remain denied. Final grant/definer/policy evidence: `verification.json`.
- **PASS — composer and estimates.** Locations: `admin_broadcast_service.dart`,
  `admin_broadcast_controller.dart`, `admin_broadcasts_screen.dart`, admin dashboard.
  Validation/audience/estimate/confirm/cancel/busy/duplicate/cooldown/daily/forbidden
  and exact-key timeout retry tests passed. Native confirmation showed title,
  Customers and estimate14; canceled first, then server confirmed14 recipients.
  Estimate never supplies the server count. Evidence: `flutter.json`, `device.json`.
- **PASS — history, stable pagination and refresh race.** Single bounded select25,
  `(created_at,id)` keyset, minimal columns/no recipient PII/no N+1. Tests cover
  cursor/dedup and a send during an older in-flight history read; authoritative
  refresh runs after it completes. Actual PostgREST history pagination traversed four pages of size2 (six records),
  no duplicate/drop (`history-pages.json`). Native history shows audience/count/time/ACCEPTED.
  ACCEPTED means committed database delivery state, not guaranteed device receipt.
- **PASS — existing FR31 list/read/badge.** Locations: existing notification controller, customer Notifications screen and
  vendor dashboard Notifications action (vendor has no shared drawer). Broadcast label added; personal rows and existing
  bigint cursor/read operations retained. The preceding FR30 APK displayed both broadcast and an
  explicitly synthetic personal fixture. Badge 2 then mark-all→0; offline new notice → 1
  then individual read→0. Evidence: `device.json`, `native-offline-send.json`.
- **PASS — actual Realtime privacy and reconnect.** One existing own-user filtered
  channel per controller/session, existing auth-generation/debounce/disposal retained.
  Subscribe/resume fetch authoritative list/count. Real websocket recipient received
  exactly one insert; another user subscribing to that recipient filter received zero.
  Physical Android network disabled/backgrounded during server send; original network
  settings restored/resume loaded the notice. No periodic polling or per-broadcast
  subscriptions. Evidence: `realtime.json`, `device.json`.
- **PASS — TEST safety.** Only `igeisilhtmglgnqvllrx`; all 29 repository migration versions
  match. Only new 004/005 applied. Final audit: zero unmarked recipients. Customer/vendor
  marker cohorts checked before committed hosted sends. Local load stack is unlinked,
  loopback-only with no hosted fallback. Production `arrqsvejrfdbacfwtpcc` untouched.

## Policy, grant and function inventory

New policies on `admin_broadcasts`: `fr30_admin_history` (SELECT approved admin) and
restrictive `fr28_session_guard` (ALL session/block gate). Existing notification and
audit policies unchanged. No recipient list is exposed by history.
`admin_broadcasts`: revoke PUBLIC/anon/authenticated, grant authenticated SELECT,
service_role ALL; identity sequence usage/select only service_role. Private schema
and limits table revoked from PUBLIC/anon/authenticated. New FK/unique recipient/audit
and owner unread/history/sender-time indexes. Two SECURITY DEFINER functions only:
`admin_send_broadcast(uuid,text,text,text)` and `fr30_estimate(text)`, fixed empty
search_path, qualified names, no PUBLIC/anon EXECUTE, authenticated EXECUTE.
005 replaces only the sender locking clause; it preserves function privileges.

## Executed verification

- **PASS:** final deployed SQL 65 (rolled back); local SQL 65; hosted HTTP 25 including
  actual concurrent requests; Realtime 3; local cross-admin ALL race 2.
- **PASS:** Flutter 123, two inherited conditional skips; scoped final analyzer clean.
  Whole analyzer: zero errors, 16 inherited warnings / 86 inherited infos. Dependencies
  resolved; changed Dart only formatted. No new Edge Function/Deno implementation. Python verification helpers compile.
- **PASS:** regressions FR21 47, FR04 49, FR25 83, FR26 95, FR33 39 (zero real emails),
  FR28 74, FR20 70. Evidence `regressions.json`.
  Initial FR21 failure was stale GPS in legacy fixtures after accepted FR20 freshness
  enforcement; wrapper refreshes authorized GPS and seeds other vendor line ready,
  preserving all original assertions. Initial FR33 transport timeout passed on rerun.
  Transient CLI login-password conflicts resolved after remote jobs finished;005
  applied once. Initial OneDrive Flutter cache-copy error passed in source-identical
  existing build mirror, sequentially. Failed attempts remain in ignored logs.
- **PASS:** final APK source99/package/TEST endpoint/credential guards and installation.
  SHA256 `e2c8ad739869e486a33e9bf873bdc77cda80e0197751f29686a34d5228983c93`;
  205955532 bytes. Device AESWNRBAEUPNTGJZ; package
  `com.example.flutter_application_1.fr21test`. Actual native admin composer/send/history,
  customer broadcast+personal list, read/badges/offline-resume executed on earlier FR30 builds.
  The only later Dart change was the six-line vendor notification entry, verified on
  the final APK. Screenshots with reused names retain the latest capture. Customer
  logs: zero fatal/unhandled/Auth/API errors. Evidence `artifact.json`, `device.json`.
- **PASS — physical double tap and persisted isolation.** Final vendor-targeted
  confirmation double tap executed; server confirmed9 recipients. Eight persistence
  assertions prove exactly one broadcast/audit, vendor ownership, customer exclusion,
  vendor exclusion from customer broadcasts and customer read states. Evidence
  `native-persistence.json`. The final rebuilt APK vendor Notifications action opened the real list and displayed
  the targeted notice. Final vendor fatal/unhandled/Auth/API error counts were zero. Vendor UI also showed
  existing server-generated personal order notices, with customer broadcasts absent.
- **NOT TESTED — native OS push.** No Firebase/messaging or Android/iOS build changes.
  Explicit approval required by task D1. See `FR-30-push-decision.md` for the concrete
  free Android FCM proposal, required Firebase/server setup and iOS/APNs cost dependency.

## Performance and free-tier qualification

`tests/load/FR-30.js` and guarded `FR-30-local.py`: local-only staged10/100/500/1000 VUs,
reads, exact unread counts, own read updates, concurrent same-key replays, cross-user
denial and refresh queries. Initial executed 10 VU run sent one 1000-recipient broadcast,
771 HTTP requests, p95 17.17ms, zero unexpected errors, one broadcast/audit and zero
duplicate recipients. The separate per-operation latency rerun was aborted by the RAM safety guard;
read/unread/broadcast latency breakdowns are NOT MEASURED (`load-rerun.json`).
Full 1000 VU qualification: **NOT EXECUTED**, latest preflight 321413120 available RAM bytes below 1GiB
safety preflight; see `load-full.json`. No 1000-user capacity claim.

Measured initial 1000-notification heap payload127997 bytes and relation/index growth
417792 bytes. The original successful result is in `load-small.json`; the later memory-aborted
2000-recipient setup is separate and makes no latency/capacity claim. Page allocation,
index state and repeated read updates affect growth. A broadcast inserts N notifications,
one broadcast, one audit and updates the final count once (N+3 row mutations plus index/WAL).
N database insert events are eligible for notification publication; actual transmitted
Realtime event volume under load was **NOT MEASURED** (local Realtime excluded). Hosted
websocket proof measured 1 authorized / 0 unauthorized events, not total project fan-out.

Official sources checked 2026-10-15:
[Supabase billing](https://supabase.com/docs/guides/platform/billing-on-supabase)
lists Free 500MB database, 2 million Realtime messages/month, 200 peak connections,
500000 Edge invocations. [Realtime limits](https://supabase.com/docs/guides/realtime/limits)
lists 100 messages/sec on Free. [Compute limits](https://supabase.com/docs/guides/platform/compute-and-disk)
lists Nano up to 0.5GB RAM, 60 direct database connections and 200 pooler clients.
The implemented broadcast path uses no Edge invocation.

**Assumption:** Realtime 100msg/sec and 200 concurrent connections are the first live
delivery bottlenecks for this fan-out design; database duplication accumulates toward
500MB. A 1000-recipient1000-active-client scenario cannot be promised on Free based
on the local 10 VU results. No paid infrastructure added. FCM is no-cost but APNs/iOS
membership must be resolved separately; details/official links are in the push decision.

## Remaining dependency

Native push approval, Firebase TEST configuration/server credentials and physical
OS delivery verification remain mandatory. iOS APNs/zero-cost scope needs an explicit
decision. High-load scalability remains unqualified independently of in-app correctness.

Final candidate security/artifact scan:38 files, zero credential matches, zero
unexpected files over5MB; `.gitignore` excluded. Exact paths are in `FR-30-files.txt`.
