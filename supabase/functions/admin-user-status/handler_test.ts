import { createHandler } from './handler.ts';
import { synchronizeAuth, updateAuthState } from './sync.ts';
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
const requestId = '11111111-1111-4111-8111-111111111111';
const request = (auth = true, body: unknown = {target_id: 2, blocked: true, request_id: requestId}) => new Request('http://localhost', {method:'POST', headers:auth ? {Authorization:'Bearer synthetic'} : {}, body:JSON.stringify(body)});
for (const [code,status] of [['FORBIDDEN',403],['SELF_FORBIDDEN',403],['ADMIN_PROTECTED',403],['NOT_FOUND',404],['BUSY',409],['REQUEST_CONFLICT',409],['NO_CHANGE',200],['ALREADY_APPLIED',200]] as const) {
  Deno.test(`reserve ${code} never calls Auth`, async () => {
    const handler=createHandler({authenticate:async()=> 'actor',reserve:async()=>({code}),synchronize:()=>{throw Error('Unexpected Auth action');}});
    equal((await handler(request())).status,status);
  });
}
Deno.test('missing and invalid JWT rejected',async()=>{
 const handler=createHandler({authenticate:async()=>null,reserve:()=>{throw Error('Unexpected reservation');},synchronize:()=>{throw Error('Unexpected Auth');}});
 equal((await handler(request(false))).status,401);equal((await handler(request())).status,401);
});
Deno.test('invalid input and oversized body rejected',async()=>{
 const handler=createHandler({authenticate:async()=> 'actor',reserve:()=>{throw Error('Unexpected reservation');},synchronize:()=>{throw Error('Unexpected Auth');}});
 equal((await handler(request(true,{target_id:2,blocked:true,request_id:requestId,actor_id:'forged'}))).status,400);
 equal((await handler(request(true,{value:'a'.repeat(2000)}))).status,413);
});
Deno.test('database reservation precedes Auth; partial failure returns 202',async()=>{
 const calls:string[]=[];
 const handler=createHandler({authenticate:async()=> 'actor',reserve:async()=>{calls.push('commit');return {code:'PENDING',active_orders:{order_ids:[9]}};},synchronize:async()=>{calls.push('Auth');return {code:'AUTH_SYNC_PENDING'};}});
 const response=await handler(request());equal(response.status,202);equal(calls,['commit','Auth']);equal((await response.json()).active_orders,{order_ids:[9]});
});
Deno.test('internal errors and credentials are redacted',async()=>{
 const handler=createHandler({authenticate:async()=>{throw Error('secret-token');},reserve:async()=>({code:'PENDING'}),synchronize:async()=>({code:'OK'})});
 const response=await handler(request());equal(response.status,503);equal(await response.json(),{code:'OPERATION_UNCONFIRMED'});
});
for(const blocked of [true,false])Deno.test(`Auth ${blocked?'ban':'unban'} supported request and confirmation`,async()=>{
 const fake:typeof fetch=async(_input,init)=>{
  equal(JSON.parse(String(init?.body)),{ban_duration:blocked?'876000h':'none'});
  return Response.json({id:'target',banned_until:blocked?'2126-01-01T00:00:00Z':null});
 };
 equal(await updateAuthState('http://localhost','server-secret','target',blocked,fake),true);
 equal(await updateAuthState('http://localhost','server-secret','target',blocked,async()=>new Response('',{status:429})),false);
 equal(await updateAuthState('http://localhost','server-secret','target',blocked,async()=>Response.json({id:'other',banned_until:null})),false);
});
for(const failure of ['AUTH_UNCONFIRMED','SESSIONS_UNCONFIRMED',undefined])Deno.test(`synchronization ${failure??'success'} and recovery`,async()=>{
 const calls:string[]=[];
 const result=await synchronizeAuth({change:async()=>{calls.push('Auth');return failure!=='AUTH_UNCONFIRMED';},revoke:async()=>{calls.push('sessions');if(failure==='SESSIONS_UNCONFIRMED')throw Error('redacted');},finish:async error=>{calls.push(error??'finish');return {code:error?'AUTH_SYNC_PENDING':'OK'};}});
 equal(result.code,failure?'AUTH_SYNC_PENDING':'OK');equal(calls,failure==='AUTH_UNCONFIRMED'?['Auth',failure]:['Auth','sessions',failure??'finish']);
 const recovered=await synchronizeAuth({change:async()=>true,revoke:async()=>{},finish:async()=>({code:'OK'})});equal(recovered.code,'OK');
});
