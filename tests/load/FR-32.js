// Local-only k6 queue qualification. Never pass a hosted project URL/key.
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';
const base = __ENV.FR32_LOCAL_HARNESS;
if (base !== 'http://127.0.0.1:8768') throw Error('Unlinked loopback harness only');
const fixture = JSON.parse(open(__ENV.FR32_LOCAL_FIXTURE));
if (fixture.synthetic_only !== true || fixture.mock_brevo !== true || fixture.project !== 'tezrider-fr30-local') throw Error('Explicit LOCAL synthetic/mock fixture required');
const errors = new Rate('unexpected_errors');
const enqueueMs = new Trend('business_enqueue_ms', true);
const full = __ENV.FR32_PROFILE === 'full';
export const options = {
  scenarios: { outbox: { executor: 'shared-iterations', vus: full ? 1000 : 2, iterations: full ? 1000 : 40, maxDuration: '3m' } },
  thresholds: { unexpected_errors: ['rate<0.01'], business_enqueue_ms: ['p(95)<800'], checks: ['rate>0.99'] },
};
const headers = { 'Content-Type': 'application/json', 'x-fr32-worker-key': fixture.worker_key };
export default function () {
  const key = `${fixture.run_prefix}-${__VU}-${__ITER}`;
  const request = JSON.stringify({ event_key: key });
  const a = http.post(base + '/enqueue', request, { headers, timeout: '15s' });
  const b = http.post(base + '/enqueue', request, { headers, timeout: '15s' });
  let x, y; try { x = a.json(); y = b.json(); } catch (_) { /* counted below */ }
  const valid = a.status === 200 && b.status === 200 && x?.id === y?.id;
  errors.add(!valid); enqueueMs.add(a.timings.duration);
  check(null, { 'same event returns same durable intent': () => valid });
  const worker = http.post(base + '/worker', '{}', { headers, timeout: '30s' });
  errors.add(worker.status !== 200);
}
export function teardown() {
  const beforeUnauthorized = http.get(base + '/stats', { headers }).json();
  const denied = http.post(base + '/worker', '{}', { headers: { 'x-fr32-worker-key': 'wrong' } });
  check(denied, { 'unauthorized worker sends nothing': (r) => r.status === 401 });
  const afterUnauthorized = http.get(base + '/stats', { headers }).json();
  check(null, { 'unauthorized worker cannot increase provider acceptances': () => beforeUnauthorized.mock_accepted === afterUnauthorized.mock_accepted });
  const recovered = http.post(base + '/recover', '{}', { headers, timeout: '30s' });
  check(recovered, { 'pre-send lease recovery fixture processed': (r) => r.status === 200 });
  // Queue processing/latency is separate from business admission latency.
  const start = Date.now();
  let stats;
  for (let i = 0; i < 45; i++) {
    const response = http.get(base + '/stats', { headers, timeout: '15s' });
    if (response.status !== 200) break;
    stats = response.json();
    if (!stats.due && !stats.sending && !stats.retry_at) break;
    http.post(base + '/worker', '{}', { headers, timeout: '30s' }); sleep(1);
  }
  check(stats, {
    'no duplicate outbox event': (s) => s && s.duplicates === 0,
    'no shared quota oversubscription': (s) => s && s.active_quota <= s.budget,
    'no OTP reserve consumption by transactional mail': (s) => s && s.transactional_quota <= s.budget - s.otp_reserve,
    'no duplicate provider acceptance': (s) => s && s.mock_duplicate_acceptances === 0,
    'mocked429 backoff exercised and resumed': (s) => s && s.mock_rate_limits > 0 && !s.retry_at,
    'backlog classified as sent, deferred or terminal': (s) => s && s.due === 0 && s.sending === 0,
  });
  console.log(JSON.stringify({ local_only: true, real_emails_sent: 0, queue_observation_ms: Date.now() - start,
    remaining_deferred: stats?.deferred, mock_provider_accepted: stats?.mock_accepted }));
}
