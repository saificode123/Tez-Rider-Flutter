"""Read-only safety/readiness evidence for explicitly authorized TEST activation."""
import hashlib,importlib.util,json,re,subprocess
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FINAL01-db.py'));db=importlib.util.module_from_spec(spec);spec.loader.exec_module(db)
ROOT=db.ROOT;OUT=db.OUT
assert db.versions()[-1]=='202610220003'and len(db.versions())==41
inspection=OUT/'activation-preflight.sql'
inspection.write_text("begin read only;select jsonb_build_object('functions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'signature',pg_get_function_identity_arguments(p.oid),'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.prokind='f'and(n.nspname='public'or n.nspname like '%private')),'tables',(select jsonb_agg(jsonb_build_object('rls',c.relrowsecurity))from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p')and(n.nspname='public'or n.nspname like '%private'or(n.nspname='storage'and c.relname in('objects','buckets'))or(n.nspname='realtime'and c.relname='messages'))))as inspection;rollback;",encoding='utf-8')
catalog=db.d.query(inspection)[0]['inspection']
before=json.loads((ROOT/'.fr21-local/final1/catalog.json').read_text())
key=lambda f:(f['schema'],f['name'],f['signature'])
old={key(f):f for f in before['functions']};new={key(f):f for f in catalog['functions']}
assert old.keys()<=new.keys()and all(old[k]['definition']==new[k]['definition']and old[k]['acl']==new[k]['acl']for k in old),'Retained body/grant drift requires review'
assert all(t['rls']for t in catalog['tables'])
gate=new[('public','fr28_pre_request','')]['definition'];assert 'APPLICATION_GATEWAY_REQUIRED'not in gate
# Forward-recovery source only; never execute automatically or relax RLS.
(OUT/'previous-pre-request.private.sql').write_text('begin;\n'+gate+";\nnotify pgrst,'reload schema';\ncommit;\n",encoding='utf-8')
build=json.loads((OUT/'build-evidence.json').read_text(encoding='utf-8-sig'))
assert build['project']==db.REF and all(hashlib.sha256((ROOT/x['path']).read_bytes()).hexdigest().upper()==x['sha256']for x in build['sources'])
adb='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe';serial='AESWNRBAEUPNTGJZ';package='com.example.flutter_application_1.fr21test'
remote=subprocess.check_output([adb,'-s',serial,'shell','pm','path',package],text=True).strip()
assert remote.startswith('package:/data/app/')and package in remote and remote.endswith('/base.apk')and '\n'not in remote
digest=subprocess.check_output([adb,'-s',serial,'shell','sha256sum',remote[len('package:'):]],text=True).split()[0].upper()
assert digest==build['sha256'],'Installed APK must match current-source build exactly'
assert '+18: All tests passed!'in(OUT/'stage0-render-serial.log').read_text(encoding='utf-8-sig')
hosted=json.loads((OUT/'hosted-compatible.json').read_text());assert len(hosted)==108 and all(c['result']=='PASS'for c in hosted)
rows=[{'schema':k[0],'function':k[1],'signature':k[2],'body_sha256':hashlib.sha256(new[k]['definition'].encode()).hexdigest(),'grants_unchanged':True,'definition_unchanged':True,'basis':'actual pre-activation catalog vs retained170-function checkpoint; not independent new functional proof'}for k in sorted(old)]
(ROOT/'docs/evidence/FINAL02-retained-functions.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
ready={'hosted_compatible':True,'client_ready':True,'direct_surfaces_reviewed':True,'project':db.REF,'authorization':'Latest FINAL STAGE0/1 COMPLETION attachment: if safe activate TEST once; physical work continues independently','client_evidence':'current source hashes, built APK hash equals installed TEST base.apk SHA256, affected18checks pass','retained_body_grant_matches':len(rows),'recovery':'Private previous pre-request forward source saved; keep new RLS/deadline/audit, never reset/replay','physical_full_acceptance':False}
(OUT/'activation-readiness.json').write_text(json.dumps(ready,indent=2),encoding='utf-8')
print(json.dumps({'TEST':db.REF,'retained_body_grant_matches':len(rows),'current_source_APK_installed':True,'versions':41,'preflight':'PASS','physical_full_acceptance':False}))
