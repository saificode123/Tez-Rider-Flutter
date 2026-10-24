import {serveSecurity, applicationFetch, sessionMediaTtl, currentSecurityContext} from '../_shared/security-runtime.ts';
import {accountBoundary} from '../_shared/fr28-access.ts';
import {Failure, validateImage, imageDigest} from '../_shared/validated-image.ts';
const base=Deno.env.get('SUPABASE_URL')??'';
const anon=Deno.env.get('SUPABASE_ANON_KEY')??'';
const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
const bucket='final2-private-photos';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
async function api(path:string,token:string,body?:unknown){
 const response=await applicationFetch(base+path,{method:body===undefined?'GET':'POST',headers:{apikey:token===service?service:anon,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 const data=await response.json();
 if(!response.ok)throw new Failure(data.code==='42501'?403:data.code==='PT409'?409:data.code==='22023'?422:response.status>=500?503:400,'Image access or upload could not be confirmed. Retry.');
 return data;
}
async function body(req:Request){
 if(!req.body)throw new Failure(400,'Request required.');
 const reader=req.body.getReader();let size=0;const parts:Uint8Array[]=[];
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;
  if(size>7*1024*1024){await reader.cancel();throw new Failure(413,'Maximum image size is 5 MB.');}parts.push(value);}
  const bytes=new Uint8Array(size);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
  const value=JSON.parse(new TextDecoder().decode(bytes));
  if(!value||typeof value!=='object'||Array.isArray(value))throw Error();return value;
 }catch(error){if(error instanceof Failure)throw error;throw new Failure(400,'Invalid request.');}finally{reader.releaseLock();}
}
const uuid=(value:unknown):value is string=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
serveSecurity('final2-private-photo',async(req)=>{
 const denied=await accountBoundary(req,base,anon);if(denied)return denied;
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply(405,{error:'Use POST.'});
 try{
  if(base!=='https://igeisilhtmglgnqvllrx.supabase.co'||!anon||!service)throw new Failure(503,'Dedicated TEST configuration required.');
  const token=/^Bearer (\S+)$/.exec(req.headers.get('Authorization')??'')?.[1];
  if(!token)throw new Failure(401,'Sign in first.');
  const identity=await api('/auth/v1/user',token);
  if(!identity.email_confirmed_at)throw new Failure(403,'Verify your email first.');
  const input=await body(req);
  if(input.action==='view'){
   if(!uuid(input.image_id))throw new Failure(400,'Invalid image reference.');
   const image=await api('/rest/v1/rpc/final2_photo_view',token,{p_image_id:input.image_id});
   const response=await applicationFetch(base+'/storage/v1/object/authenticated/'+bucket+'/'+image.path,{headers:{apikey:service,Authorization:'Bearer '+service},signal:AbortSignal.timeout(15000)});
   if(!response.ok)throw new Failure(503,'Image unavailable. Retry.');
   const bytes=new Uint8Array(await response.arrayBuffer());
   if(bytes.length!==image.size||await imageDigest(bytes)!==image.digest)throw new Failure(503,'Image could not be verified.');
   // No private Storage URL is returned or persisted. The authorized response is
   // displayed in memory and cleared when the client account changes.
   let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
   return reply(200,{image_base64:btoa(binary),mime_type:image.mime,expires_in:sessionMediaTtl()});
  }
  if(input.action!=='upload'||!uuid(input.request_id))throw new Failure(400,'Invalid image submission.');
  if(!['avatar','delivery'].includes(input.kind)||!(input.order_id===null||input.order_id===undefined||Number.isSafeInteger(input.order_id)&&input.order_id>0))throw new Failure(400,'Invalid photo scope.');
  await api('/rest/v1/rpc/final2_photo_authority',token,{p_kind:input.kind,p_order_id:input.order_id??null});
  if(typeof input.image_base64!=='string'||input.image_base64.length>Math.ceil(5242880/3)*4)throw new Failure(413,'Maximum image size is 5 MB.');
  let bytes:Uint8Array;try{bytes=Uint8Array.from(atob(input.image_base64),c=>c.charCodeAt(0));}catch(_){throw new Failure(422,'Invalid image encoding.');}
  await validateImage(bytes,input.mime_type);const hash=await imageDigest(bytes);
  const context=currentSecurityContext();if(!context?.session_id)throw new Failure(401,'Live session required.');
  const params={p_session_id:context.session_id,p_kind:input.kind,p_order_id:input.order_id??null,p_auth_id:identity.id,p_request_id:input.request_id,p_digest:hash,p_mime:input.mime_type,p_size:bytes.length};
  const path=await api('/rest/v1/rpc/final2_photo_begin',service,params);
  const response=await applicationFetch(base+'/storage/v1/object/'+bucket+'/'+path,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':input.mime_type,'x-upsert':'false','cache-control':'0'},body:new Uint8Array(bytes),signal:AbortSignal.timeout(30000)});
  if(!response.ok){
   const error=await response.json();
   if(response.status!==409&&![409,'409','Duplicate'].includes(error.statusCode))throw new Failure(503,'Upload not confirmed. Retry the same image.');
   const previous=await applicationFetch(base+'/storage/v1/object/authenticated/'+bucket+'/'+path,{headers:{apikey:service,Authorization:'Bearer '+service},signal:AbortSignal.timeout(15000)});
   if(!previous.ok||await imageDigest(new Uint8Array(await previous.arrayBuffer()))!==hash)throw new Failure(409,'Image conflict. Retry the original submission.');
  }
  const reference=await api('/rest/v1/rpc/final2_photo_finish',service,params);
  return reply(200,{reference});
 }catch(error){return error instanceof Failure?reply(error.status,{error:error.message}):reply(503,{error:'Image operation was not confirmed. Retry.'});}
});
