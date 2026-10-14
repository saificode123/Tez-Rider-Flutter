export type Result = {code: string; retry_after?: number; replayed?: boolean; otp?: string; recipient?: string; issuance_id?: string};
export interface Dependencies {
 authenticate(jwt: string): Promise<string | null>;
 reserve(order: number, request: string, actor: string): Promise<Result>;
 start(id: string): Promise<boolean>;
 finish(id: string, state: 'ACCEPTED' | 'FAILED' | 'UNKNOWN', provider?: string): Promise<Result>;
 send(recipient: string, otp: string): Promise<{state: 'ACCEPTED' | 'FAILED' | 'UNKNOWN'; provider?: string; code?: string}>;
}
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function response(code: string, extra: Record<string, unknown> = {}) {
 const status = code==='FORBIDDEN'?403:code==='UNAUTHENTICATED'?401:code==='FORMAT'?400:code==='EMAIL_FAILED'||code==='EMAIL_UNKNOWN'||code==='UNAVAILABLE'?503:200;
 return new Response(JSON.stringify({code,...extra}),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
}
async function payload(req: Request) {
 if(!req.body)throw Error();const reader=req.body.getReader();let raw='';let length=0;
 try {while(true){const part=await reader.read();if(part.done)break;length+=part.value.byteLength;if(length>1024){await reader.cancel();throw Error();}raw+=new TextDecoder().decode(part.value);}}finally{reader.releaseLock();}
 const data=JSON.parse(raw);
 if(!data||Array.isArray(data)||Object.keys(data).some(k=>!['order_id','request_id'].includes(k))||!Number.isSafeInteger(data.order_id)||data.order_id<=0||!uuid.test(data.request_id??''))throw Error();
 return data as {order_id:number;request_id:string};
}
export function createHandler(deps: Dependencies) {
 return async (req: Request): Promise<Response> => {
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
  if(req.method!=='POST')return response('FORMAT');
  const match=/^Bearer ([^\s]+)$/i.exec(req.headers.get('authorization')??'');if(!match)return response('UNAUTHENTICATED');
  let input:{order_id:number;request_id:string};try{input=await payload(req);}catch{return response('FORMAT');}
  try {
   const actor=await deps.authenticate(match[1]);if(!actor)return response('UNAUTHENTICATED');
   const reserved=await deps.reserve(input.order_id,input.request_id,actor);
   if(reserved.code!=='SEND')return response(reserved.code,{...(reserved.retry_after!==undefined?{retry_after:reserved.retry_after}:{}),...(reserved.replayed?{replayed:true}:{})});
   if(!reserved.otp||!/^\d{6}$/.test(reserved.otp)||!reserved.recipient||reserved.issuance_id!==input.request_id)return response('UNAVAILABLE');
   if(!await deps.start(input.request_id))return response('EMAIL_PENDING');
   let sent:{state:'ACCEPTED'|'FAILED'|'UNKNOWN';provider?:string;code?:string};
   try{sent=await deps.send(reserved.recipient,reserved.otp);}catch{sent={state:'UNKNOWN'};}
   // No automatic external retry. Lost provider/finalization responses reconcile by request ID.
   const final=await deps.finish(input.request_id,sent.state,sent.provider);
   return response(final.code==='EMAIL_FAILED'&&sent.code?sent.code:final.code);
  } catch{return response('UNAVAILABLE');}
 };
}
