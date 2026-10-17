// This file is never deployed as an Edge Function. Loopback and mock transport
// are mandatory; the service key belongs only to the unlinked LOCAL stack.
import { createHandler, type Job } from '../../supabase/functions/fr32-email-worker/handler.ts';
import { sendBrevo } from '../../supabase/functions/_shared/fr32-brevo.ts';
const file = Deno.env.get('FR32_LOCAL_FIXTURE');
if (!file || Deno.env.get('FR32_LOCAL_TEST') !== 'true') throw Error('Explicit LOCAL fixture required');
const f = JSON.parse(await Deno.readTextFile(file));
if (f.synthetic_only !== true || f.mock_brevo !== true || f.project !== 'tezrider-fr30-local' || f.base !== 'http://127.0.0.1:54321' || !f.service_key || f.worker_key?.length < 32) throw Error('Unlinked LOCAL stack required');
const mock = 'http://127.0.0.1:8768';
async function rpc(name: string, body: unknown) {
  const r = await fetch(f.base + '/rest/v1/rpc/' + name, { method: 'POST', headers: { apikey: f.service_key, Authorization: 'Bearer ' + f.service_key, 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(10000) });
  if (!r.ok) throw Error('LOCAL_DATABASE_UNCONFIRMED'); return await r.json();
}
const accepted = new Map<string, number>(); let attempts = 0, rateLimits = 0;
const worker = createHandler({
  workerSecret: f.worker_key, sender: 'sender@example.test', testRecipient: 'approved@example.test',
  claim: () => rpc('fr32_claim_email', { p_limit: 2 }),
  pdf: () => Promise.reject(Error('No invoice jobs belong in this LOCAL load fixture')),
  begin: async (j: Job, fingerprint: string) => (await rpc('fr32_begin_email', { p_id: j.id, p_lease: j.lease, p_fingerprint: fingerprint })).code,
  send: (body) => sendBrevo(body, 'local-mock', ((_url, options) => fetch(mock + '/send', options)) as typeof fetch),
  finish: async (j, result) => { await rpc('fr32_finish_email', { p_id: j.id, p_lease: j.lease, p_outcome: result.outcome, p_provider: 'provider' in result ? result.provider ?? null : null, p_error: result.error ?? null, p_retry_seconds: 'retrySeconds' in result ? result.retrySeconds ?? null : null }); },
});
Deno.serve({ hostname: '127.0.0.1', port: 8768 }, async (req) => {
  const path = new URL(req.url).pathname;
  if (path === '/send') {
    if (req.headers.get('api-key') !== 'local-mock') return Response.json({}, { status: 401 });
    const body = await req.json(), key = body.headers?.idempotencyKey;
    if (!key || body.to?.[0]?.email !== 'approved@example.test') return Response.json({}, { status: 400 });
    attempts++;
    if (accepted.has(key)) return Response.json({ code: 'duplicate_parameter' }, { status: 400 });
    if (attempts % 5 === 0) { rateLimits++; return Response.json({}, { status: 429, headers: { 'Retry-After': '30' } }); }
    accepted.set(key, (accepted.get(key) ?? 0) + 1); return Response.json({ messageId: 'local-mock-' + accepted.size }, { status: 201 });
  }
  if (path === '/worker') return await worker(req);
  if (req.headers.get('x-fr32-worker-key') !== f.worker_key) return Response.json({}, { status: 401 });
  try {
    if (path === '/enqueue') {
      const { event_key } = await req.json();
      if (typeof event_key !== 'string' || !/^[A-Za-z0-9_-]{1,100}$/.test(event_key)) return Response.json({}, { status: 400 });
      return Response.json({ id: await rpc('fr32_load_enqueue', { p_key: event_key }) });
    }
    if (path === '/recover') return Response.json(await rpc('fr32_load_recover', {}));
    if (path === '/stats') return Response.json({ ...await rpc('fr32_load_stats', {}), mock_accepted: accepted.size, mock_rate_limits: rateLimits,
      mock_duplicate_acceptances: Array.from(accepted.values()).reduce((sum, count) => sum + Math.max(0, count - 1), 0) });
    return Response.json({}, { status: 404 });
  } catch { return Response.json({ code: 'LOCAL_UNCONFIRMED' }, { status: 503 }); }
});
