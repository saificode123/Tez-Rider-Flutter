"""Guarded owned history review/deployment and authenticated security verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='order-detail'
action=sys.argv[2];assert action in('review','deploy','post','fixture','hosted','cancel','retire')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer']);other_vendor=b.login(legacy['vendor']);rider=b.login(legacy['rider'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610240002';migration=ROOT/'supabase/migrations/202610240002_final2_order_detail.sql'
history=OUT/'order-detail-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
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
 (OUT/('order-detail-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-order-detail.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other),('OTHER_VENDOR',other_vendor),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'order-detail-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('order-detail-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'order-detail-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert not re.search(r'(?im)^\s*delete from',source),'Ledger migration must preserve history'
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610240002','final2_order_detail');commit;")
 path=OUT/'order-detail-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'order-detail-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))
elif action in('fixture','hosted','cancel','retire'):
 fixture=state.setdefault('history_fixture',{'marker':'FINAL2 SYNTHETIC HISTORY '+uuid.uuid4().hex,'product_request_A':str(uuid.uuid4()),'product_request_B':str(uuid.uuid4()),'checkout_request':str(uuid.uuid4()),'retire_request_A':str(uuid.uuid4()),'retire_request_B':str(uuid.uuid4())})
 def save(): (OUT/'onboarding-accounts.dpapi').write_bytes(b.crypt(json.dumps(state).encode()))
 def detail():
  code,value=gateway('final2_order_detail',customer,{'p_order_id':fixture['order_id']});assert code==200;return value
 def rest(resource,token,query):
  return b.api('/functions/v1/security-gateway','POST',{'method':'GET','path':'/'+resource,'query':query,'headers':{},'body':''},token)
 save()
 if action=='fixture':
  for label,token,price,quantity in [('A',vendor,11.25,2),('B',other_vendor,7.25,1)]:
   if 'product_'+label not in fixture:
    code,value=gateway('fr17_save_product',token,{'p_request_id':fixture['product_request_'+label],'p_product_id':None,'p_data':{'name':fixture['marker']+' '+label,'price':price,'category':'FINAL2 TEST only'},'p_stock':quantity,'p_threshold':0,'p_expected_version':None})
    assert code==200 and value['code']in('UPDATED','ALREADY_APPLIED');fixture['product_'+label]=value['product_id'];save()
  if 'order_id'not in fixture:
   code,value=gateway('fr10_checkout',customer,{'p_request_id':fixture['checkout_request'],'p_items':[{'product_id':fixture['product_A'],'quantity':2},{'product_id':fixture['product_B'],'quantity':1}],
    'p_delivery':{'address':fixture['marker'],'lat':33.68,'lng':73.04,'speed':'standard','destination_confirmed':True,'destination_source':'map_pin'}})
   assert code==200 and value['code']in('PLACED','ALREADY_PLACED');fixture['order_id']=value['order_id'];save()
  value=detail();assert len(value['vendor_orders'])==2
  for label,token in [('A',vendor),('B',other_vendor)]:
   portion=next(v for v in value['vendor_orders']if(v['vendor_id']==state['live_vendor_profile_id'])==(label=='A'))
   fixture['portion_'+label]=portion['id'];save()
   if not fixture.get('accepted_'+label):
    code,result=gateway('fr10_vendor_transition',token,{'p_vendor_order_id':portion['id'],'p_status':'accepted'})
    assert code==200 and result['code']in('ACCEPTED','ALREADY_ACCEPTED'),'Real shared acceptance required, no timeout rewrite';fixture['accepted_'+label]=True;save()
  value=detail();assert value['status']=='accepted'and value['totals']['total_cents']=='22975'
  print(json.dumps({'project':REF,'real_two_vendor_checkout_and_acceptance':True,'payment':'UNPAID','GPS_or_physical_delivery_asserted':False,'provider_calls':0}))
 elif action=='hosted':
  value=detail();assert value['status']in('accepted','cancelled')
  check(value['order_id']==fixture['order_id']and value['item_source']=='CHECKOUT_SNAPSHOT'and len(value['items'])==2,'real owning Customer reads exact shared immutable checkout items')
  items={i['product_id']:i for i in value['items']}
  check(items[fixture['product_A']]['quantity']==2 and items[fixture['product_A']]['unit_cents']=='1125'and items[fixture['product_A']]['line_cents']=='2250'and items[fixture['product_B']]['line_cents']=='725','real fractional quantities and per-Vendor lines remain exact')
  check(value['totals']=={'currency':'PKR','state':'CONFIRMED','subtotal_cents':'2975','delivery_cents':'20000','total_cents':'22975'},'real trusted subtotal/delivery/total reconciliation uses exact cents')
  check(len(value['vendor_orders'])==2 and all(len(v['events'])>=(3 if value['status']=='cancelled'else 2)for v in value['vendor_orders']),'real private Vendor transitions project through owned endpoint')
  check(value['payment']['state']=='UNPAID'and value['payment']['refunded_amount']==0,'real history does not confuse checkout/cancellation with cash collection or refund')
  for token,label in [(other,'unrelated Customer'),(vendor,'Vendor'),(other_vendor,'unrelated Vendor'),(rider,'Rider'),(admin_token,'Admin')]:
   code,_=gateway('final2_order_detail',token,{'p_order_id':fixture['order_id']});check(code==403,label+' cannot impersonate owning Customer detail')
  code,_=gateway('final2_order_detail',customer,{'p_order_id':0});check(code==400,'real detail rejects invalid order identity')
  code,_=gateway('final2_order_detail',customer,{'p_order_id':9223372036854775807});check(code==403,'missing order returns no private existence/detail')
  code,_=b.api('/rest/v1/rpc/final2_order_detail','POST',{'p_order_id':fixture['order_id']},customer);check(code in(401,403),'direct authenticated detail cannot bypass mandatory gateway budget')
  code,_=b.api('/rest/v1/rpc/final2_order_detail','POST',{'p_order_id':fixture['order_id']});check(code in(401,403),'anonymous real detail denied')
  code,legacy_value=gateway('final2_order_detail',customer,{'p_order_id':state['cod_fixture']['order_id']})
  check(code==200 and legacy_value['item_source']=='UNAVAILABLE'and legacy_value['items']==[]and legacy_value['history_limited'],'real legacy records disclose missing item/milestone history honestly')
  check(legacy_value['payment']['state']=='CASH_RECORDED'and legacy_value['payment']['refunded_amount']==25.75,'real legacy committed manual refund context is preserved')
  code,old_snapshot=gateway('final2_order_detail',customer,{'p_order_id':state['cash_invoice_fixture']['order_id']})
  check(code==200 and old_snapshot['item_source']=='CHECKOUT_SNAPSHOT'and old_snapshot['totals']['total_cents']=='13000'and old_snapshot['payment']['state']=='CASH_RECORDED','earlier legitimate immutable receipt checkout remains readable with exact recorded cash context')
  code,history=gateway('fr25_order_history',customer,{'p_before':None})
  check(code==200 and len(history)<=30 and any(o['id']==fixture['order_id']for o in history),'retained owned history paging includes new detail without changing its cursor contract')
  (OUT/'order-detail-hosted-proof.json').write_text(json.dumps({'project':REF,'passed':len(checks),'synthetic_shared_checkout_only':True,'physical_delivery_GPS_OTP_or_cash_asserted':False,'production_modified':False},indent=2)+'\n',encoding='utf-8')
 elif action=='cancel':
  before=detail()
  if before['status']!='cancelled':
   assert before['status']=='accepted'
   code,value=gateway('fr10_vendor_transition',vendor,{'p_vendor_order_id':fixture['portion_A'],'p_status':'cancelled'});assert code==200 and value['code']=='ORDER_CANCELLED'
  value=detail();assert value['status']=='cancelled'and value['cancelled_at']is not None and value['delivered_at']is None
  assert value['payment']['state']=='UNPAID'and value['payment']['refunded_amount']==0
  assert len(value['events'])==3 and all(v['status']=='cancelled'and len(v['events'])==3 for v in value['vendor_orders'])
  fixture['cancelled']=True;save()
  print(json.dumps({'real_vendor_rejection_and_shared_terminal_events':True,'unpaid_COD_preserved':True,'fake_refund_or_delivery_asserted':False}))
 elif action=='retire':
  assert detail()['status']=='cancelled'
  for label,token,price in [('A',vendor,99),('B',other_vendor,7.25)]:
   if fixture.get('retired_'+label):continue
   key='retire_params_'+label
   if key not in fixture:
    code,rows=rest('products',token,'id=eq.'+str(fixture['product_'+label])+'&select=id,stock_qty,stock_version');assert code==200 and len(rows)==1
    fixture[key]={'p_request_id':fixture['retire_request_'+label],'p_product_id':fixture['product_'+label],
     'p_data':{'name':fixture['marker']+' renamed '+label,'price':price},'p_stock':0,'p_threshold':0,'p_expected_version':rows[0]['stock_version']};save()
   code,value=gateway('fr17_save_product',token,fixture[key]);assert code==200 and value['code']in('UPDATED','ALREADY_APPLIED');fixture['retired_'+label]=True;save()
  value=detail();items={i['product_id']:i for i in value['items']}
  assert items[fixture['product_A']]['product']==fixture['marker']+' A'and items[fixture['product_A']]['unit_cents']=='1125'
  fixture['retired']=True;save()
  print(json.dumps({'fixture_stock_retired_through_owner_APIs':True,'original_checkout_names_and_prices_preserved_after_real_catalogue_edit':True,'historical_orders_or_media_deleted':False}))
else:raise SystemExit('Unsupported action; no test executed')
