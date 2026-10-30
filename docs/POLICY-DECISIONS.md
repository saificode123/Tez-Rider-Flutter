# TezRider owner-approved policy decisions

Approved 2026-10-25 (Asia/Karachi).

**not in the SRDS, approved by the project owner; modeled on the publicly described base-plus-distance structure of food delivery platforms, NOT Foodpanda's actual rates**

Read this document at the start of every future stage. The owner's authoritative instruction is preserved verbatim below. Implementation and verification status belong in FINAL-DELIVERY, not in this policy text.

---

These are the approved TezRider policies. Treat them as authoritative, save them verbatim in docs/POLICY-DECISIONS.md (marked "not in the SRDS, approved by the project owner; modeled on the publicly described base-plus-distance structure of food delivery platforms, NOT Foodpanda's actual rates"), store every value in a server-side settings table (not hard-coded in Flutter), and do not ask again. Read docs/POLICY-DECISIONS.md at the start of every future stage.

1. RIDER PAY (base plus distance)
- Earning per delivery = base_amount + (per_km_rate x delivery_distance_km), rounded to the nearest PKR.
- base_amount = PKR 60. per_km_rate = PKR 20. per_minute_rate = 0. Peak, weather, bonus and tip components exist as settings but are all 0 and disabled.
- delivery_distance_km: use the route distance from vendor to customer already computed by FR-14 (stored when the delivery starts); if no route exists, use the straight-line distance from the vendor to the delivery address; record which method was used and freeze the distance at delivery start so later route recomputes do not change the pay.
- Minimum earning per delivery: PKR 80. No maximum.
- When earned: at the moment the order becomes DELIVERED (after the verified OTP and proof). One earning record per delivered order, idempotent.
- Cancelled orders, undelivered orders: no earning. Exception: if the customer or vendor cancels AFTER the rider has already picked up the order, credit the rider the base_amount only (a configurable setting). If a refund or dispute is resolved after delivery, do not claw back automatically; flag it for admin review.
- The rider sees the expected earning on the job card BEFORE accepting (transparency, per the SRDS goal of transparent earnings).
- Earnings history shows each delivery with order id, date, distance, the calculation parts and amount, plus a total. No payout system: earnings are records only, and the app must not claim money was paid out.
- Multi-vendor orders: pay per delivery task as already assigned (one rider per assignment). Do not invent splitting rules beyond the existing assignment structure.

2. AUTOMATIC LOW-RATING BLOCKING (vendors and riders)
- Evaluated once a day by a scheduled server job.
- Minimum reviews: 10 ratings inside the window. Fewer than 10: never blocked.
- Time window: last 30 days. Threshold: average rating below 2.0 out of 5.
- On breach: write an audit entry (reason "auto_low_rating"), notify all admins, and block through the existing FR-28 mechanism. Never auto-block admins.
- Active work: if the user has active orders or deliveries, do not cancel or reassign anything; apply the block once none remain.
- Unblock and appeal: no in-app appeal workflow. The blocked user contacts support through the existing Help channel, and an admin decides. Only an admin can unblock, using the existing FR-28 screen. After an unblock, ignore ratings given before the unblock date so the user is not blocked again by the same old ratings.

3. CART STOCK RESERVATION
- Duration: none. Carts never reserve stock. Stock is checked at add-to-cart, re-validated and decremented atomically at order placement, and restored on every cancellation (the FR-17 design). There is no expiry timer, because nothing is held.
- If an item sells out while in a cart, checkout fails cleanly and names the short items.

Optional modules: keep Tailoring, Prescription upload and AI Assistant working and covered by regression checks, but do not extend them. Defer wishlist and saved stores, gift ordering, promotions and bank details unless my Stage 0 dead-controls table says IMPLEMENT. Biometric login is required.

Continue with the remaining work using these rules.


## Owner addendum — temporary public support contact (2026-10-26)

The Help screen will show [urrehmansaif406@gmail.com](mailto:urrehmansaif406@gmail.com) as a temporary contact for blocked users. Please confirm the permanent support inbox when it’s ready. The address is stored in app_settings (support_email), so replacing it is a one-row change and doesn’t need an app release.

## Owner addendum — bounded TEST acceptance (2026-10-29)

The owner authorized exactly one controlled COD TEST delivery in `igeisilhtmglgnqvllrx`: Chicken Biryani, quantity one, product price PKR 350, existing approved delivery-charge calculation. Reuse the valid saved cart; do not create a second order after a retry/interruption.

