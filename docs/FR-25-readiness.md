# FR-25 readiness — 2026-10-13

**FR-25 FUNCTIONALLY ACCEPTED — Ready for the next functional requirement.** Mandatory functional/security verification passed. Performance/scalability qualification remains outstanding; no full performance acceptance.


## Scope and source reconciliation

SRDS PDF pages 8–9 (§2.3.6), 16 (FR-25), 21 (UC-07), 27 (§3.3.1/Figure G), 31–32 (S-05/SEC-01/SEC-08), and 44 (Table 5.6 rows 20–21) were inspected. Figure G depicts the existing inbox/chat entry; its surrounding prose requires order selection, reasons, evidence and status viewing. Preserve chat and provide the structured workflow separately.

The PDF does not specify reason values, a description length, 800 ms p95 or 1,000 users. The documented implementation choice is five server-defined reasons (`Damaged items`, `Missing items`, `Wrong items`, `Quality issue`, `Other`) and 2,000 Unicode code points. Flutter obtains these options from `fr25_options`; the server independently validates them. Numeric performance targets remain additional engineering qualifications, not substituted SRDS criteria.

Legacy `Open`/`Resolved` spelling is retained. Comparison/display normalize case and underscores. Supported states are OPEN, UNDER_REVIEW, RESOLVED, CLOSED, ESCALATED and REJECTED; FR-25 creates only `Open`. OPEN/UNDER_REVIEW/ESCALATED count as active. Closed/resolved/rejected history remains readable and does not block another eligible submission inside the original delivery window. No FR-26 transitions, refunds or resolution UI were implemented.

## Implementation and migrations

Base `fd478a4` contains accepted FR-21 `1173736`; `main` was not used. Branch: `feature/FR-25-dispute-submission`. Initial tree was clean. No merge, cherry-pick, push, force operation or history rewrite.

Only TEST `igeisilhtmglgnqvllrx` was accessed. The linked reference was checked before writes; HTTP helpers also fix the exact TEST URL and recheck the link. Production was never connected to or modified. Fixtures use synthetic `example.test` identities, small generated images and clearly labeled synthetic orders; no production records were copied.

New migrations were reviewed, validated in rollback transactions, previewed individually, then applied once with `--skip-vault`. Existing nine migrations were not replayed or edited:

1. `202610130001_fr25_dispute_submission.sql`: owned disputes/drafts, authoritative delivery timestamp, receipt-only historical backfill, statuses, constraints/indexes, private evidence registry/bucket, transactional creation/notifications and essential real customer/admin chat permissions.
2. `202610130002_fr25_delivery_guard.sql`: block client-forged delivered status/time at insertion; existing server OTP completion remains valid.
3. `202610130003_fr25_upload_reservations.sql`: at most three reserved immutable paths before Storage writes, trusted uploaded attestation, whitespace validation and bounded real order history.
4. `202610130004_fr25_notification_and_lock_guards.sql`: one confirmed approved admin notification, per-customer serialized draft limits, and locks filtered to owned rows.
5. `202610130005_fr25_unprepared_cleanup.sql`: missing preallocation is a safe authenticated customer cleanup no-op; another customer's or submitted evidence remains protected. Prevents failed preparation from trapping the local retry context.

No old records, policies or tables were deleted. Prior synthetic notifications generated during earlier test revisions are preserved; new submissions use exactly one admin recipient. Direct dispute mutations remain forbidden, including admin mutations reserved for FR-26. Customer/admin SELECT uses the existing authoritative role model, not client metadata role claims. New private tables have RLS and no client grants. All public helpers use explicit empty search paths; privileged attestation is service-only.

`request_id` is the preallocated dispute UUID used in `{auth.uid}/{request_id}/{sha256}.{png|jpg}`; legacy bigint dispute IDs remain compatible with existing admin code. The trusted Edge endpoint uses the database-returned canonical path. Case-varied UUIDs cannot leave differently named orphan folders. PostgreSQL locks/constraints enforce one active dispute per order and exact-request retry idempotency independently of Flutter. Images must exist, have validated content and belong to the draft. Creation, submitted-state change and one admin notification commit together. No approved confirmed admin means a recoverable rejection, not success without notification.

