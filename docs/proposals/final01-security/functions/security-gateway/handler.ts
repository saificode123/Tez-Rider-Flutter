export type Context = {code: string; jwt: string; auth_id?: string; session_id?: string; session_expires_at?: string; retry_after?: number};
export interface Dependencies {
 authorize(jwt: string): Promise<Context>;
 forward(context: Context, method: string, path: string, query: string, headers: Headers, body: string): Promise<Response>;
 audit(status: number, actor?: string): Promise<void>;
}
const cors = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info', 'Cache-Control': 'no-store'};
const methods = new Set(['GET','POST','PATCH','DELETE','HEAD']);
const allowedHeaders = new Set(['accept','content-type','prefer','range','range-unit','accept-profile','content-profile']);
export function createHandler(d: Dependencies) {
 return async (req: Request): Promise<Response> => {
  const reply = (code: string, status: number, retry?: number) => Response.json({code}, {status, headers: {...cors, ...(retry ? {'Retry-After': String(retry)} : {})}});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return reply('METHOD_NOT_ALLOWED',405);
  let context: Context | undefined;
  const finish = async (r: Response) => {
   try { await d.audit(r.status, context?.auth_id); } catch { /* Preserve failure; no fabricated audit confirmation. */ }
   return r;
  };
  try {
   const jwt=req.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];
   if(!jwt||jwt.length>8192)return await finish(reply('AUTHENTICATION_REQUIRED',401));
   context=await d.authorize(jwt);
   if(context.code!=='OK')return await finish(reply(context.code,context.code==='RATE_LIMITED'?429:context.code==='FR28_ACCOUNT_BLOCKED'?403:401,context.retry_after));
   const reader=req.body?.getReader();if(!reader)return reply('INVALID_REQUEST',400);
   const chunks:Uint8Array[]=[];let length=0;
   try {while(true){const{done,value}=await reader.read();if(done)break;length+=value.length;if(length>1048576)return reply('INVALID_REQUEST',413);chunks.push(value);}}finally{await reader.cancel();}
   const bytes=new Uint8Array(length);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
   let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return reply('INVALID_REQUEST',400);}
   if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!['method','path','query','headers','body'].includes(k))||
    !methods.has(body.method)||typeof body.path!=='string'||!/^\/(rpc\/)?[a-z][a-z0-9_]{0,100}$/.test(body.path)||
    body.path==='/rpc/final01_authorize_request'||typeof body.query!=='string'||body.query.length>8192||/[\r\n#]/.test(body.query)||
    typeof body.body!=='string'||(['GET','HEAD'].includes(body.method)&&body.body!=='')||!body.headers||typeof body.headers!=='object'||Array.isArray(body.headers))return reply('INVALID_REQUEST',400);
   const headers=new Headers();
   for(const[k,v]of Object.entries(body.headers)){
    if(!allowedHeaders.has(k.toLowerCase())||typeof v!=='string'||v.length>2048||/[\r\n]/.test(v))return reply('INVALID_REQUEST',400);
    if(['accept-profile','content-profile'].includes(k.toLowerCase())&&v!=='public')return reply('INVALID_REQUEST',400);
    headers.set(k,v);
   }
   const response=await d.forward(context,body.method,body.path,body.query,headers,body.body);
   const outgoing=new Headers(cors);
   for(const key of ['content-type','content-range','range-unit','preference-applied','retry-after','etag']){
    const value=response.headers.get(key);if(value)outgoing.set(key,value);
   }
   // Never expose internal authorization headers/proofs or an arbitrary origin.
   return await finish(new Response(response.body,{status:response.status,headers:outgoing}));
  }catch{
   return await finish(reply('UNAVAILABLE',500));
  }
 };
}
