"""Guarded FR16 product delete review/deployment and authenticated HTTP verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='product-delete'
action=sys.argv[2];assert action in('review','deploy','post')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer']);other_vendor=b.login(legacy['vendor'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610230007';migration=ROOT/'supabase/migrations/202610230007_final2_product_delete.sql'
history=OUT/'product-delete-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
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
 (OUT/('product-delete-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-product-delete.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other),('OTHER_VENDOR',other_vendor)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'product-delete-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('product-delete-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'product-delete-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert source.count('delete from public.products where id=p.id and vendor_id=actor;')==1 and len(re.findall(r'\bdelete from\b',source,re.I))==1
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610230007','final2_product_delete');commit;")
 path=OUT/'product-delete-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'product-delete-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))
