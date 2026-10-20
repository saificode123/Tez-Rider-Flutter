import {accountBoundary} from '../_shared/fr28-access.ts';
import {createHandler, type Data} from './handler.ts';
const base = Deno.env.get('SUPABASE_URL') ?? '';
const local = Deno.env.get('FR14_LOCAL_TEST') === 'true' && ['http://127.0.0.1:54321', 'http://kong:8000'].includes(base);
if (base !== 'https://igeisilhtmglgnqvllrx.supabase.co' && !local) throw Error('Isolated TEST required');
const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '', service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const key = Deno.env.get('ROUTING_API_KEY') ?? '';
async function rpc(jwt: string, name: string, body: Data, privileged = false): Promise<Data> {
  const res = await fetch(base + '/rest/v1/rpc/' + name, {method: 'POST', headers: {apikey: privileged ? service : anon, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json'}, body: JSON.stringify(body), signal: AbortSignal.timeout(8000)});
  if (!res.ok) throw Error('UNAVAILABLE');
  return res.json();
}
const handler = createHandler({
  configured: key.length > 0,
  accountBoundary: req => accountBoundary(req, base, anon),
  async authenticate(jwt) {
    const res = await fetch(base + '/auth/v1/user', {headers: {apikey: anon, Authorization: 'Bearer ' + jwt}, signal: AbortSignal.timeout(8000)});
    return res.ok && typeof (await res.json()).id === 'string';
  },
  context: (jwt, order) => rpc(jwt, 'fr14_route_context', {p_order_id: order}),
  prepare: (order, actor, configured) => rpc(service, 'fr14_prepare', {p_order_id: order, p_actor: actor, p_configured: configured}, true),
  finish: (order, actor, lease, route) => rpc(service, 'fr14_finish', {p_order_id: order, p_actor: actor, p_lease: lease, p_route: route}, true),
  async provider(origin, destination) {
    const url = new URL('https://api.geoapify.com/v1/routing');
    url.search = new URLSearchParams({waypoints: `${origin[1]},${origin[0]}|${destination[1]},${destination[0]}`, mode: 'drive', format: 'geojson', units: 'metric', apiKey: key}).toString();
    const res = await fetch(url, {
      headers: {Accept: 'application/geo+json'},
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok || Number(res.headers.get('content-length') ?? 0) > 2000000) throw Error('PROVIDER_UNAVAILABLE');
    // Bound chunked responses too; never buffer an unbounded provider body.
    const reader = res.body?.getReader();
    if (!reader) throw Error('PROVIDER_UNAVAILABLE');
    const chunks: Uint8Array[] = []; let size = 0;
    try { while (true) { const {done, value} = await reader.read(); if (done) break; size += value.length; if (size > 2000000) throw Error('PROVIDER_UNAVAILABLE'); chunks.push(value); } }
    finally { await reader.cancel(); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder().decode(bytes));
  },
});
Deno.serve({hostname: local ? '127.0.0.1' : '0.0.0.0', port: local ? 54329 : 8000}, handler);
