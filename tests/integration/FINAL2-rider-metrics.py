"""Guarded owned history review/deployment and authenticated security verification on TEST only."""
import base64,hashlib,importlib.util,json,re,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('fixture_backend','FR-04-hosted.py');db=module('guarded_db','FINAL-security.py');db.OUT=OUT
b.target();assert b.REF==REF and sys.argv[1]=='rider-metrics'
action=sys.argv[2];assert action in('review','deploy','post','hosted')
state=json.loads(b.crypt((OUT/'onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts'];admin=legacy['admin']
vendor=b.login(state['accounts']['live-vendor']);customer=b.login(state['accounts']['review-customer']);admin_token=b.login(admin);other=b.login(legacy['customer']);other_vendor=b.login(legacy['vendor']);rider=b.login(legacy['rider'])
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
version='202610240004';migration=ROOT/'supabase/migrations/202610240004_final2_rider_metrics.sql'
history=OUT/'rider-metrics-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
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
 (OUT/('rider-metrics-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-order-detail.sql').read_text(encoding='utf-8-sig')
 extension=(ROOT/'supabase/tests/FINAL2-rider-metrics.sql').read_text(encoding='utf-8-sig')
 source=source.replace("select jsonb_agg(jsonb_build_object('check',label",extension+"\nselect jsonb_agg(jsonb_build_object('check',label",1)
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 for key,token in [('VENDOR',vendor),('CUSTOMER',customer),('ADMIN',admin_token),('OTHER',other),('OTHER_VENDOR',other_vendor),('RIDER',rider)]:source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'rider-metrics-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('rider-metrics-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='deploy':
 review=json.loads((OUT/'rider-metrics-review-proof.json').read_text());assert review['rolled_back']and review['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)
 assert not re.search(r'(?im)^\s*delete from',source),'Ledger migration must preserve history'
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610240004','final2_rider_metrics');commit;")
 path=OUT/'rider-metrics-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 (OUT/'rider-metrics-deployment.json').write_text(json.dumps({'project':REF,'version':version,'versions':len(expected),'review_passes':review['passed'],'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'confirmed','project':REF,'versions':len(expected)}))

elif action=='hosted':
 code,value=gateway('final2_rider_performance',rider,{})
 check(code==200 and value.get('code')=='OK' and value['rider_id']==int(legacy['rider']['profile_id']),'approved authenticated Rider reads own actually stored performance')
 rid=value['rider_id']
 check(value['earned_fee_cents']is None and value['fee_status']=='POLICY_REQUIRED','unknown compensation is not fabricated from order amounts')
 check(value['timed_deliveries']<=value['completed_deliveries']<=value['accepted_assignments'],'stored metrics reconcile count bounds without invented legacy timing')
 code,admin_value=gateway('final2_rider_performance',admin_token,{'p_rider_id':rid})
 check(code==200 and admin_value['rider_id']==rid and admin_value['accepted_assignments']==value['accepted_assignments'],'actual Admin selected-Rider read agrees with own-role stored counters')
 for token,label in [(customer,'Customer'),(other_vendor,'Vendor')]:
  code,_=gateway('final2_rider_performance',token,{'p_rider_id':rid});check(code==403,label+' cannot inspect private Rider performance')
 code,_=gateway('final2_rider_performance',rider,{'p_rider_id':int(legacy['customer']['profile_id'])});check(code==403,'Rider cannot select a foreign canonical identity')
 code,_=gateway('final2_rider_performance',None,{});check(code in(401,403),'anonymous metrics denied at actual hosted gateway')
