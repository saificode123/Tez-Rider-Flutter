import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';
import { Rate, Trend } from 'k6/metrics';
const base = __ENV.FR10_LOCAL_URL;
if (base !== 'http://127.0.0.1:54321') throw Error('Only the unlinked local stack is allowed');
const fixture = new SharedArray('FR10 local fixture', () => [JSON.parse(open(__ENV.FR10_FIXTURE_FILE))])[0];
if (!fixture.synthetic_only || fixture.project !== 'tezrider-fr30-local') throw Error('Dedicated local synthetic fixture required');
const errors = new Rate('unexpected_errors');
const acceptance = new Trend('vendor_acceptance_ms', true);
export const options = {
  vus: __ENV.FR10_PROFILE === 'full' ? 1000 : 2,
  duration: __ENV.FR10_PROFILE === 'full' ? '30s' : '15s',
  thresholds: { vendor_acceptance_ms: ['p(95)<800'], unexpected_errors: ['rate<0.01'], checks: ['rate>0.99'] },
};
export default function () {
  const id = fixture.vendor_order_ids[((__VU - 1) * 50 + __ITER) % fixture.vendor_order_ids.length];
  const response = http.post(base + '/rest/v1/rpc/fr10_vendor_transition', JSON.stringify({ p_vendor_order_id: id, p_status: 'accepted' }), {
    headers: { apikey: fixture.anon_key, Authorization: 'Bearer ' + fixture.vendor_token, 'Content-Type': 'application/json' }, timeout: '12s',
  });
  let body;
  try { body = response.json(); } catch (_) {}
  const valid = response.status === 200 && ['ACCEPTED', 'ALREADY_ACCEPTED'].includes(body?.code);
  check(response, { 'server acceptance/replay confirmed': () => valid });
  errors.add(!valid);
  acceptance.add(response.timings.duration);
  sleep(0.05);
}
