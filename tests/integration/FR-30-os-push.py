"""Inspect only TEST app OS notifications; no unrelated notification contents."""
from pathlib import Path
import importlib.util,json,subprocess,sys,time,shlex,re,xml.etree.ElementTree as ET
spec=importlib.util.spec_from_file_location('fr30',Path(__file__).with_name('FR-30-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
adb='C:/Users/urreh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
package='com.example.flutter_application_1.fr21test';serial='AESWNRBAEUPNTGJZ'
def run(*args):
 p=subprocess.run([adb,'-s',serial,*args],capture_output=True,text=True,encoding='utf-8',timeout=30)
 assert p.returncode==0,'Authorized notification inspection failed';return p.stdout
mode=sys.argv[1]
tap=mode.startswith('tap-')
if tap:mode=mode[4:]
if mode=='terminate':
 run('shell','input','keyevent','3');time.sleep(1)
 run('shell','am','kill',package)
 deadline=time.monotonic()+10
 while True:
  process=subprocess.run([adb,'-s',serial,'shell','pidof',package],capture_output=True,text=True,timeout=15)
  if not process.stdout.strip():break
  assert time.monotonic()<deadline,'TEST process still alive';time.sleep(1)
 assert 'stopped=false'in run('shell','dumpsys','package',package),'Package must remain eligible for Android delivery'
 result={'scenario':'normal-terminated-precondition','passed':True,'process_absent':True,'package_force_stopped':False}
elif mode=='none':
 keys=[k for k in run('shell','cmd','notification','list').splitlines()if package in k]
 assert not keys,'Expected no TEST OS notification'
 result={'scenario':'no-test-os-notification','passed':True}
else:
 assert mode in('foreground','background','terminated','foreground-final','background-final','terminated-final','cron-final')
 request=b.state['push_requests'][mode];bid=request['p_request_id'];deadline=time.monotonic()+(90 if mode=='cron-final'else 45)
 while True:
  keys=[k.strip()for k in run('shell','cmd','notification','list').splitlines()if package in k and bid in k]
  if keys:break
  assert time.monotonic()<deadline,'Expected TEST OS notification not received';time.sleep(1)
 assert len(keys)==1,'One stable broadcast notification tag required'
 notice=run('shell','cmd','notification','get',shlex.quote(keys[0]))
 assert request['p_title']in notice and request['p_message']in notice,'Actual OS title/message required'
 result={'scenario':mode,'passed':True,'one_test_notification':True,'exact_title_and_message':True,'physical_os_receipt':True}
 if tap:
  run('shell','cmd','statusbar','expand-notifications');time.sleep(1)
  for attempt in range(3):
   run('shell','uiautomator','dump','/data/local/tmp/fr30-os-ui.xml')
   try:
    tree=ET.fromstring(run('exec-out','cat','/data/local/tmp/fr30-os-ui.xml'));break
   except ET.ParseError:
    if attempt==2:raise
    time.sleep(1)
  matches=[n for n in tree.iter('node')if n.get('text')==request['p_title']]
  assert len(matches)==1,'Observed TEST OS notification title required'
  xy=list(map(int,re.findall(r'\d+',matches[0].get('bounds',''))));assert len(xy)==4
  run('shell','input','tap',str((xy[0]+xy[2])//2),str((xy[1]+xy[3])//2))
  result['physical_notification_tap']=True
with(b.OUT/'push-os-evidence.jsonl').open('a',encoding='utf-8')as f:f.write(json.dumps(result)+'\n')
print(json.dumps(result))
