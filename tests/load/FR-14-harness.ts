// LOCAL Supabase only, mocked provider only. Never contacts Geoapify.
import {createHandler, type Data} from '../../supabase/functions/get-delivery-route/handler.ts';
import {accountBoundary} from '../../supabase/functions/_shared/fr28-access.ts';
const base = Deno.env.get('SUPABASE_URL');
if (base !== 'http://127.0.0.1:54321') throw Error('LOCAL only');
const anon = Deno.env.get('SUPABASE_ANON_KEY')!, service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const sequentialAuth = Deno.env.get('FR14_AUTH_SEQUENTIAL') === 'true';
let providerCalls = 0;
const timings: Record<string, number[]> = {};
async function measure<T>(name: string, work: () => Promise<T>): Promise<T> {
  const start = performance.now();
  try { return await work(); }
  finally { (timings[name] ??= []).push(performance.now() - start); }
}
function timingSummary() {
  return Object.fromEntries(Object.entries(timings).map(([name, values]) => {
    const ordered = [...values].sort((a, b) => a - b);
    return [name, {count: values.length, meanMs: values.reduce((a, b) => a + b, 0) / values.length,
      p95Ms: ordered[Math.ceil(ordered.length * .95) - 1]}];
  }));
}
async function rpc(jwt: string, name: string, body: Data, privileged = false) {
  const r = await fetch(base + '/rest/v1/rpc/' + name, {method: 'POST', headers: {apikey: privileged ? service : anon, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  if (!r.ok) throw Error('RPC failed'); return r.json();
}
const handler = createHandler({
  configured: true,
  accountBoundary: sequentialAuth ? undefined : req => measure('boundary', () => accountBoundary(req, base, anon)),
  authenticate: jwt => measure('auth', async () => {
    const r = await fetch(base + '/auth/v1/user', {headers: {apikey: anon, Authorization: 'Bearer ' + jwt}});
    // Consume the response as the deployed adapter does; release its connection.
    const data = await r.json(); return r.ok && typeof data.id === 'string';
  }),
  context: (jwt, order) => measure('context', () => rpc(jwt, 'fr14_route_context', {p_order_id: order})),
  prepare: (order, actor, configured) => measure('prepare', () => rpc(service, 'fr14_prepare', {p_order_id: order, p_actor: actor, p_configured: configured}, true)),
  finish: (order, actor, lease, route) => measure('finish', () => rpc(service, 'fr14_finish', {p_order_id: order, p_actor: actor, p_lease: lease, p_route: route}, true)),
  async provider(origin, destination) {
    providerCalls++;
    await new Promise(resolve => setTimeout(resolve, 100));
    if (Deno.env.get('FR14_MOCK_FAILURE') === 'true') throw Error('Mock timeout');
    return {type: 'FeatureCollection', features: [{geometry: {type: 'MultiLineString', coordinates: [[origin, destination]]}, properties: {distance: 1600, time: 240}}]};
  },
});
Deno.serve({hostname: '127.0.0.1', port: 54330}, async req => {
  if (new URL(req.url).pathname === '/stats') return Response.json({providerCalls, mockedProvider: true, timings: timingSummary()});
  if (sequentialAuth) return await measure('boundary', () => accountBoundary(req, base, anon)) ?? handler(req);
  return handler(req);
});
