"""Real TEST push probes; synthetic cohorts only, never logs device credentials."""
from pathlib import Path
import importlib.util,json,sys,time,uuid
spec=importlib.util.spec_from_file_location('fr30',Path(__file__).with_name('FR-30-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
def send(label):
 assert label in('denied','foreground','background','terminated','logout','blocked','foreground-final','background-final','terminated-final','cron-final')
 b.safe_audience('CUSTOMERS')
 request=b.state.setdefault('push_requests',{}).setdefault(label,{'p_request_id':str(uuid.uuid4()),'p_title':'FR30 push '+label,'p_message':'Synthetic Android OS push verification.','p_audience':'CUSTOMERS'})
 account=b.fixture('push-admin','admin')if label=='blocked'or label.endswith('-final')else b.state['accounts']['admin']
 b.save();token=b.b.login(account)
 status,result=b.b.rpc('admin_send_broadcast',request,token)
 if status==200 and result.get('code')=='COOLDOWN':
  time.sleep(min(int(result['retry_after_seconds'])+1,60));status,result=b.b.rpc('admin_send_broadcast',request,token)
 assert status==200 and result['code']in('SENT','ALREADY_SENT'),'Real broadcast acceptance required'
 if label=='cron-final':
  worker={'code':'SCHEDULED','manual_dispatch':False,'device_receipt_confirmed':False}
 else:
  status,worker=b.b.api('/functions/v1/fr30-dispatch-push','POST',{'source':'admin'},token=token)
  assert status==200,'Real worker response required'
 b.state.setdefault('push_results',{})[label]={'broadcast_id':result['id'],'recipients':result['recipient_count'],'sender_id':account['profile_id'],'worker':worker};b.save()
 print(json.dumps({'scenario':label,'database_accepted':True,'worker':worker,'device_receipt_pending':True}))
def inspect():
 customer=b.state['accounts']['customer']['profile_id']
 data=b.query(b.write('push-native-inspect.sql',"""select jsonb_build_object(
 'enabled',(select android_push_enabled from fr30_private.limits where singleton),
 'devices',(select count(*)from fr30_private.push_devices where user_id="""+str(customer)+"""),
 'other_owner_devices',(select count(*)from fr30_private.push_devices where user_id<>"""+str(customer)+"""),
 'jobs',(select coalesce(jsonb_agg(s),'[]')from(select n.broadcast_id,j.state,j.attempts,j.failure_code,j.provider_message is not null as provider_confirmed,j.device_id is not null as registered_device from fr30_private.push_deliveries j join public.notifications n on n.id=j.notification_id order by j.created_at)s),
 'credential_columns_private',not has_table_privilege('authenticated','fr30_private.push_devices','SELECT'))as inspection;"""))['rows'][0]['inspection']
 (b.OUT/'push-native-inspection.json').write_text(json.dumps(data,indent=2),encoding='utf-8');print(json.dumps(data))
if sys.argv[1]in('block','unblock'):
 customer=b.state['accounts']['customer']
 status,auth=b.b.api('/auth/v1/admin/users/'+customer['auth_id'],admin=True)
 assert status==200 and auth['user_metadata'].get('fr30_fixture')is True,'Own marked synthetic fixture required'
 blocked=sys.argv[1]=='block'
 status,rows=b.b.api('/rest/v1/users?id=eq.'+str(customer['profile_id']),'PATCH',{'is_blocked':blocked},admin=True)
 assert status==200 and len(rows)==1 and rows[0]['is_blocked']==blocked,'Synthetic block state unconfirmed'
 b.state['push_fixture_blocked']=blocked;b.save()
 print(json.dumps({'own_synthetic_customer_only':True,'blocked':blocked}))
elif sys.argv[1]=='inspect':inspect()
else:send(sys.argv[1])
