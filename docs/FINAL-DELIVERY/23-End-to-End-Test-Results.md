# Current-stage test execution

2026-10-28. Full physical delivery acceptance remains OPEN.

Initial complete Flutter run on unchanged baseline: 681 PASS, 3 FAIL, 2 SKIP. Failures were stale assertions for the previously removed Platform Settings action, replaced assistant suggestion, and newly transmitted bounded history. Tests were updated to assert current behavior while retaining disabled/pending, role-isolation, privacy and error checks.

GPS cancellation reproduction: new initial-enable Stop test FAILED before the fix (busy was already false); the focused post-fix three-file run passed 56 tests. Three additional scenarios were then added: recovery enable, failed enable response and account change. Final complete execution is recorded in `docs/evidence/MASTER-verification.json` after collection; no intermediate count is substituted for that final result.

Final source including the device-discovered pinned login selector: **689 PASS, 0 FAIL, 2 SKIP**, one complete Flutter invocation. The earlier 688-pass run preceded the login correction and is superseded. The focused 20-pass login/language run overlaps the complete suite. Final changed login/GPS source and tests: zero analyzer errors/warnings, one inherited brace-style info. Earlier broader lib analysis: zero errors, three inherited warnings and 31 infos; do not add or relabel the earlier analyzer scope as a new full analysis.

Deno location/routing/assistant: 90 PASS, 0 FAIL in one invocation. No overlap is added to this count. Matrix-inventory check: all 137 unique inherited rows validated; no new application acceptance inferred.

Twelve real TEST assistant responses were captured on the final unchanged server source. Product/price/stock and owned-order sample matched actual authorized RPC responses; invalid order denied. Semantic evaluation and source hashes are in MASTER assistant evidence. Local provider-failure, rate-limit and authorization tests are separate from those successful live responses.

Read-only TEST schema/Storage/history inspection completed. Hosted destructive/race workflows were not rerun before verified backup. This stage sent no real email/push and changed no existing order lifecycle.

Final Android DEBUG TEST build/install and independent installed base.apk hash PASS. SHA-256: `7D137F548B0E71F64A07FAF34E47D47DC29972FEB73F38EFBBAF89C1B19DDCD8`. Final English/Urdu empty-form screenshots visually reviewed; pinned selector visible and RTL correct. Urdu cold-start persistence PASS. Further role/GPS checks retain their separate artifact-bound results; no complete delivery acceptance is inferred.

Actual final-APK GPS observation: foreground 13 events/60s, background 11/60s, recovered 10/60s, zero duplicates. Online confirmed; same process 19875 and foreground location service observed in background. A 91-second network interruption had no default network, exact original Wi-Fi/mobile settings were restored and the same process recovered sharing without Share/Retry input. Actual assigned-rider STOPPED response then customer INELIGIBLE/no location/no topic confirmed cleanup. The physical in-flight Stop race itself was not reproduced; its four local regression scenarios remain separate. The 2-3s cadence target FAILS. See report 24.

The legacy native helper tapped the merged availability card's centre, missing the actual switch. Its initial Online assertions failed and are retained as harness failures; tapping the screenshot-observed thumb confirmed Online. No application online success was fabricated. GPS-disabling, lock-screen/battery, new OTP/proof/delivery/earning, post-pickup cancellation, all-role/every-control acceptance and iOS/APNs remain unaccepted.

Actual seeded Auth/profile/role, inventory, search and address checks: 44 completed application checks and 30 independent verification checks, overlapping and not added together. Two Riders remain pending. Approved catalogue cleanup: 47 quantities retained, independently verified. Encrypted database/Storage/configuration backups and bounded isolated post-seed schema/data restore passed; runtime cryptographic/Storage-upload recovery is not inferred.

A later independent demo recheck failed with a connection reset after 13 successful account/category checks; it is INCOMPLETE and does not replace the earlier completed verification timestamp. Final phone sign-out was not verified: Rider Offline was visually confirmed and server sharing stopped, then the TEST foreground guard failed. No further phone action followed that guard failure.
