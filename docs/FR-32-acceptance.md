# FR-32 acceptance — FUNCTIONALLY ACCEPTED

Status2026-10-17: **FUNCTIONALLY ACCEPTED on isolated TEST**. Mandatory inbox,
physical Android and regression checks passed. Optional1000-user qualification
was NOT EXECUTED. Production `arrqsvejrfdbacfwtpcc` was not accessed/modified.
Only isolated TEST `igeisilhtmglgnqvllrx` was used. No push or merge.

Branch `feature/FR-32-email-notifications`, base57914e2. All10 required accepted
commits were verified as ancestors before implementation (FR28=7e809fd,
FR20=fa29b4c). No accepted migration reset/replay/cherry-pick was performed.

## Functional and security criteria

Every entry names implementation, actual verification, evidence and remaining
limits. Raw private fixtures/credentials/APKs are ignored, never acceptance data.

1. **PASS — Authoritative scope:** SRDS PDF2.3.8/FR32/UC06/Table5.6 rows1,4–6,9,29/SEC04/08/10 and Payment.invoiceUrl inspected, including visual class diagram. Section3.3.3 describes HTTPS server communication and names SMS; it does not separately name an email gateway. Registration remains Auth. Evidence: FR-32-progress.md and ignored srds-relevant.txt. No invented discount/tax/gateway workflow.
2. **PASS — Atomic order confirmation:** migration202610160003 order_finalized trigger snapshots trusted checkout data and enqueues one stable order key. Real stock-aware shared checkout and duplicate enqueue SQL assertions; hosted synthetic checkout produced exactly one intent. Evidence local-review.json, hosted-review.json, checks.jsonl. Brevo failure cannot roll back committed checkout.
3. **PASS — Mandatory enqueue failure propagates:** SQL deliberately rejects outbox insertion and asserts account state rolled back; no external call in business transaction. Evidence63 latest rollback assertions. This test injects a DB failure, not a simulated successful response.
4. **PASS — Eligible payment / COD / shared-order policy:** payment_captured checks trusted server-write-only payment state, paid timestamp, reference, matching owner/method/full total and single parent payment. Immutable integer-cent source reconciles every line/vendor subtotal plus one shared fee. Uncollected COD produces no invoice. Repeated captured event produces one invoice number/intent; mutable current prices cannot alter the snapshot. Hosted fixture recorded an explicitly synthetic full COD collection, not a bank transaction. Missing historical source produces SOURCE_REVIEW_REQUIRED. No partial allocation or completed refund is introduced.
5. **PASS — Account actions:** account_transition generates fresh event UUIDs; valid rider CNIC approval sends one combined verification/approval email, never mail merely on upload. block_transition follows actual FR28 SYNCED operation IDs; repeats are distinct, repeated finish is deduplicated, unconfirmed Auth sync emits no mail. SQL covers actual vendor/rider transitions and actual FR28 workflow with synthetic ban/session confirmation. Generic rider approval never claims CNIC validity. Actual hosted vendor rejection/approval, rider rejection/combined CNIC approval, and FR28 block/unblock each emitted exactly one new intent and received explicit user inbox confirmation. The block/unblock actions used actual existing Auth-sync endpoint results, not a direct blocked-flag patch.
6. **PASS — Canonical recipient / sanitization:** server joins canonical Auth user and confirmed matching profile email. Missing/unverified recipient cannot send. Outbox stores owner/event IDs, not recipient lists/CNIC/OTP/address. Shared HTML templates escape dynamic text and have plain alternatives. Deno verifies required wording/escaping/no tracking. Original TEST owner IDs remain for audit; outbound mail redirects only to approved inbox.
7. **PASS — Outbox RLS / mutation grants:** clients cannot read/forge outbox; worker mutations only reviewed service RPCs, private schema inaccessible. Hosted owner/customer/vendor/rider HTTP read denials and unauthenticated worker401 observed. Private RPC grants and bucket protection verified in deployed TEST. Evidence verification.json/checks.jsonl and SQL role assertions.
8. **PASS — Claim/lease/concurrency:** private claim uses bounded2-minute leases and SKIP LOCKED, deterministic priority and max20 RPC limit; deployed worker uses2. Expired preparation leases recover; expired started sends quarantine.6 real independent LOCAL session assertions prove simultaneous duplicate enqueue ->one row, overlapping6-job batches disjoint,40 non-OTP reservations ->7 and20 OTP reservations ->3 under a synthetic10/3 budget. This is real concurrency, not sequential SQL. Evidence local-concurrency.json.
9. **PASS — Bounded retry / uncertainty:** SQL tests backoff, max5 provider attempts, quota deferral/resumption,10-minute uncertain recovery and after-send crash quarantine. Shared Brevo helper distinguishes201-ID/429/5xx/network/permanent4xx/duplicate_parameter. Wire hash and stable provider key prevent changed-message recovery. Database enqueue is deduplicated; exactly-once external inbox delivery is not claimed. Provider201 means acceptance only. Operations document manual reconciliation.
10. **PASS — Shared FR33 quota:** user explicitly approved temporary rolling26-hour policy.300 total/90 reserved OTP/210 nonreserved transactional capacity, atomic serial admission, conservative failure retention and historical OTP debt bootstrap. Same logical provider attempt reuses admission. Original HMAC/nonces/expiry/rate/ownership and legacy extra UTC counter retained. CRLF normalization preserves accepted FR28 canonical/unblocked guards. Hosted mode/budget verified. Provider reset timezone remains unverified; no UTC provider-day claim.
11. **PASS — Protected deployed worker / scheduler:** fr32-email-worker requires dedicated256-bit secret before claiming; key only TEST Edge secrets/Vault, never source. Cron job5 every2minutes calls private dispatch. Existing jobs1 FR30 and4 FR10 have identical schedules, active state and command hashes before/after. No duplicate FR32 job. Evidence deployment.json. Cron transport success alone is not inbox evidence.
12. **PASS — Actual PDF runtime / layout:** pinned pdf-lib1.17.1+fontkit2.0.4, licensed Noto fonts, no paid dependency. Actual Deno sample generation, deterministic repeated bytes, PDF parse and page rendering passed; Unicode sample spans2pages. Legacy fork shaping failed secure Deno defaults and was replaced, without unsafe-proto. Unsupported glyphs fail explicitly. Hosted font bundling/runtime is verified by an actual409751-byte generated PDF, parsed and visually reviewed.
13. **PASS — Hosted invoice correctness:** actual invoice TR-000000000330, order1716, synthetic full collection; two vendor groups, unit/line prices, subtotal240.00, shared delivery200.00 once, total440.00 PKR, captured status/reference/date/customer. PDF downloaded through owner authorization and parsed/rendered. Evidence hosted-invoice-verification.json and ignored hosted-invoice.pdf/PNG. Synthetic identifiers are test evidence, not proof of real provider capture.
14. **PASS — Private invoice storage / independent app access:** deterministic create-only path, immutable number/snapshot, stored hash/length and stable payments.invoiceurl path. Private5MiB bucket; owner/admin authorized server-issued900-second URLs; cross-customer403 and public fetch denied. PDF reached ready while email approval remained false. Existing Order History has Invoice action, no new screen/dependency. Actual Android Invoice action opened the private PDF in Chrome; observed PDF text matched order1716, total440.00 and exactly one shared200.00 delivery fee. Unpaid order action displayed the explicit no-paid-invoice feedback.
15. **PASS — Invoice attachment:** worker requires valid PDF attachment and exact text “Your invoice for Order #X is attached.”; base64 filename/content mocked test passes. Hosted provider accepted the known attached invoice email. User explicitly replied “invoice verified”, confirming actual email receipt and the opened PDF total440.00 with200.00 delivery counted once. No public link substitutes for the attachment.
16. **PASS — Confirmation inbox delivery:** provider ID persisted, then user explicitly confirmed receipt (“recieved”) of the new TEST Order confirmation. This is user-reported inbox evidence, not inferred from provider acceptance. No credentials/code requested.
17. **PASS — Auth unchanged / limitations documented:** read-only sender preflight confirmed active sender and free300sendLimit. TEST Auth public settings email enabled/mail_autoconfirm false; transport/SMTP host/rate configuration not exposed. Do not assert a default/custom SMTP setting without access. Official default SMTP restrictions documented; no SMTP changes made. Shared-account Auth sends outside app admission must be accounted before any production activation.
18. **PASS — Deno automated checks:**76 tests passed including FR32 and existing FR33/FR28/FR30 mocked regressions; both hosted entry points type-check. Actual PDF tests included. Evidence deno-tests.log. Local harness type-check passes; hosted Storage/signing tested separately.
19. **PASS — Flutter dependencies/format/tests:** pub get completed; no dependency changes. Changed Dart files formatted; focused3 and final reconciled full179 tests passed with2 inherited conditional skips. Final analysis:79 findings,0errors/13 inherited warnings/66 notices, no FR32 findings. Analyzer exits1 for inherited findings; no clean-lint claim. Earlier disk/OOM and conflict-source attempts are not counted. Evidence flutter-test-reconciled.log/flutter-analyze-reconciled.log.
20. **PASS — All10 accepted FR regression groups:** FR21=47, FR04=49, FR25=83, FR26=95, FR33=39; FR28 SQL54, FR20 SQL63; FR30 SQL65/HTTP25/Realtime3; FR10 SQL67/HTTP24; FR17 SQL53/HTTP27. Evidence regressions.json plus later regressions-outstanding.json. Initial launcher/tool-loss and obsolete standalone fixture failures are retained as failed attempts, superseded by passing existing accepted HTTP suites; no accepted security assertion was weakened. FR21 uses the already accepted FR30 wrapper with fresh GPS and sibling-ready setup. FR33 HTTP uses mocked provider acceptance; real physical delivery remains separate.
21. **PASS — Physical Android:** fresh TEST APK built, source/credential scanned and installed on AESWNRBAEUPNTGJZ. APK SHA256 c5cfb89afff036683ff00b603c2e847740c4790ceb356ee16e70770d8731c561. Actual Invoice button opened the private PDF with verified440.00 total/shared200.00 once; unpaid order feedback observed. Actual UI checkout created order2112, one confirmation intent, no uncollected COD invoice and cleared cart. Existing notices visible; mark-all-read persisted across reopen for all5 captured notification IDs. A later timeout notice correctly created a new unread entry, not loss of prior read state. Runtime scan found no fatal/unhandled errors. Evidence native-evidence.jsonl/artifact.json. Fresh synthetic delivery2113: native Arrived requested the real email; server recorded OTP USED/order delivered, exactly one shared OTP admission, one delivery proof and one completion audit. User explicitly confirmed “OTP verified”, code entered privately on phone. An intermediate code-entry-screen assertion did not pass while the user completed the flow; it is not claimed as observed. Completion is supported by actual server state and user confirmation. No iOS verification claimed.
22. **PASS (local smoke) / NOT EXECUTED (1000-user qualification) — k6:** actual loopback/mock run completed40 iterations/2VUs,49/49 checks, zero unexpected errors, enqueue p95=57.7359ms against800ms threshold. Intent deduplication, unauthorized worker denial, protected OTP reserve, no quota oversubscription, pre-send lease recovery, provider429 backoff/resumption and no duplicate mocked acceptance passed. Seven mocked acceptances;34 classified deferred jobs after quota exhaustion/recovery fixture. Raw HTTP failure rate0.54% includes deliberately unauthorized401. No real emails or hosted load. Only tracked leftover LOCAL pre-send fixtures were skipped before the run; prior quota usage was zero and preserved. LOCAL fixture cleanup restored prior configuration; harness stopped and original four LOCAL containers stopped. Full1000-VU readiness is not established. Evidence k6-smoke-summary.json/k6-smoke.log.
23. **PASS (documentation) — Free limits / operations:** FR-32-operations.md links official daily/API/attachment/Edge/Storage/Cron/pg_net/Auth limits, budget estimate, retention/Storage bottleneck and safe aggregate queries.1GB Storage/500000 Edge invocations are finite;105paid orders per rolling26h is explicitly an assumption with exactly2mail/order and no other traffic. No financial-history deletion or paid service added.
24. **PASS — Git acceptance prerequisites:** mandatory functional/security/device/email/regression checks passed. Feature-only local commit follows the final explicit staging and secret review; its hash is reported from Git, not embedded recursively in this document. No push/merge. No credentials/private configs/APKs/build outputs staged. OneDrive conflict copies were preserved in ignored archive after user paused sync, then latest reviewed FR32 sources restored; deployed migration is not replayed.