Private bucket `dispute-evidence`: JPEG/PNG, 5 MiB per file, non-public. Client Storage access/signing is denied so raw writes cannot bypass decoding or mint a longer TTL. Authorized Edge operations validate actual PNG CRC/inflate/JPEG decoding and generate exactly 900-second links. Flutter decodes, strips metadata, resizes to 1,600 pixels and re-encodes PNG before upload; original selection is limited to 5 MiB/16 megapixels to bound memory. No client service key. Application code never persists or logs signed URLs. The final expiry probe held its link only in RAM.

Retries retain a per-account encrypted local draft, UUID and confirmed paths. Inputs freeze after preparation, duplicate taps are blocked, and fully uploaded recovery no longer depends on temporary picker files. Ambiguous responses are reconciled before retry/cleanup. Cleanup is owner-authorized, marks abandoned atomically, and never removes submitted evidence. An interrupted cleanup can be retried; late uploads into an abandoned folder remain inaccessible and removable on repeated cleanup. Tombstones/unfinished private objects are retained until authorized cleanup; no global scheduled deletion job was introduced. Abandoned data can consume Free storage, so periodic reviewed operator maintenance/owner discard is required. This is not a claim of automatic retention management.

History/order/chat queries paginate and project needed fields. Chat has one room-filtered channel, 150 ms batching, duplicate-message suppression and disposal. Existing admin dispute mock fallback is unchanged; customer order/chat mock fallbacks were removed.

## Final physical closure

2026-10-13 final APK: Gallery/Camera preview/removal, required order/reason/description validation, network-loss error and same-request Retry, real uploads, exact success message, owned history/details/private image, expired-window exact rejection with no row, dashboard/Inbox/Order History entry, native chat persistence and Realtime, second-customer isolation, and no captured runtime exceptions passed. Native FR-21 Online/Offline/fresh heartbeat advancement and existing valid/approved FR-04 CNIC routing passed. Final hosted rerun: core83, extra23, SQL43, FR0449, FR2146; Flutter46 passed/two conditional hosted skipped; scoped9-file analysis clean. Entire prior FR04 upload/FR21 assignment native scenarios were not repeated; hosted regressions passed. Separate native force-stop draft and 15-minute viewer timer probes were not repeated; automated recovery and actual hosted expiry passed. Evidence: `docs/evidence/FR-25-device.json`, `docs/evidence/FR-25-device-submission.json`, `.fr21-local/fr25/device-final-*.log`. No application code fix/rebuild needed during this continuation.

## Actual verification



Sanitized durable summaries: `docs/evidence/FR-25-*.json`. Detailed local execution logs: ignored `.fr21-local/fr25/`. Final results must be read together with `FR-25-acceptance.md`.

- Hosted core: 83 checks; actual Auth, RPC, Storage, ownership, private signing, duplicate retry/notification and chat checks passed.
- Additional hosted checks: 23 passed, including canonical UUID, unprepared cleanup, real JPEG/PNG, three/four images, cross-customer evidence and distinct-request concurrency.
- Concurrent limit/bucket checks: 13 passed, including exactly ten accepted drafts/two rejected parallel requests, privileged MIME/oversize rejection and owner cleanup.
- SQL: 43 checks (42 assertions and harness confirmation), rollback-only. Covers role denials, direct mutations, expiry/boundary, historical closed requests and original retry. SQL object metadata fixtures are not claimed as Storage proof.
- Actual 900-second expiry: four checks passed with memory-only link, expired rejection and usable fresh authorized link.
- Flutter: 46 passed/two conditional hosted tests skipped; separate authenticated hosted Flutter run: two passed.
- Scoped analysis: nine files, no issues. Full analysis: 96 inherited warnings/info, no errors; nonzero analyzer result retained rather than represented as clean.
- FR-04 hosted regression: 49 passed. FR-21 hosted regression: 46 passed. No encryption key rotation, production migration or TEST reset.
- `flutter pub get`: completed without dependency upgrades. Changed Dart formatting and Python syntax checks executed.

Earlier failed runs are retained: missing GetX extension import in the new test, incorrect harness expectations for valid HTTP 415/400 rejections, unsupported privileged timestamp fixture parameter, and a string-vs-array ACL parsing assumption. Corrected runs passed. The first OneDrive Android build failed with a Gradle parent-path error; the established temporary build copy succeeded. A missing declared empty video directory in that copy was restored; the final frozen-source build succeeded in 52.9 seconds, retaining existing AGP/Kotlin future-support warnings.

