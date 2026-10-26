"""TEST-only event-push/cart-policy migration checks; no secret output."""
import hashlib, importlib.util, json, re, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'.fr21-local/final-delivery/event-push';OUT.mkdir(parents=True,exist_ok=True)
REF='igeisilhtmglgnqvllrx';VERSION='202610250009'
MIGRATION=ROOT/'supabase/migrations/202610250009_final_delivery_event_push.sql'
spec=importlib.util.spec_from_file_location('event_guarded_db',Path(__file__).with_name('FINAL-security.py'))
db=importlib.util.module_from_spec(spec);spec.loader.exec_module(db);db.OUT=OUT
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF
action=sys.argv[1];assert action in('review','deploy','post','hosted','status')
def query(name,source):
 path=OUT/(name+'.sql');path.write_text(source,encoding='utf-8');return db.query(path)
history=[r['version']for r in query('history','begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
assert history==[v for v in known if v<=history[-1]],'Unexpected history prefix; no replay'
digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
if action in('review','post'):
 assert(VERSION in history)==(action=='post')
 source=(ROOT/'supabase/tests/FINAL-delivery-event-push.sql').read_text(encoding='utf-8')
 if action=='review':source=source.replace('-- FINAL_EVENT_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',MIGRATION.read_text()))
 results=query('rollback-checks',source)[0]['results'];assert results and all(r['result']=='PASS'for r in results)
 evidence={'project':REF,'mode':action,'migration_sha256':digest,'passed':len(results),'checks':results,'rolled_back':True,'actual_fcm_receipt':False}
 (OUT/(action+'-proof.json')).write_text(json.dumps(evidence,indent=2)+'\n')
 (ROOT/('docs/evidence/FINAL-delivery-event-push-'+action+'.json')).write_text(json.dumps(evidence,indent=2)+'\n')
 print(json.dumps({'project':REF,'mode':action,'passed':len(results),'rolled_back':True}))
elif action=='deploy':
 assert VERSION not in history and history==[v for v in known if v<VERSION],'Apply reviewed008 predecessor first; never replay'
 review=json.loads((OUT/'review-proof.json').read_text());assert review['migration_sha256']==digest and review['rolled_back']and review['passed']>=25
 source=MIGRATION.read_text();assert source.count('\ncommit;')==1
 source=source.replace('\ncommit;',"\ninsert into supabase_migrations.schema_migrations(version,name)values('202610250009','final_delivery_event_push');\ncommit;")
 query('deploy',source)
 after=[r['version']for r in query('history-post','begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
 assert after==history+[VERSION]
 evidence={'project':REF,'version':VERSION,'migration_sha256':digest,'versions':len(after),'replayed':False,'production_modified':False}
 (ROOT/'docs/evidence/FINAL-delivery-event-push-deployment.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(evidence))
elif action=='status':
 rows=query('status',"begin read only;select jsonb_build_object('cart_policy',to_regclass('final_delivery_private.cart_settings')is not null,'trigger_installed',exists(select 1 from pg_trigger where tgname='final_delivery_notification_push_identity'and not tgisinternal),'push_enabled',(select android_push_enabled from fr30_private.limits where singleton))as state;rollback;")
 print(json.dumps({'project':REF,'versions':len(history),'state':rows[0]['state']}))
elif action=='hosted':
 assert VERSION in history
 import secrets,uuid
 spec=importlib.util.spec_from_file_location('event_hosted_backend',Path(__file__).with_name('FR-04-hosted.py'))
 b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
 statepath=OUT/'account.dpapi'
 state=json.loads(b.crypt(statepath.read_bytes(),True))if statepath.exists()else{'email':'final-event-'+uuid.uuid4().hex+'@example.test','password':secrets.token_urlsafe(28)+'aA7!','installation':str(uuid.uuid4()),'secret':secrets.token_hex(32)}
 def save():statepath.write_bytes(b.crypt(json.dumps(state).encode()))
 def quoted(text):return"'"+str(text).replace("'","''")+"'"
 save()
 if'auth_id'not in state:
  code,account=b.api('/auth/v1/admin/users','POST',{'email':state['email'],'password':state['password'],'email_confirm':True,'user_metadata':{'final_event_fixture':True}},admin=True)
  assert code in(200,201);state['auth_id']=account['id'];save()
 query('fixture-profile',"do $$begin if not exists(select 1 from public.users where auth_user_id="+quoted(state['auth_id'])+"::uuid)then insert into public.users(email,name,role,verification_status,auth_user_id)values("+quoted(state['email'])+",'FINAL Event HTTP synthetic','customer','approved',"+quoted(state['auth_id'])+"::uuid);end if;end$$;")
 uid=query('fixture-id','begin read only;select id from public.users where auth_user_id='+quoted(state['auth_id'])+'::uuid;rollback;')[0]['id']
 token=b.login(state);checks=[]
 def check(ok,label):
  assert ok,label;checks.append({'check':label,'result':'PASS','surface':'actual TEST HTTP and persisted synthetic readback'});print(json.dumps(checks[-1]),flush=True)
 def gateway(name,args):return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(args)},token)
 code,result=gateway('final_delivery_cart_policy',{});check(code==200 and result['code']=='OK'and result['reservations_enabled']is False and result['reservation_duration_seconds']==0 and result['name_short_items']is True,'real Customer reads approved no-reservation policy through the gateway')
 code,result=gateway('fr30_register_push',{'p_installation':state['installation'],'p_token':'synthetic-event-http-'+state['installation'],'p_secret':state['secret']});check(code==200 and result['code']=='REGISTERED','new synthetic installation binds to the actual authenticated Customer session')
 rows=query('fixture-events',"""begin;
 insert into public.notifications(user_id,title,message,type)values("""+str(uid)+""",'FINAL Event HTTP synthetic','Synthetic ordinary order event; no real order action.','order');
 update fr30_private.push_deliveries set due_at=clock_timestamp()+interval'2 hours'where device_id="""+quoted(state['installation'])+"""::uuid;
 select n.id,n.order_push_event_id as event_id,(select count(*)from fr30_private.push_deliveries j where j.notification_id=n.id and j.device_id="""+quoted(state['installation'])+"""::uuid)as jobs from public.notifications n where n.user_id="""+str(uid)+" and n.title='FINAL Event HTTP synthetic'order by n.id desc limit 1;commit;")
 row=rows[0];event=row['event_id'];check(event is not None and row['jobs']==1,'new ordinary order notice commits one existing durable session-bound job with a UUID hint')
 def resolve(secret,event_id=event):return b.api('/rest/v1/rpc/fr30_resolve_push','POST',{'p_installation':state['installation'],'p_secret':secret,'p_broadcast':event_id})
 try:
  code,result=resolve(state['secret']);check(code==200 and result['code']=='OK'and result['broadcast_id']==event and result['message']=='Synthetic ordinary order event; no real order action.','existing background capability resolver returns only the owning ordinary event text')
  code,result=resolve(secrets.token_hex(32));check(code==200 and result['code']=='FORBIDDEN','wrong installation capability cannot read ordinary notification')
  code,result=resolve(state['secret'],str(uuid.uuid4()));check(code==200 and result['code']=='FORBIDDEN','unrelated UUID hint cannot read another notification')
  code,_=b.api('/rest/v1/notifications','POST',{'user_id':uid,'title':'forged','message':'forged','type':'order'},token);check(code==403,'Customer cannot forge a system notification or enqueue arbitrary push')
  query('mark-only-fixture-read','update public.notifications set is_read=true where id='+str(row['id'])+' and user_id='+str(uid)+';')
  code,result=resolve(state['secret']);check(code==200 and result['code']=='FORBIDDEN','already-read ordinary event is withheld by actual HTTP resolver')
 finally:
  code,result=gateway('fr30_unregister_push',{'p_installation':state['installation']});assert code==200 and result['code']=='UNREGISTERED'
  query('expire-only-fixture-jobs','update fr30_private.push_deliveries set state=\'SKIPPED\',lease=null where notification_id='+str(row['id'])+' and user_id='+str(uid)+" and state in('PENDING','RETRY','PROCESSING');")
  cleanup=query('cleanup-readback',"begin read only;select jsonb_build_object('installation_absent',not exists(select 1 from fr30_private.push_devices where id="+quoted(state['installation'])+"::uuid),'no_pending_fixture_job',not exists(select 1 from fr30_private.push_deliveries where notification_id="+str(row['id'])+" and user_id="+str(uid)+" and state in('PENDING','RETRY','PROCESSING')))as state;rollback;")[0]['state']
  assert cleanup['installation_absent']and cleanup['no_pending_fixture_job']
 evidence={'project':REF,'passed':len(checks),'checks':checks,'actual_fcm_receipt':False,'provider_calls':0,'cleanup':'only new synthetic installation unregistered and its jobs skipped; synthetic inbox/Auth/audit retained','cleanup_state':cleanup,'production_modified':False}
 (ROOT/'docs/evidence/FINAL-delivery-event-push-hosted.json').write_text(json.dumps(evidence,indent=2)+'\n')
