# FR-26 readiness — 2026-10-14

**FR-26 FUNCTIONALLY ACCEPTED — Ready for the next functional requirement.** Mandatory functional/security and Android checks passed. No unexecuted scenario is passed. Performance qualification at 1,000 VUs remains NOT EXECUTED. No push or merge.

## Sources and safe base

Read SRDS PDF pages 8–9 (§2.3.6/2.3.7), 16 (FR-26), 17 (FR-44), 21 (UC-07), 31–32 (S-01/SEC-01/SEC-07/SEC-08), 41 (visually rendered admin sequence phases 3–5) and 44 (Table 5.6 rows 22–23). User explicitly excludes gateway refunds and new escalation workflows: resolution records a pending refund action only, never completed payment. Exact messages are retained. No explicit note bound exists in these sources; implementation choice is 5–2,000 trimmed Unicode code points, returned by server options and enforced independently server-side.

Initial tree clean at `281c8a8`; accepted FR-04 `fd478a4` and FR-21 `1173736` ancestry verified. Local/remote branches inspected; GitHub FR-25 head matched `281c8a8`. New branch `feature/FR-26-admin-dispute-resolution` starts from that accepted base. No main assumption, merge or cherry-pick.

Only TEST `igeisilhtmglgnqvllrx` is authorized. Linked reference checked for every remote operation, HTTP helpers guard each request. Production `arrqsvejrfdbacfwtpcc` is never connected to or modified. No reset, migration repair/replay, encryption key changes, production records or real user data. Protected Windows DPAPI configuration supplies TEST-only keys and synthetic passwords without printing them.

## Verified inspection and implementation

TEST initially had exactly 14 migrations matching source; FR-21/04/25 intact. Existing admin disputes were unbounded, absent from Realtime publication, included fabricated fallback rows and swallowed direct UPDATE errors before displaying success. Reject/notes/confirmation/refund/audit were missing. FR-25 private evidence and owned customer RPCs work. `security_audit_log` already exists with RLS and no client grants; reuse it.

Legacy `payments` has text order/customer links, unconstrained status, a double-precision amount and `paidat`, but no relationship constraints. TEST payment count was zero; no existing payment writer was found in targeted application usages. Legacy card UI simulates success and does not establish verified settlement; that unrelated payment feature is not modified or trusted as proof of payment.

New additive migration `202610130006_fr26_admin_dispute_decisions.sql` adds decision/note/actor/time to existing disputes, one protected `dispute_refund_actions` table, narrowly scoped queue/payment/refund/notification indexes, final-row/append-only guards, authorized queue/detail/vendor/options/decision RPCs, owned customer detail extension and disputes publication membership. No original payment record or legacy migration is edited. Original permissive dispute policies remain intersected by FR-25 ownership/deny guards; direct client mutations stay forbidden. New functions have empty fixed search paths and no PUBLIC/anonymous EXECUTE.

Eligible decisions: OPEN, UNDER_REVIEW, ESCALATED; terminal/read-only: RESOLVED, REJECTED, CLOSED. No automatic opening transition, new escalation workflow or refund execution. A row-locked final decision, trusted-actor audit, owner notification and optional refund action commit together. Same-decision retry returns the original actor/note/outcome without side effects; opposite decisions conflict. Unique audit/refund/notification constraints supplement locks; terminal rows cannot be edited/deleted.

Refund safety: RESOLVED requires exactly one payment whose text order/owner links exactly match trusted order/profile IDs, nonempty receipt ID, settled status SUCCESS (SRDS Table 5.6 row 9), PAID/COMPLETED/SUCCEEDED, valid past settlement time, matching method and finite positive matching order amount. Missing/unpaid/mismatched/ambiguous payments reject resolution without finalizing; REJECTED needs no payment and preserves all settlements. Refund action snapshots linked payment/order/customer/actor/amount and stays PENDING. Original successful payment status/history is never overwritten. One payment cannot have multiple refund actions. Synthetic settled-payment fixtures are test records, not actual receipts or returned money.

