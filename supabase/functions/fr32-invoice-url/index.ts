import { createHandler } from './handler.ts';
import { accountBoundary } from '../_shared/fr28-access.ts';
const base = Deno.env.get('SUPABASE_URL') ?? '', anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '', service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const handler = createHandler({
  base,
  authenticate: async (jwt) => {
    if (base !== 'https://igeisilhtmglgnqvllrx.supabase.co') throw Error('TEST_REQUIRED');
    const r = await fetch(`${base}/auth/v1/user`, { headers: { apikey: anon, Authorization: `Bearer ${jwt}` }, signal: AbortSignal.timeout(10000) });
    return r.ok && typeof (await r.json()).id === 'string';
  },
  authority: async (jwt, order) => {
    const r = await fetch(`${base}/rest/v1/rpc/fr32_invoice_authority`, { method: 'POST', headers: { apikey: anon, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_order_id: order }), signal: AbortSignal.timeout(10000) });
    if (!r.ok) throw Error('FORBIDDEN'); return await r.json();
  },
  sign: async (path, seconds) => {
    const r = await fetch(`${base}/storage/v1/object/sign/invoices/${path}`, { method: 'POST', headers: { apikey: service, Authorization: `Bearer ${service}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ expiresIn: seconds }), signal: AbortSignal.timeout(10000) });
    if (!r.ok) throw Error('SIGNING_UNCONFIRMED');
    const value = (await r.json()).signedURL;
    if (typeof value !== 'string') throw Error('SIGNING_UNCONFIRMED');
    return `${base}/storage/v1${value}`;
  },
});
Deno.serve(async (req) => {
  try { const denied = await accountBoundary(req, base, anon); return denied ?? await handler(req); }
  catch { return Response.json({ code: 'UNAVAILABLE' }, { status: 503 }); }
});
