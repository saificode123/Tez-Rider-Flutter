# FR-21 schema validation — 2026-10-12

**Secured public baseline applied to TEST; FR-21 authorization and hosted behavior verified.** This supersedes the audit-only report.

## Provenance and completeness

Original `schema-export/tezrider-schema.sql`: 95,674 bytes; SHA256 `3b67b93133531794941a7148d744b0b215817e62f822bfda7e45a7b68d0c8f18`. Header PostgreSQL 17.6/pg_dump 18.6. Production origin is user-attested; the header alone cannot prove it. Original unchanged; production never contacted. No top-level record writes, sequence-value restore, DROP or TRUNCATE found.

Export: 40 tables, four enums, 11 functions, 40 primary keys, eight unique constraints, 33 foreign keys, nine explicit secondary indexes, four attached triggers and 67 policies. All 23 directly queried app tables were found. Entire export restored locally, including identities, relationships, triggers and grants. Bigint application IDs and UUID Auth IDs are preserved. Named PostgREST relationships, users.email and vendors.user_id uniqueness remain intact.

Secured baseline SHA256 `32967ff13210a734f229aa37c9a59e508a6a55709c9eb3e962047cdba6639114`. Adaptations: remove psql-only restrict commands; tolerate managed public schema; omit managed supabase_admin default-privilege changes; enable RLS and contain all client privileges inside the baseline transaction. Original schema retained for comparison. All ordered migrations/hashes: reviewed manifest and migration-plan CSV. No invented baseline definitions or production records.

## Security review and remediation

Original export had three non-RLS tables, 15 RLS tables without policies, broad client ALL/default grants, permissive private-row policies and broken dormant legacy assignment/notification functions. Baseline enables RLS on all 40 tables and removes client table/sequence/function grants before commit. Follow-up grants permit reviewed FR-21 paths only. TRUNCATE, TRIGGER, REFERENCES and schema CREATE remain denied to both client roles across the schema.

Profiles/CNIC: own-row or approved administrator only. Rider raw updates: own is_online/last_seen only; server guards reject timestamp spoofing, self-approval and direct assignment changes. Eligibility uses normalized users.role/verification_status, preserving the schema rather than adding riders.is_verified. Presence, verification, owner, active-assignment and dashboard filter indexes exist. Unrelated FK index gaps remain visible in the metadata report; they were not silently repaired.

Orders, vendor lines, assignments, notifications, tailoring and OTP receipts have reviewed ownership restrictions. Vendors cannot read other vendor lines on a shared parent. Existing notification/status triggers use fixed search paths and transactional authority. RPCs implement reservation, acceptance, completion, cancellation release, bounded contacts and actual dashboard statistics. Stale lease conflicts use PT409: hosted 40001 produced retry/timeouts, corrected by forward migration. [Supabase retry explanation](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).

Unused assign_available_rider/notify_new_order bodies remain preserved but inaccessible to clients. No fake success, client privilege elevation or global RLS disable. Unrelated policies were not invented. TRUNCATE/REFERENCES are outside RLS and explicitly revoked. [PostgreSQL RLS documentation](https://www.postgresql.org/docs/18/ddl-rowsecurity.html).

## Hosted contract and managed dependencies

TEST PostgreSQL 17.11: all 40 tables, no missing required tables/functions, no tables without RLS, no client TRUNCATE grants. Eight versions match local/remote. Existing managed Auth users/uid/jwt, roles and extensions plpgsql/pg_stat_statements/uuid-ossp/pgcrypto/supabase_vault satisfy FR-21. Managed schemas were not overwritten.

Realtime publication: orders, vendor_orders, rider_assignments, tailoring_requests, notifications. Riders excluded to avoid heartbeat amplification. Actual authenticated Realtime delivery, unrelated-vendor denial and reconnection passed.

Storage remains empty. Broader app references product-images, prescriptions and documents, but authoritative size/ownership/reviewer rules were not supplied; existing public-URL calls conflict with private documents. No insecure bucket was created. FR-21 presence/assignment/OTP receipt requires no bucket. Synthetic catalog fixture uses no upload. Confirmed synthetic password login/refresh passed; signup/email delivery was not certified.

Unrelated prescription/review/chat/payment/admin contracts remain outside acceptance. Examples: UUID review identities versus bigint vendor IDs, obsolete dormant RiderAssignmentController fields, missing private-document policies. Seventeen no-policy tables remain denied; legacy policies cannot grant access without explicit reviewed grants. This is contained FR-21 TEST readiness, not unrestricted whole-app or production acceptance.

## Verification

Hosted rollback-only business/role SQL: **81 passed**. Hosted security SQL: **306 passed**. Real Auth/REST/Realtime/concurrency: **46 passed**. Actual Flutter hosted integration: **2 passed**. Final APK/Flutter/device evidence: `FR-21-test-readiness.md`.

Earlier full-export local dblink run: three race checks passed. Current secured-schema local load: 1,000 VUs, p95 15.97 ms, request failures 0.477%; 96 transport failures retained. Hosted concurrency independently checks competing orders and duplicate requests. Local Auth emulation is not proof of hosted Auth/Realtime.

All hosted writes checked the exact linked TEST ref immediately beforehand and explicitly targeted it. No hosted reset, repair, incomplete root scripts or production writes. Exclusions/dependencies remain in `FR-21-test-migration-plan.csv`.
