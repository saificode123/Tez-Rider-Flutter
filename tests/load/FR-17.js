import http from 'k6/http';
import { check } from 'k6';
import { SharedArray } from 'k6/data';
import { Counter, Rate, Trend } from 'k6/metrics';
const base = __ENV.FR17_LOCAL_URL;
if (base !== 'http://127.0.0.1:54321') throw Error('Only the unlinked local stack is permitted');
const fixture = new SharedArray('FR17 local fixture', () => [JSON.parse(open(__ENV.FR17_FIXTURE_FILE))])[0];
if (!fixture.synthetic_only || fixture.project !== 'tezrider-fr30-local') throw Error('Local synthetic fixture required');
const full = __ENV.FR17_PROFILE === 'full';
const errors = new Rate('unexpected_errors');
const checkout = new Trend('checkout_ms', true);
const purchases = new Counter('purchases');
const shortages = new Counter('expected_shortages');
export const options = {
  scenarios: { stock: { executor: 'shared-iterations', vus: full ? 1000 : 2, iterations: full ? 1000 : 200, maxDuration: '2m' } },
  thresholds: { checkout_ms: ['p(95)<800'], unexpected_errors: ['rate<0.01'], purchases: ['count==100'], checks: ['rate>0.99'] },
};
export default function () {
  const actor = fixture.customers[(__VU - 1) % fixture.customers.length];
  const hex = fixture.run_prefix + __VU.toString(16).padStart(8,'0') + __ITER.toString(16).padStart(8,'0');
  const id = `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
  const response = http.post(base + '/rest/v1/rpc/fr10_checkout', JSON.stringify({
    p_request_id: id, p_items: [{product_id:fixture.product_id,quantity:1}],
    p_delivery: {address:'FR17 LOCAL synthetic',lat:33.68,lng:73.04,speed:'standard'},
  }), { headers: {apikey:fixture.anon_key,Authorization:'Bearer '+actor.token,'Content-Type':'application/json'}, timeout:'15s' });
  let body;
  try { body = response.json(); } catch (_) {}
  const valid = response.status === 200 && ['PLACED','INSUFFICIENT_STOCK'].includes(body?.code);
  errors.add(!valid); purchases.add(body?.code === 'PLACED' ? 1 : 0); shortages.add(body?.code === 'INSUFFICIENT_STOCK' ? 1 : 0);
  checkout.add(response.timings.duration);
  check(response, {'authoritative purchase or expected shortage': () => valid});
}
