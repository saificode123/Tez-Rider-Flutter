import postgres from 'npm:postgres@3.4.9';
import { createRatingHandler } from './handler.ts';
import { updateAuthState, synchronizeAuth } from '../admin-user-status/sync.ts';
const base = Deno.env.get('SUPABASE_URL') ?? '';
if (base !== 'https://igeisilhtmglgnqvllrx.supabase.co') throw Error('Dedicated TEST target required');
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const workerKey = Deno.env.get('FINAL_RATING_WORKER_KEY') ?? '';
const url = Deno.env.get('SUPABASE_DB_URL') ?? '';
const db = new URL(url);
if (!['postgres:', 'postgresql:'].includes(db.protocol) ||
    (db.hostname !== 'db.igeisilhtmglgnqvllrx.supabase.co' &&
     !(db.hostname.endsWith('.pooler.supabase.com') && decodeURIComponent(db.username) === 'postgres.igeisilhtmglgnqvllrx')) ||
    !service || workerKey.length < 32) throw Error('TEST server worker configuration required');
const sql = postgres(url, {max: 1, prepare: false, connect_timeout: 8, idle_timeout: 5, onnotice: () => {}});
const handler = createRatingHandler({
  workerKey,
  async evaluate(daily) {
    const response = await fetch(base + '/rest/v1/rpc/final_rating_work', {
      method: 'POST', headers: {apikey: service, Authorization: 'Bearer ' + service, 'Content-Type': 'application/json'},
      body: JSON.stringify({p_evaluate: daily}), signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw Error('Rating evaluation unconfirmed');
    return await response.json();
  },
  async synchronize(operation) {
    try {
      return await sql.begin(async tx => {
        await tx`set local statement_timeout='12s'`;
        await tx`set local idle_in_transaction_session_timeout='35s'`;
        await tx`set local lock_timeout='2s'`;
        // Same service-only transaction boundary used by admin-user-status.
        // This never creates or signs a user JWT or simulates a user session.
        await tx`select set_config('request.jwt.claims','{"role":"service_role"}',true)`;
        const lock = await tx`select pg_try_advisory_xact_lock(hashtextextended(${'fr28:' + operation.target_id},28))as acquired`;
        if (!lock[0].acquired) return {code: 'AUTH_SYNC_PENDING'};
        const rows = await tx`select public.fr28_sync_context(${operation.operation_id}::uuid)as context`;
        const context = rows[0].context;
        if (context.code !== 'PENDING') return context;
        if (context.target_id !== operation.target_id || context.desired_blocked !== true) throw Error('Unsafe rating block context');
        return await synchronizeAuth({
          change: () => updateAuthState(base, service, context.auth_id, true),
          revoke: async () => { await tx`select public.fr28_revoke_sessions(${operation.operation_id}::uuid)`; },
          finish: async failure => {
            const result = await tx`select public.fr28_finish(${operation.operation_id}::uuid,${failure ?? null})as result`;
            return result[0].result;
          },
        });
      });
    } catch { return {code: 'AUTH_SYNC_PENDING'}; }
  },
});
Deno.serve(handler);
