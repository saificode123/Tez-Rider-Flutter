"""Observe actual phone GPS over TEST WebSocket; persist aggregates, never fixes."""
import datetime as dt, importlib.util, json, math, re, sys, time, urllib.parse
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr13',Path(__file__).with_name('FR-13-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
sys.path.insert(0,str(h.ROOT/'build/fr21-python'))
from websockets.sync.client import connect

def clocks():
 token=h.b.login(h.state['accounts']['physical-customer']);samples=[]
 for _ in range(3):
  before=dt.datetime.now(dt.timezone.utc);tick=time.monotonic()
  code,result=h.b.rpc('fr13_tracking_context',{'p_order_id':h.state['physical_order_id']},token)
  after=dt.datetime.now(dt.timezone.utc);duration=time.monotonic()-tick
  assert code==200 and result['code']=='OK'
  server=dt.datetime.fromisoformat(result['server_now'].replace('Z','+00:00'))
  samples.append({'round_trip_ms':round(duration*1000,1),'observer_minus_server_midpoint_ms':round(((before+(after-before)/2)-server).total_seconds()*1000,1),'uncertainty_ms':round(duration*500,1)})
 result={'samples':samples,'interpretation':'Clock estimate with half-RTT uncertainty; raw wall-clock delivery latency is not clock-corrected'}
 (h.OUT/'physical-clocks.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

def main(seconds,label=''):
 assert 30<=seconds<=1200
 assert re.fullmatch(r'[a-z-]{0,30}',label)
 token=h.b.login(h.state['accounts']['physical-customer']);oid=h.state['physical_order_id']
 code,context=h.b.rpc('fr13_tracking_context',{'p_order_id':oid},token)
 assert code==200 and context['code']=='OK' and context['sharing'],'Actual phone sharing must be active'
 topic='realtime:'+context['topic'];count=duplicates=0;seen=set();previous=None
 intervals=[];latencies=[];accuracies=[];device_intervals=[];server_intervals=[];ages=[];previous_device=previous_server=None;distance=0.;start=time.monotonic();last=None
 path=h.OUT/('physical-observer'+('-'+label if label else'')+'.json')
 def report(final=False):
  result={'actual_phone_websocket':True,'reported_at_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'observer_status':'COMPLETED'if final else'RUNNING','seconds':round(time.monotonic()-start,1),'final':final,'events':count,'duplicates':duplicates,'intervals_seconds':intervals,'device_intervals_seconds':device_intervals,'server_intervals_seconds':server_intervals,'device_to_server_ms':ages,'latency_ms':latencies,'accuracy_metres':accuracies,'distance_metres':round(distance,1),'seconds_since_last_event':None if last is None else round(time.monotonic()-last,1),'coordinates_persisted':False}
  path.write_text(json.dumps(result,indent=2))
 with connect('wss://'+h.b.REF+'.supabase.co/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':h.b.ANON,'vsn':'1.0.0'}),open_timeout=20,close_timeout=3)as ws:
  ws.send(json.dumps({'topic':topic,'event':'phx_join','ref':'1','payload':{'config':{'private':True,'broadcast':{'ack':True,'self':True},'presence':{'key':''},'postgres_changes':[]},'access_token':token}}))
  joined=False;heartbeat=time.monotonic();saved=0
  while time.monotonic()-start<seconds:
   now=time.monotonic()
   if now-heartbeat>=20:
    ws.send(json.dumps({'topic':'phoenix','event':'heartbeat','payload':{},'ref':str(int(now))}));heartbeat=now
   try:message=json.loads(ws.recv(timeout=1))
   except TimeoutError:
    if now-saved>=5:report();saved=now
    continue
   if message['event']=='phx_reply'and message.get('ref')=='1':
    assert message['payload']['status']=='ok';joined=True;print('Physical customer private WebSocket joined',flush=True)
   if message['event']!='broadcast':continue
   assert joined
   data=message['payload']['payload'];assert int(data['order_id'])==oid and int(data['assignment_id'])==context['assignment_id']
   request=data['request_id']
   if request in seen:duplicates+=1;continue
   seen.add(request);count+=1
   if last is not None:intervals.append(round(now-last,3))
   last=now
   received=dt.datetime.fromisoformat(data['received_at'].replace('Z','+00:00'))
   device=dt.datetime.fromisoformat(data['device_at'].replace('Z','+00:00'))
   if previous_device is not None:device_intervals.append(round((device-previous_device).total_seconds(),3))
   if previous_server is not None:server_intervals.append(round((received-previous_server).total_seconds(),3))
   ages.append(round((received-device).total_seconds()*1000,1));previous_device=device;previous_server=received
   latencies.append(round((dt.datetime.now(dt.timezone.utc)-received).total_seconds()*1000,1));accuracies.append(float(data['accuracy']))
   point=(float(data['latitude']),float(data['longitude']))
   if previous:
    lat1,lat2=map(math.radians,(previous[0],point[0]));dl=math.radians(point[1]-previous[1]);da=lat2-lat1
    distance+=6371000*2*math.asin(min(1,math.sqrt(math.sin(da/2)**2+math.cos(lat1)*math.cos(lat2)*math.sin(dl/2)**2)))
   previous=point;report()
  report(True);assert joined
 print(json.dumps({'actual_phone_events':count,'duplicates':duplicates,'duration_seconds':seconds}),flush=True)
if __name__=='__main__':
 if sys.argv[1]=='clocks':clocks()
 else:
  args=sys.argv[1].split(':',1);label=args[1]if len(args)>1 else''
  try:main(int(args[0]),label)
  except Exception as error:
   if re.fullmatch(r'[a-z-]{0,30}',label):
    path=h.OUT/('physical-observer'+('-'+label if label else'')+'.json')
    result=json.loads(path.read_text())if path.exists()else{}
    result.update({'observer_status':'FAILED','error_type':type(error).__name__,'reported_at_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'final':False})
    path.write_text(json.dumps(result,indent=2))
   raise
