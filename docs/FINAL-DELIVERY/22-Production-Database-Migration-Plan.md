# Protected production migration plan

2026-10-28. **NOT AUTHORIZED; NOT READY TO DEPLOY.**

TEST read-only inventory observes 68 versions. Production history/schema/configuration were not inspected in this stage. TEST parity does not establish production parity. No new migration was needed for the client GPS consent fix.

The existing source has hard TEST target guards in critical Edge entrypoints, including location and routing. Production release requires reviewed environment configuration and acceptance of equivalent authorization/security boundaries; deleting guards to make deployment run is not an approved migration plan.

Pre-deployment sequence:

1. Independently verify protected project `arrqsvejrfdbacfwtpcc`; export read-only schema/history/grants/RLS/Storage/Auth/configuration inventory into protected evidence.
2. Back up schema, roles, application/Auth data and private object bytes. Record cryptographic hashes and verify isolated restoration, Auth associations and representative owner/Admin denial/access. Securely back up secret references; never place secrets or dumps in Git.
3. Compare actual version history and definitions with every migration under `supabase/migrations/`. Select only missing compatible migrations in order. Stop on divergent history; do not reset or replay accepted migrations.
4. Review SECURITY DEFINER/search paths, grants, public/private Storage, Auth session policy, cron jobs, Vault references, workers, notification/email recipients, quota budgets and production Firebase/APNs registration.
5. Generate the exact ordered dry-run/deployment plan with affected resources and hashes. Review transactional versus nontransactional changes and backward-compatible client rollout.
6. Prepare incident ownership and rollback: stop affected workers/client rollout, preserve audit/financial evidence, restore compatible application artifact, and restore data/schema/object backups only through a reviewed recovery plan. Do not assume reversing a migration repairs data loss.
7. Obtain separate owner authorization for the concrete production plan. Deploy only after mandatory acceptance/signing gates pass, then run actual smoke tests and monitor failures/quotas.

Dry-run evidence against production: NOT RUN. Production backup/restore: NOT RUN. Deployment/rollback rehearsal: NOT RUN. Existing detailed runbooks 09 and 10 remain applicable; they are procedures, not execution evidence.
