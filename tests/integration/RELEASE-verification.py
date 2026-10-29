"""Bind current successful regression logs to sanitized release evidence."""
import datetime as dt
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def main():
    checks = [
        ('full_flutter', 'mission-final-flutter.log', r'\+691 ~2: All other tests passed!', {'passed': 691, 'skipped': 2}),
        ('full_deno', 'mission-final-deno-complete.log', r'ok \| 230 passed \| 0 failed', {'passed': 230, 'failed': 0}),
        ('focused_flutter', 'mission-gps-final-focused.log', r'\+60: All tests passed!', {'passed': 60}),
    ]
    records = {}
    for name, filename, pattern, counts in checks:
        log = (ROOT / '.fr21-local' / filename).read_bytes()
        assert re.search(pattern, log.decode('utf-8-sig')), 'Missing successful result: ' + name
        records[name] = {**counts, 'log_sha256': hashlib.sha256(log).hexdigest()}
    record = {'project': 'igeisilhtmglgnqvllrx', 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'results': records,
              'analysis': 'Focused source analysis: zero errors/warnings, three inherited brace-style infos.',
              'helper_checks': 'Seven changed/new PowerShell helpers parsed; ten changed/new Python helpers compiled.',
              'registration': 'Nine offline rollback-only guards, rollback/reapply rehearsal and actual TEST profile/cart/ratings verified separately.',
              'scope': 'Fresh current-source local regression. Initial Deno commands lacked font read/sample write permissions (227 pass, 3 permission failures each); final invocation added only scoped local reads/writes, no network permission, and passed all 230. No production, full SRDS, iOS, performance-target or new delivery acceptance implied.'}
    (ROOT / 'docs/evidence/RELEASE-verification.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(record))


if __name__ == '__main__':
    main()
