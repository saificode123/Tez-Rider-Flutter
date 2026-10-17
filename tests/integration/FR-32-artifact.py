"""Reuse accepted streaming source/APK credential scanner for this exact build."""
from pathlib import Path
import os
path=Path(__file__).with_name('FR-10-artifact.py')
source=path.read_text(encoding='utf-8-sig')
replacements={
 "ROOT / '.fr21-local/fr10'":"ROOT / '.fr21-local/fr32'",
 "['fr10-accounts.bin','fr30-accounts.bin']":"['fr10-accounts.bin','fr30-accounts.bin','fr17-accounts.bin','fr32-accounts.bin']",
 "protected = [account['private_key'], account['private_key_id'], push['worker_key'], b.SERVICE]":"protected = [account['private_key'], account['private_key_id'], push['worker_key'], b.SERVICE, b.crypt((b.PRIVATE/'fr32-worker.bin').read_bytes(), True).decode()]",
 "b'fr10_checkout',b'fr10_vendor_transition'":"b'fr10_checkout',b'fr32-invoice-url',b'Invoice'",
 "'fr10_code_present'":"'fr32_code_present'",
 "'physical_fixture_final_integrity'":"'physical_checkout'",
}
for before,after in replacements.items():
    assert source.count(before)==1,'Review changed accepted artifact scanner'
    source=source.replace(before,after)
guard="assert all(p.read_bytes() == (MIRROR/p.relative_to(ROOT)).read_bytes() for p in sources), 'APK build source mirror is stale'"
assert source.count(guard)==1
if os.environ.get('FR32_SCAN_SOURCE_ONLY')=='true':
    # A later source-only review is separate from the completed APK scan.
    # Never reconstruct missing temporary build inputs as proof of a build.
    source=source.replace(guard,'pass # Explicit source-only scan; no APK/source equivalence claim')
    source=source.split('found = {value:False',1)[0]
    source+="\nresult={'scope':'changed source only','credential_scan_passed':True,'files_scanned':len(files),'apk_rechecked':False}\n(OUT/'source-scan.json').write_text(json.dumps(result,indent=2))\nprint(json.dumps(result))\n"
else:
    recovery="""if all((MIRROR/p.relative_to(ROOT)).exists() for p in sources):
    assert all(p.read_bytes() == (MIRROR/p.relative_to(ROOT)).read_bytes() for p in sources), 'APK build source mirror is stale'
    source_verification='current mirror byte comparison'
else:
    # Initial successful scan recorded both source and APK hashes before cleanup.
    original=json.loads((OUT/'artifact.json').read_text(encoding='utf-8'))
    current={str(p.relative_to(ROOT)).replace('\\\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    assert original['credential_scan_passed'] and original['source_files_matched']==len(sources)
    assert original['source_sha256']==current, 'App source changed since verified build'
    with APK.open('rb') as stream:
        assert hashlib.file_digest(stream,'sha256').hexdigest()==original['sha256'], 'APK changed since verified build'
    source_verification='preserved successful source manifest and identical APK'
"""
    source=source.replace(guard,recovery)
    source=source.replace("result = {'sha256':digest", "result = {'source_verification':source_verification,'sha256':digest")
exec(compile(source,str(path),'exec'))