Final TEST APK: `.fr21-local/fr25/TezRider-FR25-Test-debug.apk` (verified copy); build original `C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502/build/app/outputs/flutter-apk/app-fr21test-debug.apk`. Package `com.example.flutter_application_1.fr21test`. SHA256 `a7891f5da73ab9546822ba160fff030a9fcccb01451e7388b35ac44c9879e130`; 205,861,985 bytes. Ninety-one source/configuration/credential checks passed. Build source is frozen and matches all 88 application Dart files; TEST URL/public key found, no production URL/service key/Vault key or scanned fixture password. No APK is staged in Git.

**Installation and mandatory native checks: PASS.** Final verified TEST APK installed with preserved data; actual results are in Final physical closure and `docs/evidence/FR-25-device.json`. Earlier disconnected installation and harness lookup failures were corrected without modifying Flutter or database permissions.

## Isolated load qualification

WSL/Docker became available after the user's Windows restart; Docker 29.8.2 ran. An unlinked `tezrider-fr25-local` stack initialized from the authoritative baseline and reviewed migrations through `202610130003`. No hosted load ran. Local Auth fixtures initially failed because GoTrue string-token fields were NULL; only tagged synthetic local fixtures were corrected. Auth rate limits were not relaxed. One thousand customers then uploaded actual decoded synthetic evidence through the real authenticated Edge API.

Unused local console/analytics/mail/Realtime services were stopped to reduce RAM. k6 `tests/load/FR-25.js` uses shared fixture memory, staged load and a synchronized creation burst after reaching 1,000 VUs; creation, own listing and private URL issuance have separate p95/error checks. Expected duplicate-rule rejection is explicitly tagged separately; genuine errors are not hidden. Local signed test JWTs stay out of Flutter/Git and the transient private k6 session file was removed.

**EXECUTED, NOT QUALIFIED:** the run reached 1,000 actual VUs, then the 8 GB PC's memory guard aborted during the burst (exit 1, minimum available physical RAM 5,812,224 bytes). No complete p95/error summary was available; thresholds are NOT VERIFIED. The guard terminated only the test process. Local Supabase stopped with backup enabled and Docker Desktop shut down after confirming no running containers. Data/volumes were preserved. Do not repeat this stress on the existing hosted Free TEST project. The final notification/cleanup revisions were not load-qualified; rerun on an isolated machine with adequate available resources. A local pass would still not certify hosted Free capacity.

