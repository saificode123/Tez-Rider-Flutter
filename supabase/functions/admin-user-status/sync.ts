import type {Outcome}from './handler.ts';
export async function updateAuthState(base:string,service:string,id:string,blocked:boolean,fetcher:typeof fetch=fetch):Promise<boolean>{
 try{
 const response=await fetcher(base+'/auth/v1/admin/users/'+id,{method:'PUT',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({ban_duration:blocked?'876000h':'none'}),signal:AbortSignal.timeout(8000)});
 if(!response.ok)return false;
 const user=await response.json();const banned=typeof user.banned_until==='string'&&Date.parse(user.banned_until)>Date.now();
 return user.id===id&&banned===blocked;
 }catch{return false;}
}
export interface SyncHooks{
 change():Promise<boolean>;
 revoke():Promise<void>;
 finish(failure?:string):Promise<Outcome>;
}
export async function synchronizeAuth(hooks:SyncHooks):Promise<Outcome>{
 if(!await hooks.change())return await hooks.finish('AUTH_UNCONFIRMED');
 try{await hooks.revoke();}catch{return await hooks.finish('SESSIONS_UNCONFIRMED');}
 return await hooks.finish();
}
