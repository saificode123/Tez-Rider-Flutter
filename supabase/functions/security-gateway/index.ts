import {createHandler}from './handler.ts';
import {authorizeRequest,requestTicket,recordFailure}from '../_shared/security-runtime.ts';
const base=Deno.env.get('SUPABASE_URL')??'',anon=Deno.env.get('SUPABASE_ANON_KEY')??'';
if(base!=='https://igeisilhtmglgnqvllrx.supabase.co')throw Error('Isolated TEST required');
Deno.serve(createHandler({
 authorize:jwt=>authorizeRequest(jwt,base,anon),
 async forward(context,method,path,query,headers,body){
  headers.set('apikey',anon);headers.set('Authorization','Bearer '+context.jwt);
  headers.set('x-final01-proof',await requestTicket(context,method,path));
  const r=await fetch(base+'/rest/v1'+path+(query?'?'+query:''),{method,headers,body:['GET','HEAD'].includes(method)?undefined:body,signal:AbortSignal.timeout(15000)});
  const reader=r.body?.getReader();const chunks:Uint8Array[]=[];let length=0;
  if(reader)try{while(true){const{done,value}=await reader.read();if(done)break;length+=value.length;if(length>4194304)throw Error('RESPONSE_TOO_LARGE');chunks.push(value);}}finally{await reader.cancel();}
  const bytes=new Uint8Array(length);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
  return new Response([204,205,304].includes(r.status)||method==='HEAD'?null:bytes,{status:r.status,headers:r.headers});
 },
 audit:(status,actor)=>recordFailure('rest',status,actor),
}));
