# FR priority-list verification

2026-10-28, Asia/Karachi. The owner supplied the contents of FR.docx in chat during this stage. **The binary Word document was not inspected.** The original Word SRDS is still unavailable. The supplied Completed labels are historical claims, not new acceptance evidence.

The supplied list contains 13 priorities:

- FR-04: CNIC document workflow exists in `cnic_document.dart`, `cnic_document_screen.dart` and `fr04-cnic`. Retain original bounded TEST acceptance; current bucket metadata confirms private storage. New upload/admin/expiry journey NOT RUN.
- FR-10: timeout/cancellation/refund implementation and historical SQL/HTTP evidence exist. Retain the approved COD/manual refund deviation; no provider settlement is claimed.
- FR-13: the supplied simulated-GPS claim is stale against current source. Android uses Geolocator's real position stream with a 2500ms requested interval; client delivery throttling is 2300ms. This stage fixes an in-flight consent-revocation race. Current physical foreground/background/recovery observation received 13/11/10 events with median intervals 3.946/5.422/5.218 seconds: strict 2-3s cadence FAIL. Server consent cleanup confirmed. Physical in-flight Stop race and iOS acceptance remain unverified. PARTIAL; report 24.
- FR-14: server-derived Geoapify geometry and ETA exist; no production movement simulation is used. Current actual HTTP route samples were 4265/3047/2484ms, failing 800ms. First provider stage was 753.26ms; full client rendering and load percentiles remain unmeasured. PARTIAL; report 24.
- FR-17: atomic checkout/restoration implementation and historical concurrent/duplicate/shortage evidence retained; new hosted transaction run NOT RUN.
- FR-20: radius expansion/admin notification implementation and original evidence retained; new timed hosted scenario NOT RUN.
- FR-21: real presence RPCs/heartbeat/recovery exist. New local location-consent regressions are bounded; no fresh full presence acceptance inferred.
- FR-25: actual dispute form, reason/evidence workflow and private storage exist. New submission/admin journey NOT RUN.
- FR-26: database-backed resolve/reject implementation exists. Retain approved manual COD refund scope; no fake refund/provider settlement is accepted.
- FR-28: trusted blocking, session boundary and original audit/security evidence retained. New hosted block/unblock scenario NOT RUN.
- FR-30: broadcast persistence/dispatch exists; bounded historical Android acceptance retained. Final-device receipt, production registration and iOS/APNs remain open.
- FR-32: server email/invoice implementation and historical delivery evidence retained. This stage sends no email and makes no new inbox-delivery claim.
- FR-33: `docs/FR-33-srds-deviation.md` records explicit owner approval of secure email instead of SMS. Preserve APPROVED DEVIATION, not ordinary PASS. Flutter receives no plaintext delivery OTP from the existing flow. New physical OTP/proof journey NOT RUN.

Original feature evidence is referenced per row in reports 15 and 19. No Completed annotation is promoted solely from code or file existence.
