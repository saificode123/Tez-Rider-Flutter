import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';
const base = (__ENV.FR26_LOCAL_URL || '').replace(/\/$/, '');
if (!/^http:\/\/(127\.0\.0\.1|localhost):54321$/.test(base)) {
  throw new Error('FR-26 load is restricted to an isolated loopback Supabase stack.');
}
if (!__ENV.FR26_FIXTURE_FILE) throw new Error('Private synthetic local fixture file required.');
const fixture = new SharedArray('fr26-fixtures', () => JSON.parse(open(__ENV.FR26_FIXTURE_FILE)).cases);
const settings = new SharedArray('fr26-settings', () => {
  const data = JSON.parse(open(__ENV.FR26_FIXTURE_FILE));
  return [{ project_id: data.project_id, anon_key: data.anon_key, admins: data.admins }];
})[0];
const smoke = __ENV.FR26_LOAD_PROFILE === 'smoke';
if (settings.project_id !== 'tezrider-fr25-local' || fixture.length < (smoke ? 10 : 1000)) {
  throw new Error('Wrong unlinked stack or insufficient isolated fixtures.');
}
const conflicts = new Counter('expected_decision_conflicts');
const newDecisions = new Counter('confirmed_final_decisions');
export const options = {
  stages: smoke ? [{ duration: '10s', target: 5 }, { duration: '15s', target: 10 }, { duration: '10s', target: 0 }]
    : [{ duration: '30s', target: 10 }, { duration: '1m', target: 100 }, { duration: '1m', target: 500 }, { duration: '1m', target: 1000 }, { duration: '1m', target: 1000 }, { duration: '30s', target: 0 }],
  thresholds: {
    'http_req_duration{operation:admin_queue}': ['p(95)<800'],
    'http_req_duration{operation:customer_detail}': ['p(95)<800'],
    'http_req_duration{operation:same_decision}': ['p(95)<800'],
    'http_req_duration{operation:conflicting_decision}': ['p(95)<800'],
    http_req_failed: ['rate<0.01'], checks: ['rate>0.99'],
  },
};
const headers = token => ({ apikey: settings.anon_key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
const post = (name, body, token, operation, conflict = false) => http.post(`${base}/rest/v1/rpc/${name}`, JSON.stringify(body), {
  headers: headers(token), timeout: '15s', tags: { operation },
  responseCallback: http.expectedStatuses(...(conflict ? [200, 409] : [200])),
});
export default function () {
  // Pair VUs against the same rows using different approved admin contexts;
  // this measures real row contention instead of isolated per-VU decisions.
  const data = fixture[Math.floor((__VU - 1) / 2) % fixture.length], admin = settings.admins[(__VU - 1) % 2];
  const queue = post('fr26_queue', { p_limit: 30, p_status: __ITER % 2 ? 'OPEN' : null }, admin, 'admin_queue');
  check(queue, { 'authorized bounded queue': r => r.status === 200 && Array.isArray(r.json()) && r.json().length <= 30 });
  const detail = post('fr25_detail', { p_id: data.same_id }, data.customer_token, 'customer_detail');
  check(detail, { 'customer reads own dispute': r => r.status === 200 && r.json('id') === data.same_id });
  const same = post('admin_resolve_dispute', { p_dispute_id: data.same_id, p_decision: 'RESOLVED', p_note: 'FR26 isolated same-decision load' }, admin, 'same_decision');
  check(same, { 'same decision confirms one pending outcome': r => r.status === 200 && r.json('decision') === 'RESOLVED' && r.json('refund_pending') === true });
  if (same.status === 200 && same.json('replayed') === false) newDecisions.add(1);
  const conflicting = post('admin_resolve_dispute', { p_dispute_id: data.conflict_id, p_decision: (__VU + __ITER) % 2 ? 'REJECTED' : 'RESOLVED', p_note: 'FR26 isolated conflicting decision load' }, admin, 'conflicting_decision', true);
  const expected = check(conflicting, { 'one winner or explicit opposite conflict': r => r.status === 200 || (r.status === 409 && r.json('code') === 'PT409') });
  if (expected && conflicting.status === 409) conflicts.add(1);
  if (conflicting.status === 200 && conflicting.json('replayed') === false) newDecisions.add(1);
  sleep(2);
}
