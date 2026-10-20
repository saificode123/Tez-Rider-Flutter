// LOCAL Supabase only, mocked provider only. Never contacts Geoapify.
import {createHandler, type Data} from '../../supabase/functions/get-delivery-route/handler.ts';
import {accountBoundary} from '../../supabase/functions/_shared/fr28-access.ts';
const base = Deno.env.get('SUPABASE_URL');
if (base !== 'http://127.0.0.1:54321') throw Error('LOCAL only');
const anon = Deno.env.get('SUPABASE_ANON_KEY')!, service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
let providerCalls = 0;
async function rpc(jwt: string, name: string, body: Data, privileged = false) {
  const r = await fetch(base + '/rest/v1/rpc/' + name, {method: 'POST', headers: {apikey: privileged ? service : anon, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  if (!r.ok) throw Error('RPC failed'); return r.json();
}
const handler = createHandler({
  configured: true,
  authenticate: async jwt => (await fetch(base + '/auth/v1/user', {headers: {apikey: anon, Authorization: 'Bearer ' + jwt}})).ok,
  context: (jwt, order) => rpc(jwt, 'fr14_route_context', {p_order_id: order}),
  prepare: (order, actor, configured) => rpc(service, 'fr14_prepare', {p_order_id: order, p_actor: actor, p_configured: configured}, true),
  finish: (order, actor, lease, route) => rpc(service, 'fr14_finish', {p_order_id: order, p_actor: actor, p_lease: lease, p_route: route}, true),
  async provider(origin, destination) {
    providerCalls++;
    await new Promise(resolve => setTimeout(resolve, 100));
    if (Deno.env.get('FR14_MOCK_FAILURE') === 'true') throw Error('Mock timeout');
    return {type: 'FeatureCollection', features: [{geometry: {type: 'MultiLineString', coordinates: [[origin, destination]]}, properties: {distance: 1600, time: 240}}]};
  },
});
Deno.serve({hostname: '127.0.0.1', port: 54330}, async req => {
  if (new URL(req.url).pathname === '/stats') return Response.json({providerCalls, mockedProvider: true});
  return await accountBoundary(req, base, anon) ?? handler(req);
});
