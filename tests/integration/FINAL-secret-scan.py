"""Bounded current/history credential scan. Emits paths/types, never values."""
from pathlib import Path
import base64
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.fr21-local/final1'
PATTERNS = {
    'provider_or_private_key': r'(?:sb_secret_[A-Za-z0-9_-]{12,}|xkeysib-[A-Za-z0-9-]{24,}|gsk_[A-Za-z0-9]{20,})',
    'static_private_pem': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\s*[A-Za-z0-9+/=\r\n]{80,}-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'jwt': r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}',
    'firebase_client_config_key': r'AIza[A-Za-z0-9_-]{25,}',
}


def categories(text):
    found = set()
    for name, pattern in PATTERNS.items():
        for match in re.finditer(pattern, text):
            if name != 'jwt':
                found.add(name)
            else:
                try:
                    data = match.group().split('.')[1]
                    claims = json.loads(base64.urlsafe_b64decode(data + '=' * (-len(data) % 4)))
                    found.add('public_anon_jwt' if claims.get('role') == 'anon' else 'privileged_or_unknown_jwt')
                except (ValueError, UnicodeError):
                    found.add('unclassified_jwt')
    return found


def scan():
    current = []
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
    count = 0
    for name in names:
        path = ROOT / name
        if not name or not path.is_file() or path.stat().st_size > 2_000_000:
            continue
        try:
            text = path.read_text(encoding='utf-8-sig')
        except (UnicodeError, OSError):
            continue
        count += 1
        for kind in sorted(categories(text)):
            current.append({'path': name, 'type': kind, 'active': 'not probed; no credential used'})

    objects = subprocess.check_output(['git', 'rev-list', '--objects', '--all'], cwd=ROOT).decode().splitlines()
    paths = {}
    for line in objects:
        oid, _, path = line.partition(' ')
        if path:
            paths[oid] = path
    checked = subprocess.run(['git', 'cat-file', '--batch-check'], input='\n'.join(paths) + '\n',
                             capture_output=True, text=True, cwd=ROOT, check=True).stdout.splitlines()
    candidates = [r.split()[0] for r in checked if len(r.split()) == 3 and r.split()[1] == 'blob' and int(r.split()[2]) <= 2_000_000]
    raw = subprocess.run(['git', 'cat-file', '--batch'], input=('\n'.join(candidates) + '\n').encode(),
                         capture_output=True, cwd=ROOT, check=True).stdout
    history = []
    offset = 0
    for _ in candidates:
        end = raw.index(b'\n', offset)
        oid, _, size = raw[offset:end].decode().split()
        offset = end + 1
        body = raw[offset:offset + int(size)]
        offset += int(size) + 1
        if b'\x00' in body:
            continue
        try:
            text = body.decode('utf-8-sig')
        except UnicodeError:
            continue
        for kind in sorted(categories(text)):
            history.append({'path': paths[oid], 'blob': oid, 'type': kind,
                            'active': 'not probed; historical presence is not active privilege'})
    result = {'current_text_files': count, 'historical_small_blobs': len(candidates),
              'limits': 'Reachable local/cached remote history only; UTF-8 blobs<=2MB; no credential use/rotation/history rewrite.',
              'current': current, 'history': history}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'secret-scan.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'current_text_files': count, 'historical_small_blobs': len(candidates),
                      'current_candidates': current, 'historical_candidate_count': len(history)}))


if __name__ == '__main__':
    scan()
