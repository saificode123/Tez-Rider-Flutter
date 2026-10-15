"""TEST-only push migration review and rollback security checks; no provider calls."""
from pathlib import Path
import importlib.util,json,re,sys
spec=importlib.util.spec_from_file_location('fr30',Path(__file__).with_name('FR-30-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
migration=b.ROOT/'supabase/migrations/202610150006_fr30_android_push.sql'
if sys.argv[1]=='enable':
 b.b.target()
 state=json.loads(b.b.crypt((b.b.PRIVATE/'fr30-push-state.bin').read_bytes(),True))
 assert state['project']=='tez-rider-fe12b','Verified Firebase TEST project required'
 status,result=b.b.api('/functions/v1/fr30-dispatch-push','POST',{},token=b.b.login(b.state['accounts']['admin']))
 assert status==200 and result['code']=='PROCESSED','Configured sender readiness required'
 enabled=b.query(b.write('push-enable.sql',"update fr30_private.limits set android_push_enabled=true where singleton returning android_push_enabled;"))['rows'][0]['android_push_enabled']
 assert enabled
 print(json.dumps({'test_dispatch_enabled':True,'firebase_project_verified':True,'migration_replayed':False}))
 sys.exit(0)
if sys.argv[1]=='deploy':
 b.deploy(push=True)
 sys.exit(0)
if sys.argv[1]in('edge','ready'):
 checks=[]
 for label,expected in [('anonymous',403),('customer',403),('admin',200 if sys.argv[1]=='ready'else 503)]:
  token=None if label=='anonymous'else b.b.login(b.state['accounts'][label])
  status,result=b.b.api('/functions/v1/fr30-dispatch-push','POST',{},token=token)
  assert status==expected,label+' worker boundary'
  if label=='admin'and expected==200:assert result['code']=='PROCESSED'and result['claimed']==0 and result['device_receipt_confirmed']is False,'Configured sender readiness'
  assert not any(k in result for k in('token','secret','private_key','title','message')),'No confidential worker response'
  checks.append({'check':label+' worker boundary','status':status,'result':'PASS'})
 disabled=b.query(b.write('push-disabled.sql',"select not android_push_enabled as disabled,(select count(*)from fr30_private.push_devices)as devices,(select count(*)from fr30_private.push_deliveries)as jobs from fr30_private.limits where singleton;"))['rows'][0]
 assert disabled['disabled']and disabled['devices']==0 and disabled['jobs']==0,'Unconfigured dispatch stays disabled'
 (b.OUT/('push-ready-results.json'if sys.argv[1]=='ready'else'push-edge-results.json')).write_text(json.dumps({'checks':checks,'disabled':disabled},indent=2),encoding='utf-8')
 print(json.dumps({'passed':len(checks)+1,'native_delivery_tested':False,'dispatch_disabled':True}))
 sys.exit(0)
prefix=(b.ROOT/'supabase/tests/FR-30.sql').read_text(encoding='utf-8').split('do $$declare who text;res jsonb;begin')[0]
rules=prefix+(b.ROOT/'supabase/tests/FR-30-push.sql').read_text(encoding='utf-8')
if sys.argv[1]=='review':
 source=migration.read_text(encoding='utf-8')
 source=re.sub(r'^begin;\s*|^commit;\s*','',source,flags=re.M)
 rules=rules.replace('begin;','begin;\n'+source,1)
result=b.query(b.write('push-review.sql',rules))
checks=result['rows'][0]['results']
(b.OUT/'push-sql-results.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
print(json.dumps({'passed':len(checks),'rolled_back':True,'provider_calls':0}))
