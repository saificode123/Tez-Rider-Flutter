"""Guarded FR07 cart review/deployment and authenticated HTTP verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='cart'
action=sys.argv[2];assert action in('review','deploy','post','hosted')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610230006';migration=ROOT/'supabase/migrations/202610230006_final2_cart.sql'
history=OUT/'cart-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
assert [r['version']for r in db.query(history)]==([v for v in expected if v!=version]if action in('review','deploy')else expected),'Unexpected history; no replay'
digest=hashlib.sha256(migration.read_bytes()).hexdigest()
checks=[]
def check(ok,label,level='real authenticated TEST HTTP'):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':level});print(json.dumps(checks[-1]),flush=True)
 (OUT/('cart-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-cart.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'cart-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('cart-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'cart-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert source.count('delete from public.cart_items where user_id=uid;')==1 and len(re.findall(r'\bdelete from\b',source,re.I))==1
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610230006','final2_cart');commit;")
 path=OUT/'cart-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'cart-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))
elif action=='hosted':
 import concurrent.futures
 code,original=gateway('final2_cart_get',customer,{})
 assert code==200 and original['code']=='OK'and original['items']==[],'Synthetic customer empty cart required; never replace other saved data'
 marker='FINAL2 Cart '+uuid.uuid4().hex[:10]
 code,value=gateway('fr17_save_product',vendor,{'p_request_id':str(uuid.uuid4()),'p_product_id':None,
  'p_data':{'name':marker,'price':25.75,'category':'Food'},'p_stock':5,'p_threshold':1,'p_expected_version':None})
 assert code==200 and value['code']=='UPDATED';pid=value['product_id']
 try:
  request={'p_revision':original['revision'],'p_request_id':str(uuid.uuid4()),'p_items':[{'product_id':pid,'qty':2}]}
  with concurrent.futures.ThreadPoolExecutor(max_workers=2)as pool:
   results=list(pool.map(lambda _:gateway('final2_cart_replace',customer,request),range(2)))
  check(all(c==200 for c,v in results)and {v['code']for c,v in results}=={'OK','ALREADY_APPLIED'},'two concurrent real requests apply a cart replacement once')
  revisions={v['revision']for c,v in results};assert len(revisions)==1;revision=revisions.pop()
  code,saved=gateway('final2_cart_get',customer,{})
  check(code==200 and saved['revision']==revision and len(saved['items'])==1 and saved['items'][0]['price']==25.75 and saved['items'][0]['qty']==2,'separate HTTP read confirms actual quantity and fractional canonical price')
  # A new authenticated session must restore the same server cart, without local cache.
  fresh=b.login(state['accounts']['review-customer'])
  code,same=gateway('final2_cart_get',fresh,{})
  check(code==200 and same==saved,'fresh Auth login restores the same account cart')
  code,unrelated=gateway('final2_cart_get',other,{})
  check(code==200 and all(str(i['product_id'])!=str(pid)for i in unrelated['items']),'distinct real customer cannot observe the saved cart')
  code,conflict=gateway('final2_cart_replace',customer,{**request,'p_request_id':str(uuid.uuid4()),'p_items':[]})
  check(code==200 and conflict['code']=='CART_CHANGED'and conflict['items']==saved['items'],'stale device cannot overwrite actual saved state')
  code,_=gateway('final2_cart_replace',customer,{**request,'p_items':[]})
  check(code==409,'same request UUID with altered payload denied over real HTTP')
  code,unavailable=gateway('final2_cart_replace',customer,{'p_revision':revision,'p_request_id':str(uuid.uuid4()),'p_items':[{'product_id':pid,'qty':6}]})
  check(code==200 and unavailable['code']=='UNAVAILABLE'and unavailable['revision']==revision,'insufficient stock cannot partly replace persisted cart')
  for token,label in [(vendor,'vendor'),(admin_token,'Admin')]:
   code,_=gateway('final2_cart_get',token,{})
   check(code==403,label+' cannot enter customer cart APIs')
  code,_=b.api('/rest/v1/rpc/final2_cart_get','POST',{})
  check(code in(401,403),'anonymous direct cart read denied')
  code,_=b.api('/rest/v1/cart_items','POST',{'user_id':state['accounts']['review-customer']['auth_id'],'product_id':str(pid),'name':marker,'price':0,'quantity':1},customer)
  check(code==403,'direct client write cannot bypass validated revision protocol')
 finally:
  code,current=gateway('final2_cart_get',customer,{})
  assert code==200
  code,cleared=gateway('final2_cart_replace',customer,{'p_revision':current['revision'],'p_request_id':str(uuid.uuid4()),'p_items':[]})
  assert code==200 and cleared['code']=='OK'and cleared['items']==[]
  code,value=gateway('vendor_adjust_stock',vendor,{'p_product_id':pid,'p_quantity':-5,'p_mode':'delta','p_reason':'FINAL2 synthetic fixture retirement','p_request_id':str(uuid.uuid4()),'p_threshold':None,'p_expected_version':None})
  assert code==200 and value['code']=='UPDATED'
 check(True,'synthetic saved cart cleared and fixture stock retired through real owner APIs; history preserved')
