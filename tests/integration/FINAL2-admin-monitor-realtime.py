"""Actual WebSocket authorization; synthetic stored locations are not GPS evidence."""
import contextlib,concurrent.futures,json,time,urllib.parse,uuid,sys
sys.path.insert(0,str(ROOT/'build/fr21-python'))
from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed

target_label=fixture['winner'];target_id=int(people[target_label]['profile_id'])
other_label='rider2'if target_label=='rider'else'rider'
url='wss://'+REF+'.supabase.co/realtime/v1/websocket?'+urllib.parse.urlencode({'apikey':b.ANON,'vsn':'1.0.0'})
def join(stack,token):
 ws=stack.enter_context(connect(url,open_timeout=20,close_timeout=3));topic='realtime:final2-admin-proof-'+uuid.uuid4().hex
 ws.send(json.dumps({'topic':topic,'event':'phx_join','ref':'1','payload':{'config':{'private':False,'broadcast':{'ack':False,'self':False},'presence':{'key':''},
  'postgres_changes':[{'event':'UPDATE','schema':'public','table':'riders','filter':'userid=eq.'+str(target_id)}]},'access_token':token}}))
 registered=False;deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  try:message=json.loads(ws.recv(timeout=max(.01,deadline-time.monotonic())))
  except(TimeoutError,ConnectionClosed):break
  if message.get('event')=='phx_reply'and message.get('ref')=='1':
   registered=message.get('payload',{}).get('status')=='ok'and bool(message.get('payload',{}).get('response',{}).get('postgres_changes'));break
 return ws,topic,registered
def receive(connection,seconds=6):
 ws=connection[0];deadline=time.monotonic()+seconds;records=[]
 while time.monotonic()<deadline:
  try:message=json.loads(ws.recv(timeout=max(.01,deadline-time.monotonic())))
  except(TimeoutError,ConnectionClosed):break
  if message.get('event')=='postgres_changes':records.append(message['payload']['data']['record'])
 return records
try:
 with contextlib.ExitStack()as stack:
  sessions={'Admin':tokens['admin'],'own Rider':tokens[target_label],'unrelated Rider':tokens[other_label],
   'Customer':tokens['customer'],'Vendor':tokens['vendor'],'anonymous':b.ANON}
  connections={label:join(stack,token)for label,token in sessions.items()}
  check(connections['Admin'][2]and connections['own Rider'][2],'actual approved Admin and owning Rider register Rider Postgres Changes subscriptions','real authenticated TEST WebSocket')
  position(target_label)
  with concurrent.futures.ThreadPoolExecutor(max_workers=len(connections))as pool:
   results=dict(zip(connections,pool.map(receive,connections.values())))
  for label in ['Admin','own Rider']:
   check(bool(results[label])and all(r['userid']==target_id for r in results[label]),label+' actually receives its permitted committed Rider update','real authenticated TEST WebSocket')
  for label in ['unrelated Rider','Customer','Vendor','anonymous']:
   check(not results[label],label+' receives no protected Rider update during the same committed event window','real TEST WebSocket negative observation')
  owner=connections['own Rider'];owner[0].send(json.dumps({'topic':owner[1],'event':'phx_leave','ref':'99','payload':{}}))
  left=False;deadline=time.monotonic()+10
  while time.monotonic()<deadline:
   try:message=json.loads(owner[0].recv(timeout=max(.01,deadline-time.monotonic())))
   except(TimeoutError,ConnectionClosed):break
   if message.get('event')=='phx_reply'and message.get('ref')=='99':left=message.get('payload',{}).get('status')=='ok';break
  check(left,'actual owning Rider unsubscribe is acknowledged','real authenticated TEST WebSocket')
  position(target_label);check(not receive(owner),'unsubscribed owning Rider receives no subsequent private update','real TEST WebSocket negative observation')

 with contextlib.ExitStack()as stack:
  blocked_token=b.login(people['admin']);fixture['hosted_tokens']['blocked_admin_token']=blocked_token;save()
  blocked=join(stack,blocked_token);assert blocked[2]
  try:
   admin_block(True)
   code,_=gateway('final2_admin_order_monitor',blocked_token,{});check(code==403,'blocked real Admin session loses hosted monitoring authority')
   position(target_label);check(not receive(blocked),'already-subscribed Admin receives no Rider events after actual account blocking','real TEST WebSocket + scoped synthetic-account block')
  finally:admin_block(False)

 with contextlib.ExitStack()as stack:
  revoked_token=b.login(people['admin']);fixture['hosted_tokens']['revoked_admin_token']=revoked_token;save()
  revoked=join(stack,revoked_token);assert revoked[2]
  code,_=b.api('/auth/v1/logout?scope=local','POST',{},revoked_token);check(code in(200,204),'actual provider local logout revokes only the synthetic WebSocket test session','real TEST Auth provider HTTP')
  position(target_label);check(not receive(revoked),'already-subscribed revoked Admin session receives no subsequent Rider event','real TEST WebSocket negative observation')
 with contextlib.ExitStack()as stack:
  reconnected=join(stack,revoked_token)
  position(target_label);check(not receive(reconnected),'reconnecting with the actually revoked JWT cannot regain Rider publication data','real TEST WebSocket negative observation')
 fixture['realtime_verified']=True;save()
except Exception as error:
 (OUT/'admin-monitor-realtime-error.private.log').write_text(type(error).__name__+': '+str(error),encoding='utf-8')
 raise AssertionError('Bounded Rider Realtime verification failed; protected diagnostics retained privately')from None
