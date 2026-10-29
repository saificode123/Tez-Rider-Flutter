"""Bounded map-only checks on the already authenticated TEST Android app.

No account credentials, order writes, permission changes or simulated fixes.
Network settings are restored even if an observation fails.
"""
from pathlib import Path
import json
import re
import sys
import time

helper = Path(__file__).with_name('FRONTEND-native.py')
source = helper.read_text(encoding='utf-8').split('\naction = sys.argv[1]')[0]
source = source.replace("OUT = ROOT / '.fr21-local/frontend'", "OUT = ROOT / '.fr21-local/map-native'")
exec(compile(source, str(helper), 'exec'))


def snapshot(name):
    current = nodes()
    labels = [label(n) for n in current if n.get('class') != 'android.widget.EditText']
    clean = [re.sub(r'-?\d{1,3}\.\d{3,}', '[coordinate]', s)
             for s in labels if s and '@' not in s]
    row = {'check': name, 'labels': clean,
           'utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    with (OUT / 'map-controls.jsonl').open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(row) + '\n')
    print(json.dumps(row), flush=True)
    return labels


def map_nodes():
    current = nodes()
    assert any(label(n) == 'Navigation to customer' for n in current), 'Existing active delivery map required'
    return current


action = sys.argv[1]
assert action in ('screen', 'pan', 'overview', 'follow', 'network', 'background', 'restart-stopped', 'offline-picture')
if action == 'screen':
    snapshot('physical map state')
elif action == 'offline-picture':
    current = nodes()
    labels = [label(n) for n in current]
    assert 'Rider Dashboard' in labels and 'Offline' in labels
    assert not any('@' in s or re.search(r'-?\d{1,3}\.\d{3,}', s) for s in labels)
    result = subprocess.run([ADB, '-s', SERIAL, 'exec-out', 'screencap', '-p'],
                            capture_output=True, timeout=30)
    assert result.returncode == 0 and result.stdout.startswith(b'\x89PNG\r\n\x1a\n')
    (ROOT / 'docs/evidence/MAP-final-android-offline.png').write_bytes(result.stdout)
    record('actual final Android offline dashboard captured without coordinates or account contact details')
elif action == 'pan':
    current = map_nodes()
    assert any(label(n) == 'Following Rider' for n in current), 'Confirmed follow state required'
    bounds = lambda n: list(map(int, re.findall(r'\d+', n.get('bounds', ''))))
    attribution = [bounds(n) for n in current if label(n) == '© OpenStreetMap contributors']
    back = [bounds(n) for n in current if label(n) == 'Back']
    assert len(attribution) == len(back) == 1
    a, b = attribution[0], back[0]
    assert len(a) == len(b) == 4 and a[1] > b[3] + 100, 'Observed map region required'
    y = (a[1] + b[3]) // 2
    adb('shell', 'input', 'swipe', str(a[2] // 3), str(y), str(a[2] * 2 // 3), str(y), '500')
    assert 'Recenter and follow' in snapshot('manual pan suspends follow')
    time.sleep(7)
    assert 'Recenter and follow' in snapshot('follow remains suspended across real updates')
    record('manual map pan remains respected across incoming physical fixes')
elif action in ('overview', 'follow'):
    map_nodes()
    click('Route overview' if action == 'overview' else 'Recenter and follow')
    labels = snapshot('route overview' if action == 'overview' else 'recenter resumes follow')
    assert ('Recenter and follow' if action == 'overview' else 'Following Rider') in labels
    record('physical ' + action + ' camera control confirmed')
elif action == 'network':
    map_nodes()
    assert 'Stop sharing location' in snapshot('before bounded network interruption')
    wifi = adb('shell', 'settings', 'get', 'global', 'wifi_on').strip()
    mobile = adb('shell', 'settings', 'get', 'global', 'mobile_data').strip()
    assert wifi in ('0', '1') and mobile in ('0', '1') and '1' in (wifi, mobile)
    try:
        adb('shell', 'svc', 'wifi', 'disable')
        adb('shell', 'svc', 'data', 'disable')
        print(json.dumps({'network_interruption_started': True, 'maximum_seconds': 35}), flush=True)
        time.sleep(35)
        snapshot('network unavailable: actual map feedback')
    finally:
        adb('shell', 'svc', 'wifi', 'enable' if wifi == '1' else 'disable')
        adb('shell', 'svc', 'data', 'enable' if mobile == '1' else 'disable')
        assert adb('shell', 'settings', 'get', 'global', 'wifi_on').strip() == wifi
        assert adb('shell', 'settings', 'get', 'global', 'mobile_data').strip() == mobile
        record('original phone network settings restored after bounded interruption')
    time.sleep(15)
    snapshot('after connectivity restored')
elif action == 'background':
    map_nodes()
    adb('shell', 'input', 'keyevent', '3')
    time.sleep(8)
    adb('shell', 'am', 'start', '-n', PACKAGE + '/com.example.flutter_application_1.MainActivity')
    time.sleep(2)
    assert 'Navigation to customer' in snapshot('map resumed after physical background interval')
    record('physical TEST map background and foreground resume')
else:
    assert 'Share delivery location' in snapshot('sharing stopped before restart')
    adb('shell', 'am', 'force-stop', PACKAGE)
    adb('shell', 'am', 'start', '-n', PACKAGE + '/com.example.flutter_application_1.MainActivity')
    time.sleep(4)
    snapshot('cold restart without sharing consent')
    record('physical TEST app restarted after stopping sharing; authentication retained if shown')
