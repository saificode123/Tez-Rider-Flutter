"""Reuse bounded native helper with append-only FINAL03 evidence destinations."""
import importlib.util
import sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('native', Path(__file__).with_name('FINAL01-native.py'))
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)
n.OUT = n.ROOT / '.fr21-local/final03'
n.OUT.mkdir(exist_ok=True)
def record(check, surface='android'):
    row = {'check': check, 'result': 'PASS', 'surface': surface,
           'observed_at': n.datetime.datetime.now(n.datetime.timezone.utc).isoformat(),
           'device': n.SERIAL, 'package': n.PKG,
           'activation_deployed': (n.ROOT / '.fr21-local/final01/deployment-202610220004.json').exists()}
    with (n.OUT / 'native-results.jsonl').open('a', encoding='utf-8') as f:
        f.write(n.json.dumps(row) + '\n')
    print(n.json.dumps(row), flush=True)
n.record = record
allowed = ('install', 'launch', 'status', 'back', 'scan-changed', 'network-recovery')
action = sys.argv[2]
assert action in allowed or action.startswith(('tap:', 'bounds:', 'login:', 'assert:')), 'Bounded TEST native action required'
if action == 'scan-changed':
    protected = [n.b.SERVICE]
    def collect(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key == 'password' and isinstance(child, str):
                    protected.append(child)
                else:
                    collect(child)
        elif isinstance(value, list):
            for child in value:
                collect(child)
    collect(n.accounts)
    collect(n.b.fr04)
    for filename in ('final01-workflow.bin', 'fr25-accounts.bin', 'fr32-accounts.bin', 'fr13-accounts.bin'):
        collect(n.json.loads(n.b.crypt((n.b.PRIVATE / filename).read_bytes(), True)))
    names = set()
    for args in (('diff', '--name-only', '-z', 'cb18c2b'), ('ls-files', '--others', '--exclude-standard', '-z')):
        names.update(n.subprocess.check_output(['git', *args], cwd=n.ROOT).decode().split('\0'))
    paths = [n.ROOT / name for name in names if name and (n.ROOT / name).is_file()]
    assert all(not any(value.encode() in path.read_bytes() for value in protected if value) for path in paths), 'Protected value found; value withheld'
    row = {'files_checked': len(paths), 'protected_credential_matches': 0, 'scope': 'actual TEST service key and protected FR04/13/25/28/32/FINAL01 fixture passwords; current iteration text/files only'}
    (n.OUT / 'protected-scan.json').write_text(n.json.dumps(row, indent=2) + '\n')
    print(n.json.dumps(row))
elif action == 'network-recovery':
    assert any(n.label(x) == 'My Orders' for x in n.nodes()), 'Observed TEST drawer required'
    wifi = n.adb('shell', 'settings', 'get', 'global', 'wifi_on').strip()
    mobile = n.adb('shell', 'settings', 'get', 'global', 'mobile_data').strip()
    assert wifi in ('0', '1') and mobile in ('0', '1'), 'Exact original connectivity state required'
    assert wifi == '1' or mobile == '1', 'A recovery connection is required'
    (n.OUT / 'connectivity-original.json').write_text(n.json.dumps({'wifi_on': wifi, 'mobile_data': mobile}))
    try:
        n.adb('shell', 'svc', 'wifi', 'disable')
        n.adb('shell', 'svc', 'data', 'disable')
        n.time.sleep(3)
        n.click('My Orders')
        n.main('assert:Orders could not be loaded. Retry.')
        assert not any(n.label(x) == 'No orders yet' for x in n.nodes()), 'Offline error must not become fabricated empty success'
        record('network disabled: actual authenticated order read shows failure and Retry, no fabricated empty success')
    finally:
        n.adb('shell', 'svc', 'wifi', 'enable' if wifi == '1' else 'disable')
        n.adb('shell', 'svc', 'data', 'enable' if mobile == '1' else 'disable')
        assert n.adb('shell', 'settings', 'get', 'global', 'wifi_on').strip() == wifi
        assert n.adb('shell', 'settings', 'get', 'global', 'mobile_data').strip() == mobile
        record('original Android Wi-Fi and mobile-data settings restored in finally')
    n.time.sleep(5)
    n.click('Retry')
    until = n.time.monotonic() + 25
    while n.time.monotonic() < until:
        current = n.nodes()
        if not any(n.label(x) == 'Orders could not be loaded. Retry.' for x in current) and any('Order #' in n.label(x) or n.label(x) == 'No orders yet' for x in current):
            n.picture('network-recovered')
            record('connectivity recovery: actual Retry returns confirmed order-list state without a critical write')
            break
        n.time.sleep(1)
    else:
        n.main('status')
        raise AssertionError('Confirmed retry recovery outcome required')
else:
    n.main(action)
