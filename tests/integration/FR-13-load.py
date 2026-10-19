"""Small local-only real HTTP/WebSocket load. Protected JWT files removed afterward."""
import importlib.util,json,sys,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('local_test',Path(__file__).with_name('FR-13-local-test.py'))
# Helpers are loaded without executing the CLI dispatcher.
module=Path(spec.origin).read_text();module=module.split("mode=sys.argv[1]",1)[0]
scope={'__file__':spec.origin};exec(compile(module,spec.origin,'exec'),scope)
ROOT=scope['ROOT'];OUT=scope['OUT'];d=scope['d'];FILE=OUT/'load-fixtures.json'
def stats():return json.loads(d.local("select json_build_object('inserted',n_tup_ins,'updated',n_tup_upd)from pg_stat_user_tables where relname='delivery_latest_locations';").strip())
if sys.argv[1]=='prepare':
 assert not FILE.exists(),'Finish existing LOCAL load first'
 rows=[];members=[]
 for index in range(4):
  path=OUT/f'load-member-{index}.json';scope['FILE']=path;scope['prepare']();state=json.loads(path.read_text());scope['state']=state
  rpc=scope['rpc'];oid=state['oid'];aid=state['aid']
  valid=[{'id':item,'confirmed':True}for item in('items_match','packaging_intact','details_confirmed')]
  assert rpc('submit_pre_delivery_checklist',{'p_assignment_id':aid,'p_version':1,'p_confirmations':valid})[1]['code']=='COMPLETED'
  assert rpc('start_checklisted_delivery',{'p_assignment_id':aid})[1]['code']=='STARTED'
  context=rpc('fr13_tracking_context',{'p_order_id':oid,'p_enable':True})[1];assert context['code']=='OK'
  rows.append({'order_id':oid,'assignment_id':aid,'topic':context['topic'],'rider':state['people']['rider']['token'],'customer':state['people']['customer']['token'],'other':state['people']['other-customer']['token']});members.append(path.name)
 FILE.write_text(json.dumps({'project':'tezrider-fr30-local','base':'http://127.0.0.1:54321','anon':state['keys']['anon'],'records':rows,'members':members,'before':stats()}))
 print('Four LOCAL-only rider/customer assignments prepared; no mail or quota changes')
elif sys.argv[1]=='finish':
 state=json.loads(FILE.read_text());assert state['project']=='tezrider-fr30-local';time.sleep(1.1);after=stats();before=state['before']
 result={'scope':'LOCAL only','assignments':len(state['records']),'latest_inserts':after['inserted']-before['inserted'],'latest_updates':after['updated']-before['updated'],'no_coordinate_history':True,'real_emails':0}
 for name in state['members']:
  path=OUT/name;assert path.parent==OUT and path.name.startswith('load-member-');member=json.loads(path.read_text());run=str(scope['uuid'].UUID(member['run']))
  d.local("update public.orders set order_status='cancelled'where id in(select oid from fr13_test.fixtures where run='"+run+"')and delivery_address='FR13 LOCAL SYNTHETIC'and order_status not in('delivered','cancelled');update public.rider_assignments set status='Cancelled'where orderid in(select oid from fr13_test.fixtures where run='"+run+"')and status in('Pending','Accepted');")
  path.unlink()
 FILE.unlink();(OUT/'load-persistence.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
else:raise ValueError('Choose prepare or finish')
