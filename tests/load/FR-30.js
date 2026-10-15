import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';
import { Rate, Trend } from 'k6/metrics';
const base = __ENV.FR30_LOCAL_URL;
if (base !== 'http://127.0.0.1:54321') throw Error('Only FR30 unlinked loopback stack allowed');
const fixture = new SharedArray('FR30 isolated accounts', () => [JSON.parse(open(__ENV.FR30_FIXTURE_FILE))])[0];
if (fixture.synthetic_only !== true || fixture.project_ref !== 'tezrider-fr30-local') throw Error('Dedicated synthetic FR30 stack required');
const errors = new Rate('unexpected_errors');
const readLatency = new Trend('notification_read_ms', true);
const unreadLatency = new Trend('unread_count_ms', true);
const broadcastLatency = new Trend('broadcast_acceptance_ms', true);
export const options = {
  stages: __ENV.FR30_LOAD_PROFILE === 'full'
    ? [{ duration: '15s', target: 10 }, { duration: '25s', target: 100 }, { duration: '25s', target: 500 }, { duration: '30s', target: 1000 }, { duration: '10s', target: 0 }]
    : [{ duration: '5s', target: 2 }, { duration: '10s', target: 10 }, { duration: '5s', target: 0 }],
  thresholds: { http_req_duration: ['p(95)<800'], unexpected_errors: ['rate<0.01'], checks: ['rate>0.99'] },
};
function params(token, operation) {
  return { headers: { apikey: fixture.anon_key, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, timeout: '12s', tags: { operation } };
}
function good(response, value, label) { check(response, { [label]: () => value }); errors.add(!value); }
export function setup() {
  const response = http.post(base + '/rest/v1/rpc/admin_send_broadcast', JSON.stringify(fixture.request), params(fixture.admin_token, 'broadcast'));
  const body = response.json();
  broadcastLatency.add(response.timings.duration);
  if (response.status !== 200 || body.code !== 'SENT' || body.recipient_count !== fixture.recipient_count) throw Error('Local broadcast acceptance failed');
  return { broadcast: body.id };
}
export default function (data) {
  const user = fixture.recipients[(__VU - 1) % fixture.recipients.length];
  let response = http.get(base + '/rest/v1/notifications?select=id,type,is_read&order=id.desc&limit=30', params(user.token, 'notification_read'));
  let rows; try { rows = response.json(); } catch (_) { rows = []; }
  readLatency.add(response.timings.duration);
  good(response, response.status === 200 && rows.length === 1 && rows[0].type === 'broadcast', 'authoritative list after connect');
  response = http.head(base + '/rest/v1/notifications?select=id&is_read=eq.false', { ...params(user.token, 'unread_count'), headers: { ...params(user.token, 'unread_count').headers, Prefer: 'count=exact' } });
  unreadLatency.add(response.timings.duration);
  good(response, response.status === 200 && /\/(0|1)$/.test(response.headers['Content-Range'] || ''), 'bounded exact own unread count');
  if (rows.length) {
    response = http.patch(base + '/rest/v1/notifications?id=eq.' + rows[0].id, JSON.stringify({ is_read: true }), params(user.token, 'read_update'));
    good(response, response.status === 204, 'own read update');
  }
  if (__ITER % 3 === 0) {
    response = http.post(base + '/rest/v1/rpc/admin_send_broadcast', JSON.stringify(fixture.request), params(fixture.admin_token, 'idempotent_replay'));
    good(response, response.status === 200 && response.json('code') === 'ALREADY_SENT', 'concurrent UUID replay');
    const other = fixture.recipients[(__VU) % fixture.recipients.length];
    response = http.get(base + '/rest/v1/notifications?select=id&user_id=eq.' + other.id, params(user.token, 'cross_user_read'));
    good(response, response.status === 200 && response.json().length === 0, 'no unauthorized recipient exposure');
  }
  sleep(0.4);
}
