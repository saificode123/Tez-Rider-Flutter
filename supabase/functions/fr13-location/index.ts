import {serveSecurity, applicationFetch} from '../_shared/security-runtime.ts';
import {accountBoundary} from '../_shared/fr28-access.ts';
import {createHandler, type Data} from './handler.ts';
const base = Deno.env.get('SUPABASE_URL') ?? '';
const local = Deno.env.get('FR13_LOCAL_TEST') === 'true' && ['http://kong:8000', 'http://127.0.0.1:54321'].includes(base);
if (base !== 'https://igeisilhtmglgnqvllrx.supabase.co' && !local) throw Error('Isolated TEST required');
const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
async function rpc(jwt: string, name: string, params: Data): Promise<Data> {
  const response = await applicationFetch(base + '/rest/v1/rpc/' + name, {
    method: 'POST', headers: {apikey: anon, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json'},
    body: JSON.stringify(params), signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw Error('Unconfirmed');
  return await response.json();
}
const handler = createHandler({
  submit: (jwt, v) => rpc(jwt, 'fr13_submit_location', {
    p_order_id: v.order_id, p_lat: v.latitude, p_lng: v.longitude,
    p_accuracy: v.accuracy, p_device_at: v.device_at, p_request_id: v.request_id,
  }),
  context: (jwt, order) => rpc(jwt, 'fr13_tracking_context', {p_order_id: order}),
  async publish(topic, payload) {
    const response = await applicationFetch(base + '/realtime/v1/api/broadcast', {
      method: 'POST', headers: {apikey: service, Authorization: 'Bearer ' + service, 'Content-Type': 'application/json'},
      body: JSON.stringify({messages: [{topic, event: 'location', payload, private: true}]}),
      signal: AbortSignal.timeout(5000),
    });
    return response.ok;
  },
});
serveSecurity('fr13-location', {hostname: local ? '127.0.0.1' : '0.0.0.0', port: local ? 54328 : 8000}, async req => {
  const denial = await accountBoundary(req, base, anon);
  return denial ?? await handler(req);
});
