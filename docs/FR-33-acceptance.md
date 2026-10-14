# FR-33 acceptance — 2026-10-14

**FR-33 FUNCTIONALLY ACCEPTED — Ready for the next functional requirement.**

Mandatory functional/security/native criteria passed. Performance/scalability qualification remains NOT EXECUTED; not fully accepted for the 1,000-user engineering target.

Email substitution is explicitly approved in `FR-33-srds-deviation.md`. Functional/security requirements are separate from 800 ms p95 and 1,000-user engineering qualification. No unexecuted scenario counts as passed.

| Criterion | Implementation | Actual verification | Result | Evidence / limitation |
|---|---|---|---|---|
| Approved email substitution / required delivery rules | deviation document, controller, migrations | SRDS references inspected; exact native two/one remaining and lockout messages | PASS | readiness; device evidence |
| Server-only secure six digits incl leading zero | issue_delivery_otp, Vault HMAC/nonce, fr33_equal | SQL verifier/source validation, format tests | PASS | SQL 73 / OTP tests; no client code generation |
| No plaintext DB/client/Realtime/log secrets | NULL legacy constraints; protected tables/grants; safe Edge response; customer removal | seven hosted grants/history checks, SQL role denials, Deno secret redaction, APK scan | PASS | schema-verification / artifact JSON; no protected OTP table publication |
| JWT, assigned approved rider, canonical confirmed customer recipient | Edge Auth validation + protected RPCs | customer/vendor/admin/other-rider/anonymous denials; dispatch revoked-approval check | PASS | hosted 39 / SQL 73; TEST allowlist retained |
| Ten-minute validity / sixty-second cooldown / cap five | server functions | expiry/cooldown/cap SQL; native disabled resend countdown | PASS | SQL and server-cooldown screenshot; limits are requested defaults |
| Per-rider limits / conservative daily quota | delivery_otp_rates/budgets | issuance/verification limits and 300-budget SQL | PASS | SQL; not global gateway DDoS protection |
| Provider consistency and safe idempotency | reserve/start/finish, dispatch leases | Deno acceptance/rejection/timeout/finalize failure; SQL lease crash + failed/unknown old-code retention | PASS | fifteen mocked tests / SQL; actual inbox not inferred from mock |
| Real mail acceptance and inbox code | deployed TEST Edge + active sender | user entered received email code on phone; order 365 delivered | PASS | real-email-acceptance + device-success; delivery delays/spam remain possible |
| Wrong attempt persists / max three / review/audit/one admin notice | verify_delivery_otp | native order 366 LOCKED attempts three, undelivered/admin flag; one notice; SQL audit | PASS | device-lockout / hosted SQL |
| One delivery transition/proof/audit/customer notice atomically | verify_delivery_otp; existing delivery_proof | real order 365 one proof/audit; SQL notification and transaction assertions | PASS | device-success / hosted 39 / SQL 73 |
| Correct/correct, correct/wrong, wrong/wrong races | order row lock, stable verification ID | genuine separate concurrent HTTP requests | PASS | hosted-tests 39; SQL sequential tests not race evidence |
| Issuance/issuance and issuance/verification races | order lock / unique active/reserved indexes | genuine parallel HTTP requests with cooldown-aged dedicated fixture | PASS | hosted-tests 39; privileged mock provider only |
| Retry after uncertainty / delivered replay no duplicate side effects | verification cache + client fixed UUID | Flutter timeout replay, hosted identical wrong retry; actual completed order ALREADY_DELIVERED one proof/audit | PASS | tests, actual device duplicate check |
| Replacement invalidates prior usable code only after provider acceptance | finish_send | SQL replacement/failed replacement passed; physical unchanged known-valid old input rejected after real TEST resend, one persisted failure | PASS | device-replacement-old JSON / replacement-old screenshot: initial issuance privileged mock fixture, replacement real Brevo; earlier real issuance invalidation also confirmed |
| Rider login/arrival/real request/numeric obscured entry/server-confirmed completion | GetX flow/rider dashboard | physical TEST login, Arrived, mail, wrong code, correct received code | PASS | device evidence / installed APK |
| Offline recoverable error and retry | flow timeouts/backoff | rebuilt APK disconnected refresh error and restored-network confirmed refresh; old input invalidation still enforced | PASS | network-restored-server-state / network-recoverable-error screenshots; original network settings restored |
| Customer no plaintext OTP, tracking preserved | customer_dashboard | actual customer Orders tab shows delivered order 382 and active order 366 email notice; no six-digit plaintext code | PASS | customer-email-no-plaintext-code screenshot and device observations |
| Runtime log safety / latest APK installed | isolated TEST flavor | current source match + target/secrets scan; rebuilt install success; final PID logs zero fatal/Auth/FR33 exceptions | PASS | one inherited get_vendor_ratings permission denial remains; whole-app logs are not clean |
| FR-21/04/25/26 preservation | existing components, only essential FR21 test-fixture change | hosted 47/49/83/96 checks, final 86 Flutter tests | PASS | regression execution logs; two conditional hosted Flutter tests skipped |
| Migration history and TEST-only deployment | two new reviewed migrations / exact-ref guards | nineteen expected versions, original seventeen preserved; Edge redeployed TEST only | PASS | schema-verification; no reset/replay/production access |
| Free service limits / sender verification | conservative budget / provider preflight | active sender and Free 300 API preflight; official docs checked | PASS | deviation doc; own-domain DNS NOT VERIFIED; inbox never guaranteed |
| 800 ms p95 / <1% unexpected errors / staged 1,000 users | loopback k6 + restrictive Deno SMTP mock | resource preflight refused smoke/full before traffic | NOT TESTED | local result JSON; insufficient RAM, NOT EXECUTED, nonmandatory engineering target |

