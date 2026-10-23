"""Guarded Vendor delivered-sales reporting review/deployment and authenticated HTTP verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='cash-invoices'
action=sys.argv[2];assert action in('review','deploy','post','fixture','native-fixture','hosted')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer']);other_vendor=b.login(legacy['vendor']);rider=b.login(legacy['rider'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610230010';migration=ROOT/'supabase/migrations/202610230010_final2_cash_invoices.sql'
history=OUT/'cash-invoices-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
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
 (OUT/('cash-invoices-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-cash-invoices.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other),('OTHER_VENDOR',other_vendor),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'cash-invoices-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('cash-invoices-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'cash-invoices-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 worker=json.loads((OUT/'cash-worker-deployment.json').read_text());assert worker['project']==REF and worker['deployment']=='PASS'
 assert all(hashlib.sha256((ROOT/f['file']).read_bytes()).hexdigest()==f['sha256']for f in worker['files'])
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert not re.search(r'(?im)^\s*delete from',source),'Ledger migration must preserve history'
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610230010','final2_cash_invoices');commit;")
 path=OUT/'cash-invoices-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'cash-invoices-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))


elif action in('fixture','native-fixture'):
 fixture_key='native_cash_fixture'if action=='native-fixture'else'cash_invoice_fixture'
 fixture=state.setdefault(fixture_key,{'marker':'FINAL2 SYNTHETIC CASH RECEIPT '+uuid.uuid4().hex,'product_request':str(uuid.uuid4()),'checkout_request':str(uuid.uuid4()),'cash_request':str(uuid.uuid4())})
 private=OUT/'onboarding-accounts.dpapi'
 def save():private.write_bytes(b.crypt(json.dumps(state).encode()))
 save()
 if 'product_id'not in fixture:
  code,value=gateway('fr17_save_product',vendor,{'p_request_id':fixture['product_request'],'p_product_id':None,'p_data':{'name':fixture['marker'],'price':5,'category':'FINAL2 TEST only'},'p_stock':2,'p_threshold':0,'p_expected_version':None})
  assert code==200 and value['code']=='UPDATED';fixture['product_id']=value['product_id'];save()
 if 'order_id'not in fixture:
  code,value=gateway('fr10_checkout',customer,{'p_request_id':fixture['checkout_request'],'p_items':[{'product_id':fixture['product_id'],'quantity':2}],'p_delivery':{'address':fixture['marker'],'lat':33.68,'lng':73.04,'speed':'standard','destination_confirmed':True,'destination_source':'map_pin'}})
  assert code==200 and value['code']in('PLACED','ALREADY_PLACED'),'Real stock-aware TEST checkout required; HTTP '+str(code)+' code '+str(value.get('code','unknown'))
  fixture['order_id']=value['order_id'];save()
 source=(ROOT/'supabase/tests/FINAL2-cash-invoice-hosted-state.sql').read_text(encoding='utf-8-sig')
 for key,token in [('CUSTOMER',customer),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__ORDER_ID__',str(fixture['order_id'])).replace('__VENDOR_ID__',str(state['live_vendor_profile_id'])).replace('__MARKER__',"'"+fixture['marker']+"'")
 path=OUT/'cash-invoice-fixture.private.sql';path.write_text(source,encoding='utf-8');assert db.query(path)[0]['seeded_financial_state_only']
 print(json.dumps({'project':REF,'real_customer_checkout':True,'stock_units':2,'seeded_financial_delivery_state_only':True,'physical_delivery_or_GPS_or_real_cash_asserted':False,'provider_calls':0}))
elif action=='hosted':
 import time,urllib.request,urllib.error
 fixture=state['cash_invoice_fixture'];oid=fixture['order_id']
 def rest(path,token):
  name,_,query=path.partition('?')
  return b.api('/functions/v1/security-gateway','POST',{'method':'GET','path':'/'+name,'query':query,'headers':{},'body':''},token)
 code,value=gateway('final2_order_payment',customer,{'p_order_id':oid});assert code==200
 amount=value['amount'];assert value['state']in('UNPAID','CASH_RECORDED')
 if not fixture.get('cash_recorded'):
  direct,_=b.api('/rest/v1/invoices?order_id=eq.'+str(oid)+'&select=id',token=customer)
  check(direct in(401,403),'direct invoice REST cannot bypass mandatory gateway budget')
  code,invoices=rest('invoices?order_id=eq.'+str(oid)+'&select=id',customer)
  check(code==200 and not invoices,'actual finalized unpaid COD checkout has no paid invoice')
  code,value=gateway('final2_record_cash',rider,{'p_order_id':oid,'p_event_kind':'COLLECTED','p_amount':amount,'p_request_id':fixture['cash_request'],'p_confirmed':True,'p_reference':'FINAL2-SYNTHETIC-CASH-INVOICE','p_refund_kind':None,'p_refund_id':None})
  check(code==200 and value['code']=='RECORDED','authenticated assigned Rider commits synthetic cash acknowledgement from actual checkout')
  fixture['cash_recorded']=True;(OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
 code,invoices=rest('invoices?order_id=eq.'+str(oid)+'&select=id,status,failure_code',customer)
 check(code==200 and len(invoices)==1 and invoices[0]['status']in('pending','ready'),'actual owning Customer sees one canonical receipt metadata row')
 invoice=invoices[0]
 code,jobs=b.api('/rest/v1/email_outbox?entity_type=eq.invoice&entity_id=eq.'+invoice['id']+'&select=id,status,test_approved',admin=True)
 check(code==200 and len(jobs)==1 and jobs[0]['test_approved']is False,'one durable invoice intent retains unapproved TEST delivery; no email send authorized')
 worker_key=b.crypt((b.PRIVATE/'fr32-worker.bin').read_bytes(),True).decode()
 for attempt in range(10):
  code,current=rest('invoices?id=eq.'+invoice['id']+'&select=status,failure_code',customer);assert code==200 and len(current)==1
  if current[0]['status']=='ready':break
  assert current[0]['status']!='failed','Canonical source requires review; no fabricated invoice readiness'
  request=urllib.request.Request('https://'+REF+'.supabase.co/functions/v1/fr32-email-worker',data=b'{}',headers={'Content-Type':'application/json','x-fr32-worker-key':worker_key},method='POST')
  try:
   with urllib.request.urlopen(request,timeout=100)as response:assert response.status==200
  except urllib.error.HTTPError as error:assert error.code==503,'Protected worker response unconfirmed'
  time.sleep(2)
 else:raise AssertionError('Private receipt generation pending after bounded worker attempts')
 check(True,'actual hosted worker prepares the private itemized COD receipt without a provider email send')
 for token,label,allowed in [(customer,'owner',True),(admin_token,'Admin',True),(other,'unrelated Customer',False),(vendor,'Vendor',False),(rider,'Rider',False)]:
  code,result=b.api('/functions/v1/fr32-invoice-url','POST',{'order_id':oid},token)
  check(code==200 and result.get('expires_in')==900 if allowed else code in(401,403),'real '+label+' receipt signing authorization')
  if token==customer:
   with urllib.request.urlopen(result['url'],timeout=30)as response:pdf=response.read()
   check(pdf.startswith(b'%PDF-'),'actual private COD receipt bytes download through owning Customer signed URL')
   (OUT/'hosted-cash-receipt.private.pdf').write_bytes(pdf)
   from pypdf import PdfReader
   text='\n'.join(page.extract_text()for page in PdfReader(OUT/'hosted-cash-receipt.private.pdf').pages)
   check('COD CASH RECEIPT'in text and'CASH_RECORDED'in text and'The app did not perform a payment-provider transfer.'in text,'actual hosted PDF states manual cash acknowledgement and no provider transfer')
 code,_=b.api('/storage/v1/object/public/invoices/invalid.pdf');check(code in(400,401,403,404),'invoice bucket stays private')
 code,jobs=b.api('/rest/v1/email_outbox?id=eq.'+jobs[0]['id']+'&select=status,test_approved,provider_message_id',admin=True)
 check(code==200 and jobs[0]['status']=='skipped_test'and jobs[0]['test_approved']is False and jobs[0]['provider_message_id']is None,'receipt is prepared while actual TEST email remains suppressed')
 (OUT/'cash-invoices-hosted-proof.json').write_text(json.dumps({'project':REF,'passed':len(checks),'actual_private_pdf':True,'email_sent':False,'physical_delivery_or_real_cash_asserted':False},indent=2)+'\n',encoding='utf-8')
else:raise SystemExit('Unsupported action; no test executed')
