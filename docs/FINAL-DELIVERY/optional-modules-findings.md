# Retained optional modules — current verification

Read ../POLICY-DECISIONS.md before every future stage. This work restores the existing Tailoring, Prescription and AI boundaries without adding a new business workflow. Production remains untouched.

## Actual changes

Migration202610250008 adds the missing tailoring measurement/reference fields and private validated-image/immutable-request registries, enables RLS and denies direct client mutations. Trusted RPCs validate live canonical owner/role, immutable retries, image association and allowed lifecycle transitions. Private image bytes are decoded and size/type validated server-side, fetched only after authorization and returned with bounded in-memory lifetime. No public Storage URLs or privileged Flutter credentials.

Customer checkout creates an actual pending_prescription order first, then opens its details for upload to the real vendor-order ID. It no longer requires an impossible upload with an empty order ID before checkout. Vendor review is reachable from the existing Vendor profile and confirms returned persistence. Approved prescription links the actual vendor portion and starts its existing acceptance deadline; rejection keeps the flow pending and visible. Upload success waits for both validated image completion and confirmed prescription row. Existing checklist/OTP/stock behavior is retained.

Tailoring persists real instructions/optional measurements/reference and returns an actual row. Existing Vendor/Rider transitions use a trusted returned-row RPC rather than zero-row direct-write success. No vendor pricing/assignment rule was invented: new unassigned requests remain pickup_requested and explicitly state that pickup/tailor assignment is not confirmed. The existing UI has no approved tailor-selection/pricing workflow; end-to-end tailoring fulfillment remains incomplete.

Removed unsupported Help coupon/promo/2-minute cancellation promises and fabricated external contact addresses; current Help messages reflect available behavior. An operational support contact is still an owner release dependency. New optional display strings have Urdu translations. Checkout validation/cancel/error now always releases its busy flag while preventing concurrent submissions.

## Executed verification

- TEST review25 SQL PASS in rollback; hash-bound fresh review supersedes the inherited earlier review. Migration008 applied once with exact history65, hash e2066110ee472458205d38e26fafb940331440ade476e5c967ca5e61b0b86665. TEST post25 SQL PASS in rollback (same cases, not50 unique).
- Actual TEST HTTP/persistence16 PASS: decoded private prescription image/retry, foreign/anonymous denials, owner+Vendor bounded private byte read, saved prescription retry, Vendor approval and real acceptance deadline, Tailoring measurement persistence without invented assignment, direct raw write denial and precise synthetic order retirement. Images/history/audits retained. No real cash/delivery claim.
- Final affected Flutter51 PASS/0FAIL: optional_modules_test.dart, final_security_test.dart, closure_remaining_states_test.dart and closure_ui_states_test.dart. Seven new optional cases are included; counts overlap previous affected suites. Initial stale tailoring tests and resulting Snackbar cleanup failures were corrected to assert the restored picker-failure/trusted-RPC behavior, not removed.
- Scoped11-file Dart analysis:0errors and3 inherited checkout unused-field warnings. Those exact unused fields were subsequently removed; final whole-project analysis is owned by the parent execution. Native platform sensor/picker or end-to-end optional UI acceptance is not inferred from widgets.
- Deno check optional-private-media/index.ts PASS; function deployed through hosted API to TEST only. Shared image-validation regression evidence remains retained; actual HTTP rejected invalid bytes.
- AI secure client boundary/rate/error tests pass. One real authenticated shopping-assistant call returned HTTP503/codeUNAVAILABLE; no confirmed provider text. No provider key, raw provider errors or secret values were printed. A read-only boolean query confirmed the existing groq_api_key is not configured (no value was selected). AI is BLOCKED pending owner-supplied existing free-compatible Groq credential configured server-side; never in Flutter. No provider key was invented or purchased.

## Evidence

See ../evidence/FINAL-optional-review.json, FINAL-optional-deployment.json, FINAL-optional-post.json, FINAL-optional-hosted.json, FINAL-optional-edge.json and FINAL-optional-assistant.json. Raw private logs/fixtures remain ignored under .fr21-local/final-delivery/optional and .fr21-local/final2. Dedicated reproducible commands: tests/integration/FINAL-optional-modules.ps1 -Action review|deploy|post|edge-deploy|hosted|assistant. Never rerun deploy once migration exists; history/hash gates prevent replay.

The hosted suite uses a newly tagged synthetic pending prescription order on existing test identities. Its exact unused unpaid order is cancelled after verification; no prior order, object or audit is deleted. Tailoring synthetic request and immutable media/audits remain as evidence. No production, Docker, paid dependency, push or merge.

## Credential follow-up (2026-10-26)

After owner configuration on TEST, one bounded actual shopping-assistant request returnedHTTP200/codeOK with confirmed nonempty provider content. No key or provider response text was printed. This supersedes the earlier missing-key/503 blocker; the failed initial readiness observation remains historical. Current evidence: docs/evidence/FINAL-optional-assistant.json. Native AI presentation, provider free quotas and real catalogue availability remain separately qualified; the assistant never fabricates a purchase/action. Temporary public support contact is now owner-configured; unspecified Tailoring fulfillment remains an explicit limitation.
