"""Stage2 onboarding: real Auth fixtures, rollback review, exact TEST deployment."""
import base64,concurrent.futures,hashlib,importlib.util,json,re,secrets,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2'
OUT.mkdir(exist_ok=True);REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF
assert sys.argv[1]=='onboarding';action=sys.argv[2]
assert action in('fixture','review','deploy','post','hosted')
private=OUT/'onboarding-accounts.dpapi'
state=json.loads(b.crypt(private.read_bytes(),True))if private.exists()else{'accounts':{}}
def save():private.write_bytes(b.crypt(json.dumps(state).encode()))
def fixture(label,role):
 a=state['accounts'].setdefault(label,{'email':'final2-'+label+'-'+uuid.uuid4().hex[:10]+'@example.test','password':secrets.token_urlsafe(24)+'aA7!'})
 save();assert a['email'].startswith('final2-')and a['email'].endswith('@example.test')
 if 'auth_id'not in a:
  code,user=b.api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,
   'user_metadata':{'name':'FINAL2 TEST ONLY','phone':'123456','role':role,'store_name':'FINAL2 Store','store_address':'FINAL2 Synthetic Street'}},admin=True)
  if code in(200,201):a['auth_id']=user['id'];save()
  else:
   token=b.login(a);a['auth_id']=claims(token)['sub'];save()
 return a
def claims(token):
 part=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(part+'='*(-len(part)%4)))
accounts=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
for label,role in [('review-vendor','vendor'),('review-customer','customer'),('live-vendor','vendor')]:fixture(label,role)
checks=[]
def check(ok,label,level='real authenticated TEST HTTP'):
 assert ok,label
 row={'check':label,'result':'PASS','surface':level};checks.append(row);print(json.dumps(row),flush=True)
 (OUT/('onboarding-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(path,token,body=None,query=''):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST'if path.startswith('rpc/')else'GET','path':'/'+path,'query':query,
 'headers':{'content-type':'application/json','prefer':'return=representation'},'body':json.dumps(body)if body is not None else''},token)
version='202610230004';migration=ROOT/'supabase/migrations/202610230004_final2_registration.sql'
history=OUT/'onboarding-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
versions=[r['version']for r in db.query(history)]
expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
assert versions==([v for v in expected if v!=version]if action in('fixture','review','deploy')else expected),'Unexpected history; never replay'
if action=='fixture':
 print(json.dumps({'project':REF,'synthetic_auth_fixtures':len(state['accounts']),'confirmation_level':'Admin-confirmed Auth fixtures; not real inbox email confirmation','business_records_created':0}))
elif action in('review','post'):
 vendor=claims(b.login(state['accounts']['review-vendor']));customer=claims(b.login(state['accounts']['review-customer']));admin=claims(b.login(accounts['admin']))
 template=(ROOT/'supabase/tests/FINAL2-registration.sql').read_text(encoding='utf-8-sig')
 if action=='review':template=template.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for name,value in [('__VENDOR_CLAIMS__',vendor),('__CUSTOMER_CLAIMS__',customer),('__ADMIN_CLAIMS__',admin)]:template=template.replace(name,"'"+json.dumps(value).replace("'","''")+"'")
 template=template.replace('__ADMIN_ID__',str(int(accounts['admin']['profile_id'])))
 path=OUT/'onboarding-review.private.sql';path.write_text(template,encoding='utf-8')
 result=db.query(path)[0]['results'];assert result and all(r['result']=='PASS'for r in result)
 for row in result:check(True,row['check'],row['surface'])
 (OUT/('onboarding-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':hashlib.sha256(migration.read_bytes()).hexdigest(),'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'onboarding-review-proof.json').read_text())
 assert review['rolled_back']and review['migration_sha256']==hashlib.sha256(migration.read_bytes()).hexdigest()
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate|delete)\b',source,re.I)
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610230004','final2_registration');commit;")
 path=OUT/'onboarding-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'onboarding-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))
