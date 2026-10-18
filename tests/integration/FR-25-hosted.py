"""Bounded synthetic TEST checks. Load testing is expressly excluded here."""
import base64,concurrent.futures,datetime as dt,importlib.util,io,json,os,secrets,subprocess,sys,time,urllib.request,urllib.error,uuid
from pathlib import Path
from PIL import Image,ImageDraw
spec=importlib.util.spec_from_file_location('fr04_private',Path(__file__).with_name('FR-04-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
ROOT=b.ROOT;OUT=ROOT/'.fr21-local/fr25';OUT.mkdir(parents=True,exist_ok=True)
FILE=b.PRIVATE/'fr25-accounts.bin'
state=json.loads(b.crypt(FILE.read_bytes(),True)) if FILE.exists() else {'accounts':{},'orders':{}}
checks=[]
def save():FILE.write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 if not ok:raise AssertionError(label)
 checks.append(label);record={'time':dt.datetime.now(dt.timezone.utc).isoformat(),'result':'PASS','check':label}
 with (OUT/'checks.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)
def api(*args,**kw):return b.api(*args,**kw)
def rpc(name,body={},token=None,admin=False):return b.rpc(name,body,token,admin)
def fixture(label,role='customer'):
 a=state['accounts'].setdefault(label,{'email':'fr25-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'});save()
 if 'auth_id' not in a:
  status,row=api('/auth/v1/admin/users','POST',{'email':a['email'],'password':a['password'],'email_confirm':True,'user_metadata':{'name':'FR25 synthetic '+label,'role':role,'fr25_fixture':True}},admin=True)
  assert status in (200,201),'Synthetic TEST account creation failed';a['auth_id']=row['id'];save()
 if 'profile_id' not in a:
  status,rows=api('/rest/v1/users','POST',{'email':a['email'],'name':'FR25 synthetic '+label,'role':role,'verification_status':'approved' if role=='admin' else 'pending'},admin=True)
  assert status==201,'Synthetic TEST profile creation failed';a['profile_id']=rows[0]['id'];save()
 return a,b.login(a)
def order(account,label,status='delivered'):
 body={'user_id':account['profile_id'],'order_status':status,'amount':25,'delivery_address':'FR25 SYNTHETIC TEST ONLY','payment_method':'COD'}
 if os.environ.get('CHECKLIST_REGRESSION_FIXTURES')=='true'and status=='delivered':
  from checklist_fixtures import create
  code,rows=create(b,body)
 else:code,rows=api('/rest/v1/orders','POST',body,admin=True)
 assert code==201,'Synthetic order creation failed';state['orders'][label]=rows[0]['id'];save();return rows[0]['id']
def image():
 im=Image.new('RGB',(320,180),'green');ImageDraw.Draw(im).text((12,50),'FR25 SYNTHETIC EVIDENCE\nNOT PERSONAL DATA',fill='white');out=io.BytesIO();im.save(out,format='PNG');return out.getvalue()
def upload(token,request,raw=None,mime='image/png'):
 return api('/functions/v1/fr25-evidence','POST',{'action':'upload','request_id':request,'mime_type':mime,'image_base64':base64.b64encode(raw if raw is not None else image()).decode()},token)
def submit(token,request,order_id,paths,reason='Other',description='FR25 synthetic damaged package evidence'):
 return rpc('create_dispute',{'p_request_id':request,'p_order_id':order_id,'p_reason':reason,'p_description':description,'p_evidence_paths':paths},token)
def denied(status):return status in (400,401,403,404,409,413,415,422)
def query(file):
 b.target();exe='C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
 result=subprocess.run([exe,'db','query','--linked','--project-ref',b.REF,'--file',str(file),'--output','json'],capture_output=True,text=True,timeout=90)
 if result.returncode:raise RuntimeError('TEST SQL check failed: '+('SQL error' if result.stderr else 'Transport failure'))
 return json.loads(result.stdout[result.stdout.index('{'):])
def verify():
 file=OUT/'verify.sql';file.write_text("select version,name from supabase_migrations.schema_migrations order by version;")
 data=query(file);versions=[r['version'] for r in data['rows']]
 expected=[p.name.split('_')[0] for p in (ROOT/'supabase/migrations').glob('*.sql')]
 check(sorted(versions)==sorted(expected),'TEST migration history exactly matches source')
 (OUT/'migration-history.json').write_text(json.dumps(data['rows'],indent=2))
 status,bucket=api('/storage/v1/bucket/dispute-evidence',admin=True)
 check(status==200 and bucket['public'] is False and bucket['file_size_limit']==5242880 and set(bucket['allowed_mime_types'])=={'image/png','image/jpeg'},'private evidence bucket 5MB and MIME settings')
 file.write_text("select proname,prosecdef,proconfig,proacl,has_function_privilege('anon',p.oid,'execute') as anonymous_execute from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (proname like 'fr25_%' or proname='create_dispute');")
 data=query(file);(OUT/'function-permissions.json').write_text(json.dumps(data['rows'],indent=2))
 check(all('search_path=""' in (r['proconfig'] or []) for r in data['rows']),'FR25 functions have explicit empty search_path')
 check(all(r['anonymous_execute'] is False for r in data['rows']),'FR25 RPC execution excludes PUBLIC and anonymous')
 file.write_text("select config from pg_catalog.pg_settings where false;") if False else None
def tests():
 a,token=fixture('customer-a');other,other_token=fixture('customer-b');_,vendor=fixture('vendor','vendor');_,rider=fixture('rider','rider');_,admin=fixture('admin','admin')
 oid=order(a,'valid');rid=str(uuid.uuid4())
 status,_=rpc('fr25_prepare',{'p_request_id':rid,'p_order_id':oid},token);check(status==200,'owner prepares eligible delivered order')
 for label,t in [('other customer',other_token),('vendor',vendor),('rider',rider),( 'anonymous',None)]:
  status,_=rpc('fr25_prepare',{'p_request_id':str(uuid.uuid4()),'p_order_id':oid},t);check(denied(status),label+' cannot prepare owned dispute')
 status,_=rpc('fr25_upload_authority',{'p_request_id':rid},other_token);check(denied(status),'cross-customer upload authority denied')
 status,data=upload(token,rid);check(status==200 and isinstance(data.get('path'),str),'actual decoded PNG uploads successfully');path=data['path']
 status,repeat=upload(token,rid);check(status==200 and repeat['path']==path,'same image retry has one immutable object')
 status,_=upload(token,rid,b'not an image');check(denied(status),'spoofed PNG bytes rejected by trusted decoder')
 status,_=upload(token,rid,image(),'text/plain');check(denied(status),'unsupported MIME rejected')
 status,_=upload(token,rid,b'x'*5242881);check(status==413,'oversized image rejected')
 for label,t in [('owner',token),('other',other_token),('vendor',vendor),('rider',rider),('anonymous',None)]:
  status,_=api('/storage/v1/object/authenticated/dispute-evidence/'+path,token=t);check(denied(status),'direct unsigned evidence read denied for '+label)
  status,_=api('/storage/v1/object/sign/dispute-evidence/'+path,'POST',{'expiresIn':3600},t);check(denied(status),'arbitrary TTL signing denied for '+label)
 status,_=api('/storage/v1/object/dispute-evidence/'+path,'POST',image(),token,'image/png');check(denied(status),'direct owner upload cannot bypass content validation')
 for label,reason,desc,paths in [('invalid reason','Not allowed','Valid',[path]),('empty description','Other',' ',[path]),('long description','Other','x'*2001,[path]),('zero evidence','Other','Valid',[]),('four evidence','Other','Valid',[path]*4),('duplicate evidence','Other','Valid',[path,path]),('missing evidence','Other','Valid',[a['auth_id']+'/'+rid+'/missing.png']),('foreign evidence','Other','Valid',[other['auth_id']+'/'+rid+'/other.png'])]:
  status,_=submit(token,rid,oid,paths,reason,desc);check(denied(status),label+' rejected server-side')
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  results=list(pool.map(lambda _:submit(token,rid,oid,[path]),range(2)))
 check(all(code==200 for code,_ in results) and results[0][1]['id']==results[1][1]['id'],'concurrent identical requests return one dispute')
 dispute=results[0][1]['id'];state['dispute_id']=dispute;state['request_id']=rid;state['path']=path;save()
 status,_=submit(token,rid,oid,[path],description='Changed retry payload');check(status==409,'same request cannot change submitted payload')
 status,_=rpc('fr25_prepare',{'p_request_id':str(uuid.uuid4()),'p_order_id':oid},token);check(status==409,'new UUID cannot bypass open-dispute constraint')
 status,_=upload(token,rid);check(status==409,'submitted evidence cannot be overwritten')
 status,rows=api('/rest/v1/notifications?dispute_id=eq.'+str(dispute)+'&select=id,user_id',admin=True)
 check(status==200 and len(rows)==1,'exactly one admin notification per dispute')
 status,admin_rows=api('/rest/v1/users?role=eq.admin&verification_status=eq.approved&select=id',admin=True)
 check(status==200 and {r['user_id'] for r in rows}.issubset({r['id'] for r in admin_rows}),'only approved admins receive dispute notification')
 status,history=rpc('fr25_history',{},token);check(status==200 and any(r['id']==dispute for r in history),'customer paginated history contains own dispute')
 status,detail=rpc('fr25_detail',{'p_id':dispute},token);check(status==200 and detail['evidence_count']==1,'customer detail includes owned order and evidence count')
 for label,t in [('other customer',other_token),('vendor',vendor),('rider',rider),('anonymous',None)]:
  status,rows=api('/rest/v1/disputes?select=id&id=eq.'+str(dispute),token=t);check(denied(status) or rows==[],label+' cannot read dispute')
  status,_=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':dispute,'index':1},t);check(denied(status),label+' cannot issue evidence URL')
 status,rows=api('/rest/v1/disputes?select=id&id=eq.'+str(dispute),token=admin);check(status==200 and len(rows)==1,'approved admin may read dispute for future review')
 for label,t in [('owner',token),('admin',admin),('other',other_token),('vendor',vendor),('rider',rider)]:
  status,_=api('/rest/v1/disputes','POST',{'type':'Forgery','status':'Open'},t);check(denied(status),label+' direct dispute INSERT denied')
  status,_=api('/rest/v1/disputes?id=eq.'+str(dispute),'PATCH',{'status':'Resolved'},t);check(denied(status),label+' direct dispute UPDATE denied')
  status,_=api('/rest/v1/disputes?id=eq.'+str(dispute),'DELETE',token=t);check(denied(status),label+' direct dispute DELETE denied')
 status,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':rid},token);check(status==200,'cleanup of submitted request is harmless')
 for label,t in [('owner',token),('approved admin',admin)]:
  status,link=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':dispute,'index':1},t)
  check(status==200 and link['expires_in']==900,label+' receives authorized 900-second URL')
  claims=json.loads(base64.urlsafe_b64decode(link['url'].split('token=')[1].split('.')[1]+'=='))
  check(claims['exp']-claims['iat']==900,label+' signed token has exact TTL')
  with urllib.request.urlopen(link['url'],timeout=30) as response:check(response.status==200 and response.read()==image(),label+' signed evidence bytes match synthetic upload')

 status,_=api('/storage/v1/object/public/dispute-evidence/'+path);check(denied(status),'public evidence URL denied')
 undelivered=order(a,'undelivered','placed');status,_=rpc('fr25_prepare',{'p_request_id':str(uuid.uuid4()),'p_order_id':undelivered},token);check(denied(status),'undelivered order rejected')
 status,_=api('/rest/v1/orders','POST',{'user_id':a['profile_id'],'order_status':'delivered','amount':1},token);check(denied(status),'client cannot forge delivered order or delivery time')
 cleanup_order=order(a,'cleanup');cleanup_id=str(uuid.uuid4());rpc('fr25_prepare',{'p_request_id':cleanup_id,'p_order_id':cleanup_order},token);status,obj=upload(token,cleanup_id);check(status==200,'unfinished synthetic upload prepared for cleanup')
 status,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':cleanup_id},other_token);check(denied(status),'other customer cannot clean draft')
 status,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':cleanup_id},token);check(status==200,'authorized cleanup abandons draft and deletes unattached image')
 status,_=api('/storage/v1/object/authenticated/dispute-evidence/'+obj['path'],admin=True);check(denied(status),'cleaned object actually absent from Storage API')
 status,_=rpc('fr25_prepare',{'p_request_id':cleanup_id,'p_order_id':cleanup_order},token);check(denied(status),'abandoned UUID cannot be reused')
 # Preserve a new eligible fixture for actual phone submission.
 order(a,'device');(OUT/'synthetic-evidence.png').write_bytes(image())
 # Existing chat functionality is genuine and isolated.
 status,room=rpc('fr25_support_chat',{},token);check(status==200 and isinstance(room,int),'customer opens genuine support chat')
 status,again=rpc('fr25_support_chat',{},token);check(status==200 and again==room,'support chat retry creates no duplicate room')
 status,_=api('/rest/v1/chat_messages','POST',{'room_id':room,'sender_id':a['profile_id'],'message':'FR25 synthetic chat preservation check'},token);check(status==201,'customer sends genuine support message')
 status,rooms=rpc('fr25_chat_list',{},token);check(status==200 and any(r['room_id']==room for r in rooms),'inbox lists real support conversation')
 status,_=api('/rest/v1/chat_messages','POST',{'room_id':room,'sender_id':other['profile_id'],'message':'Forbidden'},other_token);check(denied(status),'cross-customer chat send denied')
 status,rows=api('/rest/v1/chat_messages?room_id=eq.'+str(room)+'&select=id',token=other_token);check(status==200 and rows==[],'cross-customer chat read denied')
def extra():
 a,token=fixture('customer-a');other,other_token=fixture('customer-b')
 status,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':str(uuid.uuid4())},token);check(status==200,'unprepared rejected request can safely discard without touching files')
 canonical_order=order(a,'canonical-uuid');uppercase=str(uuid.uuid4()).upper()
 status,_=rpc('fr25_prepare',{'p_request_id':uppercase,'p_order_id':canonical_order},token);check(status==200,'uppercase UUID draft is securely canonicalized')
 status,obj=upload(token,uppercase);check(status==200 and obj['path'].split('/')[1]==uppercase.lower(),'Storage uses the server-canonical dispute UUID')
 status,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':uppercase},token);check(status==200,'canonical UUID cleanup removes its own unsubmitted evidence')
 oid=order(a,'three-images');rid=str(uuid.uuid4())
 status,_=rpc('fr25_prepare',{'p_request_id':rid,'p_order_id':oid},token);check(status==200,'three-image draft prepared')
 paths=[]
 for i in range(3):
  im=Image.new('RGB',(150,90),['red','green','blue'][i]);buffer=io.BytesIO();im.save(buffer,format='JPEG' if i==1 else 'PNG')
  status,data=upload(token,rid,buffer.getvalue(),'image/jpeg' if i==1 else 'image/png');check(status==200,'actual JPEG/PNG evidence '+str(i+1)+' validated');paths.append(data['path'])
 status,_=upload(token,rid,image());check(status==422,'fourth distinct image is rejected before Storage write')
 status,objects=api('/storage/v1/object/list/dispute-evidence','POST',{'prefix':a['auth_id']+'/'+rid,'limit':10,'offset':0},admin=True)
 check(status==200 and len(objects)==3,'Storage API confirms exactly three immutable objects')
 status,_=submit(token,rid,oid,paths,description='\t\n');check(status in (400,422),'whitespace-only description rejected')
 foreign_order=order(other,'foreign-evidence');foreign_request=str(uuid.uuid4());rpc('fr25_prepare',{'p_request_id':foreign_request,'p_order_id':foreign_order},other_token)
 status,foreign=upload(other_token,foreign_request);check(status==200,'actual separate-customer evidence fixture uploaded')
 status,_=submit(token,rid,oid,[foreign['path']]);check(status==403,'real other-customer evidence cannot be attached')
 status,data=submit(token,rid,oid,paths);check(status==200,'three-image dispute submitted successfully')
 status,detail=rpc('fr25_detail',{'p_id':data['id']},token);check(status==200 and detail['evidence_count']==3,'three-image detail preserved')
 # Distinct UUIDs racing for the same order: exactly one wins.
 oid=order(a,'race-distinct');requests=[]
 for _ in range(2):
  request=str(uuid.uuid4());status,_=rpc('fr25_prepare',{'p_request_id':request,'p_order_id':oid},token);check(status==200,'distinct racing draft prepared')
  status,obj=upload(token,request);check(status==200,'distinct racing evidence uploaded');requests.append((request,obj['path']))
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  results=list(pool.map(lambda pair:submit(token,pair[0],oid,[pair[1]]),requests))
 check(sorted(code for code,_ in results)==[200,409],'distinct concurrent requests produce one success and one business rejection')
 status,rows=api('/rest/v1/disputes?order_id=eq.'+str(oid)+'&select=id',admin=True);check(status==200 and len(rows)==1,'concurrent order has exactly one open dispute')
 for pair,(code,result) in zip(requests,results):
  if code==409:
   status,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':pair[0]},token);check(status==200,'losing race cleans only unattached evidence')
 # Clean the still-unsubmitted foreign fixture; submitted evidence stays intact.
 status,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':foreign_request},other_token);check(status==200,'foreign fixture cleanup is performed only by its owner')
def limits():
 a,token=fixture('draft-limit');requests=[]
 for i in range(12):requests.append((str(uuid.uuid4()),order(a,'limit-'+str(i))))
 with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
  results=list(pool.map(lambda pair:rpc('fr25_prepare',{'p_request_id':pair[0],'p_order_id':pair[1]},token),requests))
 check(sum(status==200 for status,_ in results)==10 and sum(status==429 for status,_ in results)==2,'concurrent per-customer draft limit is exactly ten')
 request=next(pair[0] for pair,(status,_) in zip(requests,results) if status==200)
 prefix=a['auth_id']+'/'+request+'/'
 status,_=api('/storage/v1/object/dispute-evidence/'+prefix+'forbidden.txt','POST',b'not an image',admin=True,mime='text/plain')
 check(denied(status),'Storage bucket itself rejects unsupported MIME for privileged upload')
 status,_=api('/storage/v1/object/dispute-evidence/'+prefix+'oversized.png','POST',b'x'*5242881,admin=True,mime='image/png')
 check(denied(status),'Storage bucket itself rejects oversized privileged upload')
 for pair,(status,_) in zip(requests,results):
  if status==200:
   code,_=api('/functions/v1/fr25-evidence','POST',{'action':'cleanup','request_id':pair[0]},token);check(code==200,'isolated limit draft abandoned by its owner')
def sql():
 data=query(ROOT/'supabase/tests/FR-25.sql');(OUT/'sql-assertions.json').write_text(json.dumps(data,indent=2));
 for row in data['rows']:
  if 'test' in row:check(row['result']=='PASS',row['test'])
 check(any('test' in row for row in data['rows']),'FR25 rollback SQL assertions executed')
def ttl():
 token=b.login(state['accounts']['customer-a'])
 status,issued=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':state['dispute_id'],'index':1},token)
 assert status==200,'Authorized expiry-test URL issuance failed'
 saved={'url':issued['url']}
 claims=json.loads(base64.urlsafe_b64decode(saved['url'].split('token=')[1].split('.')[1]+'=='))
 check(claims['exp']-claims['iat']==900,'expiry probe starts with actual 900-second link')
 (OUT/'ttl-wait.json').write_text(json.dumps({'started':dt.datetime.now(dt.timezone.utc).isoformat(),'expires_at':claims['exp'],'url_persisted':False}))
 while time.time()<=claims['exp']+2:time.sleep(min(10,max(.1,claims['exp']+3-time.time())))
 b.target()
 try:
  with urllib.request.urlopen(saved['url'],timeout=30) as r:status=r.status
 except urllib.error.HTTPError as e:status=e.code
 check(denied(status),'actual evidence signed URL rejected after 900 seconds')
 token=b.login(state['accounts']['customer-a'])
 status,fresh=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':state['dispute_id'],'index':1},token)
 check(status==200 and fresh['url']!=saved['url'],'fresh authorized evidence link after expiry')
 with urllib.request.urlopen(fresh['url'],timeout=30) as r:check(r.status==200,'fresh evidence link usable after expiry')
def device():
 import runpy
 runpy.run_path(str(Path(__file__).with_name('FR-25-device.py')),init_globals={'backend':sys.modules[__name__]})
if __name__=='__main__':
 try:
  mode=sys.argv[1];{'tests':tests,'extra':extra,'limits':limits,'sql':sql,'verify':verify,'ttl':ttl,'device':device}[mode]()
  (OUT/(mode+'-results.json')).write_text(json.dumps({'project_ref':b.REF,'passed':len(checks),'failed':0,'checks':checks},indent=2));print(json.dumps({'passed':len(checks),'failed':0}))
 except Exception as error:
  print(json.dumps({'passed':len(checks),'failed':1,'error_type':type(error).__name__,'reason':str(error) if isinstance(error,(AssertionError,RuntimeError)) else 'Transport or protocol failure'}));sys.exit(1)
