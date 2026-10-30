"""Reproduce all 137 acceptance rows, distinguishing retained and fresh evidence.

Run: python tests/integration/MASTER-compliance.py
This validates the complete inventory and linked evidence, not application acceptance.
"""
from collections import Counter
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'docs/FINAL-DELIVERY/15-SRDS-Complete-Test-Matrix.md'
OUTPUT = ROOT / 'docs/evidence/MASTER-compliance.json'


def inventory():
    rows = []
    for line in SOURCE.read_text(encoding='utf-8').splitlines():
        if not line.startswith('| ') or line.startswith('| Requirement ID '):
            continue
        values = [v.strip() for v in line.strip('|').split('|')]
        if len(values) != 7:
            raise ValueError('Unexpected matrix structure')
        ident, description, flutter, backend, evidence, actual, status = values
        if status == 'NOT RUN':
            status = 'BLOCKED' if 'BLOCKED' in actual else 'PARTIAL'
        if status not in {'PASS', 'APPROVED DEVIATION', 'PARTIAL', 'BLOCKED'}:
            raise ValueError('Unrecognized acceptance status: ' + status)
        rows.append({
            'id': ident, 'description': description,
            'implementation': {'flutter': flutter, 'backend': backend},
            'test_id_and_evidence': evidence,
            'environment': 'Historical bounded TEST; see original evidence',
            'actual_result': actual,
            'acceptance_status': status,
            'fresh_requirement_acceptance': False,
        })
    assert len(rows) == 137, 'The full inventory must contain exactly 137 rows'
    assert len({r['id'] for r in rows}) == 137, 'Duplicate requirement ID'
    counts = dict(Counter(r['acceptance_status'] for r in rows))
    assert counts == {'PASS': 77, 'APPROVED DEVIATION': 17,
                      'PARTIAL': 42, 'BLOCKED': 1}, counts
    # FR22 is the only fresh promotion. Require its actual persisted outcome,
    # role-authorized report and owner-reported genuine Rider UI evidence.
    evidence = ROOT / 'docs/evidence'
    stored = json.loads((evidence / 'COMPLETE-stored-rider-metrics.json').read_text(encoding='utf-8-sig'))
    reports = json.loads((evidence / 'COMPLETE-cross-role-reports.json').read_text())
    phone = json.loads((evidence / 'COMPLETE-owner-earnings.json').read_text())
    assert stored['project'] == reports['project'] == phone['project'] == 'igeisilhtmglgnqvllrx'
    assert stored['order_id'] == reports['order_id'] == phone['order_id'] == 3180
    assert stored['metrics_rows'] == 1 and stored['duration_stored'] is True
    assert stored['completed_deliveries'] == stored['timed_deliveries'] == 1
    assert stored['earned_amount'] == phone['displayed_earning_pkr'] == 113
    assert reports['metrics']['earned_fee_cents'] == 11300 and len(reports['checks']) == 9
    new_evidence = {
        'FR-01': 'MASTER-demo-verify.json: synthetic Auth/profile roles; not real inbox verification',
        'FR-02': 'MASTER-demo-verify.json: seven real Auth fixture logins; final installed Rider login',
        'FR-06': 'MASTER-demo-verify.json: real seeded product lookup; no full browse/control promotion',
        'FR-13': 'MASTER-gps-performance.json: real foreground/background/recovery; 2-3s cadence FAIL',
        'FR-14': 'MASTER-gps-performance.json: actual road geometry; 2484-4265ms HTTP calls fail 800ms',
        'FR-17': 'MASTER-catalogue-apply.json: approved availability changes preserve quantities; no new concurrent-checkout acceptance',
        'FR-21': 'MASTER-gps-network.json and MASTER-gps-performance.json: actual Online/background/recovery/cleanup scope only',
    }
    for row in rows:
        if row['id'] in new_evidence:
            row['current_stage_bounded_evidence'] = new_evidence[row['id']]
        if row['id'] == 'FR-22':
            assert row['acceptance_status'] == 'PASS'
            row['fresh_requirement_acceptance'] = True
            row['environment'] = 'Fresh bounded Android TEST order 3180, 2026-10-30; not production qualification'
    return {
        'total': len(rows), 'classification_counts': counts,
        'classification_scope': '76 retained bounded passes and one fresh bounded Android TEST FR22 pass; not 77 fresh production passes',
        'baseline_classification_counts': {'PASS': 76, 'APPROVED DEVIATION': 17, 'PARTIAL': 43, 'BLOCKED': 1},
        'source': str(SOURCE.relative_to(ROOT)),
        'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'inspected_revision': subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'verdict': 'NOT READY FOR PRODUCTION', 'requirements': rows,
    }


if __name__ == '__main__':
    result = inventory()
    OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n',
                      encoding='utf-8')
    print(json.dumps({'inventory_validated': result['total'],
                      'current_counts': result['classification_counts'],
                      'fresh_requirement_acceptance': sum(r['fresh_requirement_acceptance'] for r in result['requirements'])}))