Reuse existing `AdminController` through feature-specific state/service, and the FR-25 private evidence viewer/Edge endpoint (900 seconds, URLs not persisted/logged). Queue uses 30-row keyset pages ordered by submission timestamp/id and indexed normalized status. Detail joins projected identities/order/decision/refund fields and pages vendors by 20; no queue-wide signing/N+1 requests. One positive-ID-filtered, RLS-authorized queue channel allows transitions out of the selected status to refresh correctly; coalesce at 350 ms, unsubscribe on inactive tab/detail navigation/onClose, no polling. Confirmation precedes decision; no optimistic finalization. Ambiguous writes reconcile server outcome before bounded 400/800 ms retries and preserve the unchanged pending decision.

Essential customer integration displays final note/decision/pending-refund distinction. Existing notification controller had an undisposed unbounded listener and cached ownership across account changes. It now uses selected 30-row pages, authoritative owner resolution, one owner-filtered/coalesced channel, auth-generation guards, explicit errors/Retry and disposal. Its unrelated legacy notification-send helper remains unchanged; resolution notifications originate only inside the database transaction.

## Actual executed verification

- Three new TEST migrations applied once, in order: `202610130006_fr26_admin_dispute_decisions.sql`, `202610130007_fr26_canonical_payment_success.sql`, `202610130008_fr26_nullable_state_guards.sql`. Each reviewed with rollback validation and a dry-run selecting only new migrations. Existing 14 migrations preserved; total 17 verified. Later migrations preserve applied migration files. Explicit null legacy status / missing or blank payment-method guards close SQL three-valued-logic gaps without changing records.
- Final rollback SQL suite: **91 assertions passed**, including every role, forbidden direct writes, payment compatibility, final immutability, idempotent duplicates and injected audit/notification failure rollback. `evidence/FR-26-sql.json`.
- Hosted authenticated HTTP and real separate-thread/barrier races: **95 passed again after all three migrations**. Actual uploaded private synthetic images are used in HTTP checks; SQL fixture metadata alone is not treated as Storage proof.
- Canonical SRDS SUCCESS payment: **6 passed again after all three migrations**; original successful receipt unchanged, refund remains PENDING.
- Migration/security/publication verification: **5 passed**. Actual hosted 900-second URL expiry and authorized refresh: **4 passed**. `evidence/FR-26-verification.json`, `FR-26-migrations.json`, `FR-26-evidence-expiry.json`.
- `flutter pub get`: success, no dependency upgrades. Scoped Dart formatting executed. Full Flutter tests: **65 passed, 2 conditional hosted tests skipped**; separately authenticated FR-21 Flutter checks passed. New FR-26 suite contributes **19 tests**. Final nine-file scoped analysis: **No issues** (192.2 seconds). Full analysis: **96 inherited warnings/info, no errors**, exit 1; not claimed clean. `evidence/FR-26-flutter.txt`, `FR-26-scoped-analysis.txt`, `FR-26-full-analysis.txt`.
- FR-25 regressions: hosted **83**, extra **23**, SQL **43** passed. FR-04 hosted **49** passed. FR-21 hosted **46** and authenticated Flutter **2** passed. These ran after final Dart changes; subsequent SQL guards are FR-26-only. `evidence/FR-26-regressions.json`.
- Final TEST APK built successfully (139.1 seconds), installed successfully, all **91 Dart sources** match the build mirror. Exact TEST URL/public anon key verified in compiled APK; production URL, service/Vault keys and protected synthetic passwords absent. APK SHA256 `e4c52e3d8ef06d5be34cbeaaaa0917da721f3d1acdea1c6297e099fd3da4ff68`, 205,893,149 bytes. APK stays ignored at `.fr21-local/fr26/TezRider-FR26-Test-debug.apk`; `evidence/FR-26-apk.json`.
- Android `AESWNRBAEUPNTGJZ`: real admin login/queue/details/customer identity, joined synthetic vendor/rider identities, short-note validation, confirmation/Cancel, Resolve #75/order #210 and Reject #76/order #211 passed. Final decisions persisted with correct admin #83 and original notes; exactly one audit/owner notice each, one PENDING refund for Resolve, none for Reject. Both final displays are read-only.
- Actual native evidence expiration observed after 910 seconds and authorized fresh image visually verified; no simulated clock. Native status filters Open/Rejected and live arrival of #152/order #302, followed by second-admin rejection disappearing from Open and appearing in Rejected, observed without manual queue refresh.
- Owning customer native Notifications show both exact messages; owned details show `FR26 Android resolve note` / `FR26 Android reject note`, final decisions/time and pending manual processing with money not returned. Native FR-25 regression passed: Android submitted #161/order #303 with one real synthetic image, correct description and owned history. First request was unconfirmed and no row existed; unchanged Retry succeeded with exactly one record. Actual private uploaded image visually inspected. Support message persisted once and an authorized admin reply appeared through native Realtime without refresh. Timestamped observations and locally retained screenshots: `evidence/FR-26-device.json`, `.fr21-local/fr26/`.
- Final Android current-process log check at 2026-10-14T07:31:44Z: zero observed fatal, authentication or API exceptions after native submission/chat. No claim of exhaustive lifetime logging. Existing splash restores rider accounts only; admin/customer returning to Login after reinstall is preserved routing, not a new FR-26 session defect.
- Harness-only failures were corrected: ambiguous text-selector hitting an EditText, an extra keyboard Back navigating out of detail, transient XML dump parsing, and first mirror-copy path mistake. Failed checks were not counted as application passes. No failed APK was installed.

