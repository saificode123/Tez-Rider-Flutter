"""Read-only native TEST acceptance; no credentials, coordinates or raw UI output.

Run only against the owner-authorized TEST phone. The owner completes biometric
prompts. Navigate to the requested screen before invoking a check.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

PACKAGE = 'com.example.flutter_application_1.fr21test'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--device', required=True)
    parser.add_argument('--check', required=True, choices=[
        'customer-home', 'biometric-login', 'favorites-empty',
        'test-address-present', 'test-address-absent', 'rider-home', 'rider-earnings'])
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    expected = args.expected_sha256.lower()
    if not re.fullmatch(r'[a-f0-9]{64}', expected):
        raise ValueError('An exact reviewed TEST APK hash is required')
    prefix = [args.adb, '-s', args.device]
    def adb(*command):
        result = subprocess.run(prefix + list(command), capture_output=True, timeout=30)
        if result.returncode:
            raise RuntimeError('Android command failed; device output withheld')
        return result.stdout
    installed = adb('shell', 'pm', 'path', PACKAGE).decode().strip().removeprefix('package:')
    if not re.fullmatch(r'/data/app/[\w~=/+.-]+/base.apk', installed):
        raise RuntimeError('Expected installed TEST package was not found')
    actual = adb('shell', 'sha256sum', installed).decode().split()[0]
    if actual != expected:
        raise RuntimeError('Installed APK does not match reviewed artifact')
    remote = '/sdcard/tezrider-readonly-' + uuid.uuid4().hex + '.xml'
    try:
        output = adb('shell', 'uiautomator', 'dump', remote)
        if b'UI hierchary dumped' not in output and b'UI hierarchy dumped' not in output:
            raise RuntimeError('Native screen is not ready; no stale snapshot used')
        root = ET.fromstring(adb('exec-out', 'cat', remote))
    finally:
        adb('shell', 'rm', '-f', remote)
    nodes = list(root.iter('node'))
    if not nodes or any(n.get('package') != PACKAGE for n in nodes):
        raise RuntimeError('Another app or system overlay is visible; no UI input performed')
    labels = [(n.get('text', '') + ' ' + n.get('content-desc', '')).strip() for n in nodes]
    def has(text):
        return any(text in label for label in labels)
    checks = ['installed TEST APK matches reviewed SHA-256', 'only TEST app is visible']
    if args.check == 'customer-home':
        assert all(has(s) for s in ['Home', 'Orders', 'Me', 'Categories']), 'Customer home is not visible'
        checks.append('Customer catalogue and navigation visible after server-gated entry')
    elif args.check == 'rider-home':
        assert has('Earnings') and has('Profile') and (has('Online') or has('Offline')) and not has('Categories'), 'Genuine Rider home is not visible'
        checks.append('Rider navigation and availability visible after authorized entry')
    elif args.check == 'rider-earnings':
        assert has('Earnings records only. This is not a payout confirmation.') and has('PKR 113'), 'Expected owner TEST earnings record not visible'
        assert not has('Earnings could not be loaded.'), 'Earnings request failed'
        checks.append('owner-confirmed PKR 113 stored earning and explicit no-payout statement visible')
    elif args.check == 'biometric-login':
        button = next((n for n in nodes if 'Continue with Biometrics' in (n.get('text', '') + n.get('content-desc', ''))), None)
        assert button is not None and button.get('enabled') == 'true', 'Enrolled biometric action is not available'
        assert not has('Categories'), 'Customer dashboard must remain locked'
        fields = [n for n in nodes if n.get('class') == 'android.widget.EditText']
        assert fields, 'Password fallback fields are not present'
        def top(node):
            return int(re.fullmatch(r'\[\d+,(\d+)\]\[\d+,\d+\]', node.get('bounds', '')).group(1))
        assert top(button) < min(top(n) for n in fields), 'Biometric action must precede credential fields'
        checks.append('enrolled biometric action enabled above credential fields; dashboard locked')
    elif args.check == 'favorites-empty':
        assert has('No Favorites') and has('Add to Favorites'), 'Expected confirmed empty state and discovery action'
        checks.append('real Favorites empty state and discovery action visible')
    else:
        assert has('Saved Addresses'), 'Saved-address screen is not visible'
        present = has('TEST device acceptance')
        assert present == (args.check == 'test-address-present'), 'TEST address presence does not match checkpoint'
        checks.append('approved TEST address ' + ('present after reload' if present else 'absent after cleanup'))
    report = {'checked_utc': datetime.now(timezone.utc).isoformat(),
              'kind': 'ADB native integration; read-only assertions, not Flutter integration_test runner',
              'package': PACKAGE, 'installed_apk_sha256': actual,
              'checkpoint': args.check, 'passed': len(checks), 'failed': 0,
              'checks': checks, 'writes': 0, 'external_sends': 0,
              'raw_ui_saved': False, 'coordinates_logged': False}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
