# Vendor/Rider Favorites — proposed authorization contract

Prepared 2026-11-05. Not implemented or deployed. Product Favorites already use the existing `favourite` table and are restored separately.

The existing `public.favorites` table has UUID `user_id`, UUID `favorite_user_id`, `type`, `created_at`, and a unique actor/target pair. TEST currently has zero rows and no verified role/history contract. The final delivery request explicitly requires approval before introducing this model.

Proposed bounded change:

- Reuse this existing table; bind both UUID columns to Supabase Auth identities through trusted `users.auth_user_id` mappings.
- Permit Customer-owned favorites only. `type` must match the target's server role: Vendor or Rider.
- A Vendor must belong to an actual order in that Customer's history. A Rider must belong to an actually delivered order for that Customer. No account directory, fabricated relationship, role change, CNIC disclosure or location disclosure.
- Owner-only read/add/remove; verified live session and unblocked account required. Anonymous, unrelated Customer, Vendor and Rider mutations denied. Keep unique actor/target pairs and idempotent saves.
- Display only permitted public name, store name, profile image and rating. Unavailable targets remain removable without exposing private information.
- Add the actions to existing order details/history and the existing Favorites view. Do not create a matching, payment, messaging or scheduling workflow.
- Verify through rollback SQL, real authenticated TEST HTTP and app tests before acceptance. No production operation or external notification.

Approval applies to this contract and the matching non-destructive TEST migration, not to production deployment or any account approval.

Owner response, 2026-11-05: **Approve this TEST-only implementation**. Implementation and acceptance are recorded separately in FINAL-CUSTOMER-ACCEPTANCE.md.
