# Database migrations

TEST retained baseline: 62 versions through 202610250005. Six additive migrations were applied once: 006 rider earnings, 007 daily moderation, 008 retained optional modules, 009 event enqueue/cart policy, 010 verified Auth-email sync, and 011 support contact. Current confirmed TEST history: 68 versions. No replay/reset or production mutation. Exact hashes and review/deploy/post checks are in docs/evidence/FINAL-delivery-*, FINAL-optional-*, FINAL-profile-email-* and FINAL-support-*.

Production schema/history has not been reconciled. The local source sequence below is not authorization to apply every migration to an existing database. Compare actual history, review differences and deploy only missing compatible versions after explicit production approval.


011support contact:5 review/post checks overlap; actualGET/negativeHTTP5PASS. The approved row remains service-only except for a fixed public email endpoint. Legacy settings sequence is advanced monotonically; IDs/private values are unchanged.

- `202610080001_tezrider_baseline.sql`
- `202610090001_fr21_presence.sql`
- `202610110001_fr21_test_security.sql`
- `202610110002_fr21_dashboard_consistency.sql`
- `202610110003_fr21_presence_http_conflict.sql`
- `202610110004_fr21_delivery_receipt.sql`
- `202610110005_fr21_ready_state.sql`
- `202610110006_fr21_visibility_guards.sql`
- `202610120001_fr04_cnic_document.sql`
- `202610130001_fr25_dispute_submission.sql`
- `202610130002_fr25_delivery_guard.sql`
- `202610130003_fr25_upload_reservations.sql`
- `202610130004_fr25_notification_and_lock_guards.sql`
- `202610130005_fr25_unprepared_cleanup.sql`
- `202610130006_fr26_admin_dispute_decisions.sql`
- `202610130007_fr26_canonical_payment_success.sql`
- `202610130008_fr26_nullable_state_guards.sql`
- `202610140001_fr33_email_delivery_otp.sql`
- `202610140002_fr33_dispatch_recovery.sql`
- `202610140003_fr28_account_blocking.sql`
- `202610140004_fr28_identity_trigger_context.sql`
- `202610140005_fr28_order_policy_cycle.sql`
- `202610140006_fr28_active_order_bounds.sql`
- `202610140007_fr28_canonical_service_identity.sql`
- `202610150001_fr20_radius_assignment.sql`
- `202610150002_fr20_escalation_receipt.sql`
- `202610150003_fr20_shared_parent_ready.sql`
- `202610150004_fr30_admin_broadcasts.sql`
- `202610150005_fr30_sender_lock.sql`
- `202610150006_fr30_android_push.sql`
- `202610160001_fr10_order_timeout.sql`
- `202610160002_fr17_inventory.sql`
- `202610160003_fr32_email_outbox.sql`
- `202610170001_pre_delivery_checklist.sql`
- `202610180001_fr13_live_gps.sql`
- `202610190001_fr14_route_eta.sql`
- `202610190002_fr14_bounded_cleanup.sql`
- `202610200001_fr14_cache_read_path.sql`
- `202610220001_final1_security_foundation.sql`
- `202610220002_final1_legacy_definer_paths.sql`
- `202610220003_final01_security_prerequisites.sql`
- `202610220004_final01_security_activation.sql`
- `202610230001_final03_product_media_guard.sql`
- `202610230002_final03_tracking_session_topics.sql`
- `202610230003_final03_active_tracking_readers.sql`
- `202610230004_final2_registration.sql`
- `202610230005_final2_catalogue.sql`
- `202610230006_final2_cart.sql`
- `202610230007_final2_product_delete.sql`
- `202610230008_final2_cod_ledger.sql`
- `202610230009_final2_vendor_reporting.sql`
- `202610230010_final2_cash_invoices.sql`
- `202610240001_final2_feedback.sql`
- `202610240002_final2_order_detail.sql`
- `202610240003_final2_product_images.sql`
- `202610240004_final2_rider_metrics.sql`
- `202610240005_final2_admin_monitor.sql`
- `202610250001_final2_private_photos.sql`
- `202610250002_final2_photo_session_deadline.sql`
- `202610250003_final2_photo_completion_order.sql`
- `202610250004_final2_store_settings.sql`
- `202610250005_final2_saved_addresses.sql`
- `202610250006_final_delivery_rider_earnings.sql`
- `202610250007_final_delivery_rating_policy.sql`
- `202610250008_final_optional_modules.sql`
- `202610250009_final_delivery_event_push.sql`
- `202610250010_final_profile_email.sql`
- `202610250011_final_support_contact.sql`
