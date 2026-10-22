import {securityHandler,applicationFetch}from './security-runtime.ts';
function ok(v:unknown):asserts v{if(!v)throw Error('Assertion failed');}
const base='https://igeisilhtmglgnqvllrx.supabase.co';
const vars={SUPABASE_URL:base,SUPABASE_ANON_KEY:'synthetic-anon',SUPABASE_SERVICE_ROLE_KEY:'synthetic-service'};
const good={code:'OK',auth_id:'00000000-0000-4000-8000-000000000001',session_id:'00000000-0000-4000-8000-000000000002',role:'customer',session_expires_at:'2030-01-01T00:00:00Z'};
const info={remoteAddr:{transport:'tcp',hostname:'127.0.0.1',port:1}}as Deno.ServeHandlerInfo;
async function isolated(test:(counts:{authorization:number,tickets:number,forward:number,audit:number})=>Promise<void>,result:unknown=good){
 const oldFetch=globalThis.fetch;const previous:Record<string,string|undefined>={};
 for(const[k,v]of Object.entries(vars)){previous[k]=Deno.env.get(k);Deno.env.set(k,v);}
 const counts={authorization:0,tickets:0,forward:0,audit:0};
 globalThis.fetch=async(input,init)=>{
  const r=new Request(input,init);
  if(r.url.endsWith('/rpc/final01_authorize_request')){counts.authorization++;ok(r.headers.get('Authorization')==='Bearer synthetic-user');return Response.json(result);}
  if(r.url.endsWith('/rpc/final01_request_ticket')){counts.tickets++;ok(r.headers.get('Authorization')==='Bearer synthetic-service');return Response.json('synthetic-private-proof');}
  if(r.url.endsWith('/rpc/final01_record_failure')){counts.audit++;return Response.json(true);}
  counts.forward++;ok(r.headers.get('Authorization')==='Bearer synthetic-user');ok(r.headers.get('x-final01-proof')==='synthetic-private-proof');return Response.json({code:'OK'});
 };
 try{await test(counts);}finally{globalThis.fetch=oldFetch;for(const[k,v]of Object.entries(previous)){if(v===undefined)Deno.env.delete(k);else Deno.env.set(k,v);}}
}
Deno.test('one incoming Edge request claims shared budget once while internal RPCs retain user RLS',()=>isolated(async counts=>{
 const handler=securityHandler('shopping-assistant',async()=>{
  for(const name of['fr28_account_status','final1_claim_assistant']){
   const r=await applicationFetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{Authorization:'Bearer synthetic-user'},body:'{}'});ok(r.ok);
  }
  return Response.json({code:'OK'});
 });
 const r=await handler(new Request(base+'/functions/v1/shopping-assistant',{method:'POST',headers:{Authorization:'Bearer synthetic-user'},body:'{}'}),info);
 ok(r.status===200&&counts.authorization===1&&counts.tickets===2&&counts.forward===2);ok(!(await r.text()).includes('private-proof'));
}));
for(const[code,status]of[['FR28_SESSION_REVOKED',401],['FR28_ACCOUNT_BLOCKED',403],['RATE_LIMITED',429]]as const){
 Deno.test('shared Edge boundary denies '+code+' before handler/provider',()=>isolated(async counts=>{
  let called=false;const handler=securityHandler('fr04-cnic',()=>{called=true;return Response.json({code:'BAD'});});
  const r=await handler(new Request(base,{method:'POST',headers:{Authorization:'Bearer synthetic-user'},body:'{}'}),info);
  ok(r.status===status&&!called&&counts.forward===0&&counts.tickets===0);if(status===429)ok(r.headers.get('retry-after')==='19');
 },{code,retry_after:19}));
}
Deno.test('unhandled Edge exception gives private500 and trusted classified audit',()=>isolated(async counts=>{
 const handler=securityHandler('fr04-cnic',()=>{throw Error('synthetic-private-credential');});
 const r=await handler(new Request(base,{method:'POST',headers:{Authorization:'Bearer synthetic-user'},body:'{}'}),info);
 ok(r.status===500&&!(await r.text()).includes('credential')&&counts.audit===1);
}));
Deno.test('trusted workers retain independent worker-secret handler',()=>isolated(async counts=>{
 let called=false;const handler=securityHandler('fr32-email-worker',()=>{called=true;return Response.json({code:'WORKER_DENIED'},{status:403});});
 const r=await handler(new Request(base,{method:'POST',body:'{}'}),info);ok(called&&r.status===403&&counts.authorization===0&&counts.audit===1);
}));
