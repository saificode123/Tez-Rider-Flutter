"""Hash-bound TEST-only additive verified-email migration. No email is sent."""
import hashlib, importlib.util, json, re, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final-delivery/email';OUT.mkdir(parents=True,exist_ok=True)
REF='igeisilhtmglgnqvllrx';VERSION='202610250010';MIGRATION=ROOT/'supabase/migrations/202610250010_final_profile_email.sql'
spec=importlib.util.spec_from_file_location('email_guarded_db',Path(__file__).with_name('FINAL-security.py'))
db=importlib.util.module_from_spec(spec);spec.loader.exec_module(db);db.OUT=OUT
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF
action=sys.argv[1];assert action in('review','deploy','post','hosted')
def query(name,text):
 path=OUT/(name+'.sql');path.write_text(text,encoding='utf-8');return db.query(path)
history=[r['version']for r in query('history','begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
assert history==known[:len(history)],'Unexpected TEST migration prefix; no replay'
digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
if action=='hosted':
 assert VERSION in history
 spec=importlib.util.spec_from_file_location('email_test_backend',Path(__file__).with_name('FR-04-hosted.py'))
 b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b);b.target()
 legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
 checks=[]
 for role in('customer','vendor','rider','admin'):
  token=b.login(legacy[role]);account=legacy[role]['auth_id']
  code,value=b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/final_delivery_email_status','query':'','headers':{'content-type':'application/json'},'body':'{}'},token)
  assert code==200 and value['code']=='OK'and value['account']==account and value['verified']is True and isinstance(value['email'],str)
  checks.append({'check':role+' own confirmed email status is account-bound and canonical; no email-change request sent','result':'PASS','surface':'actual authenticated TEST HTTP read'})
 code,_=b.api('/rest/v1/rpc/final_delivery_email_status','POST',{})
 assert code in(401,403)
 checks.append({'check':'anonymous cannot read any profile email state','result':'PASS','surface':'actual TEST HTTP denial'})
 result={'project':REF,'action':action,'passed':len(checks),'checks':checks,'email_change_request_sent':False,'actual_external_confirmation':False,'business_mutations':False}
 (ROOT/'docs/evidence/FINAL-profile-email-hosted.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'project':REF,'mode':'hosted','passed':len(checks),'email_change_request_sent':False}))
elif action in('review','post'):
 assert(VERSION in history)==(action=='post')
 source=(ROOT/'supabase/tests/FINAL-profile-email.sql').read_text()
 if action=='review':source=source.replace('-- FINAL_EMAIL_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',MIGRATION.read_text()))
 rows=query('email-'+action,source)[0]['results'];assert rows and all(r['result']=='PASS'for r in rows)
 result={'project':REF,'action':action,'migration_sha256':digest,'rolled_back':True,'passed':len(rows),'checks':rows,'actual_email_sent':False,'actual_external_confirmation':False}
 (OUT/(action+'-proof.json')).write_text(json.dumps(result,indent=2)+'\n')
 (ROOT/('docs/evidence/FINAL-profile-email-'+action+'.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'project':REF,'mode':action,'passed':len(rows),'rolled_back':True,'actual_email_sent':False}))
else:
 assert VERSION not in history and history==[v for v in known if v<VERSION],'Apply exact reviewed predecessors first; no replay'
 proof=json.loads((OUT/'review-proof.json').read_text());assert proof['rolled_back']and proof['migration_sha256']==digest and proof['passed']>=20
 source=MIGRATION.read_text();assert source.count('\ncommit;')==1
 assert not re.search(r'\b(drop|truncate)\b|disable\s+row',source,re.I)
 source=source.replace('\ncommit;',"\ninsert into supabase_migrations.schema_migrations(version,name)values('202610250010','final_profile_email');\ncommit;")
 query('email-deploy',source)
 actual=[r['version']for r in query('history-post','begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
 assert actual==history+[VERSION]
 result={'project':REF,'version':VERSION,'migration_sha256':digest,'versions':len(actual),'replayed':False,'production_modified':False,'auth_email_request_sent':False}
 (ROOT/'docs/evidence/FINAL-profile-email-deployment.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))
