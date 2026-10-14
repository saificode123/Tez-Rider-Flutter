"""Bounded synthetic hosted TEST verification; never a hosted load generator."""
import base64,concurrent.futures,datetime as dt,importlib.util,json,os,secrets,sys,threading,time,urllib.request,urllib.error,uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr25_shared',Path(__file__).with_name('FR-25-hosted.py'))
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g);b=g.b
ROOT=g.ROOT;OUT=ROOT/'.fr21-local/fr26';OUT.mkdir(parents=True,exist_ok=True)
FILE=b.PRIVATE/'fr26-accounts.bin'
state=json.loads(b.crypt(FILE.read_bytes(),True)) if FILE.exists() else {'accounts':{},'disputes':{}}
checks=[];timings=[]
def save():FILE.write_bytes(b.crypt(json.dumps(state).encode()))
def check(ok,label):
 if not ok:raise AssertionError(label)
 record={'time':dt.datetime.now(dt.timezone.utc).isoformat(),'result':'PASS','check':label};checks.append(record)
 with (OUT/'checks.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
 print(json.dumps(record),flush=True)
def api(*args,**kwargs):return b.api(*args,**kwargs)
def rpc(name,params={},token=None,admin=False):
 start=time.monotonic();result=b.rpc(name,params,token,admin);timings.append({'operation':name,'milliseconds':round((time.monotonic()-start)*1000,2),'status':result[0]});return result
def fixture(label,role='customer',approved=True):
 account=state['accounts'].setdefault(label,{'email':'fr26-'+label+'@example.test','password':secrets.token_urlsafe(28)+'aA7!'});save()
 if 'auth_id' not in account:
  code,row=api('/auth/v1/admin/users','POST',{'email':account['email'],'password':account['password'],'email_confirm':True,'user_metadata':{'name':'FR26 synthetic '+label,'role':role,'fr26_fixture':True}},admin=True)
  assert code in (200,201),'Synthetic TEST Auth fixture creation failed';account['auth_id']=row['id'];save()
 if 'profile_id' not in account:
  code,rows=api('/rest/v1/users','POST',{'email':account['email'],'name':'FR26 synthetic '+label,'role':role,'verification_status':'approved' if role=='admin' and approved else 'pending'},admin=True)
  assert code==201,'Synthetic TEST profile fixture creation failed';account['profile_id']=rows[0]['id'];save()
 return account,b.login(account)
def new_dispute(label,customer,token,payment='PAID'):
 code,rows=api('/rest/v1/orders','POST',{'user_id':customer['profile_id'],'order_status':'delivered','amount':25,'delivery_address':'FR26 SYNTHETIC TEST ONLY','payment_method':'COD'},admin=True);assert code==201
 order=rows[0]['id'];request=str(uuid.uuid4());code,_=rpc('fr25_prepare',{'p_request_id':request,'p_order_id':order},token);assert code==200
 code,image=g.upload(token,request);assert code==200
 code,data=g.submit(token,request,order,[image['path']],description='FR26 synthetic decision evidence');assert code==200
 payment_id=None
 if payment is not None:
  body={'orderid':str(order),'customerid':str(customer['profile_id']),'paymentid':'FR26-SYNTHETIC-'+str(order),'method':'COD','status':payment,'amount':25,'paidat':dt.datetime.now(dt.timezone.utc).isoformat() if payment in ('SUCCESS','PAID') else None}
  code,rows=api('/rest/v1/payments','POST',body,admin=True);assert code==201;payment_id=rows[0]['id']
 state['disputes'][label]={'id':data['id'],'order_id':order,'payment_id':payment_id};save();return data['id']
def decide(token,id,decision='RESOLVED',note='FR26 synthetic admin decision'):
 return rpc('admin_resolve_dispute',{'p_dispute_id':id,'p_decision':decision,'p_note':note},token)
def effects(id,owner,winner):
 code,audit=api('/rest/v1/security_audit_log?target_type=eq.dispute&action=eq.dispute_decision&target_id=eq.'+str(id)+'&select=id,actor_id&limit=2',admin=True)
 check(code==200 and len(audit)==1,'exactly one final audit for dispute '+str(id))
 code,notice=api('/rest/v1/notifications?dispute_id=eq.'+str(id)+'&user_id=eq.'+str(owner)+'&select=id,message&limit=2',admin=True)
 check(code==200 and len(notice)==1,'exactly one owner decision notification for dispute '+str(id))
 code,refund=api('/rest/v1/dispute_refund_actions?dispute_id=eq.'+str(id)+'&select=id,status,amount&limit=2',admin=True)
 check(code==200 and len(refund)==(1 if winner=='RESOLVED' else 0),'pending refund count matches winning decision '+str(id))
 if refund:check(refund[0]['status']=='PENDING' and refund[0]['amount']==25,'refund action remains pending and amount intact')
 return audit,notice
def tests():
 customer,ct=fixture('customer');other,ot=fixture('other');admin,at=fixture('admin','admin');admin2,at2=fixture('admin-2','admin')
 _,vendor=fixture('vendor','vendor');_,rider=fixture('rider','rider');_,pending_admin=fixture('pending-admin','admin',False)
 d=new_dispute('resolve',customer,ct);code,opts=rpc('fr26_options',{},at);check(code==200 and opts['note_min']==5 and opts['note_max']==2000,'authorized server note bounds')
 for label,token in [('customer',ct),('other customer',ot),('vendor',vendor),('rider',rider),('pending admin',pending_admin),('anonymous',None)]:
  for endpoint,params in [('fr26_queue',{}),('fr26_detail',{'p_id':d}),('admin_resolve_dispute',{'p_dispute_id':d,'p_decision':'RESOLVED','p_note':'Forbidden actor decision'})]:
   code,_=rpc(endpoint,params,token);check(g.denied(code),label+' denied '+endpoint)
 code,detail=rpc('fr26_detail',{'p_id':d},at);check(code==200 and detail['customer_id']==customer['profile_id'] and detail['evidence_count']==1,'admin real order/customer/evidence details')
 for decision,note,label in [('CLOSED','Valid note','unsupported transition'),('RESOLVED','abcd','short note'),('REJECTED','x'*2001,'long note'),('RESOLVED',None,'missing note')]:
  code,_=decide(at,d,decision,note);check(code==422,label+' rejected without decision')
 code,result=decide(at,d,note='FR26 original winning refund note');check(code==200 and result['decision']=='RESOLVED' and result['refund_pending'] is True,'real admin resolve confirms pending refund')
 code,retry=decide(at2,d,note='FR26 different retry note');check(code==200 and retry['replayed'] is True and retry['decided_by']==admin['profile_id'] and retry['admin_note']=='FR26 original winning refund note','other-admin same-decision retry preserves winning actor/note')
 code,_=decide(at,d,'REJECTED');check(code==409,'opposite retry returns conflict')
 audit,notice=effects(d,customer['profile_id'],'RESOLVED');check(audit[0]['actor_id']==admin['profile_id'],'audit actor derived from authenticated profile')
 check('Pending manual processing' in notice[0]['message'] and 'not been returned' in notice[0]['message'],'refund notification never claims paid money')
 code,owner_detail=rpc('fr25_detail',{'p_id':d},ct);check(code==200 and owner_detail['admin_note']=='FR26 original winning refund note' and owner_detail['refund_pending'] is True,'customer sees final note and pending refund')
 code,_=rpc('fr25_detail',{'p_id':d},ot);check(g.denied(code),'other customer cannot read native final detail')
 payment_id=state['disputes']['resolve']['payment_id'];code,payment=api('/rest/v1/payments?id=eq.'+str(payment_id)+'&select=status,amount,paidat&limit=1',admin=True)
 check(code==200 and payment[0]['status']=='PAID' and payment[0]['amount']==25 and payment[0]['paidat'] is not None,'original payment settlement remains intact')
 for token,label in [(ct,'customer'),(at,'admin'),(vendor,'vendor'),(rider,'rider'),(None,'anonymous')]:
  code,_=api('/rest/v1/disputes?id=eq.'+str(d),'PATCH',{'status':'Rejected'},token);check(g.denied(code),label+' direct dispute update forbidden')
  code,_=api('/rest/v1/payments?id=eq.'+str(payment_id),'PATCH',{'status':'REFUNDED'},token);check(g.denied(code),label+' direct settlement update forbidden')
  code,_=api('/rest/v1/security_audit_log','POST',{'actor_id':admin['profile_id'],'action':'forged','target_type':'dispute','target_id':d},token);check(g.denied(code),label+' cannot forge audit')
  code,_=api('/rest/v1/notifications','POST',{'user_id':customer['profile_id'],'title':'forged','message':'forged','type':'dispute'},token);check(g.denied(code),label+' cannot forge notification')
  code,_=api('/rest/v1/dispute_refund_actions','POST',{'dispute_id':d,'payment_id':payment_id,'order_id':state['disputes']['resolve']['order_id'],'customer_id':customer['profile_id'],'actor_id':admin['profile_id'],'amount':25},token);check(g.denied(code),label+' cannot forge refund action')
 for label,payment in [('missing-payment',None),('unpaid-payment','pending')]:
  invalid=new_dispute(label,customer,ct,payment);code,_=decide(at,invalid);check(code==422,label+' blocks resolution')
  code,row=rpc('fr26_detail',{'p_id':invalid},at);check(code==200 and row['decision'] is None and row['refund_pending'] is False,label+' retains nonfinal state')
 reject=new_dispute('reject',customer,ct,None);code,row=decide(at,reject,'REJECTED','FR26 synthetic rejection reason');check(code==200 and row['decision']=='REJECTED','real admin rejection succeeds without payment');effects(reject,customer['profile_id'],'REJECTED')
 for label,decisions in [('same-resolve',['RESOLVED','RESOLVED']),('same-reject',['REJECTED','REJECTED']),('conflicting',['RESOLVED','REJECTED'])]:
  target=new_dispute(label,customer,ct);barrier=threading.Barrier(2)
  def compete(args):
   token,decision=args;barrier.wait(timeout=10);return decide(token,target,decision,'FR26 concurrent '+decision)
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:outcomes=list(pool.map(compete,[(at,decisions[0]),(at2,decisions[1])]))
  codes=sorted(r[0] for r in outcomes);check(codes==([200,200] if decisions[0]==decisions[1] else [200,409]),label+' genuinely concurrent HTTP outcomes')
  if decisions[0]==decisions[1]:check(sum(r[1]['replayed'] is False for r in outcomes)==1,label+' exactly one new decision')
  code,final=rpc('fr26_detail',{'p_id':target},at);check(code==200 and final['decision'] in decisions,label+' one final winner')
  effects(target,customer['profile_id'],final['decision'])
 code,queue=rpc('fr26_queue',{'p_status':'RESOLVED','p_limit':2},at);check(code==200 and len(queue)<=2 and all(r['status']=='Resolved' for r in queue),'queue bounded status filter')
 if len(queue)==2:
  last=queue[-1];code,next_page=rpc('fr26_queue',{'p_status':'RESOLVED','p_limit':2,'p_before_at':last['created_at'],'p_before_id':last['id']},at)
  check(code==200 and not ({r['id'] for r in next_page}&{r['id'] for r in queue}),'queue cursor has no repeated rows')
 code,link=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':d,'index':1},at);check(code==200 and link['expires_in']==900,'admin evidence issuance exact 900-second TTL')
 for token,label in [(ot,'other customer'),(vendor,'vendor'),(rider,'rider'),(pending_admin,'unapproved admin'),(None,'anonymous')]:
  code,_=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':d,'index':1},token);check(g.denied(code),label+' cannot view private final evidence')
 # Preserve separate unresolved fixtures for physical Resolve and Reject.
 if 'device-resolve' not in state['disputes']:new_dispute('device-resolve',customer,ct)
 if 'device-reject' not in state['disputes']:new_dispute('device-reject',customer,ct,None)
def canonical():
 customer=state['accounts']['customer'];token=b.login(customer);admin=b.login(state['accounts']['admin'])
 id=new_dispute('canonical-success',customer,token,'SUCCESS');code,result=decide(admin,id)
 check(code==200 and result['decision']=='RESOLVED' and result['refund_pending'] is True,'SRDS SUCCESS receipt supports confirmed pending refund')
 effects(id,customer['profile_id'],'RESOLVED')
 payment=state['disputes']['canonical-success']['payment_id'];code,rows=api('/rest/v1/payments?id=eq.'+str(payment)+'&select=status&limit=1',admin=True)
 check(code==200 and rows[0]['status']=='SUCCESS','canonical successful payment history preserved')
def sql():
 data=g.query(ROOT/'supabase/tests/FR-26.sql');rows=data['rows'];assert rows and isinstance(rows[0].get('results'),list)
 for item in rows[0]['results']:check(item['result']=='PASS',item['test'])
 (OUT/'sql-results.json').write_text(json.dumps(rows[0]['results'],indent=2))
def verify():
 file=OUT/'verify.sql';file.write_text("select version,name from supabase_migrations.schema_migrations order by version;")
 rows=g.query(file)['rows'];check([r['version'] for r in rows]==sorted(p.name.split('_')[0] for p in (ROOT/'supabase/migrations').glob('*.sql')),'all migration versions intact and new FR26 applied once')
 (OUT/'migration-history.json').write_text(json.dumps(rows,indent=2))
 file.write_text("select proname,prosecdef,proconfig,has_function_privilege('anon',p.oid,'execute') as anonymous_execute from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (proname like 'fr26_%' or proname='admin_resolve_dispute');")
 rows=g.query(file)['rows'];check(all('search_path=\"\"' in (r['proconfig'] or []) for r in rows),'FR26 fixed empty search_path');check(all(not r['anonymous_execute'] for r in rows),'anonymous FR26 execution denied')
 file.write_text("select c.relname,c.relrowsecurity,has_table_privilege('authenticated',c.oid,'INSERT') as client_insert,has_table_privilege('authenticated',c.oid,'UPDATE') as client_update from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('disputes','payments','dispute_refund_actions','security_audit_log','notifications');")
 rows=g.query(file)['rows'];check(all(r['relrowsecurity'] and not r['client_insert'] and not r['client_update'] for r in rows),'touched financial/decision/audit tables RLS and no direct client mutation grants')
 file.write_text("select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='disputes') as published;")
 check(g.query(file)['rows'][0]['published'],'disputes published for RLS-authorized Realtime')
def ttl():
 token=b.login(state['accounts']['admin']);id=state['disputes']['resolve']['id']
 code,issued=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':id,'index':1},token);check(code==200 and issued['expires_in']==900,'actual admin signed URL issued')
 url=issued['url'];jwt=url.split('token=')[1];payload=jwt.split('.')[1];claims=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))
 with urllib.request.urlopen(url,timeout=30) as response:check(response.status==200,'actual admin evidence initially readable')
 while time.time()<claims['exp']+3:time.sleep(min(25,max(.1,claims['exp']+3-time.time())))
 try:
  with urllib.request.urlopen(url,timeout=30) as response:status=response.status
 except urllib.error.HTTPError as error:status=error.code
 check(g.denied(status),'actual admin evidence expires after 900 seconds')
 code,fresh=api('/functions/v1/fr25-evidence','POST',{'action':'view','dispute_id':id,'index':1},token);assert code==200
 with urllib.request.urlopen(fresh['url'],timeout=30) as response:check(response.status==200,'fresh authorized admin link usable')
