// Real LOCAL PostgREST + RLS/RPC; no hosted load and no email requests.
import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';
const f = JSON.parse(open(__ENV.CHECKLIST_LOCAL_FIXTURE));
if (f.synthetic_only !== true || f.project !== 'tezrider-fr30-local' || f.base !== 'http://127.0.0.1:54321') throw Error('Unlinked LOCAL synthetic fixtures required');
const errors = new Rate('unexpected_errors');
const latency = new Trend('checklist_operation_ms', true);
const rejections = new Rate('expected_business_rejections');
export const options = {
  scenarios: {
    distinct: { executor: 'shared-iterations', vus: 2, iterations: 20, exec: 'distinct', maxDuration: '2m' },
    contention: { executor: 'shared-iterations', vus: 2, iterations: 20, exec: 'contention', startTime: '3s', maxDuration: '2m' },
  },
  thresholds: { unexpected_errors: ['rate<0.01'], checklist_operation_ms: ['p(95)<800'], checks: ['rate>0.99'] },
};
function headers(row) { return { apikey: f.api_key, Authorization: 'Bearer ' + row.token, 'Content-Type': 'application/json' }; }
function rpc(name, body, row) {
  const r = http.post(f.base + '/rest/v1/rpc/' + name, JSON.stringify(body), { headers: headers(row), timeout: '15s' });
  latency.add(r.timings.duration); errors.add(r.status !== 200); return r;
}
function run(row, initial) {
  if (initial) {
    const gate = rpc('start_checklisted_delivery', { p_assignment_id: row.assignment_id }, row);
    const denied = gate.status === 200 && gate.json().code === 'CHECKLIST_REQUIRED';
    rejections.add(denied); check(null, { 'incomplete start rejected': () => denied });
  }
  const definition = rpc('pre_delivery_checklist', { p_order_id: row.order_id }, row).json();
  const body = { p_assignment_id: row.assignment_id, p_version: definition.version,
    p_confirmations: definition.items.map(i => ({ id: i.id, confirmed: true })) };
  const a = rpc('submit_pre_delivery_checklist', body, row).json();
  const b = rpc('submit_pre_delivery_checklist', body, row).json();
  check(null, { 'same assignment has one immutable completion': () => a.code === 'COMPLETED' && b.code === 'COMPLETED' && a.completed_at === b.completed_at && b.replayed === true });
  const started = rpc('start_checklisted_delivery', { p_assignment_id: row.assignment_id }, row).json();
  check(null, { 'completed checklist permits real start': () => started.code === 'STARTED' });
  const unauthorized = rpc('submit_pre_delivery_checklist', body, f.fixtures[21]);
  rejections.add(unauthorized.status === 200 && unauthorized.json().code === 'FORBIDDEN');
  check(unauthorized, { 'another rider completion rejected': r => r.status === 200 && r.json().code === 'FORBIDDEN' });
  const response = http.get(f.base + '/rest/v1/pre_delivery_checklists?assignment_id=eq.' + row.assignment_id + '&select=assignment_id', { headers: headers(row) });
  errors.add(response.status !== 200);
  check(response, { 'exactly one durable response after contention': r => r.status === 200 && r.json().length === 1 });
}
export function distinct() { run(f.fixtures[exec.scenario.iterationInTest], true); }
export function contention() { run(f.fixtures[20], false); }
