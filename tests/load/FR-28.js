import http from 'k6/http';
import {check,sleep} from 'k6';
import {SharedArray} from 'k6/data';
import {Counter,Rate} from 'k6/metrics';
const base=__ENV.FR28_LOCAL_URL;
if(base!=='http://127.0.0.1:54321')throw Error('FR28 load requires isolated loopback Supabase; hosted TEST and production forbidden');
const fixture=new SharedArray('FR28 isolated synthetic fixtures',()=>[JSON.parse(open(__ENV.FR28_FIXTURE_FILE))])[0];
if(fixture.synthetic_only!==true||fixture.project_ref!=='local-fr28')throw Error('Dedicated synthetic fixture marker required');
const expected=new Counter('expected_authorization_rejections');
const errors=new Rate('unexpected_errors');
export const options={stages:__ENV.FR28_LOAD_PROFILE==='full'?[{duration:'30s',target:10},{duration:'45s',target:100},{duration:'45s',target:500},{duration:'60s',target:1000},{duration:'30s',target:0}]:[{duration:'10s',target:2},{duration:'15s',target:5},{duration:'10s',target:0}],thresholds:{http_req_duration:['p(95)<800'],unexpected_errors:['rate<0.01'],checks:['rate>0.99']}};
function call(path,token,body,operation){
 const headers={apikey:fixture.anon_key,Authorization:'Bearer '+token,'Content-Type':'application/json'};
 return body===undefined?http.get(base+path,{headers,tags:{operation}}):http.post(base+path,JSON.stringify(body),{headers,tags:{operation}});
}
function assertResult(response,statuses,label){const ok=statuses.includes(response.status);check(response,{[label]:()=>ok});errors.add(!ok);if([401,403,409,429].includes(response.status))expected.add(1);}
export default function(){
 const row=fixture.accounts[(__VU-1)%fixture.accounts.length];
 assertResult(call('/rest/v1/orders?select=id&limit=10',row.allowed_token,undefined,'protected_read'),[200],'allowed bounded read');
 assertResult(call('/rest/v1/orders?select=id&limit=10',row.blocked_token,undefined,'blocked_read'),[403],'existing blocked JWT denied');
 assertResult(call('/rest/v1/rpc/fr28_user_list',fixture.admin_token,{p_limit:25},'admin_list'),[200],'bounded admin list');
 // Dedicated target per pair, idempotency IDs pre-generated in local fixture.
 const pair=fixture.targets[Math.floor((__VU-1)/2)%fixture.targets.length];
 const blocked=__VU%2===0;
 assertResult(call('/functions/v1/admin-user-status',fixture.admin_token,{target_id:pair.id,blocked,request_id:pair.requests[blocked?'block':'unblock'][__ITER%pair.requests.block.length]},'concurrent_change'),[200,202,409,429],'concurrent synthetic change or expected conflict');
 sleep(.5);
}