## Performance qualification

800 ms p95 / unexpected errors <1% / 1,000 VUs are additional engineering targets, not numeric SRDS requirements. No capacity claim based on bounded tests. Prior isolated FR-25 run reached 1,000 VUs but the 8 GB PC ran below 6 MB available RAM and resource-aborted; local volumes retained, Docker Desktop stopped. No hosted stress test is authorized. FR-26 staged k6 must use an unlinked isolated stack, distinguish expected conflicts, and stop safely on resource exhaustion.

Current official limits checked 2026-10-13: [Supabase pricing](https://supabase.com/pricing) — Free database 500 MB, shared CPU/500 MB RAM, file Storage 1 GB, egress 5 GB plus cached egress 5 GB. [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes) documents RLS authorization and per-change fan-out cost. Free API request count is not a throughput guarantee. Only active screens should subscribe; evidence signing is on demand. Paired 10-VU isolated k6 run passed (exit 0): 364 checks, 0 unexpected request errors, 45 expected PT409 conflicts. p95 queue 75.20 ms, customer detail 47.42 ms, same decision 121.40 ms, conflicting decision 86.74 ms. Five pairs share case IDs and two administrators, so concurrent contention is exercised. Minimum available memory 327,008,256 bytes (~312 MiB). Evidence: `evidence/FR-26-load-result.json` and `FR-26-load-summary.json`. Docker/local stack stopped afterward, volumes preserved.

**1,000-VU qualification: NOT EXECUTED.** Prior resource-aborted FR-25 run plus this machine's 8 GB RAM and low remaining memory prevent safe full qualification. Use the existing isolated runner on a better-resourced machine; never hosted Free TEST or production. The 10-VU result does not establish 1,000-user capacity. Free Realtime also allows 200 peak connections and 2 million messages/month, so 1,000 simultaneous connected clients exceed the connection allowance. Free mitigations are active-screen-only subscriptions, removing inactive channels and reducing fan-out; these do not guarantee 1,000 always-connected users. No paid dependencies added.

## Reproducible commands and remaining action

Executed feature runners (TEST reference is checked by the runner and each HTTP call):

```powershell
& tests/integration/FR-26-run.ps1 -Kind sql
& tests/integration/FR-26-run.ps1 -Kind tests
& tests/integration/FR-26-run.ps1 -Kind canonical
& tests/integration/FR-26-run.ps1 -Kind verify
& tests/integration/FR-26-run.ps1 -Kind ttl
& tests/integration/FR-26-run.ps1 -Kind artifact
```

The TTL runner genuinely waits for expiry; it is not a shortened clock test. Do not rerun migrations or generate new keys. Local k6 uses `tests/load/FR-26-local.py smoke` with existing isolated, unlinked `tezrider-fr25-local` stack only; staged `full` is NOT EXECUTED and requires sufficient RAM. Neither runner permits hosted load targets. Public build defines and protected fixture credentials remain outside Git.

All mandatory native checks are complete; no physical action or migration remains. Finalize the FR-26-only commit on `feature/FR-26-admin-dispute-resolution`, without pushing or merging. Performance qualification remains separate and requires an adequately resourced isolated host.

## Device retest checklist (synthetic TEST only)

1. Sign in as an approved synthetic Admin: real queue loads; ordinary roles are denied admin RPCs.
2. Select Open/Rejected/Resolved: only matching records appear, newest first; Load more fetches the next bounded page.
3. Open a synthetic dispute: order/customer/vendor/rider where assigned, description and evidence match TEST.
4. Open private evidence, wait more than 15 minutes, then Retry: expired state appears and authorized refresh restores the image.
5. Enter fewer than 5 characters: decision is blocked; enter a valid note and Cancel confirmation: persisted state remains unchanged.
6. Resolve a separate synthetic paid case and Reject an unpaid one: exact messages, correct notes, one audit/notice each; only Resolve creates a PENDING refund, no returned-money claim.
7. Reopen each final case: read-only; other administrator same-decision retry returns original outcome; opposite decision conflicts without new side effects.
8. Sign in as the owning customer: both notifications and notes appear; a different customer cannot access the details/evidence.
9. Submit a fresh eligible synthetic dispute with a test image, then send a support chat message: real upload/submission/history and reply must work; inspect current Android logs afterward.

## Changed/new files (FR-26 scope)

- `docs/FR-26-acceptance.md`
- `docs/FR-26-readiness.md`
- `docs/analysis_report.md`
- `docs/evidence/FR-26-android-runtime.json`
- `docs/evidence/FR-26-apk.json`
- `docs/evidence/FR-26-artifact.json`
- `docs/evidence/FR-26-canonical-payment.json`
- `docs/evidence/FR-26-device-reject.json`
- `docs/evidence/FR-26-device-resolve.json`
- `docs/evidence/FR-26-device-submission.json`
- `docs/evidence/FR-26-device.json`
- `docs/evidence/FR-26-evidence-expiry.json`
- `docs/evidence/FR-26-flutter.txt`
- `docs/evidence/FR-26-full-analysis.txt`
- `docs/evidence/FR-26-hosted.json`
- `docs/evidence/FR-26-load-result.json`
- `docs/evidence/FR-26-load-summary.json`
- `docs/evidence/FR-26-migrations.json`
- `docs/evidence/FR-26-regressions.json`
- `docs/evidence/FR-26-scoped-analysis.txt`
- `docs/evidence/FR-26-sql.json`
- `docs/evidence/FR-26-verification.json`
- `lib/controllers/admin_controller.dart`
- `lib/controllers/admin_dispute_state.dart`
- `lib/controllers/notification_controller.dart`
- `lib/screens/admin_dashboard.dart`
- `lib/screens/admin_disputes_screen.dart`
- `lib/screens/customer/dispute_screen.dart`
- `lib/screens/customer/notifications_screen.dart`
- `lib/services/admin_dispute_service.dart`
- `supabase/migrations/202610130006_fr26_admin_dispute_decisions.sql`
- `supabase/migrations/202610130007_fr26_canonical_payment_success.sql`
- `supabase/migrations/202610130008_fr26_nullable_state_guards.sql`
- `supabase/tests/FR-26.sql`
- `test/admin_dispute_test.dart`
- `tests/integration/FR-26-device.py`
- `tests/integration/FR-26-hosted.py`
- `tests/integration/FR-26-run.ps1`
- `tests/load/FR-26-local.py`
- `tests/load/FR-26.js`
