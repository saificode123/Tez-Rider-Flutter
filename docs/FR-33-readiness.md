# FR-33 TEST readiness — 2026-10-14

Target: `igeisilhtmglgnqvllrx` only. Branch: `feature/FR-33-email-delivery-otp`, based on FR-26 `aabd6ca`, containing accepted FR-21, FR-04 and FR-25 ancestry. No production connection, reset, migration replay, existing key rotation, push or merge performed.

## Implementation and requirements

Read SRDS FR-33, UC-04, rider sequence phase 4 (rendered visually), Table 5.6 rows 17–19, S-04 and SEC-02/04/10. Approved email substitution is recorded in `FR-33-srds-deviation.md`. Six digits, ten minutes, sixty-second resend cooldown and five total issuance reservations/order are the user-specified engineering defaults; three failed attempts and exact required UI messages remain mandatory. The SRDS does not specify 800 ms p95 or 1,000 virtual users; those are additional engineering qualification targets.

Existing table is singular `delivery_proof`, not a new duplicate table. Two new migrations applied once in dependency order: `202610140001_fr33_email_delivery_otp.sql`, then `202610140002_fr33_dispatch_recovery.sql`. All original seventeen migrations remain intact; total nineteen versions match repository history. Legacy TEST plaintext codes were cleared and constrained NULL; no production records imported or changed. Existing proof receipt convention and FR-25 delivered-at trigger preserved.

Vault-held HMAC-SHA256 key and per-issuance random nonce protect six-digit server-generated codes; constant-time verifier comparison. Protected tables have RLS and no client CRUD grants/policies or Realtime publication. Restricted service-role issuance/dispatch/finalization RPCs resolve confirmed customer identity and assigned approved rider. Safe status/verification RPCs independently authorize callers. All definer functions have empty fixed search paths. Direct delivery bypasses are blocked for ordinary roles.

Issuance progresses RESERVED → SENDING → ACCEPTED/FAILED/UNKNOWN; provider acceptance activates the ten-minute code and invalidates the previous code. Failed/unknown replacement retains the previous usable issuance. External sends are never automatically retried. Same request ID cannot send twice. Dispatch leases recover without duplicate external sends; approval/assignment is revalidated at dispatch. Limits: five reservations/order, sixty-second cooldown, ten new issuance reservations/rider/minute, one hundred new verification operations/rider/minute, 300 UTC-day reservations. These are business limits, not a claim of global gateway DDoS protection.

Verification locks the order and atomically persists incorrect attempts, lockout/admin review, one admin notification/audit, or delivered status, one protected proof and completion notification/audit. UUID retries replay safely without consuming attempts. Genuine independent simultaneous requests verified correct/correct, correct/wrong, wrong/wrong, issuance/issuance and issuance/verification races.

Edge `send-delivery-otp` deployed to TEST with explicit Auth `/user` JWT validation and server assignment authorization. Gateway `--no-verify-jwt` is limited to this function and is not anonymous authorization. Private provider configuration is only in ignored `supabase/functions/.env.test.local` and TEST secrets. New HMAC key stays in Vault; existing encryption keys unchanged. No secrets, plaintext OTPs or full customer emails returned to Flutter. TEST real mail is allowlisted; load tests use only local mock mail.

Flutter reuses RiderController/GetX, bounded timeouts/backoff, stable request IDs, disabled duplicate actions, cooldown, masked server email, remaining attempts and recoverable errors. Rider input is obscured and numeric. Customer dashboard plaintext code was removed. Client does not optimistically mark delivery successful.

## Executed verification

