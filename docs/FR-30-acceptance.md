# FR-30 acceptance — 2026-10-15

**FR-30 FUNCTIONALLY ACCEPTED — Ready for the next functional requirement (authorized Android TEST scope).**

In-app functionality/security passed the executed TEST and physical checks below. SRDS §2.3.8 also
requires native push; the approved Android TEST implementation is configured and
physically verified. iOS native push/APNs is not accepted by these Android tests. Full 1,000-user
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
- **PASS — TEST safety.** Only `igeisilhtmglgnqvllrx`; all 30 repository migration versions
  match. Only new 004/005/006 applied. Final audit: zero unmarked recipients. Customer/vendor
  marker cohorts checked before committed hosted sends. Local load stack is unlinked,
  loopback-only with no hosted fallback. Production `arrqsvejrfdbacfwtpcc` untouched.

## Policy, grant and function inventory

New policies on `admin_broadcasts`: `fr30_admin_history` (SELECT approved admin) and
restrictive `fr28_session_guard` (ALL session/block gate). Existing notification and
audit policies unchanged. No recipient list is exposed by history.
`admin_broadcasts`: revoke PUBLIC/anon/authenticated, grant authenticated SELECT,
service_role ALL; identity sequence usage/select only service_role. Private schema
and limits table revoked from PUBLIC/anon/authenticated. New FK/unique recipient/audit
and owner unread/history/sender-time indexes. In-app SECURITY DEFINER functions:
`admin_send_broadcast(uuid,text,text,text)` and `fr30_estimate(text)`, fixed empty
search_path, qualified names, no PUBLIC/anon EXECUTE, authenticated EXECUTE.
005 replaces only the sender locking clause; it preserves function privileges.
006 adds private RLS-protected device/outbox tables with no client table grants.
Authenticated-only definer RPCs: `fr30_register_push`, `fr30_unregister_push`.
Service-role-only definer RPCs: `fr30_claim_push`, `fr30_push_eligible`,
`fr30_finish_push`. The anon/authenticated `fr30_resolve_push` definer RPC requires
a random 256-bit encrypted device credential; it resolves only one existing unread
snapshot job for that installation, unchanged owner/session/credential hashes,
confirmed unblocked owner, live Auth session and one-hour expiry. It provides no
list, registration or read-state access. PUBLIC EXECUTE revoked; all search paths
empty. Private trigger functions `queue_push`, `block_push` and scheduled
`dispatch_push` have no client EXECUTE. No existing RLS policy was weakened.
The cron job runs once/minute and makes no HTTP request while dispatch is disabled
or no due jobs exist; server worker key must come from Vault, never client code.

## Executed verification

- **PASS:** final deployed SQL 65 (rolled back); local SQL 65; hosted HTTP 25 including
  actual concurrent requests; Realtime 3; local cross-admin ALL race 2.
- **PASS:** Baseline in-app Flutter123, two inherited conditional skips; later push suite135 below.
  Whole analyzer: zero errors, 16 inherited warnings / 86 inherited infos. Dependencies
  resolved; changed Dart only formatted. These are baseline in-app results; approved push preparation results follow below. Python verification helpers compile.
- **PASS:** regressions FR21 47, FR04 49, FR25 83, FR26 95, FR33 39 (zero real emails),
  FR28 74, FR20 70. Evidence `regressions.json`.
  Initial FR21 failure was stale GPS in legacy fixtures after accepted FR20 freshness
  enforcement; wrapper refreshes authorized GPS and seeds other vendor line ready,
  preserving all original assertions. Initial FR33 transport timeout passed on rerun.
  Transient CLI login-password conflicts resolved after remote jobs finished;005
  applied once. Initial OneDrive Flutter cache-copy error passed in source-identical
  existing build mirror, sequentially. Failed attempts remain in ignored logs.
- **PASS — baseline in-app APK:** source99/package/TEST endpoint/credential guards and installation.
  SHA256 `e2c8ad739869e486a33e9bf873bdc77cda80e0197751f29686a34d5228983c93`;
  205955532 bytes. Device AESWNRBAEUPNTGJZ; package
  `com.example.flutter_application_1.fr21test`. Actual native admin composer/send/history,
  customer broadcast+personal list, read/badges/offline-resume executed on earlier FR30 builds.
  The last baseline Dart change was the six-line vendor notification entry, verified on
  that APK. Approved push changes require a separate rebuilt APK and device verification. Screenshots with reused names retain the latest capture. Customer
  logs: zero fatal/unhandled/Auth/API errors. Evidence `artifact.json`, `device.json`.
- **PASS — physical double tap and persisted isolation.** Final vendor-targeted
  confirmation double tap executed; server confirmed9 recipients. Eight persistence
  assertions prove exactly one broadcast/audit, vendor ownership, customer exclusion,
  vendor exclusion from customer broadcasts and customer read states. Evidence
  `native-persistence.json`. The final rebuilt APK vendor Notifications action opened the real list and displayed
  the targeted notice. Final vendor fatal/unhandled/Auth/API error counts were zero. Vendor UI also showed
  existing server-generated personal order notices, with customer broadcasts absent.
