"""Bounded frontend checks on the owner-authorized TEST Android package.

Uses existing encrypted synthetic fixture credentials only for sign-in. Does
not reset app data, change permissions, or submit orders/admin mutations.
"""
from pathlib import Path
import ctypes
import datetime
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.fr21-local/frontend'
OUT.mkdir(parents=True, exist_ok=True)
ADB = 'C:/Users/urreh/AppData/Local/Android/sdk/platform-tools/adb.exe'
SERIAL = 'AESWNRBAEUPNTGJZ'
PACKAGE = 'com.example.flutter_application_1.fr21test'


def adb(*args, input=None):
    result = subprocess.run([ADB, '-s', SERIAL, *args], input=input,
                            capture_output=True, text=True, encoding='utf-8', timeout=60)
    assert result.returncode == 0, 'Authorized TEST Android action failed; output withheld'
    return result.stdout


def nodes():
    active = adb('shell', 'dumpsys', 'activity', 'activities')
    assert re.search(r'topResumedActivity=ActivityRecord\{[^}]*' + re.escape(PACKAGE) + '/', active), 'TEST app must be foreground'
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/frontend-ui.xml')
    raw = adb('exec-out', 'cat', '/data/local/tmp/frontend-ui.xml')
    return list(ET.fromstring(raw).iter('node'))


def label(node):
    return (node.get('text') or node.get('content-desc') or '').strip()


def tap(node):
    bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
    assert len(bounds) == 4 and bounds[2] > bounds[0] and bounds[3] > bounds[1]
    adb('shell', 'input', 'tap', str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))
    time.sleep(.6)


def click(value):
    matches = [node for node in nodes() if label(node) == value and node.get('enabled') != 'false']
    clickable = [node for node in matches if node.get('clickable') == 'true']
    matches = clickable or matches
    assert len(matches) == 1, 'One observed control required: ' + value
    tap(matches[0])


def record(check):
    row = {'check': check, 'result': 'PASS', 'device': SERIAL, 'package': PACKAGE,
           'utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    with (OUT / 'results.jsonl').open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(row) + '\n')
    print(json.dumps(row))


def credentials(role):
    class Blob(ctypes.Structure):
        _fields_ = [('size', ctypes.c_ulong), ('data', ctypes.POINTER(ctypes.c_ubyte))]
    private = Path(os.environ['LOCALAPPDATA']) / 'TezRider-FR21/fr28-accounts.bin'
    encrypted = private.read_bytes()
    buffer = ctypes.create_string_buffer(encrypted)
    source = Blob(len(encrypted), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    output = Blob()
    assert ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)), 'Fixture storage inaccessible'
    try:
        account = json.loads(ctypes.string_at(output.data, output.size))['accounts'][role]
    finally:
        ctypes.windll.kernel32.LocalFree(output.data)
    assert account['email'].startswith('fr28-') and account['email'].endswith('@example.test')
    return account


action = sys.argv[1]
if action == 'install':
    evidence = json.loads((ROOT / 'build/delivery/test/build-evidence.json').read_text(encoding='utf-8-sig'))
    assert evidence['project'] == 'igeisilhtmglgnqvllrx' and evidence['environment'] == 'TEST'
    apk = Path(evidence['artifact'])
    assert hashlib.sha256(apk.read_bytes()).hexdigest().upper() == evidence['sha256']
    for source in evidence['sources']:
        assert hashlib.sha256((ROOT / source['path']).read_bytes()).hexdigest().upper() == source['sha256'], 'Source changed after build'
    aapt = 'C:/Users/urreh/AppData/Local/Android/sdk/build-tools/36.0.0/aapt.exe'
    package = subprocess.check_output([aapt, 'dump', 'badging', str(apk)], text=True)
    assert re.search(r"^package: name='" + re.escape(PACKAGE) + "'", package)
    assert 'Success' in adb('install', '-r', str(apk))
    record('installed current-source APK with TEST package, source hashes and artifact hash checked')
elif action == 'launch':
    adb('shell', 'am', 'force-stop', PACKAGE)
    adb('shell', 'monkey', '-p', PACKAGE, '1')
    time.sleep(5)
elif action == 'status':
    current = nodes()
    print(json.dumps({'controls': [{'label': re.sub(r'\S+@\S+', '[email]', label(node)),
                                  'bounds': node.get('bounds'), 'clickable': node.get('clickable')}
                                 for node in current if label(node) and node.get('class') != 'android.widget.EditText'],
                      'fields': len([node for node in current if node.get('class') == 'android.widget.EditText'])}, ensure_ascii=False))
elif action.startswith('tap:'):
    click(action[4:])
elif action.startswith('bounds:'):
    matches = [node for node in nodes() if node.get('bounds') == action[7:] and node.get('clickable') == 'true']
    assert len(matches) == 1
    tap(matches[0])
elif action == 'back':
    nodes()
    adb('shell', 'input', 'keyevent', '4')
elif action.startswith('assert:'):
    expected = action[7:]
    deadline = time.monotonic() + 25
    while not any(expected in label(node) for node in nodes()):
        assert time.monotonic() < deadline, 'Expected native outcome missing: ' + expected
        time.sleep(1)
    record('observed native ' + expected)
elif action.startswith('login:'):
    role = action[6:]
    assert role in ('customer', 'vendor', 'rider', 'admin')
    account = credentials(role)
    assert any(label(node) == 'Sign in as ' + role.title() for node in nodes())
    for index, value in enumerate([account['email'], account['password']]):
        fields = [node for node in nodes() if node.get('class') == 'android.widget.EditText']
        assert len(fields) == 2
        tap(fields[index])
        adb('shell', input='input keyevent 123\ninput keyevent ' + ' '.join(['67'] * 160) + '\ninput text ' + shlex.quote(value) + '\nexit\n')
        adb('shell', 'input', 'keyevent', '4')
    click('Sign in as ' + role.title())
    time.sleep(5)
elif action.startswith('picture:'):
    name = action[8:]
    assert re.fullmatch(r'[a-z0-9-]{1,48}', name)
    current = nodes()
    assert all(not node.get('text') for node in current if node.get('class') == 'android.widget.EditText'), 'Only empty forms may be captured for public evidence'
    assert not any('@' in label(node) for node in current if node.get('class') != 'android.widget.EditText'), 'Public screenshot must not contain account email'
    screenshot = subprocess.run([ADB, '-s', SERIAL, 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30, check=True)
    path = ROOT / 'docs/evidence' / ('FRONTEND-' + name + '.png')
    path.write_bytes(screenshot.stdout)
    record('captured empty-form native screenshot: ' + name)
else:
    raise SystemExit('Unsupported bounded frontend action')
