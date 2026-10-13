import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';
const base = (__ENV.FR25_LOCAL_URL || '').replace(/\/$/, '');
// An explicit loopback allowlist prevents accidental Free TEST/production load.
if (!/^http:\/\/(127\.0\.0\.1|localhost):54321$/.test(base)) {
  throw new Error('FR-25 load test requires isolated loopback Supabase on port 54321.');
}
if (!__ENV.FR25_FIXTURE_FILE) throw new Error('A private synthetic local fixture file is required.');
const accounts = new SharedArray('fr25-accounts', () => JSON.parse(open(__ENV.FR25_FIXTURE_FILE)).accounts);
const metadata = new SharedArray('fr25-metadata', () => {const data=JSON.parse(open(__ENV.FR25_FIXTURE_FILE)); return [{project_id:data.project_id,anon_key:data.anon_key}];});
if (metadata[0].project_id !== 'tezrider-fr25-local' || accounts.length < 1000) {
  throw new Error('Prepare 1000 isolated synthetic local customer fixtures first.');
}
const expectedRejections = new Counter('expected_business_rejections');
const newAttempts = new Counter('new_submission_attempts');
let attempted = false;
export const options = {
  stages: [{ duration:'30s',target:10 },{ duration:'1m',target:100 },{ duration:'1m',target:500 },{ duration:'1m',target:1000 },{ duration:'1m',target:1000 },{ duration:'30s',target:0 }],
  thresholds: {
    'http_req_duration{operation:create_dispute}':['p(95)<800'],
    'http_req_duration{operation:list_disputes}':['p(95)<800'],
    'http_req_duration{operation:evidence_url}':['p(95)<800'],
    http_req_failed:['rate<0.01'],checks:['rate>0.99'],
    new_submission_attempts:['count>=1000'],
  },
};
// All 1000 VUs arrive before a common burst time. New submissions are measured
// at peak occupancy rather than only during the low-load ramp.
export function setup() { return {createAt: Date.now()+210000}; }
export default function(schedule) {
  if (Date.now()<schedule.createAt) {sleep(Math.min(1,(schedule.createAt-Date.now())/1000));return;}
  const account=accounts[__VU-1];
  if(!account || !account.submissions?.length)throw new Error('Missing local fixture');
  const submission=account.submissions[__ITER % account.submissions.length];
  const headers={apikey:metadata[0].anon_key,Authorization:'Bearer '+account.token,'Content-Type':'application/json'};
  const kind=attempted?'idempotent_retry':'new';if(!attempted)newAttempts.add(1);attempted=true;
  const created=http.post(base+'/rest/v1/rpc/create_dispute',JSON.stringify({p_order_id:submission.order_id,p_request_id:submission.request_id,p_reason:submission.reason,p_description:submission.description,p_evidence_paths:submission.paths}),{headers,timeout:'15s',tags:{operation:'create_dispute',request_kind:kind}});
  // The fixture's request UUID is reused exactly. An unexpected 409 is a failed
  // request here, never disguised as an expected duplicate-business rejection.
  const valid=check(created,{'submission confirmed':r=>r.status===200 && !!r.json('id')});
  const listed=http.post(base+'/rest/v1/rpc/fr25_history','{}',{headers,timeout:'15s',tags:{operation:'list_disputes'}});
  check(listed,{'bounded own history':r=>r.status===200 && Array.isArray(r.json()) && r.json().length<=30});
  if(valid) {
    const signed=http.post(base+'/functions/v1/fr25-evidence',JSON.stringify({action:'view',dispute_id:created.json('id'),index:1}),{headers,timeout:'45s',tags:{operation:'evidence_url'}});
    check(signed,{'private 900-second URL':r=>r.status===200 && r.json('expires_in')===900});
  }
  // Separate negative probe: a second new UUID for an already open order is
  // intentionally rejected. Exclude only this explicitly tagged probe from
  // transport-error metrics, retaining the success check and rejection count.
  if (kind==='new' && valid) {
    const second=submission.negative_request_id;
    if(second){const rejected=http.post(base+'/rest/v1/rpc/fr25_prepare',JSON.stringify({p_request_id:second,p_order_id:submission.order_id}),{headers,responseCallback:http.expectedStatuses(409),tags:{operation:'expected_duplicate_rule'}});
      check(rejected,{'new request cannot bypass open dispute':r=>r.status===409});if(rejected.status===409)expectedRejections.add(1);}
  }
  sleep(2);
}
