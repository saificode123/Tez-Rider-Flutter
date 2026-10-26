# Ordinary event push and persisted cart policy

Owner policies: `docs/POLICY-DECISIONS.md`. Work targets authorized TEST `igeisilhtmglgnqvllrx` only; production untouched.

## Implementation

Migration `202610250009_final_delivery_event_push.sql` applied once after008; exact migration prefix66 at deployment. Source SHA256 `21d00454abbe14b77f5ee292d347556fbf2b6b5f64b65a0722520886c49aaa41` matches the reviewed candidate. No accepted migration was replayed and no historical inbox/job backfill occurred.

- Private RLS-enabled `final_delivery_private.cart_settings` persists every approved cart decision: no reservations, zero reservation seconds, no expiry timer, add-time stock checks, atomic placement revalidation/decrement, cancellation restoration and named shortages. Constraints preserve the accepted FR07/FR17 design; enabling an unsupported reservation workflow requires a separately reviewed implementation. Only approved Customer gateway reads may use `final_delivery_cart_policy`; direct application/service table access is denied.
- `pay_settings.maximum_amount` explicitly stores NULL and constrains it to NULL, preserving the owner's no-maximum rule without changing existing or frozen earning calculations.
- A narrow BEFORE INSERT trigger assigns a transport UUID to new canonical non-broadcast notifications with actual nonempty title/message when their existing transport UUID is absent. Existing timeout/stock/cancellation UUIDs are preserved. Existing notification ownership and denied direct INSERT grants remain authoritative.
- FR10 had already extended the accepted FR30 durable outbox, claim, capability resolver and FCM transport to `coalesce(broadcast_id,order_push_event_id)`. New ordinary order/assignment/dispute/delivery/account/system notices now enter that same flow. No new sender, resolver, client parser, secret or external dependency was introduced. FCM still contains only a transport UUID hint; message text is fetched through the existing installation-secret capability bound to the live owner/Auth session.
- Existing lease/retry limits, one-hour job expiry, read-state suppression, secret hashing, account switch/rebind, logout/unregister, session deadline, blocking and late-device exclusion remain unchanged. Provider acceptance remains distinct from device receipt.

## Verification

- Candidate **28 rollback SQL PASS**; deployed **28 post SQL PASS** repeat the same cases and are not summed. Fixtures/leases and simulated provider outcomes rolled back; no provider call or physical delivery is claimed. Evidence: `docs/evidence/FINAL-delivery-event-push-review.json` and `FINAL-delivery-event-push-post.json`.
- Cases cover persisted cart/no-cap settings and grants; six ordinary notification types; one durable snapshot job per recipient installation; existing UUID preservation; own/foreign/wrong-secret reads; denied client notification forgery; worker claim/eligibility/finish; read/expiry/absolute-session-deadline/rebind denials.
- Actual HTTP fixture verification: **8 PASS**, with final persisted cleanup readback, recorded separately in `FINAL-delivery-event-push-hosted.json`. The isolated fake installation's jobs are committed with a future due time before external visibility so the test does not send to FCM. It is subsequently unregistered and only its exact synthetic jobs are skipped. Synthetic inbox/Auth/audit records remain, clearly marked.

## Limits and rollback

This closes the missing ordinary-event enqueue path using the already accepted Android transport. It does not claim a new physical foreground/background/terminated observation for every event type; previous Android broadcast/timeout/stock transport evidence remains retained with its exact scope. Production registration/transport remains deliberately TEST-gated. iOS/APNs and free-service platform availability are unresolved separately.

Rollback must use a reviewed corrective migration preserving notification/job/audit history. Do not erase delivered notices or private installations. A source revert alone does not reverse applied settings/trigger state. No production deployment is authorized by this report.
