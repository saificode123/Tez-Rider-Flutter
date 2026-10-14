import http from 'k6/http';
import {check,sleep} from 'k6';
import {SharedArray} from 'k6/data';
import {Counter} from 'k6/metrics';
const base=__ENV.FR33_LOCAL_URL;
const issue=__ENV.FR33_LOCAL_ISSUE_URL;
if(base!=='http://127.0.0.1:54321'||issue!=='http://127.0.0.1:8000')throw Error('Isolated loopback targets required; hosted email/load forbidden');
const data=new SharedArray('protected local fixtures',()=>[JSON.parse(open(__ENV.FR33_FIXTURE_FILE))])[0];
if(data.project_id!=='tezrider-fr25-local'||data.real_email_enabled!==false)throw Error('Wrong isolated fixture boundary');
const conflicts=new Counter('expected_business_rejections');
const profile=__ENV.FR33_LOAD_PROFILE;
export const options={stages:profile==='full'?[{duration:'30s',target:10},{duration:'45s',target:100},{duration:'45s',target:500},{duration:'60s',target:1000},{duration:'30s',target:0}]:[{duration:'10s',target:5},{duration:'15s',target:10},{duration:'10s',target:0}],thresholds:{'http_req_duration{operation:verify}':['p(95)<800'],'http_req_duration{operation:issue_mock}':['p(95)<800'],'http_req_failed':['rate<0.01'],checks:['rate>0.99']}};
export default function(){
 const row=data.cases[Math.floor((__VU-1)/2)%data.cases.length];
 const headers={apikey:data.anon_key,Authorization:'Bearer '+row.token,'Content-Type':'application/json'};
 const invalid=(__VU%2===0&&__ITER===0);
 const result=http.post(base+'/rest/v1/rpc/verify_delivery_otp',JSON.stringify({p_order_id:row.verify_order,p_otp:invalid?row.wrong:row.code,p_request_id:row.verify_requests[__VU%2]}),{headers,tags:{operation:'verify'}});
 let body;try{body=result.json();}catch{body={};}
 const expected=['OK','ALREADY_DELIVERED','INVALID','LOCKED','EXPIRED','RATE_LIMIT','REQUEST_CONFLICT'];
 check(result,{'verification structured authorized result':r=>r.status===200&&expected.includes(body.code)});
 if(!['OK','ALREADY_DELIVERED'].includes(body.code))conflicts.add(1);
 const sent=http.post(issue,JSON.stringify({order_id:row.issue_order,request_id:row.issue_requests[__ITER%row.issue_requests.length]}),{headers,tags:{operation:'issue_mock'}});
 let state;try{state=sent.json();}catch{state={};}
 const allowed=['EMAIL_ACCEPTED','EMAIL_PENDING','COOLDOWN','ISSUANCE_LIMIT','RATE_LIMIT','QUOTA_EXCEEDED','ALREADY_DELIVERED'];
 check(sent,{'local mocked issuance structured result':r=>r.status===200&&allowed.includes(state.code)});
 if(state.code!=='EMAIL_ACCEPTED')conflicts.add(1);
 sleep(.5);
}
