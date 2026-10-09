import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';

// Fixture JSON: 1000 distinct riders plus vendor accounts, each with a test
// JWT, and disposable vendor_order_id values. Never include this file in Git.
const fixtures = new SharedArray('FR21 accounts', () => JSON.parse(open(__ENV.FR21_FIXTURES)));
const base = (__ENV.FR21_URL || '').replace(/\/$/, '');
const isLocal = /^http:\/\/(localhost|127\.0\.0\.1):54321$/.test(base);
const testRef = __ENV.FR21_TEST_PROJECT_REF || '';
if (!isLocal && (__ENV.FR21_ISOLATED_TEST !== 'true' || !testRef || !__ENV.FR21_LIVE_PROJECT_REF ||
    base !== `https://${testRef}.supabase.co` || testRef === __ENV.FR21_LIVE_PROJECT_REF)) {
  throw new Error('Use local Supabase or explicitly identified isolated test project. Live testing is forbidden.');
}
if (!__ENV.FR21_ANON_KEY || fixtures.length < 1000) throw new Error('Test key and 1000 fixtures required.');

export const options = {
  stages: [
    { duration: '1m', target: 100 }, { duration: '2m', target: 500 },
    { duration: '2m', target: 1000 }, { duration: '5m', target: 1000 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<800'], http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

function rpc(name, body, token) {
  const response = http.post(`${base}/rest/v1/rpc/${name}`, JSON.stringify(body), {
    headers: { apikey: __ENV.FR21_ANON_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    tags: { endpoint: name }, timeout: '8s',
  });
  check(response, { 'RPC confirmed': r => r.status === 200 });
  return response;
}

let epoch;
let sequence = 0;
export default function () {
  const fixture = fixtures[__VU - 1];
  if (epoch === undefined) {
    const response = rpc('fr21_begin_presence', {}, fixture.rider_token);
    if (response.status !== 200) { sleep(1); return; }
    epoch = response.json('epoch');
    sleep(Math.random() * 10);
  }
  rpc('fr21_set_presence', { p_online: true, p_epoch: epoch, p_sequence: ++sequence }, fixture.rider_token);
  // Repeated assignment tests the same transaction's idempotency under load.
  rpc('fr21_ready_and_assign', { p_vendor_order_id: fixture.vendor_order_id }, fixture.vendor_token);
  sleep(45 + Math.random() * 10);
}
