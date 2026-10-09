# FR-21 reviewed production package

Target: existing TezRider / main / Production, `arrqsvejrfdbacfwtpcc`.
**NOT DEPLOYED. No production write is authorized yet.**

Apply only `supabase/migrations/202610090001_fr21_presence.sql`, after a verified
private backup, successful recovery rehearsal and explicit approval of this file's
SHA-256. The transaction has 5-second lock and 60-second statement timeouts.
Reviewed migration SHA-256: `a07d16d38e332d5d6b8677cab71f08adf1125bc80f34fa7004f92431a88f1196`.
Do not push root bootstrap SQL or any other migrations.

## Exact scope

- Add missing `is_online`, `last_seen`, `presence_epoch`, `presence_sequence`;
  preserve IDs/FKs/coordinates/two legacy availability flags. No account-role,
  approval or verification backfill; no `riders.is_verified` column.
- Unique rider owner index; presence/verification/assignment/owner/filter indexes.
  Verification lives in `users`, so a cross-table `(is_online,is_verified,last_seen)`
  index is impossible: use rider `(is_online,last_seen)` plus user
  `(role,verification_status,id)` indexes instead of duplicating verification.
- Five idempotently created policies: rider owner/read guards, user update-owner
  guard, vendor-order update-owner guard. Existing unrelated policies remain.
- Rider direct grants limited to own presence updates; revoke client rider
  insert/delete/protected-column updates. Revoke TRUNCATE/TRIGGER on seven touched
  tables. Five triggers protect rider fields, identities/approval, direct order
  assignment/OTP, assignment rows, and immutable vendor-order ownership. A sixth
  transactional trigger releases reservations on authorized cancellation.
- Confirmed Auth identity resolves server-side by existing unique email to bigint
  user ID. Approved rider/vendor checks use `users.verification_status`.
- Presence session/sequence RPCs, validated location RPC, transactional ready and
  assignment, accept and OTP completion RPCs; fixed empty search paths and scoped
  execution grants. Assignment locks parent order and candidate rider/user rows;
  both availability flags reserve/release together. Ready preserves existing
  notification/status triggers and issues an OTP for the active delivery.
- Reload the PostgREST schema cache after commit with `NOTIFY pgrst` so newly
  granted RPC signatures are discoverable without a server restart.
- No table drop/truncate, record deletion, manual role correction, global trigger
  replacement, Realtime publication or migration-history initialization.

## Preflight evidence and stop conditions

`supabase/inspection/FR-21-preflight.sql` and `FR-21-current.sql` are the exact
executed read-only statements. Re-run immediately before approval/apply.
Expected: PostgreSQL 17.6; no migration-history table or FR-21 RPCs; six legacy
rider columns; 10 rows; zero null/duplicate owners; six true values per availability
flag; zero flag disagreements; identity digest `c56748db27552227350068f6986defc5`.
All ten rider rows link to **approved vendor-role accounts**. Preserve them;
the owner must resolve the ambiguous mappings separately. They remain ineligible.
An approved actual rider account can provision only its own profile through the RPC.

Production RLS is enabled but legacy permissive reads remain broad. This migration
secures the specified presence/assignment and identity writes; it is not a complete
privacy audit of unrelated customer/CNIC/order tables. The dormant legacy
`RiderAssignmentController` references obsolete UUID/rider_id fields; it is not
instantiated by any screen and must not be enabled without separate integration.
The unused legacy `assign_available_rider` function is not attached to a trigger.

Stop on schema drift, duplicates, incompatible column types, changed trigger bodies,
unresolved backup/restore failure or missing explicit approval. No account changes
are included in the approval request.

## Backup, apply, recovery

Dashboard evidence: Free has **no project backups**. No private production database
credential, dump or verified restore is available. Recovery is **BLOCKED**.
Configure a private PostgreSQL service named `tezrider_fr21_prod` outside the repo
using the dashboard's verified connection details; never paste its password in chat.
Create private schema/roles/data backups and rehearse their restore into a compatible
local Supabase environment following the [official backup guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore).
The reconstructed test schema is not a production backup or a full Supabase restore.

After backup evidence and explicit approval, the only intended apply command is:

```powershell
psql "service=tezrider_fr21_prod" -X -v ON_ERROR_STOP=1 -f supabase/migrations/202610090001_fr21_presence.sql
```

Verify file SHA-256 immediately beforehand. Never use `supabase db push/reset` here.
Failure before COMMIT rolls back DDL/grants/functions atomically. After COMMIT,
disable new client rollout and use a reviewed forward correction or the verified
private restore procedure; dropping columns/guards would lose presence history or
reopen authorization holes. No destructive down migration is provided.

## Post-apply smoke tests (not run)

Re-run metadata queries: identity digest/legacy flag counts unchanged; four presence
columns, expected index/policy names, five guards, cancellation release and seven public operation RPCs
present; only presence UPDATE grants remain on riders. Check fixed search paths and
no PUBLIC/anon execution grants. Test own online/offline, fresh versus 121-second
heartbeat, pending approval, other-user writes, vendor ownership, duplicate ready,
one rider/two concurrent orders, and completion releasing both flags using approved
disposable test accounts only. Exercise real Auth, signup and device Realtime after
deployment; these were not established by the local Auth-contract fixtures.
