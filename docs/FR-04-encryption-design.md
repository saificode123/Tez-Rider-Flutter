# FR-04 CNIC encryption design — approved for TEST

User approval received: “Approve encryption design for TEST.” The approved TEST migration and protected backup were completed on 2026-10-12; they must not be repeated during acceptance testing.

Scope: TEST only, new rider submissions. Read-only inspection found zero nonempty rider CNIC values and zero document paths. Existing accounts/approval/presence stay unchanged. No production connection or migration.

Use existing users.cnic text for version-tagged pgcrypto PGP AES-256 ciphertext. Normalize13-digit input server-side before encryption. Generate a32-byte random key inside PostgreSQL; store it only as a Supabase Vault secret (encrypted by Vault), never in application tables, Flutter, environment build files or Git. Use private-schema functions with fixed search_path; revoke all client execution and Vault access. Only reviewed SECURITY DEFINER application functions may encrypt and produce masked CNIC, after authenticating the caller. Customer identity RPC validates owned order and returns only3***0-*******-* style masks. Admin queue uses masks and on-demand private document viewing; no unrestricted decryption endpoint.

Encryption is application-level cryptography in addition to provider disk encryption. Ciphertext remains protected by own-profile/admin RLS. Admin approval requires a valid server-validated document; image bytes remain in private Storage, whose provider encryption is separate from CNIC-number encryption.

Key rotation: create a new versioned Vault key, switch new writes, retain old key versions for decryption, then perform a separately approved bounded/transactional re-encryption migration with rollback backup. Do not remove a key until old ciphertext is gone and backups are retained. No existing numbers are altered by this proposed initial deployment.

Backup: retain a Windows-DPAPI protected key backup outside the repository in the existing current-user private configuration directory. Read the key only into a protected process, encrypt it locally and never print it. Database backup must include ciphertext and version information; Vault restoration depends on its encryption/wrapping material. Loss of both Vault key and protected backup makes decryption impossible. Restoring a different project requires controlled secret restoration rather than assuming Vault ciphertext is portable.

Privileges: database owners/privileged service operators inherently have access to backend secrets; client roles do not. No encryption key in Edge Function source or Flutter. The Edge Function uses its hosted backend credential only for validated operations and never returns keys.

Approval scope: TEST key provisioning, new rider CNIC encryption and protected key backup. No existing CNIC migration or production access is included. Rotation and destructive changes require separate approval.