## Corrections and rejected evidence

Network recovery exposed a stale status-refresh message. The flow now clears a resolved connection error on confirmed refresh while preserving uncertain verification until its original request retries. Added two meaningful tests; final full Flutter suite 86 passed / two conditional hosted skips. The first added-test run failed due a missing GetX extension import in test setup; corrected map assignment and reran successfully. Initial APK build without the test flavor failed; corrected flavor build succeeded. These failures were not counted as passes.

A concurrent hosted rerun initially used the physical rider fixture and changed its active order through Realtime. The wrong-attempt hosted check failed and the physical replacement check was discarded. Hosted tests now use a separate synthetic security rider; subsequent 39 checks passed. Only explicitly tagged FR33 synthetic assignments were detached to isolate the device rider. No unrelated account, production record, or global policy was changed.

## Completed physical evidence and limitations

Order 382 is the conclusive unchanged-input invalidation test: protected initial mock-provider issuance (no initial inbox claim), code entered only by the private test runner and held in memory/obscured field, actual sixty-second cooldown, real allowlisted TEST Edge/Brevo replacement, unchanged old code rejected with exactly one persisted failed attempt and two remaining. The user then entered the newly received email code: order delivered once, one protected proof and one audit. Earlier real-email orders 365/367 also verified receipt, actual completion and previous real-issuance invalidation. Order 381 had completed before the unchanged-input test and was not counted as rejection evidence. No OTP was logged, printed in chat or stored in plaintext.

Rebuilt APK network test passed: recoverable error while disconnected, original Wi-Fi/mobile-data settings restored, confirmed status refresh clears the old error. Native customer Orders shows delivered order 382 and active order 366's generic email message without a code. Screenshot and hosted evidence are saved under `docs/evidence/FR-33-*`.

Final Android PID logs: zero observed fatal/authentication/FR33 or unclassified API exceptions, **one inherited vendor-rating API permission denial**. Baseline `202610080001_tezrider_baseline.sql` line 3803 revokes all public-function execution; FR33 migration ACL changes exclude `get_vendor_ratings`, and its controller is unchanged. This is recorded, not hidden or counted as clean whole-app logs. Vendor ratings are outside the authorized FR33 scope and were not changed.

Own-domain DNS authentication NOT VERIFIED; active sender and actual inbox-code verification passed. Neither future inbox timing nor 1,000-user Free capacity is guaranteed. Engineering load qualification remains NOT EXECUTED because RAM guards refused both profiles before traffic.

## Manual checks after acceptance

1. Sign into a confirmed approved TEST rider: dashboard loads actual status.
2. Open its eligible synthetic delivery and tap Arrived: code request accepted, masked email, countdown; buttons disable while busy.
3. Check authorized inbox/spam: six-digit code arrives; never expose it in chat/logs.
4. Enter an incorrect code: remaining decreases; repeating the same uncertain HTTP request does not consume another attempt.
5. Third incorrect attempt: expiry message, undelivered order, admin review and one notice.
6. Request a new code after cooldown: prior code rejected; newly emailed code valid.
7. Confirm valid code: server-delivered order, one proof, one audit and one notice; retry remains idempotent.
8. Disconnect network and refresh/retry, reconnect: recoverable error followed by confirmed actual state, no duplicate send.
9. Customer tracking: email message without any code; order reflects server delivery state.
10. Check runtime logs and previous accepted workflows; report actual failures rather than assume success.

Mandatory acceptance complete; commit only FR33 changes on the existing feature branch. No push/merge. Pre-existing trailing command text in `.gitignore` is preserved as an unrelated unstaged change; only the required private-config ignore rule belongs to the FR33 commit.