## Evidence and acceptance limits

Portable sanitized evidence is in evidence/FR-32-acceptance.json. Mandatory
functional checks are complete; optional full-load qualification remains unexecuted. Raw evidence currently under ignored .fr21-local/fr32; original
private account fixtures and worker credentials are DPAPI protected outside Git.
User inbox confirmations must be recorded separately from provider acceptance.

All six account-action receipts, confirmation and attached invoice receipts were
explicitly user-confirmed one at a time. Physical FR33 OTP was also user-confirmed
and independently checked in TEST. All10 automated regression groups, final
analysis/179 Flutter tests, APK scan, physical checkout/invoice/notification/OTP
checks and local k6 smoke passed. No mandatory functional blocker remains.

Production migration implications: requires separate authorization, production
credential provisioning, verified quota/reset policy and Auth usage accounting,
Storage/backlog retention planning and lifting the deliberate TEST-only guards
only after review. Nothing in this acceptance authorizes production deployment.

Final checkpoint review: TEST quota/RLS/private bucket and single active FR32 cron
verified again; FR10/FR30 jobs remain active. All38 changed files passed the
protected-credential scan. Temporary mirror cleanup removed a source file after
the initial successful scan. Reverification used its recorded108-source hashes
and the identical APK SHA256, then rescanned the APK and manifest: PASS. No
missing source was recreated to manufacture build evidence. Artifact result
records this recovery method; actual native results remain separate.

