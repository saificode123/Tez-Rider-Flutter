"""Scan current Git-deliverable UTF-8 files; emit candidate types, never values."""
import importlib.util
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--evidence', choices=('MASTER-secret-scan.json', 'RELEASE-secret-scan.json', 'ACCEPT-secret-scan.json', 'AUTH-secret-scan.json', 'MAP-secret-scan.json', 'COMPLETE-secret-scan.json'), default='MASTER-secret-scan.json')
options = parser.parse_args()
spec = importlib.util.spec_from_file_location(
    'scanner', Path(__file__).with_name('FINAL-secret-scan.py'))
scanner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scanner)
names = subprocess.check_output(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
    cwd=ROOT).decode().split('\0')
results = []
count = 0
for name in names:
    path = ROOT / name
    if not name or not path.is_file() or path.stat().st_size > 2_000_000:
        continue
    try:
        content = path.read_text(encoding='utf-8-sig')
    except (UnicodeError, OSError):
        continue
    count += 1
    for kind in sorted(scanner.categories(content)):
        results.append({'path': name, 'type': kind})
result = {
    'files_scanned': count, 'candidates': results,
    'scope': 'Current tracked/unignored UTF-8 files <=2MB. History not rescanned. '
             'Candidate values never printed; candidates require review.',
}
(ROOT / 'docs/evidence' / options.evidence).write_text(
    json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
