# Edge Functions and APIs

Existing functions: security-gateway (live identity/proof/quota), fr04-cnic (private encrypted identity media), fr13-location (eligible session-scoped GPS publication), get-delivery-route (authorized provider route/cache/quota), fr25-evidence, fr30-dispatch-push (Android TEST Admin broadcasts), fr32-email-worker/fr32-invoice-url (canonical invoice/event outbox), send-delivery-otp (approved server email), admin-user-status (canonical block and Auth synchronization), shopping-assistant (server-only provider), final2-product-image and final2-private-photo (validated private images).

New sources: final-rating-worker and optional-private-media. Actual deployments/configuration are recorded in their findings; source existence is not a deployment claim. Routing timing headers expose bounded stage labels/durations only, no coordinates/IDs/tokens.

Earnings public RPCs: final_delivery_rider_quote(p_order_id), final_delivery_rider_earnings(p_limit,p_before,p_rider_id). They authorize assigned approved Rider/approved Admin or own history and return server calculations; no client pay formula or payout API. Modifying private tables directly is denied.

Never expose service-role/provider/worker credentials to Flutter. Check supabase/config.toml and each function's explicit session or worker-key authentication before deployment; verify_jwt=false is not anonymous authorization. Functions must be deployed with --project-ref igeisilhtmglgnqvllrx for TEST. Production requires explicit owner approval and reviewed deployment order.

Public support-contact GET is deliberately available to signed-out/blocked people, exposing only the owner-authorized support_email string. Queries selecting other settings and writes are rejected; no client table grants are added. It is deployed to TEST only and caches at most60seconds.