Latency limits: load enqueue p95=57.7359ms; separate queue observation31,067ms
includes the mocked30-second429 retry.34 jobs remained safely quota-deferred, so
full queue drain is not claimed. Actual inbox latency was not instrumented; user
receipt confirmation is independent evidence and is not inferred from201.

## Files changed

- `docs/FR-32-acceptance.md`
- `docs/FR-32-operations.md`
- `docs/FR-32-progress.md`
- `docs/analysis_report.md`
- `evidence/FR-32-acceptance.json`
- `lib/screens/customer/order_history_screen.dart`
- `lib/services/invoice_service.dart`
- `lib/widgets/invoice_button.dart`
- `supabase/config.toml`
- `supabase/functions/_shared/fr32-brevo.ts`
- `supabase/functions/_shared/fr32-fonts/NotoNaskhArabic-Regular.ttf`
- `supabase/functions/_shared/fr32-fonts/NotoSans-Regular.ttf`
- `supabase/functions/_shared/fr32-fonts/OFL.txt`
- `supabase/functions/_shared/fr32-invoice.ts`
- `supabase/functions/_shared/fr32-templates.ts`
- `supabase/functions/fr32-email-worker/handler.ts`
- `supabase/functions/fr32-email-worker/handler_test.ts`
- `supabase/functions/fr32-email-worker/index.ts`
- `supabase/functions/fr32-invoice-url/handler.ts`
- `supabase/functions/fr32-invoice-url/handler_test.ts`
- `supabase/functions/fr32-invoice-url/index.ts`
- `supabase/inspection/FR-32-preflight.sql`
- `supabase/migrations/202610160003_fr32_email_outbox.sql`
- `supabase/tests/FR-32.sql`
- `test/fr32_invoice_test.dart`
- `tests/integration/FR-32-artifact.py`
- `tests/integration/FR-32-build.ps1`
- `tests/integration/FR-32-db.py`
- `tests/integration/FR-32-hosted.py`
- `tests/integration/FR-32-load.py`
- `tests/integration/FR-32-local.py`
- `tests/integration/FR-32-native.py`
- `tests/integration/FR-32-run.ps1`
- `tests/load/FR-32-harness.ts`
- `tests/load/FR-32-local.sql`
- `tests/load/FR-32.js`

Final source reconciliation: two additional OneDrive copies preserved outside
Git in the ignored evidence archive. Restored typed Uint8Array upload body and
PDF-available-with-suppressed-email test to canonical files. Both Deno entries
type-check; final76 tests passed with read and narrowly scoped PDF-output write
permission. First rerun had74passes/2 permission-denied PDF writes, not product
failures; corrected permission rerun passed76. Reconciled worker deployed only
to TEST, no SQL migration or scheduler replay. Final feature change set36files.
