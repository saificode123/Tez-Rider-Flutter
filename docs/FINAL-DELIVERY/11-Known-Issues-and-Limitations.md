# Known issues and limitations

- FR14: historical 3610/2109ms requests failed the separate 800ms engineering gate; meaningful physical movement/deviation/rerouting remains unaccepted. Local cache/timing changes do not prove latency or native movement.
- iOS: no macOS build/signing/physical device; APNs/native push availability and minimum OS compatibility remain unresolved. Windows cannot certify iOS runtime.
- Ordinary notification enqueue is now repaired and tested through the accepted Android capability/outbox flow. New physical OS receipt for each event type remains unverified; production remains TEST-gated and iOS/APNs unresolved.
- Production: approved application ID/upload keystore/key.properties, production schema/history/security/config reconciliation, backup restore review and explicit deployment authorization missing. No production release artifact/deployment.
- Zero cost versus SRDS 99.9% managed SLA is unresolved; free-provider quotas and project pausing apply. No excluded Docker/1000-user run or scalability guarantee.
- The>=80% domain/data coverage target is not met/certified: measured instrumented services73.63%, models45.00%; uninstrumented files excluded. Timed first-order<3min and full device/battery matrix remain unverified.
- Owner pay/moderation/cart policies are now explicit; actual implementation/deployment/native acceptance must be checked in current findings. Existing historical delivered orders are not fabricated into new earning records. Earned records are not payouts.
- Post-pickup cancellation now has a trusted unpaid-COD RPC and Customer/Vendor confirmation UI. Both roles/stock restoration/assignment cleanup pass rollback tests; current native UI remains to be exercised. Paid/collected cash requires Admin review.
- Tailoring requests/private reference persistence and prescription upload/review are verified; Tailoring assignment/pricing remains unspecified. AI now returns actual200/confirmed provider response after owner configuration; initial503/missing-key observation remains historical. Temporary owner-authorized support contact is now configured in app_settings.support_email; native rendering remains pending.
- Full local suite600PASS/0FAIL/2SKIP; additional affected37PASS includes10 new email tests,27 overlap. Analysis0errors/4warnings/34infos. Build/native results remain pending until recorded. Actual external email confirmation and SDK-refresh recovery remain unverified.

Status: NOT READY. Every unresolved mandatory clause is explicit in 01-SRDS-Requirement-Compliance.md. A delivery demonstration is not production acceptance.
