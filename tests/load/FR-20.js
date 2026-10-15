import http from 'k6/http';
import {check,sleep} from 'k6';
import {SharedArray} from 'k6/data';
import {Counter,Rate} from 'k6/metrics';
const base=__ENV.FR20_LOCAL_URL;
if(base!=='http://127.0.0.1:54321')throw Error('Only the unlinked FR20 loopback stack is allowed');
const fixture=new SharedArray('FR20 isolated fixtures',()=>[JSON.parse(open(__ENV.FR20_FIXTURE_FILE))])[0];
if(fixture.synthetic_only!==true||fixture.project_ref!=='tezrider-fr20-local')throw Error('Dedicated FR20 synthetic marker required');
const errors=new Rate('unexpected_errors');
const business=new Counter('expected_business_results');
export const options={
 stages:__ENV.FR20_LOAD_PROFILE==='full'?[{duration:'15s',target:10},{duration:'25s',target:100},{duration:'25s',target:500},{duration:'30s',target:1000},{duration:'10s',target:0}]:[{duration:'5s',target:2},{duration:'10s',target:10},{duration:'5s',target:0}],
 thresholds:{http_req_duration:['p(95)<800'],unexpected_errors:['rate<0.01'],checks:['rate>0.99']},
};
export default function(){
 // Each two VUs share an order, while all orders compete for the same bounded
 // rider pool. Repeated calls exercise assignment and escalation deduplication.
 const id=fixture.orders[Math.floor((__VU-1)/2)%fixture.orders.length];
 const response=http.post(base+'/rest/v1/rpc/fr21_ready_and_assign',JSON.stringify({p_vendor_order_id:id}),{headers:{apikey:fixture.anon_key,Authorization:'Bearer '+fixture.vendor_token,'Content-Type':'application/json'},timeout:'12s',tags:{operation:'assignment'}});
 let code;try{code=response.json('code');}catch(_){}
 const expected=['ASSIGNED_5KM','ASSIGNED_10KM','ALREADY_ASSIGNED','NO_RIDER_AVAILABLE','RETRYABLE_CONFLICT'];
 const ok=response.status===200&&expected.includes(code);
 check(response,{'structured authorized assignment result':()=>ok});errors.add(!ok);
 if(ok)business.add(1,{code});
 sleep(.3);
}
