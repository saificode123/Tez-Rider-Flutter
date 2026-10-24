"""Guarded canonical feedback review/deployment and authenticated HTTP/WebSocket verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='feedback'
action=sys.argv[2];assert action in('review','deploy','post','hosted')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer']);other_vendor=b.login(legacy['vendor']);rider=b.login(legacy['rider'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610240001';migration=ROOT/'supabase/migrations/202610240001_final2_feedback.sql'
history=OUT/'feedback-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
expected=[v for v in known if v<=version]
actual=[r['version']for r in db.query(history)]
if action in('review','deploy'):
 assert actual==[v for v in expected if v!=version],'Unexpected history; no replay'
else:
 assert actual==known[:len(actual)] and version in actual,'Target must be applied within an exact known migration prefix'
digest=hashlib.sha256(migration.read_bytes()).hexdigest()
checks=[]
def check(ok,label,level='real authenticated TEST HTTP'):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':level});print(json.dumps(checks[-1]),flush=True)
 (OUT/('feedback-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-feedback.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other),('OTHER_VENDOR',other_vendor),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'feedback-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('feedback-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'feedback-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert not re.search(r'(?im)^\s*delete from',source),'Ledger migration must preserve history'
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610240001','final2_feedback');commit;")
 path=OUT/'feedback-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'feedback-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))
elif action=='hosted':
 prior=OUT/'feedback-hosted-proof.json'
 if prior.exists():
  proof=json.loads(prior.read_text());assert proof['project']==REF and proof['passed']==27 and proof['websocket_verified']
  print(json.dumps({'retained_prior_passes':27,'fresh_tests_executed':0,'reason':'immutable hosted review fixture already consumed; retain original proof'}));raise SystemExit(0)
 import time,urllib.parse
 sys.path.insert(0,str(ROOT/'build/fr21-python'))
 from websockets.sync.client import connect
 from websockets.exceptions import ConnectionClosed
 oid=state['cash_invoice_fixture']['order_id']
 code,context=gateway('final2_feedback_context',customer,{'p_order_id':oid})
 check(code==200 and context['order_id']==oid and {t['role']for t in context['targets']}=={'vendor','rider'},'real owning Customer resolves delivered Vendor and assigned Rider separately')
 targets={t['role']:t for t in context['targets']};vid=targets['vendor']['target_id'];rid=targets['rider']['target_id']
 check(vid==state['live_vendor_profile_id']and rid!=vid,'server returns canonical distinct numeric identities')
 for token,label in [(other,'unrelated Customer'),(vendor,'Vendor'),(rider,'Rider'),(admin_token,'Admin')]:
  code,_=gateway('final2_feedback_context',token,{'p_order_id':oid});check(code==403,label+' cannot read owning-Customer feedback context')
 fixture=state.setdefault('feedback_fixture',{'order_id':oid,'vendor_request':str(uuid.uuid4()),'rider_request':str(uuid.uuid4())})
 assert fixture['order_id']==oid
 def save(): (OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
 save()
 for params,label in [({'p_target_id':vid,'p_rating':0},'invalid stars'),({'p_target_id':vid,'p_rating':4,'p_comment':'x'*2001},'oversized comment')]:
  data={'p_order_id':oid,'p_target_id':vid,'p_rating':4,'p_comment':'FINAL2 SYNTHETIC FEEDBACK','p_request_id':str(uuid.uuid4()),**params}
  code,_=gateway('final2_submit_feedback',customer,data);check(code==400,'real server rejects '+label)
 data={'p_order_id':oid,'p_target_id':vid,'p_rating':4,'p_comment':'FINAL2 SYNTHETIC FEEDBACK Vendor','p_request_id':fixture['vendor_request']}
 for token,label in [(other,'unrelated Customer'),(vendor,'Vendor'),(rider,'Rider')]:
  code,_=gateway('final2_submit_feedback',token,data);check(code==403,label+' cannot forge Customer feedback')
 code,_=b.api('/rest/v1/rpc/final2_submit_feedback','POST',data,customer)
 check(code in(401,403),'direct authenticated REST cannot bypass shared gateway budget')
 if not fixture.get('vendor_submitted'):
  assert targets['vendor']['review']is None,'Fresh isolated review required for live WebSocket signal'
  url='wss://'+REF+'.supabase.co/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':b.ANON,'vsn':'1.0.0'})
  with connect(url,open_timeout=20,close_timeout=3)as ws:
   topic='realtime:final2-safe-rating-'+uuid.uuid4().hex
   ws.send(json.dumps({'topic':topic,'event':'phx_join','ref':'1','payload':{'config':{'private':False,'broadcast':{'ack':False,'self':False},'presence':{'key':''},'postgres_changes':[{'event':'*','schema':'public','table':'rating_summaries','filter':'target_user_id=eq.'+str(vid)}]},'access_token':vendor}}))
   registered=False;deadline=time.monotonic()+20
   while time.monotonic()<deadline:
    message=json.loads(ws.recv(timeout=max(.01,deadline-time.monotonic())))
    if message.get('event')=='phx_reply'and message.get('ref')=='1':
     assert message['payload']['status']=='ok';registered=bool(message['payload'].get('response',{}).get('postgres_changes'));break
   check(registered,'real approved Vendor registers aggregate Postgres Changes subscription','real authenticated TEST WebSocket')
   code,value=gateway('final2_submit_feedback',customer,data)
   check(code==200 and value['code']=='SUBMITTED'and value['rating']==4,'real owning Customer submits canonical Vendor feedback')
   fixture['vendor_submitted']=True;save();received=None;deadline=time.monotonic()+20
   while time.monotonic()<deadline:
    try:message=json.loads(ws.recv(timeout=max(.01,deadline-time.monotonic())))
    except(TimeoutError,ConnectionClosed):break
    if message.get('event')=='postgres_changes':received=message['payload']['data']['record'];break
   check(received is not None and received['target_user_id']==vid and received['rating_count']>=1,'real Vendor receives committed aggregate update','real authenticated TEST WebSocket')
   check(not any(k in received for k in('reviewer_id','reviewee_id','order_id','comment','request_payload')),'actual Realtime payload contains no private review or Customer identity','real authenticated TEST WebSocket')
   fixture['websocket_verified']=True;save()
 else:
  assert fixture.get('websocket_verified'),'Live event evidence incomplete; use a fresh explicitly labelled fixture'
 code,replay=gateway('final2_submit_feedback',customer,data)
 check(code==200 and replay['code']=='ALREADY_APPLIED'and replay['rating']==4,'identical real request UUID safely restores committed feedback')
 code,_=gateway('final2_submit_feedback',customer,{**data,'p_rating':1});check(code==409,'changed payload with existing UUID is rejected')
 code,duplicate=gateway('final2_submit_feedback',customer,{**data,'p_request_id':str(uuid.uuid4()),'p_rating':1})
 check(code==200 and duplicate['code']=='ALREADY_REVIEWED'and duplicate['rating']==4,'new UUID cannot overwrite or duplicate original review')
 rider_data={**data,'p_target_id':rid,'p_rating':2,'p_comment':'FINAL2 SYNTHETIC FEEDBACK Rider','p_request_id':fixture['rider_request']}
 code,value=gateway('final2_submit_feedback',customer,rider_data)
 check(code==200 and value['code']in('SUBMITTED','ALREADY_APPLIED')and value['rating']==2,'real separate Rider feedback succeeds')
 fixture['rider_submitted']=True;save()
 for target,expected in [(vid,4),(rid,2)]:
  code,summary=gateway('final2_rating_summary',other,{'p_target_id':target})
  check(code==200 and summary['target_id']==target and summary['count']==1 and summary['average']==expected,'real app-visible summary has exact separate '+('Vendor'if target==vid else'Rider')+' average')
  check(all(set(r)=={'id','rating','comment','created_at'}for r in summary['recent']),'real summary omits Customer identity and order links')
 code,ratings=gateway('get_vendor_ratings',customer,{'p_vendor_ids':[vid]})
 check(code==200 and len(ratings)==1 and ratings[0]['avg_rating']==4 and ratings[0]['review_count']==1,'legacy Vendor-card API excludes Rider rating from Vendor average')
 code,_=b.api('/rest/v1/rpc/final2_rating_summary','POST',{'p_target_id':vid})
 check(code in(401,403),'anonymous summary request is denied')
 path=OUT/'feedback-hosted-audit.private.sql'
 path.write_text("begin read only;select(select count(*)from public.reviews where order_id="+str(oid)+" and verified_at is not null)as reviews,(select count(*)from public.security_audit_log where action='feedback_submitted'and actor_id=(select user_id from public.orders where id="+str(oid)+")and target_id in("+str(vid)+","+str(rid)+"))as audits;rollback;",encoding='utf-8')
 counts=db.query(path)[0];check(counts['reviews']==2 and counts['audits']==2,'persisted synthetic fixture has exactly two reviews and canonical actor/target audits')
 (OUT/'feedback-hosted-proof.json').write_text(json.dumps({'project':REF,'passed':len(checks),'synthetic_financial_delivery_fixture':True,'physical_delivery_or_GPS_or_real_cash_asserted':False,'websocket_verified':fixture['websocket_verified'],'production_modified':False},indent=2)+'\n',encoding='utf-8')



else:raise SystemExit('Unsupported action; no test executed')
