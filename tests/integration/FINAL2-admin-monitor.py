"""Exact-history, hash-reviewed TEST Admin monitoring acceptance; no Docker."""
import hashlib,importlib.util,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
db=module('guarded_db','FINAL-security.py');db.OUT=OUT
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF and sys.argv[1]=='admin-monitor'
action=sys.argv[2];assert action in('review','deploy','post','hosted','fixture-status','prepare-native','verify-native','verify-native-cancel','cleanup','realtime')
version='202610240005';migration=ROOT/'supabase/migrations/202610240005_final2_admin_monitor.sql'
digest=hashlib.sha256(migration.read_bytes()).hexdigest()
history=OUT/'admin-monitor-history.sql';history.write_text('begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;',encoding='utf-8')
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
expected=[v for v in known if v<=version];actual=[r['version']for r in db.query(history)]
assert(actual in([v for v in expected if v!=version],expected)if action=='fixture-status'else actual==([v for v in expected if v!=version]if action in('review','deploy')else expected)),'Unexpected TEST history; never replay'
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-admin-monitor.sql').read_text(encoding='utf-8-sig')
 if action=='review':source=source.replace('-- FINAL2_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8-sig')))
 assert source.rstrip().endswith('rollback;')
 path=OUT/'admin-monitor-check.private.sql';path.write_text(source,encoding='utf-8')
 checks=db.query(path)[0]['results'];assert checks and all(r['result']=='PASS'for r in checks)
 (OUT/('admin-monitor-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
 proof={'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True}
 (OUT/('admin-monitor-'+action+'-proof.json')).write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(proof))
elif action=='deploy':
 proof=json.loads((OUT/'admin-monitor-review-proof.json').read_text());assert proof['passed']>=33 and proof['rolled_back'] and proof['migration_sha256']==digest
 source=migration.read_text(encoding='utf-8-sig');assert source.count('commit;')==1 and not re.search(r'\b(drop|truncate)\b',source,re.I)and not re.search(r'(?im)^\s*delete from',source)
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('202610240005','final2_admin_monitor');commit;")
 path=OUT/'admin-monitor-deploy.private.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==expected
 proof={'project':REF,'version':version,'versions':len(expected),'migration_sha256':digest,'review_passes':proof['passed'],'replayed':False,'production_modified':False}
 (OUT/'admin-monitor-deployment.json').write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8');print(json.dumps(proof))
elif action in('hosted','prepare-native','verify-native','verify-native-cancel','cleanup','realtime'):
 import runpy
 runpy.run_path(str(Path(__file__).with_name('FINAL2-admin-monitor-live.py')),init_globals={'b':module('fixture_backend','FR-04-hosted.py'),'db':db,'OUT':OUT,'ROOT':ROOT,'REF':REF,'action':action})
elif action=='fixture-status':
 b=module('fixture_backend','FR-04-hosted.py');b.target()
 stored=json.loads(b.crypt((b.PRIVATE/'fr20-accounts.bin').read_bytes(),True))
 checks=[]
 for label in ['vendor','customer','rider','rider2']:
  a=stored['accounts'][label];uid=int(a['profile_id'])
  code,users=b.api('/rest/v1/users?id=eq.'+str(uid)+'&select=id,role,verification_status,is_blocked,auth_user_id,name',admin=True)
  assert code==200 and len(users)==1 and users[0]['name']=='FR20 synthetic '+label,'Exact synthetic fixture identity required'
  row={'label':label,'approved':users[0]['verification_status']=='approved','blocked':users[0]['is_blocked'],'auth_linked':users[0]['auth_user_id']==a['auth_id']}
  if label.startswith('rider'):
   code,busy=b.api('/rest/v1/orders?rider_id=eq.'+str(uid)+'&order_status=not.in.(delivered,cancelled)&select=id',admin=True);assert code==200
   code,pending=b.api('/rest/v1/rider_assignments?riderid=eq.'+str(uid)+'&status=in.(Pending,Accepted)&select=id',admin=True);assert code==200
   row.update(active_orders=len(busy),active_assignments=len(pending))
   code,presence=b.api('/rest/v1/riders?userid=eq.'+str(uid)+'&select=is_online,is_available,isavailable',admin=True);assert code==200 and len(presence)==1
   row.update(presence[0])
  if label=='vendor':
   code,shops=b.api('/rest/v1/vendors?user_id=eq.'+str(uid)+'&select=is_active,latitude,longitude',admin=True);assert code==200 and len(shops)==1
   row.update(store_active=shops[0]['is_active'],isolated_synthetic_pickup=shops[0]['latitude']==-60 and shops[0]['longitude']==-140)
  checks.append(row)
 print(json.dumps({'project':REF,'fixture_flags':checks,'service_reads_are_not_authorization_acceptance':True}))
