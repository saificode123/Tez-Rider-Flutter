"""Unauthorized second customer against the actual physical TEST assignment."""
import importlib.util,json,sys,urllib.parse
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr13',Path(__file__).with_name('FR-13-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
sys.path.insert(0,str(h.ROOT/'build/fr21-python'))
from websockets.sync.client import connect
oid=h.state['physical_order_id'];owner=h.b.login(h.state['accounts']['physical-customer'])
code,context=h.b.rpc('fr13_tracking_context',{'p_order_id':oid},owner)
assert code==200 and context['code']=='OK'and context['sharing']
token=h.b.login(h.state['accounts']['other-customer'])
code,result=h.b.rpc('fr13_tracking_context',{'p_order_id':oid},token)
assert code==200 and result['code']=='FORBIDDEN'
code,rows=h.b.api('/rest/v1/delivery_latest_locations?order_id=eq.'+str(oid)+'&select=assignment_id',token=token)
assert code==200 and rows==[]
with connect('wss://'+h.b.REF+'.supabase.co/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':h.b.ANON,'vsn':'1.0.0'}),open_timeout=20,close_timeout=3)as ws:
 ws.send(json.dumps({'topic':'realtime:'+context['topic'],'event':'phx_join','ref':'1','payload':{'config':{'private':True,'broadcast':{'ack':True,'self':True},'presence':{'key':''},'postgres_changes':[]},'access_token':token}}))
 while True:
  message=json.loads(ws.recv(timeout=20))
  assert message['event']!='broadcast','Unauthorized actual GPS delivery'
  if message['event']=='phx_reply'and message.get('ref')=='1':
   assert message['payload']['status']=='error';break
result={'actual_physical_order':oid,'second_customer_context':'DENIED','second_customer_latest_rows':0,'actual_private_websocket_join':'DENIED','result':'PASS'}
(h.OUT/'physical-security.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