For that order only: at most two OTP emails, one confirmation email and one invoice email, exclusively to the verified owner-controlled TEST inbox after configuration/recipient verification. Order-related push is limited to the connected owner TEST Android phone. No SMS, real online payment, unrelated broadcast or production operation.

When asked whether to reuse the retained approved synthetic Rider fixture, the owner answered: **"I will provide a genuinely verified Rider"**. Synthetic identity fixtures are therefore excluded from this delivery. Do not fabricate CNIC approval or bypass eligibility; wait for the genuine Rider dependency while continuing independent work.

The original GPS 2–3-second target and routing 800ms target remain active. The owner has not approved the proposed relaxed targets. Implementation and acceptance remain separately recorded in FINAL-DELIVERY.

## Owner addendum — existing Rider email and password (2026-10-29)

The owner corrected the Rider email to the existing two-r address `urrehmansaif406@gmail.com`, repeating that address rather than accepting the suggested alias. Do not create an alias or duplicate account, or change the Customer's role. Canonical account identification and verification evidence are recorded separately, not inferred from an email mask.

Do not request, print, log, commit or reuse the previously exposed Rider password. The owner will enter a strong, unique replacement through a secure mechanism. No agent password sign-in for this Rider. One genuine verification-email resend is authorized separately from the existing delivery-email limits if the account needs it; do not manually confirm email or fabricate delivery. Production remains protected and all earlier delivery/GPS/routing limits remain unchanged.

## Owner addendum — physical pickup and notification check (2026-10-29)

For the one controlled TEST delivery, the owner confirmed **"Yes, use this pickup point"** for the phone's current stationary position as Sana Foods' pickup. The owner selects the actual destination through the phone's delivery-pin confirmation.

After the prepared notification check was explained, the owner explicitly answered **"Approve this TEST-only check"**: read the connected TEST app's notification token locally and compare only its SHA-256 hash with the TEST database, publishing neither value and sending no notification. This approval does not authorize unrelated notifications or production access.

The owner also explicitly answered **"Approve sanitized evidence push"** for publishing TEST order/account IDs, status and review timestamps, stock counts and email-delivery status to `feature/final-2-functional`. Exclude passwords, tokens, CNIC contents, coordinates and recipient addresses from that delivery evidence.

## Owner addendum — leave the controlled delivery unfinished (2026-10-29)

After stating they cannot reach the confirmed destination, the owner selected **"Leave delivery pending and stop location sharing"**. Retain order 3180 for later normal completion; do not cancel, reset its lifecycle, create a replacement order or fabricate arrival, OTP, proof, cash, earnings or delivery. Stop live sharing and idle matching-location updates. This decision does not relax the original timing requirements or authorize production operations.

## Owner addendum — bounded map-upgrade GPS checks (2026-10-30)

For the requested map upgrade, the owner explicitly answered **"Yes, bounded stationary sharing test"** for restarting Rider 999's live sharing on existing TEST order 3180 after the updated APK is installed, then stopping it again. Preserve the existing order status and assignment; no new order, arrival, OTP, proof, cash or completion is authorized by this map-only consent. Retain the original timing targets and protected production boundary.

## Owner addendum — resume delivery and change its actual destination (2026-10-30)

The owner requested resuming and legitimately completing existing TEST order 3180, preserving the one-order checkpoint and previous notification limits. The owner manually restored Rider sign-in, enabled Online and pressed the normal sharing-consent control.

Before arrival, the owner clarified: **"i want to change delivery location near to me so i can acutally walk there and test"**. Select and confirm a real nearby handover point through the Customer flow before resuming the same delivery. Do not fabricate GPS, arrival, proof, cash, earnings or completion. The existing start-frozen pay policy remains in effect; the destination change does not authorize another order, database reset, extra messages or a production change.

## Owner addendum — bounded external road-route verification (2026-10-30)

The owner specifically approved sending only order 3180's synthetic TEST Customer-selected destination and current Rider coordinates to the existing Geoapify routing endpoint to compute one road route, with at most three routing requests for this verification, then stop and report the count. Include automatic map refreshes and failed/uncertain attempts in the cap; do not reset it on retry. No real Customer, Vendor or production data or additional personal details may be sent. Log only status, distance, duration and request count, never coordinates, API key or full request URLs. The key stays in the gitignored `supabase/functions/.env.test.local` and Supabase TEST secrets; never Flutter, docs or Git. Automated/load tests use mocked providers and send no Geoapify traffic. Verify and report the current official free-tier limits and the verification's actual request consumption. This approval does not relax delivery evidence, message limits, timing requirements or production protection.
