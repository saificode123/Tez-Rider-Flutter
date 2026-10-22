"""Deploy only the reviewed compatible TEST entrypoints through the API (no Docker)."""
import importlib.util,json,subprocess
from pathlib import Path
spec=importlib.util.spec_from_file_location('db',Path(__file__).with_name('FINAL01-db.py'));db=importlib.util.module_from_spec(spec);spec.loader.exec_module(db)
names=['security-gateway','admin-user-status','fr04-cnic','fr13-location','fr25-evidence','fr30-dispatch-push','fr32-email-worker','fr32-invoice-url','get-delivery-route','send-delivery-otp','shopping-assistant']
assert db.versions()[-1]=='202610220003','Additive prerequisites must be deployed first'
checks=json.loads((db.OUT/'prerequisite-http.json').read_text());assert len(checks)==25 and all(c['result']=='PASS'for c in checks)
results=[]
for name in names:
 result=subprocess.run([db.d.CLI,'functions','deploy',name,'--project-ref',db.REF,'--use-api','--no-verify-jwt'],cwd=db.ROOT,capture_output=True,text=True,encoding='utf-8',timeout=180)
 (db.OUT/('deploy-'+name+'.private.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
 assert result.returncode==0,'TEST function deployment failed: '+name
 results.append({'function':name,'deployment':'PASS','project':db.REF})
 (db.OUT/'compatible-edge-deployment.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 print(json.dumps(results[-1]),flush=True)