elif action=='hosted':
 import time,urllib.parse
 sys.path.insert(0,str(ROOT/'build/fr21-python'))
 from websockets.sync.client import connect
 vendor=b.login(state['accounts']['live-vendor']);admin=b.login(accounts['admin'])
 customer=b.login(state['accounts']['review-customer'])
 data={'p_name':'FINAL2 TEST ONLY Vendor','p_phone':'123456','p_role':'vendor',
  'p_store_name':'FINAL2 Store','p_store_address':'FINAL2 Synthetic Street','p_update_profile':False}
 auth_id=state['accounts']['live-vendor']['auth_id']
 code,existing=b.api('/rest/v1/users?auth_user_id=eq.'+auth_id+'&select=id,verification_status',admin=True)
 assert code==200 and len(existing)<=1
 if not existing:
  code,value=gateway('rpc/final2_complete_registration',vendor,{**data,'p_role':'admin'})
  check(code==400,'fresh verified Auth identity cannot self-register as Admin')
  code,value=gateway('rpc/final2_complete_registration',vendor,{**data,'p_phone':'bad-phone'})
  check(code==400,'real gateway registration rejects malformed phone before persistence')
  code,value=gateway('rpc/final2_complete_registration',vendor,{**data,'p_store_address':''})
  check(code==200 and value.get('code')=='STORE_REQUIRED','missing store address returns explicit incompletion')
  code,missing=b.api('/rest/v1/users?auth_user_id=eq.'+auth_id+'&select=id',admin=True)
  check(code==200 and missing==[],'incomplete store leaves no partly-created vendor profile')
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
  results=list(pool.map(lambda _:gateway('rpc/final2_complete_registration',vendor,data),range(2)))
 assert all(code==200 and value.get('code')=='OK'for code,value in results)
 first=results[0][1];uid=int(first['id']);sid=int(first['store_id'])
 check(all(value['id']==uid and value['store_id']==sid for code,value in results),'two concurrent real registration requests produce the same profile and store')
 state['live_vendor_profile_id']=uid;state['live_vendor_store_id']=sid;save()
 code,stores=b.api('/rest/v1/vendors?user_id=eq.'+str(uid)+'&select=id,address,is_active',admin=True)
 check(code==200 and len(stores)==1 and stores[0]['address']==data['p_store_address'],'actual persisted store address and unique owner verified by TEST read')
 if not existing:
  check(first['verification_status']=='pending'and not stores[0]['is_active'],'new vendor remains pending with an inactive store')
  code,value=gateway('rpc/fr17_save_product',vendor,{'p_request_id':str(uuid.uuid4()),'p_product_id':None,
   'p_data':{'name':'FINAL2 pending denial','price':1,'image_url':''},'p_stock':1,'p_threshold':0,'p_expected_version':None})
  check(code==403 or(code==200 and value.get('code')=='FORBIDDEN'),'pending vendor cannot operate inventory before Admin approval')
 code,value=gateway('rpc/final2_complete_registration',vendor,{**data,'p_role':'admin','p_name':'Editable metadata override'})
 check(code==200 and value['role']=='vendor'and value['name']=='FINAL2 TEST ONLY Vendor','editable metadata cannot replace canonical vendor role or saved name')
 code,value=gateway('rpc/final2_complete_registration',vendor,{**data,'p_name':'FINAL2 confirmed owner','p_phone':'987654','p_update_profile':True})
 check(code==200 and value['name']=='FINAL2 confirmed owner'and value['phone']=='987654','explicit owner name and phone update is actually persisted')
 code,value=gateway('rpc/final2_complete_registration',vendor,data)
 check(code==200 and value['name']=='FINAL2 confirmed owner','later login metadata cannot overwrite the explicit profile update')
 # Restore the clearly marked synthetic display name, without touching other users.
 code,value=gateway('rpc/final2_complete_registration',vendor,{**data,'p_update_profile':True})
 assert code==200
 code,cu=gateway('rpc/final2_complete_registration',customer,{'p_name':'FINAL2 TEST ONLY Customer','p_phone':'123456','p_role':'customer'})
 check(code==200 and cu['role']=='customer'and cu['verification_status']=='approved','actual customer completion does not invent an Admin-approval requirement')
 code,value=gateway('rpc/final2_review_vendor',customer,{'p_user_id':uid,'p_status':'approved'})
 check(code==403,'real unrelated customer cannot approve a vendor')
 code,value=b.api('/rest/v1/rpc/final2_complete_registration','POST',data)
 check(code in(401,403),'anonymous direct registration RPC remains denied')
 # If resuming an interrupted test, establish a different state using the real
 # authorized API before opening sockets. No direct status writes or fabricated events.
 code,profile=gateway('users',vendor,query='select=id,verification_status&id=eq.'+str(uid))
 assert code==200 and len(profile)==1
 if profile[0]['verification_status']=='rejected':
  code,_=gateway('rpc/final2_review_vendor',admin,{'p_user_id':uid,'p_status':'approved'});assert code==200
 def accounting():
  code,audit=b.api('/rest/v1/security_audit_log?target_type=eq.users&target_id=eq.'+str(uid)+'&action=in.(vendor_approved,vendor_rejected)&select=id,actor_id,action',admin=True)
  assert code==200
  code,notice=b.api('/rest/v1/notifications?user_id=eq.'+str(uid)+'&select=id,message',admin=True);assert code==200
  return audit,notice
 before_audit,before_notice=accounting()
 code,value=gateway('rpc/final2_review_vendor',admin,{'p_user_id':uid,'p_status':'rejected','p_reason':''})
 check(code==400,'real Admin cannot reject without a reason')
 code,value=gateway('rpc/final1_review_vendor',admin,{'p_user_id':uid,'p_status':'rejected'})
 check(code==400,'legacy HTTP review signature cannot bypass rejection validation')
 sockets=[]
 try:
  url='wss://'+REF+'.supabase.co/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':b.ANON,'vsn':'1.0.0'})
  for label,token in [('owner',vendor),('unrelated customer',customer)]:
   ws=connect(url,open_timeout=20,close_timeout=3);sockets.append(ws)
   ws.send(json.dumps({'topic':'realtime:final2-onboarding-'+uuid.uuid4().hex,'event':'phx_join','ref':'1','payload':{
    'config':{'private':False,'broadcast':{'ack':False,'self':False},'presence':{'key':''},
     'postgres_changes':[{'event':'INSERT','schema':'public','table':'notifications','filter':'user_id=eq.'+str(uid)}]},'access_token':token}}))
   while True:
    message=json.loads(ws.recv(timeout=20))
    if message.get('event')=='phx_reply'and message.get('ref')=='1':assert message['payload']['status']=='ok';break
  reason='FINAL2 synthetic registration review'
  review={'p_user_id':uid,'p_status':'rejected','p_reason':reason}
  code,value=gateway('rpc/final2_review_vendor',admin,review)
  check(code==200 and value['rejection_reason']==reason,'real Admin reasoned rejection confirms the canonical target')
  for label,ws in zip(['owner','unrelated customer'],sockets):
   found=False;until=time.monotonic()+(12 if label=='owner'else 2)
   while time.monotonic()<until:
    try:message=json.loads(ws.recv(timeout=max(.01,until-time.monotonic())))
    except TimeoutError:break
    if message.get('event')=='postgres_changes':
     row=message['payload']['data']['record'];found=row.get('message')==reason;break
   check(found==(label=='owner'),label+': actual review notice Realtime delivery respects ownership','actual authenticated user websocket; bounded denial observation')
  code,value=gateway('rpc/final2_review_vendor',admin,review);check(code==200,'identical real rejection replay is safely reconciled')
  code,notice=gateway('notifications',vendor,query='select=id,message&user_id=eq.'+str(uid)+'&order=id.desc&limit=1')
  check(code==200 and len(notice)==1 and notice[0]['message']==reason,'affected vendor reads the actual persisted rejection notice')
  code,forbidden=gateway('notifications',customer,query='select=id&user_id=eq.'+str(uid))
  check(code==200 and forbidden==[],'unrelated customer cannot read the affected vendor private notices')
  code,value=gateway('rpc/final2_review_vendor',admin,{'p_user_id':uid,'p_status':'approved'})
  check(code==200 and value['verification_status']=='approved'and value['rejection_reason']is None,'subsequent real approval clears the rejection reason')
  code,store=b.api('/rest/v1/vendors?id=eq.'+str(sid)+'&select=is_active',admin=True)
  check(code==200 and len(store)==1 and store[0]['is_active'],'approved owner store is actually active in TEST')
  code,status=gateway('rpc/fr28_account_status',vendor,{})
  check(code==200 and status['role']=='vendor'and status['verification_status']=='approved','existing session/role guard observes actual vendor approval')
  after_audit,after_notice=accounting()
  check(len(after_audit)==len(before_audit)+2 and all(row['actor_id']==int(accounts['admin']['profile_id'])for row in after_audit),
   'exactly two committed decisions carry the correct canonical Admin actor and target','service accounting after real user actions; not an authorization test')
  check(len(after_notice)==len(before_notice)+2,'replay and validation failures do not duplicate recipient notices','service accounting after real user actions')
  state['hosted_completed']=True;save()
 finally:
  for ws in sockets:ws.close()
 # Records are retained as marked synthetic fixtures for physical and later
 # integration checks. No deletion of Auth/profile/store/audit/outbox/history.

print(json.dumps({'project':REF,'action':action,'passed':len(checks),'failed':0,'direct_provider_calls':0}))