Official quotas checked 2026-10-13: [Supabase pricing](https://supabase.com/pricing), [Storage file limits](https://supabase.com/docs/guides/storage/uploads/file-limits), [egress](https://supabase.com/docs/guides/storage/serving/bandwidth). Free includes 1 GB Storage, 500 MB database/shared CPU with 500 MB RAM, 5 GB uncached plus 5 GB cached egress, 50 MB global file limit (our bucket is stricter), 500,000 monthly Edge invocations, 200 peak Realtime connections and two million monthly messages. Unlimited API request count does not guarantee 1,000 simultaneous HTTP operations meet latency targets.

**1,000 simultaneously connected app users do not fit the Free Realtime limit.** A worst-size 1,000-dispute batch also requires approximately 14.65 GiB of evidence alone, exceeding 1 GB. Smaller client-compressed images, reviewed cleanup and bounded active subscriptions reduce use; they do not establish 1,000-user certification. **Assumption:** smaller HTTP-only batches may fit capacity, but actual hosted concurrency/latency remains unverified. A larger existing self-hosted test machine is a zero-subscription qualification option; no paid dependency was added.

## Commands executed / resume

Actual deployment sequence (each invocation preceded by the exact TEST-link guard):

```powershell
git checkout -b feature/FR-25-dispute-submission
supabase db query --linked --project-ref igeisilhtmglgnqvllrx --file <reviewed-rollback-file> --output json
supabase db push --linked --project-ref igeisilhtmglgnqvllrx --skip-vault --dry-run
supabase db push --linked --project-ref igeisilhtmglgnqvllrx --skip-vault --yes
supabase functions deploy fr25-evidence --project-ref igeisilhtmglgnqvllrx --use-api
tests/integration/FR-25-run.ps1 -Kind tests
tests/integration/FR-25-run.ps1 -Kind extra
tests/integration/FR-25-run.ps1 -Kind limits
tests/integration/FR-25-run.ps1 -Kind sql
tests/integration/FR-25-run.ps1 -Kind verify
tests/integration/FR-25-run.ps1 -Kind ttl
tests/integration/FR-04-run.ps1 -Kind tests
tests/integration/FR-21-run.ps1 -Kind backend
tests/integration/FR-21-run.ps1 -Kind flutter
flutter pub get
dart format <changed-Dart-files>
flutter analyze
flutter test --no-pub
flutter build apk --debug --flavor fr21test --dart-define-from-file=<public-TEST-defines>
supabase start --workdir .fr21-local/fr25/local-stack
python tests/load/FR-25-local.py prepare
python tests/load/FR-25-local.py load
supabase stop --workdir .fr21-local/fr25/local-stack
```

Paths represented by angle brackets above are documented in the adjacent logs; they are not commands to paste blindly. Flutter commands used the installed SDK's Dart/Flutter-tools launcher; APK builds used the verified temporary source copy. Never repeat applied hosted migrations when resuming. Protected credentials remain outside Git; no password/token is needed in chat.

## Device checklist (all outstanding on final APK)

1. Reconnect/unlock the named phone; install final verified APK with `adb install -r` (keep data). Expected TEST banner/package and TEST backend only.
2. Sign in using the privately managed synthetic customer. Expected real Customer Dashboard; no credentials shown in evidence.
3. Open Inbox → Chat with Admin; send a synthetic message. Expected real persisted message/Realtime reply and no mock conversation.
4. Open dashboard Disputes and eligible Order History → Dispute. Expected owned delivered orders within 24 hours only; no active disputed order eligible.
5. Try missing reason/description/images and overlong description. Expected clear validation/no dispute or notification write.
6. Select the generated synthetic Gallery image; inspect preview/removal. Capture a synthetic test target with Camera. Expected real valid previews and at most three images.
7. Submit once/rapidly tap twice. Expected disabled in-flight controls/progress, exact SRDS success message, one dispute and one admin notification.
8. Open My disputes/details/evidence. Expected own status/order/description and private images; fresh signing on demand and Retry after expiry.
9. Use an isolated expired synthetic order and interrupt/reconnect submission. Expected exact expired-window rejection or same-request recovery with no incomplete/duplicate submission and safe cleanup.
10. Verify another customer/vendor/rider cannot view evidence; exercise FR-04/FR-21 on device and inspect current process logs. Expected authorization denial, preserved CNIC/presence/assignment and no observed unhandled crashes/Auth/API errors.

Mandatory acceptance is complete; FR-25-only commit is authorized. No push or merge. Safe push after commit: `git push -u origin feature/FR-25-dispute-submission`.

## Changed/new files only

- `docs/FR-25-acceptance.md`
- `docs/FR-25-readiness.md`
- `docs/analysis_report.md`
- `docs/evidence/FR-25-analysis.txt`
- `docs/evidence/FR-25-apk.json`
- `docs/evidence/FR-25-config.json`
- `docs/evidence/FR-25-device.json`
- `docs/evidence/FR-25-device-submission.json`
- `docs/evidence/FR-25-expiry.json`
- `docs/evidence/FR-25-extra.json`
- `docs/evidence/FR-25-flutter.txt`
- `docs/evidence/FR-25-hosted.json`
- `docs/evidence/FR-25-limits.json`
- `docs/evidence/FR-25-load.json`
- `docs/evidence/FR-25-migrations.json`
- `docs/evidence/FR-25-regressions.json`
- `docs/evidence/FR-25-sql.json`
- `lib/controllers/chat_controller.dart`
- `lib/controllers/dispute_controller.dart`
- `lib/screens/chat_rooms_screen.dart`
- `lib/screens/chat_screen.dart`
- `lib/screens/customer/dispute_screen.dart`
- `lib/screens/customer/order_history_screen.dart`
- `lib/screens/customer_dashboard.dart`
- `lib/services/dispute_service.dart`
- `lib/widgets/dispute_evidence_viewer.dart`
- `supabase/functions/fr25-evidence/index.ts`
- `supabase/migrations/202610130001_fr25_dispute_submission.sql`
- `supabase/migrations/202610130002_fr25_delivery_guard.sql`
- `supabase/migrations/202610130003_fr25_upload_reservations.sql`
- `supabase/migrations/202610130004_fr25_notification_and_lock_guards.sql`
- `supabase/migrations/202610130005_fr25_unprepared_cleanup.sql`
- `supabase/tests/FR-25.sql`
- `test/dispute_test.dart`
- `tests/integration/FR-25-device.py`
- `tests/integration/FR-25-hosted.py`
- `tests/integration/FR-25-run.ps1`
- `tests/load/FR-25-local.py`
- `tests/load/FR-25.js`
