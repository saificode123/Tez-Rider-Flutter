export type Outcome = {code:string;[key:string]:unknown};
export interface Dependencies {
 authenticate(jwt:string):Promise<string|null>;
 reserve(actor:string,target:number,blocked:boolean,request:string):Promise<Outcome>;
 synchronize(request:string,target:number):Promise<Outcome>;
}
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store'};
const reply=(status:number,body:unknown)=>Response.json(body,{status,headers:cors});
export function createHandler(deps:Dependencies):(req:Request)=>Promise<Response>{return async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers:cors});
 if(req.method!=='POST')return reply(405,{code:'METHOD_NOT_ALLOWED'});
 const bearer=/^Bearer (\S+)$/.exec(req.headers.get('Authorization')??'');
 if(!bearer)return reply(401,{code:'AUTH_REQUIRED'});
 try {
  const actor=await deps.authenticate(bearer[1]);if(!actor)return reply(401,{code:'SESSION_EXPIRED'});
  if(!req.body)return reply(400,{code:'INVALID_INPUT'});
  const reader=req.body.getReader();const pieces:Uint8Array[]=[];let length=0;
  try{while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>1024){await reader.cancel();return reply(413,{code:'INVALID_INPUT'});}pieces.push(value);}}finally{reader.releaseLock();}
  const bytes=new Uint8Array(length);let offset=0;for(const piece of pieces){bytes.set(piece,offset);offset+=piece.length;}
  let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return reply(400,{code:'INVALID_INPUT'});}
  if(!body||Array.isArray(body)||Object.keys(body).some(k=>!['target_id','blocked','request_id'].includes(k))||!Number.isSafeInteger(body.target_id)||body.target_id<1||typeof body.blocked!=='boolean'||typeof body.request_id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.request_id))return reply(400,{code:'INVALID_INPUT'});
  const reserved=await deps.reserve(actor,body.target_id,body.blocked,body.request_id);
  if(reserved.code==='FORBIDDEN')return reply(403,{code:'FORBIDDEN'});
  if(reserved.code==='NOT_FOUND')return reply(404,reserved);
  if(['SELF_FORBIDDEN','ADMIN_PROTECTED'].includes(reserved.code))return reply(403,reserved);
  if(['BUSY','REQUEST_CONFLICT'].includes(reserved.code))return reply(409,reserved);
  if(reserved.code!=='PENDING')return reply(200,reserved);
  // No external Auth action until the fail-closed database state is committed.
  const result=await deps.synchronize(body.request_id,body.target_id);
  return reply(result.code==='AUTH_SYNC_PENDING'?202:200,{...result,active_orders:result.active_orders??reserved.active_orders});
 }catch{return reply(503,{code:'OPERATION_UNCONFIRMED'});}
};}
