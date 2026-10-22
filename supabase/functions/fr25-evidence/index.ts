import {serveSecurity, applicationFetch, sessionMediaTtl} from '../_shared/security-runtime.ts';
import {accountBoundary}from '../_shared/fr28-access.ts';
// Isolated private evidence boundary. No credentials, paths or links are logged.
const base = Deno.env.get('SUPABASE_URL') ?? '';
const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const local = Deno.env.get('FR25_LOCAL_TEST') === 'true' && ['http://kong:8000','http://127.0.0.1:54321'].includes(base);
const publicBase = local ? 'http://127.0.0.1:54321' : base;
const bucket = 'dispute-evidence';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info, x-region','Access-Control-Allow-Methods':'POST, OPTIONS'};
class Failure extends Error { constructor(public status:number,message:string) {super(message);} }
function reply(status:number,body:unknown) {return new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});}
async function api(path:string,token:string,method='POST',body?:unknown) {
 const response=await applicationFetch(base+path,{method,headers:{apikey:token===service?service:anon,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 const data=await response.json();
 if(!response.ok) {
  const status=data.code==='42501'?403:data.code==='PT409'?409:data.code==='PT422'||data.code==='22023'?422:response.status>=500?503:400;
  throw new Failure(status,['42501','PT409','PT422','22023'].includes(data.code)?data.message:'Evidence operation could not be confirmed. Retry.');
 }
 return data;
}
async function readBody(req:Request) {
 if(!req.body) throw new Failure(400,'Request required.');
 const reader=req.body.getReader();const parts:Uint8Array[]=[];let length=0;
 try {while(true) {const {done,value}=await reader.read();if(done)break;length+=value.length;
  if(length>7*1024*1024){await reader.cancel();throw new Failure(413,'Maximum image size is 5 MB.');}parts.push(value);}
  const bytes=new Uint8Array(length);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
  return JSON.parse(new TextDecoder().decode(bytes));
 } catch(e){if(e instanceof Failure)throw e;throw new Failure(400,'Invalid request.');}finally{reader.releaseLock();}
}
async function validate(bytes:Uint8Array,mime:string) {
 if(!bytes.length||bytes.length>5242880)throw new Failure(413,'Maximum image size is 5 MB.');
 if(!['image/png','image/jpeg'].includes(mime))throw new Failure(415,'Select a JPEG or PNG image.');
 try {
  if(mime==='image/png') {
   if(![137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v)||bytes.length<33)throw Error();
   const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
   if(!view.getUint32(16)||!view.getUint32(20)||view.getUint32(16)>2048||view.getUint32(20)>2048)throw Error();
   const [{default:pngjs},{Buffer}]=await Promise.all([import('npm:pngjs@7.0.0'),import('node:buffer')]);
   pngjs.PNG.sync.read(Buffer.from(bytes),{checkCRC:true});
  } else {
   const {default:jpeg}=await import('npm:jpeg-js@0.4.4');
   const image=jpeg.decode(bytes,{useTArray:true,maxResolutionInMP:4,maxMemoryUsageInMB:64,tolerantDecoding:false});
   if(!image.width||!image.height||image.width>2048||image.height>2048)throw Error();
  }
 }catch(_){throw new Failure(422,'This file is not a valid JPEG or PNG image.');}
}
const digest=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes)))).map(v=>v.toString(16).padStart(2,'0')).join('');
serveSecurity('fr25-evidence', async(req)=>{
 const denied=await accountBoundary(req,base,anon);if(denied)return denied;
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply(405,{error:'Use POST.'});
 try {
  if((base!=='https://igeisilhtmglgnqvllrx.supabase.co'&&!local)||!anon||!service)throw new Failure(503,'Dedicated TEST configuration required.');
  const token=/^Bearer (\S+)$/.exec(req.headers.get('Authorization')??'')?.[1];
  if(!token)throw new Failure(401,'Sign in first.');
  const identity=await api('/auth/v1/user',token,'GET');
  if(!identity.email_confirmed_at)throw new Failure(403,'Verify your email first.');
  const input=await readBody(req);
  if(input.action==='view') {
   if(!Number.isSafeInteger(input.dispute_id)||!Number.isInteger(input.index))throw new Failure(400,'Invalid evidence reference.');
   const path=await api('/rest/v1/rpc/fr25_evidence_authority',token,'POST',{p_dispute_id:input.dispute_id,p_index:input.index});
   const signed=await api('/storage/v1/object/sign/'+bucket+'/'+path,service,'POST',{expiresIn:sessionMediaTtl()});
   const url=signed.signedURL??signed.signedUrl;
   if(typeof url!=='string')throw new Failure(503,'Evidence unavailable. Retry.');
   return reply(200,{url:publicBase+'/storage/v1'+url,expires_in:sessionMediaTtl()});
  }
  if(typeof input.request_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input.request_id))throw new Failure(400,'Invalid submission identifier.');
  if(input.action==='cleanup') {
   // Database marks abandoned atomically before deletion; a submitted draft returns no paths.
   const paths=await api('/rest/v1/rpc/fr25_abandon',token,'POST',{p_request_id:input.request_id});
   if(paths.length)await api('/storage/v1/object/'+bucket,service,'DELETE',{prefixes:paths});
   return reply(200,{cleaned:true});
  }
  if(input.action!=='upload')throw new Failure(400,'Unknown operation.');
  const authority=await api('/rest/v1/rpc/fr25_upload_authority',token,'POST',{p_request_id:input.request_id});
  if(authority.auth_id!==identity.id)throw new Failure(403,'Evidence access forbidden.');
  if(typeof input.image_base64!=='string'||input.image_base64.length>Math.ceil(5242880/3)*4)throw new Failure(413,'Maximum image size is 5 MB.');
  let bytes:Uint8Array;try{bytes=Uint8Array.from(atob(input.image_base64),c=>c.charCodeAt(0));}catch(_){throw new Failure(422,'Invalid image encoding.');}
  await validate(bytes,input.mime_type);
  const hash=await digest(bytes);
  // Use the database's canonical UUID path, including uppercase UUID retries.
  const path=await api('/rest/v1/rpc/fr25_begin_evidence',service,'POST',{p_auth_id:identity.id,p_request_id:input.request_id,p_digest:hash,p_mime:input.mime_type,p_size:bytes.length});
  if(typeof path!=='string')throw new Failure(503,'Evidence reservation was not confirmed. Retry.');
  const upload=await applicationFetch(base+'/storage/v1/object/'+bucket+'/'+path,{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':input.mime_type,'x-upsert':'false','cache-control':'0'},body:new Uint8Array(bytes),signal:AbortSignal.timeout(30000)});
  if(!upload.ok) {
   const data=await upload.json();
   if(![409,'409','Duplicate'].includes(data.statusCode)&&upload.status!==409)throw new Failure(503,'Upload was not confirmed. Retry.');
   // Ambiguous/repeated upload: compare actual immutable bytes, not a MIME claim.
   const existing=await applicationFetch(base+'/storage/v1/object/authenticated/'+bucket+'/'+path,{headers:{apikey:service,Authorization:'Bearer '+service},signal:AbortSignal.timeout(15000)});
   if(!existing.ok||await digest(new Uint8Array(await existing.arrayBuffer()))!==hash)throw new Failure(409,'Evidence conflict. Retry.');
  }
  const confirmed=await api('/rest/v1/rpc/fr25_finish_upload',service,'POST',{p_auth_id:identity.id,p_request_id:input.request_id,p_digest:hash,p_mime:input.mime_type,p_size:bytes.length});
  return reply(200,{path:confirmed});
 }catch(e){return e instanceof Failure?reply(e.status,{error:e.message}):reply(503,{error:'Evidence operation was not confirmed. Retry.'});}
});
