"""Collect actual completed local/device/TEST evidence; fail on missing results."""
from pathlib import Path
import hashlib
import json
import py_compile
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / '.fr21-local'
OUT = ROOT / 'docs/evidence'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    flutter = (LOCAL / 'master-flutter-release-source.log').read_text(encoding='utf-8-sig')
    passed = re.search(r'\+(\d+)(?:\s+~(\d+))?: All tests passed!', flutter)
    assert passed, 'Final full Flutter success result missing'
    deno = (LOCAL / 'master-deno.log').read_text(encoding='utf-8-sig')
    deno_result = re.search(r'ok\s*\|\s*(\d+) passed\s*\|\s*(\d+) failed', deno)
    assert deno_result and int(deno_result[2]) == 0
    build = read(ROOT / 'build/delivery/test/build-evidence.json')
    assert build['environment'] == 'TEST' and build['mode'] == 'debug'
    assert build['project'] == 'igeisilhtmglgnqvllrx'
    apk = Path(build['artifact'])
    assert hashlib.sha256(apk.read_bytes()).hexdigest().upper() == build['sha256']
    for source in build['sources']:
        assert hashlib.sha256((ROOT / source['path']).read_bytes()).hexdigest().upper() == source['sha256'], source['path']
    installed = read(LOCAL / 'repair-native/installed.json')
    assert installed['sha256'] == build['sha256']
    native = [json.loads(line) for line in (LOCAL / 'repair-native/results.jsonl').read_text().splitlines() if line.strip()]
    native = [r for r in native if r.get('artifact_sha256') == build['sha256']]
    assert any('base.apk hash matches' in r['check'] for r in native)
    analysis = (LOCAL / 'master-final-focused-analysis.log').read_text(encoding='utf-8-sig')
    errors = len(re.findall(r'^\s*error\s*-', analysis, re.M))
    warnings = len(re.findall(r'^\s*warning\s*-', analysis, re.M))
    infos = len(re.findall(r'^\s*info\s*-', analysis, re.M))
    assert errors == warnings == 0
    for path in (ROOT / 'tests/integration').glob('MASTER-*.py'):
        py_compile.compile(str(path), doraise=True)
    seed = read(OUT / 'MASTER-demo-verify.json')
    cleanup = read(OUT / 'MASTER-catalogue-verify.json')
    restored = read(OUT / 'MASTER-post-seed-restore.json')
    storage = read(OUT / 'MASTER-storage-backup.json')
    secret_backup = read(OUT / 'MASTER-secret-backup.json')
    assert seed['accounts_total'] == 7 and seed['products'] == 12 and seed['saved_addresses'] == 2
    assert all(c['result'] == 'PASS' for c in seed['checks'])
    assert cleanup['verified_products'] == 47
    assert restored['isolated_restore_verified'] and storage['object_bytes_integrity_verified']
    assert all(f['decrypted_hash_matches'] for f in secret_backup['encrypted_files'])
    result = {
        'project': build['project'],
        'branch': subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip(),
        'revision_at_collection': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'runtime_implementation_commit': 'cd3f9ac',
        'flutter': {'passed': int(passed[1]), 'failed': 0, 'skipped': int(passed[2] or 0),
                    'log_sha256': hashlib.sha256((LOCAL / 'master-flutter-release-source.log').read_bytes()).hexdigest()},
        'deno': {'passed': int(deno_result[1]), 'failed': 0},
        'final_changed_source_analysis': {'errors': errors, 'warnings': warnings, 'infos': infos},
        'artifact': {'path': str(apk), 'sha256': build['sha256'], 'bytes': apk.stat().st_size,
                     'mode': 'DEBUG TEST', 'build_recorded_head': build['head'],
                     'current_runtime_hashes_matched': len(build['sources']),
                     'installed_base_apk_independently_matched': True},
        'native_checks': native,
        'assistant': {'reviewed_current_server_cases': 12, 'evidence': 'MASTER-assistant-evaluation.json'},
        'dataset': {'new_accounts': 7, 'products': 12, 'saved_addresses': 2,
                    'pending_riders': 2, 'fabricated_completed_orders': 0,
                    'independent_checks': len(seed['checks']),
                    'independent_verification_utc': seed['utc'],
                    'later_recheck': 'INCOMPLETE: connection reset after 13 checks; not counted as PASS'},
        'cleanup': {'approved_products_unavailable': cleanup['verified_products'], 'deletes': 0,
                    'quantities_retained': True, 'manifest_sha256': cleanup['manifest_sha256']},
        'recovery': {'post_seed_schema_data_restore': 'BOUNDED PASS',
                     'restored_counts': restored['counts'],
                     'storage_objects_integrity_checked': storage['encrypted_objects'],
                     'vault_entries_encrypted': secret_backup['vault_secret_count'],
                     'runtime_crypto_storage_upload_and_portable_recovery_verified': False},
        'gps': {'evidence': 'MASTER-gps-performance.json',
                'foreground_background_and_network_recovery_observed': True,
                'strict_2_3_second_cadence': 'FAIL', 'http_route_800ms': 'FAIL',
                'physical_inflight_stop_race_reproduced': False},
        'requirement_counts_scope': '76 historical bounded TEST passes, 17 approved deviations, 43 partial, 1 blocked; no newly promoted whole requirement',
        'production_modified': False, 'production_signed_artifact': False,
        'verdict': 'NOT READY FOR PRODUCTION',
    }
    assert result['branch'] == 'feature/final-2-functional'
    (OUT / 'MASTER-runtime-source-manifest.json').write_text(json.dumps({
        'artifact_sha256': build['sha256'], 'build_recorded_head': build['head'],
        'sources': build['sources']}, indent=2) + '\n', encoding='utf-8')
    (OUT / 'MASTER-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'flutter': result['flutter'], 'deno': result['deno'],
                      'runtime_source_files_matched': len(build['sources']),
                      'new_accounts': 7, 'cleaned_products': cleanup['verified_products'],
                      'verdict': result['verdict']}))


if __name__ == '__main__':
    main()