def device():
 import runpy
 runpy.run_path(str(Path(__file__).with_name('FR-26-device.py')),init_globals={'backend':sys.modules[__name__]})
def artifact():
 import hashlib,subprocess,zipfile
 mirror=Path('C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-auth-debug/android-build-20261012-125502');apk=OUT/'TezRider-FR26-Test-debug.apk'
 sources=list((ROOT/'lib').rglob('*.dart'))
 check(all(source.read_bytes()==(mirror/source.relative_to(ROOT)).read_bytes() for source in sources),'final APK mirror matches all '+str(len(sources))+' current Dart sources')
 backup=json.loads(b.crypt((b.PRIVATE/'fr04-key-backup.dpapi').read_bytes(),True))
 forbidden=[b.SERVICE.encode(),backup['key'].encode()]
 for accounts in [b.state['accounts'],b.fr04['accounts'],g.state['accounts'],state['accounts']]:forbidden.extend(a['password'].encode() for a in accounts.values())
 names=set()
 for command in [['git','diff','--name-only','-z'],['git','diff','--cached','--name-only','-z'],['git','ls-files','--others','--exclude-standard','-z']]:names.update(subprocess.check_output(command,cwd=ROOT).decode().split('\0'))
 for name in names-{''}:
  file=ROOT/name
  if not file.is_file():continue
  assert file.stat().st_size<=5*1024*1024 and file.suffix.lower() not in ('.apk','.png','.jpg','.jks','.keystore','.bin','.dpapi') and not file.name.startswith('.env'),'Unexpected large/private artifact in Git candidates'
  assert not any(secret in file.read_bytes() for secret in forbidden),'Protected value in Git candidates'
 check(True,'Git candidates contain no protected credentials, private images or build artifacts')
 found=False;public=False
 with zipfile.ZipFile(apk) as archive:
  for item in archive.infolist():
   if item.is_dir():continue
   data=archive.read(item);assert not any(secret in data for secret in forbidden),'Protected value in compiled APK'
   assert b'arrqsvejrfdbacfwtpcc.supabase.co' not in data,'Production URL in compiled APK'
   found|=b.BASE.encode() in data;public|=b.ANON.encode() in data
 check(found and public,'compiled APK has exact TEST URL and actual public client key')
 check(True,'compiled APK excludes all four suites passwords, service-role key and Vault key')
 (OUT/'apk-manifest.json').write_text(json.dumps({'project_ref':b.REF,'path':str(apk),'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'size':apk.stat().st_size,'source_verified':True,'dart_source_count':len(sources)},indent=2))
if __name__=='__main__':
 try:
  mode=sys.argv[1];{'tests':tests,'sql':sql,'verify':verify,'ttl':ttl,'device':device,'artifact':artifact,'canonical':canonical}[mode]()
  result={'mode':mode,'project_ref':b.REF,'passed':len(checks),'failed':0};(OUT/(mode+'-results.json')).write_text(json.dumps({'summary':result,'checks':checks},indent=2))
  if timings:(OUT/(mode+'-bounded-timings.json')).write_text(json.dumps(timings,indent=2))
  print(json.dumps(result))
 except Exception as error:
  print(json.dumps({'passed':len(checks),'failed':1,'error_type':type(error).__name__,'reason':str(error) if isinstance(error,AssertionError) else 'Transport or database check failed'}));sys.exit(1)
