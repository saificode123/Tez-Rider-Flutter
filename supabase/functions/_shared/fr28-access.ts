export const blockedMessage = 'Your account has been blocked. Please contact support.';
// This trusted RPC uses the verified JWT subject even after Auth bans a user.
// It discloses only that subject's account status; no directory access is granted.
export async function accountBoundary(req: Request, base: string, anon: string, adminOnly=false): Promise<Response | null> {
 if(req.method==='OPTIONS')return null;
 const authorization=req.headers.get('Authorization')??'';
 if(!/^Bearer \S+$/.test(authorization))return null; // Existing handler emits its 401.
 try {
  const response=await fetch(base+'/rest/v1/rpc/fr28_account_status',{method:'POST',headers:{apikey:anon,Authorization:authorization,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(10000)});
  const data=await response.json();
  let code:string|undefined,status=503;
  if(response.ok&&data.code==='FR28_ACCOUNT_BLOCKED'){code=data.code;status=403;}
  else if(response.ok&&data.code==='FR28_SESSION_REVOKED'){code=data.code;status=401;}
  else if(response.ok&&adminOnly&&(data.role!=='admin'||data.verification_status!=='approved')){code='FORBIDDEN';status=403;}
  else if(!response.ok){code=response.status===401?'SESSION_EXPIRED':'ACCOUNT_CHECK_UNAVAILABLE';status=response.status===401?401:503;}
  if(code)return Response.json({code,message:code==='FR28_ACCOUNT_BLOCKED'?blockedMessage:'Account access could not be confirmed.'},{status,headers:{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Cache-Control':'no-store'}});
  return null;
 }catch{return Response.json({code:'ACCOUNT_CHECK_UNAVAILABLE'},{status:503,headers:{'Access-Control-Allow-Origin':'*','Cache-Control':'no-store'}});}
}
