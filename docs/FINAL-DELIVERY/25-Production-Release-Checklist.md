# Production release gates

Current continuation (2026-10-29): see [report 27](27-Release-Execution-Ledger.md) and [report 28](28-Remaining-Release-Dependencies.md) for the newer APK, implementation and fresh results. The dated checklist below remains historical.

2026-10-28. **NOT READY FOR PRODUCTION.**

- OPEN: all 137 clauses accepted in release scope. Retained baseline is 76 historical bounded passes, 17 deviations, 43 partial, one blocked.
- OPEN: original Word requirements comparison. FR priority text supplied by owner; binary FR.docx not inspected.
- OPEN: current physical foreground/background GPS, recovery/battery and routing latency/deviation acceptance.
- OPEN: full current customer/vendor/rider/admin order-to-proof/email-OTP/delivery/new-priced-earning journey and post-pickup cancellation.
- OPEN: every required rendered control, full accessibility/RTL/large-text/device matrix, all relevant performance/capacity/SLA gates.
- BOUNDED PASS: encrypted database/Auth/roles/configuration exports, all 259 Storage byte integrity checks, and isolated post-seed schema/data/count restore. Exact 47-product reversible cleanup approved/applied/verified. Seven fictional accounts, twelve products, two addresses verified. Runtime/Vault/document/Storage-upload recovery, portable handover and full physical four-role acceptance remain OPEN.
- OPEN: protected production schema/history/grants/secret/config review, reviewed dry-run, rollback rehearsal and separate deployment authorization.
- OPEN: owner-approved Android production application ID, upload keystore/private signing configuration, production Firebase and signed release verification. No signing identity was generated or changed.
- OPEN: iOS supported build/device/signing/APNs acceptance or explicit approved exclusion. Android success is not iOS acceptance.
- BOUNDED: final server assistant live evaluation and local fault/authorization regressions; see MASTER evidence, not an unrestricted AI reliability guarantee.
- BOUNDED: Flutter/Deno regression and source analysis results in report 23 and MASTER-verification.json.

The final artifact `build/delivery/test/app-fr21test-debug.apk` is a DEBUG TEST build. SHA-256 `7D137F548B0E71F64A07FAF34E47D47DC29972FEB73F38EFBBAF89C1B19DDCD8`; build/source manifest, installation and independently read installed base.apk hash PASS. Package `com.example.flutter_application_1.fr21test`, display name TezRider. It is not a production APK/AAB. Original report 17 hashes remain historical. Build metadata recorded pre-commit HEAD 294f289 while current-file hashes include the subsequently committed cd3f9ac changes; source hashes, not that earlier HEAD alone, bind this artifact.

Do not publish, modify production, send external notifications, introduce paid services or create production signing credentials under this checklist.

Free-service limits rechecked 2026-10-28: [Supabase](https://supabase.com/pricing) lists 500MB database, 1GB file storage, 5GB egress and 500,000 included Edge invocations; Free projects may pause after one week of inactivity. [Geoapify](https://www.geoapify.com/pricing/) lists 3000 credits/day, up to five requests/second and required attribution for free commercial production use. [Brevo](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan) lists 300 email sends/day. Actual project-wide consumption, release workload, capacity and 99.9% SLA are not certified by these advertised quotas. No paid subscription or store publication was performed.
