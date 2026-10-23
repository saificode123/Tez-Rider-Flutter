"""Deploy only the verified COD-compatible FR32 worker to isolated TEST via API."""
import hashlib,importlib.util,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF
s=importlib.util.spec_from_file_location('guarded_db',Path(__file__).with_name('FINAL-security.py'))
db=importlib.util.module_from_spec(s);s.loader.exec_module(db);db.OUT=OUT
review=json.loads((OUT/'cash-invoices-review-proof.json').read_text())
assert review['rolled_back']and review['passed']==8
assert review['migration_sha256']==hashlib.sha256((ROOT/'supabase/migrations/202610230010_final2_cash_invoices.sql').read_bytes()).hexdigest()
assert re.search(r'30 passed.*0 failed',(OUT/'cash-invoices-deno.log').read_text(encoding='utf-8'))
files=['supabase/functions/fr32-email-worker/index.ts','supabase/functions/fr32-email-worker/handler.ts',
 'supabase/functions/_shared/fr32-invoice.ts','supabase/functions/_shared/fr32-templates.ts']
manifest=[{'file':name,'sha256':hashlib.sha256((ROOT/name).read_bytes()).hexdigest()}for name in files]
result=subprocess.run([db.CLI,'functions','deploy','fr32-email-worker','--project-ref',REF,'--use-api','--no-verify-jwt'],
 cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=180)
(OUT/'cash-worker-deploy.private.log').write_text(result.stdout+result.stderr,encoding='utf-8')
assert result.returncode==0,'TEST worker deployment unconfirmed; protected log retained'
(OUT/'cash-worker-deployment.json').write_text(json.dumps({'project':REF,'function':'fr32-email-worker',
 'deployment':'PASS','deno_passed':30,'files':manifest,'docker_used':False,'production_modified':False},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'project':REF,'function':'fr32-email-worker','deployment':'PASS','provider_send_invoked_by_deployment':False}))
