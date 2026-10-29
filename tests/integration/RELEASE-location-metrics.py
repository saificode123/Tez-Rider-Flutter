"""Capture only whitelisted numeric TEST location timings, never raw logcat."""
from collections import defaultdict
import datetime as dt
import hashlib
import json
from pathlib import Path
import queue
import re
import statistics
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
ADB = 'C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL = 'AESWNRBAEUPNTGJZ'
PACKAGE = 'com.example.flutter_application_1.fr21test'


def adb(*args):
    return subprocess.check_output([ADB, '-s', SERIAL, *args], text=True, timeout=30).strip()


def main(label):
    assert label in ('foreground', 'background', 'recovery')
    manifest = json.loads((ROOT / 'build/delivery/test/build-evidence.json').read_text(encoding='utf-8-sig'))
    assert manifest['project'] == 'igeisilhtmglgnqvllrx' and manifest['mode'] == 'debug'
    assert hashlib.sha256(Path(manifest['artifact']).read_bytes()).hexdigest().upper() == manifest['sha256']
    installed = adb('shell', 'pm', 'path', PACKAGE)
    assert installed.startswith('package:/data/app/') and installed.endswith('/base.apk')
    assert adb('shell', 'sha256sum', installed[8:]).split()[0].upper() == manifest['sha256']
    pid = adb('shell', 'pidof', PACKAGE)
    assert re.fullmatch(r'\d+', pid)
    process = subprocess.Popen([ADB, '-s', SERIAL, 'logcat', '--pid=' + pid, '-T', '1', '-v', 'brief', '-s', 'flutter:I'],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding='utf-8', errors='replace')
    messages = queue.Queue()
    def read():
        for line in process.stdout:
            match = re.search(r'FR13_METRIC (fix_device_interval|fix_arrival_interval|client_queue|publish_roundtrip) (-?\d+)\s*$', line)
            if match:
                messages.put((match[1], int(match[2])))
    thread = threading.Thread(target=read, daemon=True)
    thread.start()
    values = defaultdict(list)
    started = time.monotonic()
    try:
        while time.monotonic() - started < 60:
            try:
                name, value = messages.get(timeout=.25)
                values[name].append(value)
            except queue.Empty:
                assert process.poll() is None, 'Numeric timing capture exited early'
    finally:
        process.terminate()
        process.wait(timeout=10)
        thread.join(timeout=2)
    assert adb('shell', 'pidof', PACKAGE) == pid, 'TEST process changed during measurement'
    result = {'utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'project': manifest['project'],
              'artifact_sha256': manifest['sha256'], 'phase': label, 'seconds': 60,
              'metrics_ms': dict(values), 'summary': {name: {'samples': len(items),
                  'p50_ms': statistics.median(items), 'worst_ms': max(items)} for name, items in values.items()},
              'scope': 'TEST process numeric timings only. Device generation intervals and monotonic callback/queue/HTTP roundtrip are separate. No coordinate, absolute fix timestamp, request ID, credential or raw log line retained.'}
    out = ROOT / '.fr21-local/release-gps'
    out.mkdir(exist_ok=True, parents=True)
    (out / ('pipeline-' + label + '.json')).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'phase': label, 'summary': result['summary']}))
    assert all(values.get(name) for name in ('fix_device_interval', 'fix_arrival_interval', 'client_queue', 'publish_roundtrip')), 'Incomplete physical pipeline timing evidence'


if __name__ == '__main__':
    main(sys.argv[1])