- Hosted FR-33 independent HTTP authorization/concurrency: 39 checks passed; explicit mock provider fixtures, zero real mail.
- Hosted transactional role/security/rule SQL: 73 assertions passed and rolled back; separate HTTP tests supply race evidence.
- Hosted schema/grants/history: seven checks passed, nineteen migration versions, plaintext order/proof count zero.
- Deno Edge tests: fifteen passed, mocked provider only; type checks passed.
- Final Flutter full suite: 86 passed, two conditional hosted tests skipped. Twenty-one new OTP tests included.
- Full analysis: 98 inherited warnings/information, no errors. Scoped changed-source analysis: two inherited customer curly-brace information findings, no warnings/errors. No unrelated lint cleanup.
- Hosted regression: FR-21 47, FR-04 49, FR-25 83, FR-26 96 checks passed. FR-21 test fixture now uses privileged protected issuance rather than obsolete plaintext storage; assertions retained.
- `flutter pub get` passed; changed Dart files formatted.
- Android first build without test flavor failed at Firebase client matching; corrected `--flavor fr21test` build succeeded. Current APK source matches all 92 Dart files, TEST package/URL confirmed, private credentials and production URL absent. APK installed successfully with app data preserved on AESWNRBAEUPNTGJZ.
- Real email: actual Brevo acceptance, received code entered on physical device and validated, order 365 delivered exactly once; one incorrect attempt persisted, one protected proof/audit, idempotent completion retry passed.
- Native lockout: order 366 remained on_the_way, attempts three, LOCKED, admin-review flag persisted; exact two/one remaining and expiry messages observed.
- Native replacement: order 382 unchanged protected old input rejected after real TEST email resend; user-entered new received code completed once, one proof/audit. Rebuilt native network failure and confirmed refresh recovery passed. Customer order tracking displays delivered 382 and active 366 safe email notice, no plaintext code. Final customer-phase logs: fatal/auth/FR33 exceptions zero, one inherited get_vendor_ratings permission denial; whole-app logs are not clean.

## Isolated load qualification

Docker existing unlinked `tezrider-fr25-local` stack started from preserved volumes. Initially only about 211 MiB available; stack stopped without reset. After recovery, small-load preflight with stack running had 504,528,896 available bytes, below its 512 MiB safety requirement. Full profile had 811,237,376 bytes, below two GiB guard. Both k6 profiles NOT EXECUTED; no p95 or error result exists. No hosted load or real emails. Local runner and staged k6 script remain available for a machine with adequate RAM. Stack stopped preserving its volumes. New local migrations/fixtures were not applied because resource guards stopped before those operations.

## Evidence and commands

Sanitized durable evidence under `docs/evidence/FR-33-*`; ignored execution logs/screenshots/APK under `.fr21-local/fr33/`. No private configuration, fixture passwords, email addresses, OTPs or provider IDs belong in Git.

Executed secure runner kinds: inspect/preflight/review/deploy/fixtures/security-fixtures/tests/sql/verify/recovery-review/recovery-apply/refresh-config/artifact/device. Do not rerun deploy or applied migrations. Read-only/retest commands:

```powershell
& tests/integration/FR-33-run.ps1 verify
& tests/integration/FR-33-run.ps1 tests
& tests/integration/FR-33-run.ps1 sql
flutter analyze
flutter test
# Local only; existing isolated stack must be running and unlinked:
python tests/load/FR-33-local.py smoke
python tests/load/FR-33-local.py full
```

Build command used in protected local mirror: `flutter build apk --debug --flavor fr21test --dart-define-from-file=<private public-TEST-defines file>`. Only public client configuration embedded. APK: `.fr21-local/fr33/TezRider-FR33-Test-debug.apk` (205,903,465 bytes); SHA256 `fcb4124f8e28731ee529b834cd6dcb8f7d9b9a35500e9f7d5ac4197b68128e06`.

**FR-33 FUNCTIONALLY ACCEPTED — Ready for the next functional requirement.** Performance/scalability qualification remains NOT EXECUTED. Commit only FR33 work; preserve unrelated `.gitignore` trailing text unstaged; no push/merge.

Final physical acceptance evidence includes order 382 old-code rejection and real received new-code completion, rebuilt network recovery, and actual customer tracking screen. Prior ambiguous/interfered attempts were discarded. Final analysis 16 warnings + 82 information, zero errors; scoped two information. Flutter 86 passed / two conditional skips; 21 OTP tests. Final runtime classification records one existing vendor-rating permission denial from the pre-FR33 baseline; no fatal/auth/FR33 errors. No unrelated vendor-rating permission changes were made.
