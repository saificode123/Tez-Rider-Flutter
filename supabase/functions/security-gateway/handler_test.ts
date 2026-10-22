import {createHandler,type Context,type Dependencies}from './handler.ts';
import {mediaTtl,failureClass}from '../_shared/security-runtime.ts';
function ok(value:unknown):asserts value{if(!value)throw Error('Assertion failed');}
const context:Context={code:'OK',jwt:'synthetic-user',auth_id:'synthetic-actor',session_id:'synthetic-session',session_expires_at:'2030-01-01T00:00:00Z'};
const envelope=(extra={})=>({method:'GET',path:'/products',query:'limit=1',headers:{accept:'application/json'},body:'',...extra});
function setup(changes:Partial<Dependencies>={}){
 const calls={authorize:0,forward:0,audit:[]as number[]};
 const d:Dependencies={authorize:async()=>{calls.authorize++;return context;},forward:async()=>{calls.forward++;return Response.json([{id:1}],{headers:{'content-range':'0-0/1','x-final01-proof':'private-capability'}});},audit:async status=>{calls.audit.push(status);},...changes};
 const handler=createHandler(d);
 return{calls,run:(body:unknown= envelope(),token='Bearer synthetic')=>handler(new Request('https://example.test',{method:'POST',headers:{Authorization:token},body:JSON.stringify(body)})),handler};
}
Deno.test('gateway preserves confirmed rows/range and never exposes private proof',async()=>{
 const{run,calls}=setup();const r=await run();ok(r.status===200);ok((await r.json())[0].id===1);ok(r.headers.get('content-range')==='0-0/1');ok(r.headers.get('x-final01-proof')===null);ok(calls.authorize===1&&calls.forward===1);
});
for(const[code,status]of[['FR28_ACCOUNT_BLOCKED',403],['FR28_SESSION_REVOKED',401],['RATE_LIMITED',429]]as const){
 Deno.test('gateway fails closed for '+code,async()=>{
  const{run,calls}=setup({authorize:async()=>({...context,code,retry_after:17})});const r=await run();ok(r.status===status&&calls.forward===0);if(status===429)ok(r.headers.get('retry-after')==='17');
 });
}
Deno.test('missing JWT never reaches authorization or forwarding',async()=>{const{run,calls}=setup();ok((await run(envelope(),'')).status===401);ok(calls.authorize===0&&calls.forward===0);});
for(const bad of [
 {path:'https://other.test/a'}, {path:'/../private'}, {path:'/%2e%2e/private'},
 {path:'/rpc/final01_authorize_request'}, {path:'/rpc/private.fn'}, {method:'PUT'},
 {query:'x\r\nInjected: value'}, {query:'x#fragment'}, {method:'GET',body:'unexpected'},
 {headers:{'x-final01-proof':'forged'}}, {headers:{authorization:'Bearer other'}},
 {headers:{'accept-profile':'final1_private'}}, {headers:{prefer:'a\r\nb'}}, {actor:'other'},
]){
 Deno.test('gateway rejects untrusted envelope '+JSON.stringify(bad).slice(0,90),async()=>{const{run,calls}=setup();ok((await run(envelope(bad))).status===400);ok(calls.forward===0);});
}
Deno.test('gateway body stream bounded before JSON parse',async()=>{
 const{handler,calls}=setup();const r=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer synthetic'},body:'x'.repeat(1048577)}));ok(r.status===413&&calls.forward===0);
});
Deno.test('method and preflight do not authenticate',async()=>{
 const{handler,calls}=setup();ok((await handler(new Request('https://example.test',{method:'GET'}))).status===405);ok((await handler(new Request('https://example.test',{method:'OPTIONS'}))).status===204);ok(calls.authorize===0);
});
Deno.test('upstream failures are private and classified, never fake successes',async()=>{
 const{run,calls}=setup({forward:async()=>{throw Error('synthetic-private-credential');}});const r=await run();ok(r.status===500);ok(await r.text()==='{"code":"UNAVAILABLE"}');ok(calls.audit.includes(500));
});
Deno.test('confirmed non-success remains non-success',async()=>{
 const{run,calls}=setup({forward:async()=>Response.json({code:'42501'},{status:403})});ok((await run()).status===403);ok(calls.audit.includes(403));
});
Deno.test('audit outage never emits credentials or fabricates confirmed logging',async()=>{
 const{run}=setup({forward:async()=>Response.json({code:'FORBIDDEN'},{status:403}),audit:async()=>{throw Error('synthetic-private');}});const r=await run();ok(r.status===403&&!(await r.text()).includes('synthetic-private'));
});
Deno.test('media URL TTL cannot extend past absolute session deadline',()=>{
 const now=Date.parse('2026-10-22T00:00:00Z');ok(mediaTtl('2026-10-22T00:01:40Z',900,now)===100);ok(mediaTtl('2026-10-23T00:00:00Z',900,now)===900);
 for(const deadline of['invalid','2026-10-21T23:59:59Z']){let denied=false;try{mediaTtl(deadline,900,now);}catch{denied=true;}ok(denied);}
});
Deno.test('failure classes distinguish handled validation/business from security/server failures',()=>{
 ok(failureClass(401)==='authentication'&&failureClass(403)==='authorization'&&failureClass(500)==='server'&&failureClass(503)==='server');
 for(const status of[200,400,409,413,422,429])ok(failureClass(status)===null);
});
