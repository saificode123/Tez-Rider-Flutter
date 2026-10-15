import {accountBoundary} from './fr28-access.ts';
const request=new Request('http://localhost',{method:'POST',headers:{Authorization:'Bearer synthetic'}});
for(const [data,status,code]of [
 [{code:'FR28_ACCOUNT_BLOCKED',role:'admin',verification_status:'approved'},403,'FR28_ACCOUNT_BLOCKED'],
 [{code:'OK',role:'customer',verification_status:'approved'},403,'FORBIDDEN'],
 [{code:'OK',role:'admin',verification_status:'pending'},403,'FORBIDDEN'],
 [{code:'FR28_SESSION_REVOKED'},401,'FR28_SESSION_REVOKED'],
 [{code:'OK',role:'admin',verification_status:'approved'},200,'OK'],
]as const)Deno.test(`trusted admin boundary ${code} ${data.verification_status??''}`,async()=>{
 const original=globalThis.fetch;
 try{
  globalThis.fetch=async()=>Response.json(data);
  const result=await accountBoundary(request,'http://localhost','public-key',true);
  if(status===200){if(result!==null)throw Error('Approved caller incorrectly denied');}
  else if(result?.status!==status||(await result.json()).code!==code)throw Error('Incorrect authorization disposition');
 }finally{globalThis.fetch=original;}
});
Deno.test('network failure remains fail-closed and redacted',async()=>{
 const original=globalThis.fetch;
 try{
  globalThis.fetch=async()=>{throw Error('private-secret');};
  const result=await accountBoundary(request,'http://localhost','public-key',true);
  if(result?.status!==503||(await result.text()).includes('private-secret'))throw Error('Unsafe network failure');
 }finally{globalThis.fetch=original;}
});
