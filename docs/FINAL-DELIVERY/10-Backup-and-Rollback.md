# Backup and rollback

Source checkpoints are local Git commits on the existing branch; no push/merge is authorized. Generated APK/AAB/build caches/private evidence are ignored. Preserve current user changes and never reset the working tree to implement rollback.

Before deployment: verified logical backup of schema+data+Auth and private Storage contents; catalog migration IDs/hashes, function definitions, grants/RLS, scheduled jobs and secret names. Database-only backups do not establish recovery of Storage binaries. Supabase recommends exports for Free projects: https://supabase.com/docs/guides/platform/backups.

For client regression, reinstall the last verified TEST APK only after compatibility review; preserve app data and durable logout fences. Never reconnect a TEST build to production. Document its commit/source/package/APK hash.

For database regression, stop only the newly added worker/job through a reviewed server configuration change, preserve ledger/audit/receipt rows and use a forward corrective migration with regression tests. Do not delete earning history, reset rating cutoff, alter historical pay, replay migration versions or drop/recreate tables. Unblock only through canonical Admin FR28 if an actual erroneous block is confirmed; do not bypass Auth synchronization.

Database restore, destructive rollback and production changes require explicit owner approval with exact impact. No backup or restore rehearsal is claimed executed in this run.
