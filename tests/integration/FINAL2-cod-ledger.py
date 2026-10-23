"""Guarded COD manual ledger review/deployment and authenticated HTTP verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='cod-ledger'
action=sys.argv[2];assert action in('review','deploy','post','fixture','hosted')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer']);other_vendor=b.login(legacy['vendor']);rider=b.login(legacy['rider'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610230008';migration=ROOT/'supabase/migrations/202610230008_final2_cod_ledger.sql'
history=OUT/'cod-ledger-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
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
 (OUT/('cod-ledger-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-cod-ledger.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other),('OTHER_VENDOR',other_vendor),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'cod-ledger-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('cod-ledger-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'cod-ledger-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert not re.search(r'(?im)^\s*delete from',source),'Ledger migration must preserve history'
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610230008','final2_cod_ledger');commit;")
 path=OUT/'cod-ledger-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'cod-ledger-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))


elif action=='fixture':
 fixture=state.setdefault('cod_fixture',{'marker':'final2-cod-'+uuid.uuid4().hex})
 private=OUT/'onboarding-accounts.dpapi'
 private.write_bytes(b.crypt(json.dumps(state).encode()))
 source=(ROOT/'supabase/tests/FINAL2-cod-hosted-fixture.sql').read_text(encoding='utf-8-sig')
 for key,token in [('CUSTOMER',customer),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__MARKER__',"'"+fixture['marker']+"'").replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'cod-fixture.private.sql';path.write_text(source,encoding='utf-8')
 fixture.update(db.query(path)[0]['value']);private.write_bytes(b.crypt(json.dumps(state).encode()))
 print(json.dumps({'project':REF,'synthetic_financial_orders':2,'physical_delivery_or_money_transfer_asserted':False,'uploaded_dispute_evidence_asserted':False,'provider_calls':0}))
elif action=='hosted':
 import concurrent.futures
 fixture=state['cod_fixture'];assert not fixture.get('hosted_completed'),'Retain prior passing evidence; do not replay a settled financial fixture'
 oid=fixture['order_id'];amount=25.75
 def read(token,order=oid):return gateway('final2_order_payment',token,{'p_order_id':order})
 code,value=read(customer)
 check(code==200 and value['state']=='UNPAID'and value['events']==[],'real customer snapshot keeps delivered synthetic COD unpaid until explicit receipt')
 payload={'p_order_id':oid,'p_event_kind':'COLLECTED','p_amount':amount,'p_request_id':str(uuid.uuid4()),'p_confirmed':True,'p_reference':'FINAL2-SYNTHETIC-CASH-ACK','p_refund_kind':None,'p_refund_id':None}
 for token,label in [(customer,'customer'),(vendor,'Vendor')]:
  code,_=gateway('final2_record_cash',token,payload);check(code==403,'real '+label+' cannot forge collection')
 code,_=b.api('/rest/v1/rpc/final2_record_cash','POST',payload,rider)
 check(code in(401,403),'direct authenticated cash RPC cannot bypass mandatory gateway authorization/budget')
 for changed,label in [({'p_amount':'NaN'},'non-finite amount'),({'p_confirmed':False},'missing explicit acknowledgement'),({'p_amount':20},'wrong canonical amount')]:
  code,_=gateway('final2_record_cash',rider,{**payload,**changed});check(code in(400,409),'real server rejects '+label)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
  results=list(pool.map(lambda _:gateway('final2_record_cash',rider,payload),range(2)))
 check(all(c==200 for c,v in results)and {v['code']for c,v in results}=={'RECORDED','ALREADY_APPLIED'}and len({v['event_id']for c,v in results})==1,'two real Rider acknowledgements with the same UUID produce one committed receipt')
 code,value=gateway('final2_record_cash',rider,{**payload,'p_request_id':str(uuid.uuid4()),'p_reference':'FINAL2-DUPLICATE-ACK'})
 check(code==200 and value['code']=='ALREADY_COLLECTED','new-request duplicate cannot collect twice or replace original receipt')
 code,value=read(customer)
 check(code==200 and value['state']=='CASH_RECORDED'and len(value['events'])==1 and value['events'][0]['actor_role']=='rider','actual customer read observes committed canonical Rider cash evidence')
 code,original=b.api('/rest/v1/payments?id=eq.'+str(fixture['payment_id'])+'&select=status,paidat',admin=True)
 check(code==200 and original==[{'status':'pending','paidat':None}],'original immutable pending-payment history remains intact')
 code,value=gateway('admin_resolve_dispute',admin_token,{'p_dispute_id':fixture['dispute_id'],'p_decision':'RESOLVED','p_note':'FINAL2 synthetic committed cash evidence review'})
 check(code==200 and value['code']=='RESOLVED','real retained FR26 decision creates refund eligibility from the committed COD receipt')
 code,value=read(admin_token);assert code==200 and len(value['refunds'])==1;refund=value['refunds'][0]
 check(refund['state']=='PENDING'and value['refunded_amount']==0,'actual pending refund action never reports returned cash')
 refund_payload={'p_order_id':oid,'p_event_kind':'REFUND_FAILED','p_amount':amount,'p_request_id':str(uuid.uuid4()),'p_confirmed':True,'p_reference':'FINAL2-SYNTHETIC-ATTEMPT-FAILED','p_refund_kind':'DISPUTE','p_refund_id':refund['id']}
 code,value=gateway('final2_record_cash',admin_token,refund_payload)
 check(code==200 and value['code']=='RECORDED','authorized Admin records a synthetic unsuccessful refund attempt')
 code,value=read(customer)
 check(code==200 and value['refunds'][0]['state']=='RETRY_REQUIRED'and value['refunded_amount']==0,'failed attempt is retryable and still records no cash return')
 confirmed={**refund_payload,'p_event_kind':'REFUND_CONFIRMED','p_request_id':str(uuid.uuid4()),'p_reference':'FINAL2-SYNTHETIC-MANUAL-RETURN'}
 with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
  results=list(pool.map(lambda _:gateway('final2_record_cash',admin_token,confirmed),range(2)))
 check(all(c==200 for c,v in results)and {v['code']for c,v in results}=={'RECORDED','ALREADY_APPLIED'},'concurrent Admin confirmation/retry commits one refund record')
 code,value=gateway('final2_record_cash',admin_token,{**confirmed,'p_request_id':str(uuid.uuid4())})
 check(code==200 and value['code']=='ALREADY_REFUNDED','a fresh request cannot duplicate an already confirmed refund')
 code,_=gateway('final2_record_cash',admin_token,{**refund_payload,'p_request_id':str(uuid.uuid4())})
 check(code==409,'late unsuccessful attempt cannot reverse a confirmed cash refund')
 code,value=read(customer)
 check(code==200 and value['refunded_amount']==amount and value['refunds'][0]['state']=='CONFIRMED'and len(value['events'])==3,'customer sees the exact committed manual refund and three immutable result events')
 code,value=read(vendor)
 check(code==200 and value['amount']is None and all(e['amount']is None and e['reference']is None for e in value['events']),'participating Vendor sees state without private whole-order amounts/receipt references')
 for token,label in [(other,'customer'),(other_vendor,'Vendor')]:
  code,_=read(token);check(code==403,'unrelated '+label+' cannot read private finance snapshot')
 code,value=read(admin_token,fixture['cancelled_order_id'])
 check(code==200 and value['state']=='LEGACY_SETTLED'and value['refunds'][0]['state']=='PENDING','legacy settled cancelled COD remains available for actual order-refund reconciliation')
 code,value=gateway('final2_record_cash',admin_token,{'p_order_id':fixture['cancelled_order_id'],'p_event_kind':'REFUND_CONFIRMED','p_amount':31.5,'p_request_id':str(uuid.uuid4()),'p_confirmed':True,'p_reference':'FINAL2-SYNTHETIC-ORDER-RETURN','p_refund_kind':'ORDER','p_refund_id':fixture['order_refund_id']})
 check(code==200 and value['code']=='RECORDED','authorized Admin reconciles the retained order-refund action without overwriting its history')
 code,value=read(customer,fixture['cancelled_order_id'])
 check(code==200 and value['refunded_amount']==31.5 and value['refunds'][0]['state']=='CONFIRMED','customer reads the actual committed order-refund outcome')
 code,events=b.api('/rest/v1/cod_cash_events?order_id=in.('+str(oid)+','+str(fixture['cancelled_order_id'])+')&select=id,actor_id,actor_role,event_kind',admin=True)
 assert code==200 and len(events)==4
 ids=','.join(str(e['id'])for e in events)
 code,audits=b.api('/rest/v1/security_audit_log?target_type=eq.cod_cash_event&target_id=in.('+ids+')&select=actor_id,target_id,action',admin=True)
 check(code==200 and len(audits)==4 and all(any(a['target_id']==e['id']and a['actor_id']==e['actor_id']for a in audits)for e in events),'four real critical results have exactly four canonical actor audits; retries add none')
 customer_id=claims(customer)['sub']
 code,profile=b.api('/rest/v1/users?auth_user_id=eq.'+customer_id+'&select=id',admin=True);assert code==200 and len(profile)==1;uid=profile[0]['id']
 code,failures=b.api('/rest/v1/security_audit_log?actor_id=eq.'+str(uid)+'&action=eq.final01_api_authorization&target_type=eq.rest&select=id',admin=True)
 check(code==200 and bool(failures),'bounded existing authorization-failure audit retains the real denying actor without payload data')
 fixture['hosted_completed']=True;(OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
 (OUT/'cod-ledger-hosted-proof.json').write_text(json.dumps({'project':REF,'passed':len(checks),'surface':'real authenticated TEST HTTP/persistence','provider_calls':0,'physical_delivery_or_real_money_transfer_asserted':False,'synthetic_financial_fixtures_preserved':True},indent=2)+'\n',encoding='utf-8')

else:raise SystemExit('Unsupported action; no test was executed')
