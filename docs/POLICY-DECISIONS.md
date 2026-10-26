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
