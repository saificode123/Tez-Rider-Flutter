"""Collect this acceptance continuation without relabelling historical passes."""
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/evidence'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    logs = {}
    for label, filename, pattern in (
        ('reproduction', 'accept-checkout-before.log', r'Expected: <1>[\s\S]*Actual: <2>'),
        ('focused_flutter', 'accept-checkout-qualified.log', r'\+61: All tests passed!'),
        ('full_flutter', 'accept-final-flutter-qualified.log', r'\+704 ~2: All other tests passed!'),
        ('final_analysis', 'accept-checkout-final-analyze.log', r'No issues found!'),
    ):
        path = ROOT / '.fr21-local' / filename
        assert re.search(pattern, path.read_text(encoding='utf-8-sig')), 'Unconfirmed result: ' + label
        logs[label] = digest(path)
    spec = importlib.util.spec_from_file_location('accept_inventory', ROOT / 'tests/integration/MASTER-compliance.py')
    inventory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory)
    matrix = inventory.inventory()
    for row in matrix['requirements']:
        if 'current_stage_bounded_evidence' in row:
            row['prior_stage_bounded_evidence'] = row.pop('current_stage_bounded_evidence')
        if row['id'] in ('FR-07', 'UC-02'):
            row['current_stage_bounded_evidence'] = 'ACCEPT-verification.json: protected interrupted-checkout retry recovery, local tests only; no hosted order/OTP/earning acceptance.'
    matrix['fresh_requirement_acceptance'] = 0
    (OUT / 'ACCEPT-compliance.json').write_text(json.dumps(matrix, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    built_path = ROOT / 'build/delivery/test/build-evidence.json'
    built = json.loads(built_path.read_text(encoding='utf-8-sig'))
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    assert re.fullmatch('[0-9a-f]{40}', built['head'])
    assert built['environment'] == 'TEST' and not built['productionDeployed']
    subprocess.run(['git', 'merge-base', '--is-ancestor', built['head'], head], cwd=ROOT, check=True)
    current_paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '--',
                                             'lib', 'assets', 'android', 'pubspec.yaml', 'pubspec.lock'], cwd=ROOT, text=True).splitlines()
    assert {p for p in current_paths if (ROOT / p).is_file()} == {s['path'] for s in built['sources']}
    for source in built['sources']:
        assert digest(ROOT / source['path']).upper() == source['sha256'].upper(), 'Build source changed'
    result = {'project': 'igeisilhtmglgnqvllrx', 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'implementation_revision': built['head'], 'inspected_revision': head,
              'full_flutter': {'passed': 704, 'failed': 0, 'skipped': 2},
              'focused_flutter': {'passed': 61, 'failed': 0}, 'analysis': 'Seven files; no issues',
              'log_sha256': logs, 'build_manifest_sha256': digest(built_path),
              'artifact_sha256': digest(ROOT / 'build/delivery/test/app-fr21test-debug.apk').upper(),
              'build_sources_matched': len(built['sources']), 'artifact_scope': 'DEBUG TEST built; not installed/physically accepted in this continuation',
              'historical_server_suite': '230 passes from prior unchanged server source; not rerun here',
              'inventory': {'total': matrix['total'], 'retained_counts': matrix['classification_counts'], 'new_whole_requirements_accepted': 0},
              'initial_full_run': '701 pass, two skip, two failures: checkout widget lacked the newly required secure-storage platform adapter and the following test cascaded. Adapter added; assertions retained. Final complete invocation passed.',
              'hosted_delivery': 'NOT EXECUTED: owner is providing a genuinely verified Rider; phone disconnected',
              'scope': 'Fix reproduced with two local fake-server orders after a lost response. Protected journal now reuses one request/order, fails closed on storage/account errors, and retains unresolved data until confirmed completion. No hosted order, mail, push, proof, payment, earnings or production operation.'}
    (OUT / 'ACCEPT-verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
