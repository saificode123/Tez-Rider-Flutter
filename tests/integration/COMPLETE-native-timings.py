"""Retain scalar TEST GPS stage timings only; never persist raw device logs."""
import datetime as dt
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import time
from tracking_timing import summarize

ROOT = Path(__file__).resolve().parents[2]
ADB = 'C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL = 'AESWNRBAEUPNTGJZ'
PACKAGE = 'com.example.flutter_application_1.fr21test'

def adb(*args):
    return subprocess.run([ADB,'-s',SERIAL,*args],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=30,check=True).stdout

capture = json.loads((ROOT/'docs/evidence/COMPLETE-gps.json').read_text())
end = dt.datetime.fromisoformat(capture['reported_at_utc']).timestamp()
start = end-capture['seconds']
before = time.time()
device_now = int(adb('shell','date','+%s').strip())
after = time.time()
offset = device_now-(before+after)/2
uncertainty = 1+(after-before)/2
pid = adb('shell','pidof',PACKAGE).strip()
assert re.fullmatch(r'\d+',pid),'Unique TEST process required'
raw = adb('logcat','-d','--pid='+pid,'-v','epoch','-t','5000')
stages = {s:[] for s in ('fix_device_interval','fix_arrival_interval','client_queue','publish_roundtrip')}
for line in raw.splitlines():
    match = re.match(r'^\s*(\d+\.\d+).*?\bFR13_METRIC (fix_device_interval|fix_arrival_interval|client_queue|publish_roundtrip) (\d+)\s*$',line)
    if match and start+offset-uncertainty<=float(match[1])<=end+offset+uncertainty:
        stages[match[2]].append(int(match[3]))
del raw
proof = {'project':'igeisilhtmglgnqvllrx','order_id':3180,
 'artifact_sha256':capture['artifact_sha256'],'stages_ms':{s:summarize(v)for s,v in stages.items()},
 'log_window_clock_uncertainty_seconds':round(uncertainty,3),
 'scope':'Scalar-only app-PID-filtered debug metrics within the observed five-minute GPS window. Phone clock alignment is bounded by one-second date precision plus half RTT. Native fix timestamps and callback intervals include all accepted native callbacks, separately from queued publication roundtrip. No raw logs, PID, coordinates, credentials or identities retained.'}
(ROOT/'docs/evidence/COMPLETE-native-timings.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps(proof))
