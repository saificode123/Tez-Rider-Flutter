"""Guarded FR06 review/deployment and authenticated HTTP verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='catalogue'
action=sys.argv[2];assert action in('review','deploy','post','hosted')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
admin=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin)
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610230005';migration=ROOT/'supabase/migrations/202610230005_final2_catalogue.sql'
history=OUT/'catalogue-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
expected=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
assert [r['version']for r in db.query(history)]==([v for v in expected if v!=version]if action in('review','deploy')else expected),'Unexpected history; no replay'
digest=hashlib.sha256(migration.read_bytes()).hexdigest()
checks=[]
def check(ok,label,level='real authenticated TEST HTTP'):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':level});print(json.dumps(checks[-1]),flush=True)
 (OUT/('catalogue-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-catalogue.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'catalogue-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('catalogue-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'catalogue-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate|delete)\b',source,re.I)
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610230005','final2_catalogue');commit;")
 path=OUT/'catalogue-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'catalogue-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))
elif action=='hosted':
 marker='FINAL2 '+uuid.uuid4().hex[:10];ids=[]
 for n in range(3):
  code,value=gateway('fr17_save_product',vendor,{'p_request_id':str(uuid.uuid4()),'p_product_id':None,'p_data':{'name':marker+' '+str(n),'price':25,'category':marker+' Books','description':'literal,*() '+marker},'p_stock':5,'p_threshold':1,'p_expected_version':None})
  assert code==200 and value['code']=='UPDATED';ids.append(value['product_id'])
 check(len(set(ids))==3,'three real synthetic inventory records created through approved vendor API')
 query={'p_query':marker,'p_category':None,'p_after':None,'p_limit':2}
 code,first=gateway('final2_catalog',customer,query)
 check(code==200 and len(first['items'])==2 and first['has_more'],'real customer receives bounded first page')
 code,last=gateway('final2_catalog',customer,{**query,'p_after':first['next_cursor']})
 check(code==200 and len(last['items'])==1 and not last['has_more']and set(ids)=={p['id']for p in first['items']+last['items']},'real keyset follow-up returns exact persisted products without overlap')
 code,rows=gateway('final2_catalog',customer,{**query,'p_query':'literal,*() '+marker,'p_limit':40})
 check(code==200 and len(rows['items'])==3,'real HTTP query treats filter punctuation literally')
 code,rows=gateway('final2_catalog',customer,{**query,'p_query':'','p_category':marker+' Books','p_limit':40})
 check(code==200 and len(rows['items'])==3,'real category-only request finds persisted category')
 code,rows=gateway('final2_catalog_categories',customer,{})
 check(code==200 and any(r['name']==marker+' Books'for r in rows),'real category projection includes actual inventory')
 for params,label in [({**query,'p_limit':101},'oversized page'),({**query,'p_query':'x'*121},'oversized keyword'),({**query,'p_after':{'id':1,'name':'x','extra':True}},'unknown cursor key')]:
  code,_=gateway('final2_catalog',customer,params);check(code==400,'real server denies '+label)
 code,_=b.api('/rest/v1/rpc/final2_catalog','POST',query)
 check(code in(401,403),'anonymous direct catalogue RPC denied')
 # Preserve synthetic history, but stop fixtures being offered for new purchases.
 for pid in ids:
  code,value=gateway('vendor_adjust_stock',vendor,{'p_product_id':pid,'p_quantity':-5,'p_mode':'delta','p_reason':'FINAL2 synthetic fixture retirement','p_request_id':str(uuid.uuid4()),'p_threshold':None,'p_expected_version':None})
  assert code==200 and value['code']=='UPDATED'
 check(True,'synthetic fixtures retired with actual stock ledger, no historical deletion')
