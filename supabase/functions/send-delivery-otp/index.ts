import {serveSecurity, applicationFetch} from '../_shared/security-runtime.ts';
import {accountBoundary}from '../_shared/fr28-access.ts';
import {createHandler, type Dependencies, type Result} from './handler.ts';
function dependencies(): Dependencies {
 const base=Deno.env.get('SUPABASE_URL')??'';
 const local=Deno.env.get('FR33_LOCAL_TEST')==='true'&&['http://kong:8000','http://127.0.0.1:54321'].includes(base);
 if(base!=='https://igeisilhtmglgnqvllrx.supabase.co'&&!local)throw Error('Authorized TEST target required');
 const anon=Deno.env.get('SUPABASE_ANON_KEY')??'',service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
 const key=Deno.env.get('BREVO_API_KEY')??'',sender=Deno.env.get('BREVO_SENDER_EMAIL')??'';
 const recipientAllowed=Deno.env.get('BREVO_TEST_RECIPIENT')??'';
 const mock=Deno.env.get('FR33_MOCK_EMAIL_URL');
 if(mock&&(!local||!/^http:\/\/(127\.0\.0\.1|host\.docker\.internal):\d+\/send$/.test(mock)))throw Error('Isolated local mock only');
 if(!service||!anon||(!mock&&(!key||!sender||!recipientAllowed)))throw Error('Private TEST email configuration required');
 async function rpc(name: string, body: unknown): Promise<any> {
  const r=await applicationFetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  if(!r.ok)throw Error('Database operation unconfirmed');return await r.json();
 }
 return {
  async authenticate(jwt) {
   const r=await applicationFetch(base+'/auth/v1/user',{headers:{apikey:anon,Authorization:'Bearer '+jwt},signal:AbortSignal.timeout(10000)});
   if(!r.ok)return null;const user=await r.json();return typeof user.id==='string'?user.id:null;
  },
  reserve:(order,request,actor)=>rpc('issue_delivery_otp',{p_order_id:order,p_request_id:request,p_actor:actor}) as Promise<Result>,
  start:(id)=>rpc('fr33_start_send',{p_id:id}),
  finish:(id,state,provider)=>rpc('fr33_finish_send',{p_id:id,p_result:state,p_provider_id:provider??null}) as Promise<Result>,
  async send(recipient,otp) {
   if(!mock&&recipient.toLowerCase()!==recipientAllowed.toLowerCase())return {state:'FAILED',code:'TEST_RECIPIENT_ONLY'};
   try {
    const r=await applicationFetch(mock??'https://api.brevo.com/v3/smtp/email',{method:'POST',headers:{'api-key':mock?'local-mock':key,'Content-Type':'application/json',Accept:'application/json','User-Agent':'TezRider-TEST-FR33'},body:JSON.stringify({sender:{name:'TezRider TEST',email:sender||'sender@example.test'},to:[{email:recipient}],subject:'TezRider delivery verification',textContent:'Your TezRider delivery verification code is '+otp+'. It expires in 10 minutes. Share it only with your assigned rider when receiving your order.'}),signal:AbortSignal.timeout(20000)});
    if(r.status===201){const body=await r.json();if(typeof body.messageId==='string'&&body.messageId.length>0&&body.messageId.length<=200)return {state:'ACCEPTED',provider:body.messageId};return {state:'UNKNOWN'};}
    if(r.status>=500)return {state:'UNKNOWN'};
    let reason='EMAIL_FAILED';if(r.status===429)reason='RATE_LIMIT';
    try {const body=await r.json();if(['not_enough_credits','insufficient_credits'].includes(body.code))reason='QUOTA_EXCEEDED';}catch{/* Only safe outcome codes leave this boundary. */}
    return {state:'FAILED',code:reason};
   }catch{return {state:'UNKNOWN'};}
  },
 };
}
serveSecurity('send-delivery-otp', {hostname:Deno.env.get('FR33_LOCAL_TEST')==='true'?'127.0.0.1':'0.0.0.0'},async req=>{
 try{const denied=await accountBoundary(req,Deno.env.get('SUPABASE_URL')??'',Deno.env.get('SUPABASE_ANON_KEY')??'');if(denied)return denied;return await createHandler(dependencies())(req);}catch{return new Response(JSON.stringify({code:'UNAVAILABLE'}),{status:503,headers:{'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*'}});}
});
