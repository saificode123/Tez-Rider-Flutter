# Stage2 onboarding workstream (S2-01)

Authoritative scope: SRDS FR01/03/27, registration use case and approval decision rows; approved Stage2 roadmap. Implementation is in progress, not accepted by source presence.

- `final2_complete_registration` requires a real live confirmed Auth identity, derives the profile from auth.uid, creates only Customer/Vendor/Rider roles, and leaves new Vendor/Rider pending. Vendor profile/store insertion is atomic, serialized on that Auth identity, and retry-safe. Existing canonical role/status cannot be overwritten from editable metadata. Explicit owner form submission can update only name/phone; ordinary login metadata does not overwrite saved fields.
- New vendor store requires bounded name/address and stays inactive until approval. Existing legitimate profile/store data is preserved. No broad vendors/users table grants added.
- `final2_review_vendor` requires canonical Admin, persists rejection reason, synchronizes approval/store state, and creates the owned in-app notice atomically with retained critical audit and FR32 account email triggers. Same decision/reason replay has no duplicate effects; a changed reason cannot silently replace a decision. Old `final1_review_vendor` signature retains approval/no-op compatibility but cannot bypass required rejection reasons.
- Signup no longer makes anonymous/direct users/vendors upserts or hides persistence failures. Verified login resumes registration; the existing signup screen supplies missing details. Rider CNIC draft/private upload remains FR04; raw Vendor CNIC is not collected as an invented registration requirement.

## Verification levels

Candidate SQL review:19PASS, real synthetic live claims, full transaction rollback. Auth fixtures are explicitly Admin-confirmed test accounts; this does NOT establish a fresh real-email inbox verification. Focused Flutter/affected regression execution is recorded under ignored `.fr21-local/final2/`. Hosted persistent lifecycle:27PASS, including concurrent idempotent completion, real customer/vendor/Admin denials, rejection/approval, owned Realtime notice, unrelated-recipient denial and audit/notice exactness. Post-deployment rollback SQL:19PASS (same candidate cases). Combined affected Flutter cohort:92PASS across ten files, including22new onboarding cases; see `evidence/FINAL2-01-results.json`. Fresh real-email native signup, first login/pending routing, actual store persistence, reasoned rejection display, approval recovery, owned notice rendering and app-restart Vendor routing have now passed on AESWNRBAEUPNTGJZ. Final reads confirmed one store, two owned notices and two canonical Admin decision audits. S2-01 is accepted for this bounded Vendor onboarding/review workstream; this does not accept Stage2 overall.

## Deployment and recovery

Applied once on TEST:202610230004_final2_registration.sql (45→46versions), followed by catalogue005 (47versions). Baseline45versions verified; do not replay0004 or any previous migration. Deployment helper requires exact current history and a review proof matching the migration file hash; post-deployment SQL must pass.

No destructive change, Auth configuration change, bucket change, RLS relaxation or provider secret change. No production target. Existing profiles/stores and accepted evidence must never be deleted to undo this change.

Recovery, if a confirmed regression occurs: suspend new TEST registration/review entry points while preserving records; restore only the previous final1_review_vendor function definition from the protected baseline catalog in a reviewed corrective migration, and use the matching prior TEST app. Revoke new API execution only after checking client dependencies. Never reapply the whole earlier security migration, delete Auth/application records, reset migration history or silently roll back the critical audit. No recovery action is executed automatically.
