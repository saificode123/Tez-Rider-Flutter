import {serveSecurity, applicationFetch} from '../_shared/security-runtime.ts';
import postgres from 'npm:postgres@3.4.9';
import {createHandler,type Outcome}from './handler.ts';
import {updateAuthState,synchronizeAuth}from './sync.ts';
import {accountBoundary}from '../_shared/fr28-access.ts';
const base=Deno.env.get('SUPABASE_URL')??'';
const local=Deno.env.get('FR28_LOCAL_TEST')==='true'&&['http://127.0.0.1:54321','http://kong:8000'].includes(base);
if(base!=='https://igeisilhtmglgnqvllrx.supabase.co'&&!local)throw Error('Dedicated TEST target required');
const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',anon=Deno.env.get('SUPABASE_ANON_KEY')??'';
const url=Deno.env.get('SUPABASE_DB_URL')??'';
if(!url||!service||!anon)throw Error('Server-only database/Auth configuration missing');
let db:URL;
try{db=new URL(url);}catch{throw Error('Server database configuration invalid');}
if(!['postgres:','postgresql:'].includes(db.protocol))throw Error('Server database protocol invalid');
if(!local&&db.hostname!=='db.igeisilhtmglgnqvllrx.supabase.co'&&!(db.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(db.username)==='postgres.igeisilhtmglgnqvllrx'))throw Error('Dedicated TEST database required');
if(local&&!['127.0.0.1','localhost','db'].includes(db.hostname))throw Error('Isolated local database required');
// A transaction-level advisory lock serializes external actions as well as the
// final SQL transition. Completed request replay never calls Auth again.
const sql=(()=>{try{return postgres(url,{max:1,prepare:false,connect_timeout:8,idle_timeout:5,onnotice:()=>{}});}catch{throw Error('Server database client configuration invalid');}})();
async function rpc(name:string,body:unknown):Promise<Outcome>{
 const response=await applicationFetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(12000)});
 if(response.status===403)return{code:'FORBIDDEN'};
 if(!response.ok)throw Error('Unconfirmed database operation');return await response.json();
}
const handler=createHandler({
 async authenticate(jwt){const r=await applicationFetch(base+'/auth/v1/user',{headers:{apikey:anon,Authorization:'Bearer '+jwt},signal:AbortSignal.timeout(10000)});if(r.status===401||r.status===403)return null;if(!r.ok)throw Error('Auth access could not be confirmed');const user=await r.json();return typeof user.id==='string'?user.id:null;},
 reserve:(actor,target,blocked,request)=>rpc('admin_set_user_blocked',{p_actor:actor,p_target:target,p_blocked:blocked,p_request:request}),
 async synchronize(request,target){
  try{return await sql.begin(async tx=>{
   await tx`set local statement_timeout='12s'`;await tx`set local idle_in_transaction_session_timeout='35s'`;await tx`set local lock_timeout='2s'`;
   await tx`select set_config('request.jwt.claims','{"role":"service_role"}',true)`;
   const lock=await tx`select pg_try_advisory_xact_lock(hashtextextended(${'fr28:'+target},28))as acquired`;
   if(!lock[0].acquired)return{code:'AUTH_SYNC_PENDING',operation_id:request,is_blocked:true};
   const rows=await tx`select public.fr28_sync_context(${request}::uuid)as context`;const context=rows[0].context;
   if(context.code!=='PENDING')return context;
   return await synchronizeAuth({
    change:()=>updateAuthState(base,service,context.auth_id,context.desired_blocked),
    revoke:async()=>{await tx`select public.fr28_revoke_sessions(${request}::uuid)`;},
    finish:async failure=>{const result=await tx`select public.fr28_finish(${request}::uuid,${failure??null})as result`;return result[0].result;},
   });
  })as Outcome;}catch{return{code:'AUTH_SYNC_PENDING',operation_id:request,is_blocked:true};}
 },
});
let active=0;
serveSecurity('admin-user-status', async req=>{
 const denied=await accountBoundary(req,base,anon,true);if(denied)return denied;
 if(active>=4)return Response.json({code:'RATE_LIMIT'},{status:429,headers:{'Access-Control-Allow-Origin':'*','Retry-After':'2','Cache-Control':'no-store'}});
 active++;try{return await handler(req);}finally{active--;}
});