- **PASS — approved push preparation:** new push SQL45 rollback assertions (also rerun with a live registered phone), existing
  SQL65 rerun, Node and Deno TypeScript worker/sender4 tests in each runtime (synthetic OAuth/FCM responses,
  real generated RSA signing), deployed Edge boundary4 checks. Worker returns403 to
  anonymous/customer callers and503 to authorized admin without credentials. These were pre-configuration failure-boundary checks. After secure configuration,
  anonymous/customer403 and admin readiness200 passed before enabling dispatch.
  Subsequent real provider and device results are recorded below.
- **PASS — updated Flutter suite:**135 passed, two inherited skips, including eight
  lookup/privacy tests and four async OS-post/logout-race tests. Firebase packages resolved.
  Whole workspace:0 errors/16 inherited warnings/86 inherited infos; no new push findings.
- **PASS — live Android TEST OS push:** real configuration matched project
  `tez-rider-fe12b` and the exact TEST package. Private sender credential stayed
  outside Git/client/log output; Edge-only secrets and private Vault worker key
  configured securely. Seven real deliveries across initial/final builds, including
  foreground/background/normal-terminated on final APK, each had one actual OS
  notification with exact title/body. Provider acceptance was checked separately.
  Process absence and non-force-stopped package were proved before terminated sends.
- **PASS — permission, authentication and recipient safety:** actual deny/retry/allow;
  denied in-app delivery without OS push; authenticated registration; logout erased
  registration/notices; signed-out send had0 jobs; blocked recipient excluded from
  immutable in-app snapshot and push, registration removed, blocked sign-in message
  observed. Fixture restored and exactly one authorized installation re-registered.
  Ten real scenarios each have one trusted audit, exact counts and no other-role
  recipients. Blocked-time broadcast remains absent after unblock. Read-all/badge0
  and legitimate existing personal notifications preserved.
- **PASS — autonomous dispatch:** one additional real broadcast was left for cron;
  no manual Edge dispatch occurred. The scheduled Vault-key-authenticated worker
  delivered the exact OS notice, verifying the durable fallback independently of
  the admin client. Its unread badge changed0→1→0 through normal read-all.
- **PASS — cold-start interaction:** the observed Android TEST notification was
  selected from its OEM group. Existing customer cold-start sign-in remains required;
  pending notification route opened the correct list after authentication. No unrelated
  session-restoration behavior was changed. OEM idle hierarchy failure required
  observed screenshot coordinates; unrelated shade contents were not committed.
- **PASS — runtime scoped to FR30:** zero fatal/unhandled/Auth errors and zero FR30
  API errors. One reproducible inherited customer-dashboard log is **not fixed or
  hidden**: unchanged `VendorInfoController` calls `get_vendor_ratings`, denied42501
  by the baseline public-function revoke. Its source and grants were preserved.
  This is an unrelated existing ratings issue, not accepted as working by FR30.
- **PASS — final build:** SHA256
  `ad2676f55ba055c20b95ed6bc33fbbe0d2403b8c3183fd8586e82ee53ea680e7`,
  206306517 bytes,101 identical Dart sources; installed on authorized device.
  Actual server-key/worker-key/fixture-password/service-role scans found0 matches.
  TEST client JSON ignored by flavor `.gitignore`; no private JSON added to repository.
- **PASS — Deno:** entry-point type check and4 isolated tests; formatted source
  deployed to TEST. No Docker rebuild, migration replay or production modification.
  Evidence for this approved follow-up: `FR-30-push.json`, `FR-30-push-sql.json`,
  `FR-30-push-ready.json` and the earlier fail-closed `FR-30-push-edge.json`.
- **NOT TESTED — iOS native push:** no APNs credentials/capabilities or paid membership
  configured. This acceptance covers the explicitly authorized Android TEST scope.

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
In-app fan-out uses no Edge invocation. Approved native push adds bounded Edge batches
and cron invocations only when due jobs exist, within the same Free invocation quota.

**Assumption:** Realtime 100msg/sec and 200 concurrent connections are the first live
delivery bottlenecks for this fan-out design; database duplication accumulates toward
500MB. A 1000-recipient1000-active-client scenario cannot be promised on Free based
on the local 10 VU results. No paid infrastructure added. FCM is no-cost but APNs/iOS
membership must be resolved separately; details/official links are in the push decision.

## Remaining limitations

iOS APNs/zero-cost availability remains a separate platform dependency; Android
verification does not establish iOS delivery. Full1000 VU scalability qualification
remains NOT EXECUTED. Existing vendor-ratings42501 is documented above and unchanged.
No remaining blocker for the authorized Android FR30 implementation.

Exact feature paths are in `FR-30-files.txt`; follow-up paths in
`FR-30-push-files.txt`. Final candidate security/artifact scan passed:42 follow-up files,0 credential
matches,0 unexpected files over5MB; final TEST APK also scanned. Unrelated root `.gitignore` is preserved and excluded from staging.
