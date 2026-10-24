"""Low-volume canonical profile validation on TEST, preserving fixture values."""
import datetime,importlib.util,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2'
s=importlib.util.spec_from_file_location('backend',Path(__file__).with_name('FR-04-hosted.py'))
b=importlib.util.module_from_spec(s);s.loader.exec_module(b)
b.target();assert b.REF=='igeisilhtmglgnqvllrx' and sys.argv[1:]==['profiles','hosted']
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
accounts={'customer':state['accounts']['review-customer'],'vendor':state['accounts']['live-vendor'],'rider':legacy['rider'],'admin':legacy['admin']}
checks=[]
def check(ok,label):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':'authenticated TEST HTTP','observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat()})
def gateway(token,path,method='GET',body=None,query=''):
 return b.api('/functions/v1/security-gateway','POST',{'method':method,'path':path,'query':query,'headers':{'content-type':'application/json'},'body':json.dumps(body)if body is not None else''},token)
def rpc(token,body):return gateway(token,'/rpc/final2_complete_registration','POST',body)
for role,account in accounts.items():
 token=b.login(account)
 query='auth_user_id=eq.'+account['auth_id']+'&select=id,name,phone,email,role'
 code,rows=gateway(token,'/users',query=query)
 if code!=200:print(json.dumps({'role':role,'status':code,'code':rows.get('code')if isinstance(rows,dict)else None}))
 check(code==200 and len(rows)==1 and rows[0]['role']==role,role+' reads exactly its canonical profile')
 before=rows[0]
 payload={'p_name':before['name'],'p_phone':before['phone'],'p_update_profile':True}
 code,value=rpc(token,payload)
 if before.get('phone'):
  check(code==200 and value['code']=='OK' and value['id']==before['id'] and value['name']==before['name'] and value['phone']==before['phone'] and value['role']==role,role+' trusted idempotent profile Save confirms actual persisted fields without role change')
 else:
  check(code==200 and value['code']=='PROFILE_REQUIRED',role+' legacy missing phone requires valid details instead of fabricated saved success')
 for fields,label in [({'p_name':'\u0000bad'},'control-character name'),({'p_phone':'invalid@example.test'},'invalid phone'),({'p_name':'x'*121},'oversized name')]:
  code,_=rpc(token,{**payload,'p_phone':before.get('phone')or'123456',**fields});check(code==400,role+' server rejects '+label)
 code,value=rpc(token,{**payload,'p_update_profile':False,'p_role':'admin' if role!='admin' else 'customer'})
 check(code==200 and value['role']==role,role+' cannot change canonical role through profile payload')
 code,after=gateway(token,'/users',query=query)
 check(code==200 and after==[before],role+' negative checks preserve name/phone/email/role exactly')
code,_=rpc(None,{'p_name':'Anonymous','p_phone':'1234','p_update_profile':True});check(code in(401,403),'anonymous profile mutation denied')
result={'project':b.REF,'pass':len(checks),'fail':0,'checks':checks,'fixtures_unchanged':True,'new_migration':False,'production_modified':False}
(OUT/'profiles-hosted-results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'project':b.REF,'pass':len(checks),'fail':0,'fixtures_unchanged':True}))
