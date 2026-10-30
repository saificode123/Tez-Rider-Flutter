"""Bounded live scalar-only capture from the TEST app's own process."""
import datetime as dt
import json
import math
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
from tracking_timing import summarize

ROOT = Path(__file__).resolve().parents[2]
ADB = 'C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
SERIAL = 'AESWNRBAEUPNTGJZ'
PACKAGE = 'com.example.flutter_application_1.fr21test'
seconds = int(sys.argv[1])
assert 60 <= seconds <= 600
pid = subprocess.check_output([ADB,'-s',SERIAL,'shell','pidof',PACKAGE],text=True).strip()
assert re.fullmatch(r'\d+',pid),'Unique TEST app process required'
installed = json.loads((ROOT/'.fr21-local/complete-native/installed.json').read_text())
stages = {s:[] for s in ('fix_device_interval','fix_arrival_interval','client_queue','publish_roundtrip',
 'route_rpc_fresh','route_rpc_cached','route_rpc_stale','route_rpc_unavailable','geometry_decode','route_widget_frame')}
frames = queue.Queue(maxsize=2048)
proc = subprocess.Popen([ADB,'-s',SERIAL,'logcat','--pid='+pid,'-v','epoch','-T','1'],
 stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,encoding='utf-8',errors='replace')

def read():
    for line in proc.stdout:
        # Discard every non-metric line immediately; never write raw app logs.
        match = re.search(r'\bFR(?:13|14)_METRIC ([a-z_]+) ([0-9]+(?:\.[0-9]+)?)\s*$',line)
        if match and match[1] in stages:
            try: frames.put_nowait((match[1],float(match[2])))
            except queue.Full: pass

threading.Thread(target=read,daemon=True).start()
start = time.monotonic()
started = dt.datetime.now(dt.timezone.utc).isoformat()
print(json.dumps({'scalar_test_metrics_capture_started':True,'bounded_seconds':seconds}),flush=True)
try:
    while time.monotonic()-start<seconds:
        try: stage,value = frames.get(timeout=.5)
        except queue.Empty:
            if proc.poll() is not None: raise RuntimeError('TEST metric stream disconnected')
            continue
        if math.isfinite(value) and value>=0: stages[stage].append(value)
finally:
    proc.terminate()
    try: proc.wait(timeout=3)
    except subprocess.TimeoutExpired: proc.kill();proc.wait()
proof = {'project':'igeisilhtmglgnqvllrx','order_id':3180,'artifact_sha256':installed['sha256'],
 'started_at_utc':started,'seconds':round(time.monotonic()-start,2),
 'stages_ms':{s:summarize(values)for s,values in stages.items()},
 'scope':'Live scalar TEST-app-only numeric metrics. Device fix timestamp and callback intervals cover native callbacks; queue/publication are separate. route_rpc includes SDK transport/response decoding, geometry_decode is application geometry parsing, route_widget_frame ends at Flutter framework frame completion and excludes tile downloads/GPU completion. No raw logs, PID, positions, recipient data or credentials retained.'}
(ROOT/'docs/evidence/COMPLETE-native-live-timings.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps(proof))
