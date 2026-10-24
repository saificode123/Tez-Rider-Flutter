"""Deploy only the verified validated product-image endpoint to isolated TEST via API."""
import hashlib,importlib.util,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final2';REF='igeisilhtmglgnqvllrx'
assert(ROOT/'supabase/.temp/project-ref').read_text().strip()==REF
s=importlib.util.spec_from_file_location('guarded_db',Path(__file__).with_name('FINAL-security.py'))
db=importlib.util.module_from_spec(s);s.loader.exec_module(db);db.OUT=OUT
review=json.loads((OUT/'product-images-review-proof.json').read_text())
assert review['rolled_back']and review['passed']==15
assert review['migration_sha256']==hashlib.sha256((ROOT/'supabase/migrations/202610240003_final2_product_images.sql').read_bytes()).hexdigest()
assert re.search(r'16 passed.*0 failed',(OUT/'product-images-lifetime-deno.log').read_text(encoding='utf-8'))
files=['supabase/functions/final2-product-image/index.ts','supabase/functions/_shared/validated-image.ts','supabase/functions/_shared/security-runtime.ts','supabase/functions/_shared/fr28-access.ts']
manifest=[{'file':name,'sha256':hashlib.sha256((ROOT/name).read_bytes()).hexdigest()}for name in files]
result=subprocess.run([db.CLI,'functions','deploy','final2-product-image','--project-ref',REF,'--use-api','--no-verify-jwt'],
 cwd=ROOT,capture_output=True,text=True,encoding='utf-8',timeout=180)
(OUT/'product-image-edge-deploy.private.log').write_text(result.stdout+result.stderr,encoding='utf-8')
assert result.returncode==0,'TEST worker deployment unconfirmed; protected log retained'
(OUT/'product-image-edge-deployment.json').write_text(json.dumps({'project':REF,'function':'final2-product-image',
 'deployment':'PASS','deno_passed':16,'files':manifest,'docker_used':False,'production_modified':False},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'project':REF,'function':'final2-product-image','deployment':'PASS','provider_send_invoked_by_deployment':False}))
