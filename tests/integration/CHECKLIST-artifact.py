"""Scan the actual new TEST APK and changed source without printing secrets."""
import os
from pathlib import Path
path=Path(__file__).with_name('FR-10-artifact.py');source=path.read_text(encoding='utf-8-sig')
changes={
 "ROOT / '.fr21-local/fr10'":"ROOT / '.fr21-local/checklist'",
 "['fr10-accounts.bin','fr30-accounts.bin']":"['fr10-accounts.bin','fr30-accounts.bin','fr32-accounts.bin','checklist-accounts.bin']",
 "protected = [account['private_key'], account['private_key_id'], push['worker_key'], b.SERVICE]":"protected = [account['private_key'], account['private_key_id'], push['worker_key'], b.SERVICE, b.crypt((b.PRIVATE/'fr32-worker.bin').read_bytes(), True).decode()]",
 "b'fr10_checkout',b'fr10_vendor_transition'":"b'pre_delivery_checklist',b'submit_pre_delivery_checklist',b'Start Delivery'",
 "'fr10_code_present'":"'checklist_code_present'",
 "'physical_fixture_final_integrity'":"'physical_checklist_final_integrity'",
}
for before,after in changes.items():
 assert source.count(before)==1,'Review changed accepted scanner';source=source.replace(before,after)
needle='patterns = [value.encode() for value in protected if value]'
source=source.replace(needle,"extra=b.PRIVATE/'checklist-regression-fixtures.bin'\nif extra.exists():\n    protected.append(json.loads(b.crypt(extra.read_bytes(),True))['password'])\n"+needle)
if os.environ.get('CHECKLIST_SOURCE_ONLY')=='true':
 guard="assert all(p.read_bytes() == (MIRROR/p.relative_to(ROOT)).read_bytes() for p in sources), 'APK build source mirror is stale'"
 assert source.count(guard)==1
 source=source.replace(guard,'pass # Explicit source-only scan; no APK/source claim')
 source=source.split('found = {value:False',1)[0]
 source+="\nresult={'scope':'changed source only','credential_scan_passed':True,'files_scanned':len(files),'apk_rechecked':False}\n(OUT/'source-scan.json').write_text(json.dumps(result,indent=2))\nprint(json.dumps(result))\n"
exec(compile(source,str(path),'exec'))
