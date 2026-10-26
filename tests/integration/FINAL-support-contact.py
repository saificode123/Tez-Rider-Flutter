"""Hash-bound TEST-only additive public support-contact configuration. No message is sent."""
import hashlib, importlib.util, json, re, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final-delivery/support';OUT.mkdir(parents=True,exist_ok=True)
REF='igeisilhtmglgnqvllrx';VERSION='202610250011';MIGRATION=ROOT/'supabase/migrations/202610250011_final_support_contact.sql'
spec=importlib.util.spec_from_file_location('email_guarded_db',Path(__file__).with_name('FINAL-security.py'))
db=importlib.util.module_from_spec(spec);spec.loader.exec_module(db);db.OUT=OUT
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF
action=sys.argv[1];assert action in('review','deploy','post','hosted','edge-deploy')
def query(name,text):
 path=OUT/(name+'.sql');path.write_text(text,encoding='utf-8');return db.query(path)
history=[r['version']for r in query('history','begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
assert history==known[:len(history)],'Unexpected TEST migration prefix; no replay'
digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
if action=='edge-deploy':
 import subprocess
 assert VERSION in history
 result=subprocess.run([db.CLI,'functions','deploy','support-contact','--project-ref',REF,'--no-verify-jwt','--use-api'],cwd=ROOT,capture_output=True,text=True,timeout=120)
 (OUT/'edge-deploy.private.log').write_text(result.stdout+result.stderr,encoding='utf-8')
 assert result.returncode==0,'TEST support Edge deployment failed; private log retained'
 print(json.dumps({'project':REF,'function':'support-contact','deployed':True,'production_modified':False}))
elif action=='hosted':
 spec=importlib.util.spec_from_file_location('support_backend',Path(__file__).with_name('FR-04-hosted.py'))
 b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b);b.target()
 checks=[]
 def check(ok,label):
  assert ok,label
  checks.append({'check':label,'result':'PASS','surface':'actual TEST HTTP'})
 code,value=b.api('/functions/v1/support-contact','GET')
 check(code==200 and value=={'code':'OK','email':'urrehmansaif406@gmail.com'},'signed-out caller reads only the configured public support email')
 code,value=b.api('/functions/v1/support-contact','GET',token='not-a-live-session')
 check(code==200 and value.get('code')=='OK','public contact remains available with an invalid or expired session')
 code,value=b.api('/functions/v1/support-contact','POST',{})
 check(code in(401,405),'public support contact cannot be used to write settings')
 code,value=b.api('/functions/v1/support-contact?setting=groq_api_key','GET')
 check(code==400 and 'email'not in value,'caller-selected private settings are rejected without disclosure')
 code,value=b.api('/rest/v1/app_settings?setting_key=eq.support_email&select=setting_value','GET')
 check(code in(401,403),'contact does not grant raw settings table access')
 result={'project':REF,'passed':len(checks),'checks':checks,'message_sent':False,'production_modified':False}
 (ROOT/'docs/evidence/FINAL-support-hosted.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'project':REF,'passed':len(checks),'message_sent':False}))
elif action in('review','post'):
 assert(VERSION in history)==(action=='post')
 source=(ROOT/'supabase/tests/FINAL-support-contact.sql').read_text()
 if action=='review':source=source.replace('-- SUPPORT_CANDIDATE',re.sub(r'(?m)^(begin|commit);\s*$','',MIGRATION.read_text()))
 rows=query('support-'+action,source)[0]['results'];assert rows and all(r['result']=='PASS'for r in rows)
 result={'project':REF,'action':action,'migration_sha256':digest,'rolled_back':True,'passed':len(rows),'checks':rows,'actual_email_sent':False,'actual_external_confirmation':False}
 (OUT/(action+'-proof.json')).write_text(json.dumps(result,indent=2)+'\n')
 (ROOT/('docs/evidence/FINAL-support-'+action+'.json')).write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'project':REF,'mode':action,'passed':len(rows),'rolled_back':True,'actual_email_sent':False}))
else:
 assert VERSION not in history and history==[v for v in known if v<VERSION],'Apply exact reviewed predecessors first; no replay'
 proof=json.loads((OUT/'review-proof.json').read_text());assert proof['rolled_back']and proof['migration_sha256']==digest and proof['passed']>=5
 source=MIGRATION.read_text();assert source.count('\ncommit;')==1
 assert not re.search(r'\b(drop|truncate)\b|disable\s+row',source,re.I)
 source=source.replace('\ncommit;',"\ninsert into supabase_migrations.schema_migrations(version,name)values('202610250011','final_support_contact');\ncommit;")
 query('support-deploy',source)
 actual=[r['version']for r in query('history-post','begin read only;select version from supabase_migrations.schema_migrations order by version;rollback;')]
 assert actual==history+[VERSION]
 result={'project':REF,'version':VERSION,'migration_sha256':digest,'versions':len(actual),'replayed':False,'production_modified':False,'message_sent':False}
 (ROOT/'docs/evidence/FINAL-support-deployment.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))
