# Delivery backend findings — 2026-10-26

Read ../POLICY-DECISIONS.md before future stages. **Production remains untouched; this is bounded TEST evidence, not production acceptance.**

## Rider earnings

`202610250006_final_delivery_rider_earnings.sql` was applied once to TEST `igeisilhtmglgnqvllrx` at verified migration history63. Reviewed/deployed/current source SHA256: `76fb909543f4c6632f444e1047395aa03a4b6f959dd88bc43fef551571fb68b2`. Later0007 history was preserved;006 was not replayed.

Private RLS-enabled settings store owner-approved PKR60 base,20/km,80minimum, zero/disabled minute/peak/weather/bonus/tip components and cancellation-base toggle. One existing assignment task uses its canonical first pickup. A valid FR14 provider cache is used only near that vendor origin with the actual confirmed destination; an arbitrary Rider→Customer cache is never mislabeled as the full vendor route. Otherwise the server computes straight-line vendor→destination distance. Rates, distance and method freeze once at secured `on_the_way` delivery start. No later recompute/rate edit rewrites the snapshot.

`final_delivery_rider_quote` authorizes assigned approved Rider/Admin and returns expected amount before acceptance. `final_delivery_rider_earnings` authorizes own Rider history/approved Admin, with keyset pages, calculation parts, total, historical-unpriced count and review flag. Each delivered earning is deferred until the canonical verified OTP receipt and USED challenge commit; one row/audit per order. No old delivery is fabricated into the new ledger and nothing claims a payout.

`final_delivery_cancel_after_pickup` is now callable for the owning Customer/participating Vendor: explicit whole-order confirmation/reason, immutable request UUID, valid checklist-started `on_the_way` pickup and unpaid canonical COD required. A merely ready/assigned order is insufficient. The transaction locks parent/children/stock/payment, reuses accepted stock and assignment/tracking cleanup and records only the frozen base earning. Collected/uncertain payment requires Admin review. Ordinary pre-pickup cancellation remains unchanged and earns nothing. Actual dispute-resolution/refund-action triggers add immutable earning-review flags without deducting the delivered earning.

## Executed verification

- Final **44 SQL rollback assertions PASS**: includes accepted checkout/history/checklist/OTP baseline checks plus pay math, nearest-PKR rounding, freezing, no historical backfill, immutable ledger/audit, role/blocked/anonymous denials, exact wire field types, both Customer/Vendor whole-order cancellation, stock restoration/assignment/private-tracking cleanup, and review-without-clawback trigger effects.
- **9 actual authenticated TEST HTTP read/denial assertions PASS**: Rider/Admin totals agree; Customer/Vendor/foreign-account/anonymous/invalid-page denials; accepted performance endpoint reconciles recorded cents. These HTTP checks perform no application-business writes.
- SQL38 review and39/42 intermediate post results overlap the final44; **do not add them**. The controlled dispute/refund trigger probes are synthetic rollback records, not a claimed end-user dispute/refund settlement. Neither SQL nor HTTP proves physical delivery, money, email or GPS movement.

## Routing

Cached immutable segment lengths and last-fix projection remove repeated geometry work on stationary GPS/timer ticks without changing progression/off-route math. Earlier current-source Flutter routing25PASS retained; final Flutter checks belong to the root ledger. Routing handler **38 Deno PASS** newly rerun. Sanitized successful `Server-Timing` reports only stage durations; excludes wrapper/network/cold-start and contains no coordinates/identity/token/provider errors.

Reviewed routing handler deployed to TEST through the hosted API, no Docker or secret changes. Actual unauthenticated endpoint returned401 with no route or timing disclosure. No live provider/GPS request was made in this follow-up. Prior3610/2109ms and meaningful physical movement/deviation/rerouting remain unaccepted; these changes do not manufacture FR14 acceptance.

## Evidence and recovery

Sanitized record: `docs/evidence/FINAL-delivery-rider-pay-results.json`. Raw credentials/JWT-bearing SQL stay under ignored `.fr21-local/final-delivery/`. SQL changes/fixtures were rolled back during verification. Existing accepted business records were not replaced; hosted tests only log in existing authorized TEST accounts and read/deny access. No production operation, migration reset, push/merge or excluded load test.

Use forward corrective migrations if a defect is found; preserve ledger/audit/frozen records and existing migration versions. Final native quote/earning/cancellation, full Flutter suite/analyzer/APK and production qualification remain root-owned pending checks; source existence is not a native pass.
