# FR-28 architecture and interpretation

TEST only: `igeisilhtmglgnqvllrx`. Existing five accepted feature ancestors verified; FR28 branch created from `ec1c63b`. Preserve unrelated unstaged `.gitignore` text. No production access or hosted reset/replay.

SRDS physical pages 9, 16, 22, 28, 31-32 and 45 cover admin user management, FR28/UC08, confirmation, RLS/audit and Table 5.6 row25 (BLOCKED, revoke session, next protected API 403). No automatic low-rating suspension or broadcasts.

One authoritative boolean: `users.is_blocked=false` means active account authorization; `true` maps to SRDS BLOCKED. Existing verification/CNIC/product flags remain independent. An Auth UUID FK/unique binding prevents email-change impersonation. All 33 initial TEST profiles matched confirmed canonical Auth identities at inspection; no production records copied. Block operations retain desired intent separately from current authorization, never a second account-status authority.

Block: authenticate/authorize approved unblocked admin; validate target (no self/admin); commit is_blocked=true, rider Offline/new presence epoch, one BLOCK_USER audit and PENDING operation. Existing orders are read with a 21-ID bound for warnings, never modified. Then a server-only Postgres transaction-level advisory lock serializes Auth work and reconciliation for this target. Opposite intent cannot supersede pending work. Same completed UUID replay never performs an old Auth action. Lock/op state are checked again before the external action. Failed/crashed work remains denied and reconcilable with the same operation UUID. Auth side effects cannot be rolled back by a SQL rollback.

Unblock: retain BLOCKED while synchronizing; call Auth unban and revoke any remaining old sessions; only confirmed Auth/database verification clears is_blocked and emits one UNBLOCK_USER audit. Rider remains Offline. SQL transaction failure after successful Auth unban still leaves database denial. No false full-success response for partial/unconfirmed work.

Important Auth API limitation: supported updateUserById ban_duration only changes banned_until; it does not delete sessions. Supported admin.signOut requires a target access JWT, which an administrator should not collect/store. The requested session revocation therefore uses a restricted server-only SQL routine to delete only the operation target's auth.refresh_tokens/auth.sessions after identity/role/pending-operation checks. No passwords or token values are read. This is intentional targeted session invalidation, not identity deletion, and is verified using the installed TEST Auth schema. Managed Auth schema compatibility must be reviewed on future upgrades. Do not describe this as an Auth API ban automatically revoking sessions.

A verified current session is required by RLS/actor guards. Previously issued JWTs remain cryptographically valid until expiry, but cannot regain protected application access after unblock if their sessions were revoked. PostgREST pre-request explicitly returns PT403/FR28_ACCOUNT_BLOCKED for protected REST reads/writes/RPCs. Own fr28_account_status is a narrow exception, returning only signed subject status so the client can show the exact support message after ban. Other products use independent RLS/actor/Edge checks, not reliance on the REST hook. Existing signed Storage bearer URLs remain valid until their existing TTL (up to15min); they are not account-authenticated requests and cannot be individually revoked without replacing objects or changing that architecture. No such destructive/global changes are introduced.

Own users-row SELECT remains allowed for the one id-filtered Realtime security channel, including block events; ordinary users still cannot enumerate accounts. Protected HTTP reads are denied by the pre-request hook. Every other public RLS table and Storage objects receives restrictive session guards, preserving original permissive/ownership policies. Service-context FR04/25 upload/FR33 issuance entry points explicitly recheck actor blocked state. Approved-rider helper excludes blocked candidates. Product visibility additionally rejects blocked vendors while retaining other existing product restrictions.

Shared Flutter HTTP handling reacts only to trusted FR28 account-blocked/session-revoked codes, never arbitrary 403/network failures. Login/biometric/session restoration check server status; one filtered own-profile Realtime channel is coalesced and disposed. No polling. Admin list uses keyset pagination/search/status/role filters; mutations require confirmation and retain request UUIDs across uncertainty. No service/DB keys in Flutter. Edge uses built-in server secrets and validates TEST URL and direct DB identity before connection.

Five additive FR28 migrations and four guarded Edge functions are deployed only to TEST. Final SQL 54, hosted 74, mocked Edge 23 and Flutter 95 checks passed; physical acceptance is recorded separately. Two focused fixes retain the original authorization rules: a definer identity-binding trigger avoids unauthorized Auth-schema access by PostgREST's service role, and a trusted vendor-order membership helper removes the inherited cyclic RLS dependency. Active-order warnings now use separate indexed branches capped at 21 IDs.

All protected mobile REST and Edge denials were verified as HTTP 403. Direct Storage list is a product-specific exception: blocked JWT returns 200 with an empty list and no protected records. The mobile CNIC Edge returned 403. Exact 403 on direct Storage would require a broader gateway/proxy; this does not weaken its restrictive RLS. Detailed quotas, test limits, policy inventory and evidence are in FR-28-readiness.md and FR-28-acceptance.md.

Official sources verified:
- https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid
- https://supabase.com/docs/reference/javascript/auth-admin-signout
- https://supabase.com/docs/guides/auth/managing-user-data
- https://supabase.com/docs/guides/auth/signout
- https://raw.githubusercontent.com/supabase/auth/master/internal/models/user.go (Ban only updates banned_until)
- https://supabase.com/docs/guides/functions/connect-to-postgres (server-only DB connection)
- https://supabase.com/docs/guides/database/debugging-performance (REST hook does not replace other-product RLS)
