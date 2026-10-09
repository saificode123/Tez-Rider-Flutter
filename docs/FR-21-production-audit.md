# FR-21 production preflight — 2026-10-09

## Outcome

**STOPPED BEFORE PRODUCTION CHANGES. No migration applied.** The original c72f510
candidate was unsafe unchanged; it has now been revised and tested locally.
No records, roles, verification values, policies,
grants, functions, indexes, or availability flags were changed remotely.

## Local audit

`git show -s --format='%h %s' c72f510` returned:
`c72f510 feat(FR-21): persist rider online/offline status`.
Initial `git status --short` listed only untracked `AGENTS.md` and
`docs/Tez Rider SRDS updated.pdf`. Existing committed FR-21 files were clean.

The only local migration is `supabase/migrations/202610090001_fr21_presence.sql`.
No `supabase/config.toml` or linked `.temp/project-ref` exists. Supabase CLI,
Postgres CLI, and Docker were not found on PATH. Root SQL files are inconsistent
destructive bootstrap scripts; they are not an ordered production migration history.

The app verifies riders through `public.users.verification_status = 'approved'`
and `users.role = 'rider'`. Signup and admin approval use this source. The current
original c72f510 migration unnecessarily added and synchronized `riders.is_verified`;
the revised candidate uses the existing user verification source directly.
The similarly named `is_verified` write in `RiderController` belongs to
`delivery_proof`, not `riders`; the earlier audit attribution was incorrect.
Presence RPC names and epoch/sequence arguments are already integrated in Dart.

Deficiencies in the original c72f510 candidate (superseded by the revised local migration):
- Unconditional CREATE POLICY/CREATE TRIGGER statements prevent reruns.
- Adds a redundant vendor user index despite live `vendors_user_id_key`.
- Revokes rider INSERT and all other UPDATE privileges, affecting existing
  client profile provisioning, location, and availability writes.
- Restrictive assignment policy has WITH CHECK(false), blocking existing client
  assignment status updates. Adding permissive read policies does not narrow
  existing USING(true) policies.
- Broader identity/signup and order guards have not been regression tested.
- Existing RiderAssignmentController uses UUID/rider_id while the live table
  uses bigint/riderid. Do not rename columns or repair identities automatically.

## Actual remote SELECT results

Authenticated dashboard target: TezRider main, project `arrqsvejrfdbacfwtpcc`;
same reference as Flutter's configured Supabase URL. This confirms the browser
target, **not a CLI link**. Database `postgres`, PostgreSQL `17.6`.

Three SELECT statements were executed through the dashboard SQL Editor. Their
exact text is in `supabase/inspection/FR-21-preflight.sql`. Each returned one JSON
row successfully; no CLI apply command was used.

- `supabase_migrations.schema_migrations` does not exist. No remote migration
  history can be compared. No `fr21_*` functions are present.
- Riders contains exactly the six supplied legacy columns; all FR-21 columns
  are absent. Only `riders_pkey` exists on that table.
- Rider rows: **10**; null userid: **0**; duplicate userids: **0**.
  Each availability flag has **6 true**, **0 null**, and flags disagree in **0** rows.
  Identity digest: `c56748db27552227350068f6986defc5`.
- Joined verification aggregate: **role vendor, verification_status approved,
  riders 10**. No existing row qualifies as an approved rider. Preserve identities;
  account-role correction requires owner review, not automatic migration changes.
- FKs remain present: riders.userid → users.id; assignments.riderid → users.id;
  assignments.orderid → orders.id; orders.rider_id → users.id; vendor_orders
  order/vendor references; notifications.user_id → users.id. IDs are bigint;
  notifications user_id is bigint, not UUID.
- RLS is enabled, not forced, on all seven inspected tables. Authenticated
  INSERT/SELECT/UPDATE policies are permissive with true checks on users,
  riders, orders, vendor_orders, rider_assignments, and notifications; vendors
  also has public SELECT true. Users UPDATE explicitly allows any row and true
  checks. These policies do not establish owner or approval protection.
- anon and authenticated have table SELECT/INSERT/UPDATE/DELETE/TRUNCATE/
  REFERENCES/TRIGGER grants on all seven tables. RLS does not secure TRUNCATE;
  actual API exposure was not exercised. No destructive privilege was tested.
- No user/rider authorization triggers exist. Four inspected triggers are
  notification/order-status triggers on orders/vendor_orders. Existing functions
  include `assign_available_rider`, `sync_order_status_from_vendor_order`,
  notification helpers, `is_admin`, and vendor helpers. Their full bodies and
  interplay require isolated regression testing before assignment replacement.

## Recovery and deployment blockers

The project's scheduled-backup page says: **Free Plan does not include project
backups**. No downloadable backup or tested recovery path was available.
Official free alternative: private logical backups through Supabase CLI/pg_dump,
then validate restoration locally. Do not commit dumps or credentials.
Sources: https://supabase.com/docs/guides/platform/backups and
https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore.

Original audit follow-up (local items 3–4 are now implemented/tested):
1. Produce a private schema/roles/data backup and demonstrate local recovery.
   Use secure credential entry; do not paste credentials into chat or source.
2. Review why all rider profiles reference vendor accounts; establish correct
   account mappings without guessing or changing production identities.
3. Review narrowly scoped protection of user identity/role/approval and assignment
   writes. Existing true policies permit bypassing a presence-only RPC. Secure
   these dependencies while preserving signup, admin, location, delivery, and
   notification workflows; test on the restored local database.
4. Correct the existing unapplied migration in place: use users verification,
   preserve both availability columns, make owned policies/triggers rerunnable,
   reuse live indexes, and update dependent Dart/SQL tests together.
5. Apply that reviewed file alone via an explicit SQL transaction or `psql -f`
   after target/recovery validation; do not blindly use `supabase db push` or run
   any bootstrap/reset. A production apply command is deliberately not supplied
   while the file remains unsafe. Browser permission changes require action-time
   confirmation under the computer-use tool policy.

## Verification status

Remote metadata SELECTs were repeated successfully; the legacy schema, permissive
policies, verification source and vendor-linked rider aggregate were unchanged.
The existing parent-status and notification trigger bodies were inspected and
reproduced in the isolated test baseline. Current executable evidence is in
`docs/FR-21-verification.md`; exact production scope and remaining backup/approval
gates are in `docs/FR-21-deployment.md`. Local tests are not a restored production
clone, physical-device proof or production deployment. No production database writes occurred.
