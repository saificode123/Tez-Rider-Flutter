"""Final persisted Android TEST acceptance, without credentials or recipient PII."""
from pathlib import Path
import importlib.util,json,uuid
spec=importlib.util.spec_from_file_location('fr30',Path(__file__).with_name('FR-30-hosted.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
customer=int(b.state['accounts']['customer']['profile_id'])
assert not b.state.get('push_fixture_blocked'),'Restore synthetic fixture before final verification'
checks=[]
for label,result in b.state['push_results'].items():
 bid=str(uuid.UUID(result['broadcast_id']))
 row=b.query(b.write('push-verify-'+label+'.sql',"""select jsonb_build_object(
 'one_broadcast',(select count(*)=1 from public.admin_broadcasts where id='"""+bid+"""'),
 'count_matches',(select b.recipient_count=(select count(*)from public.notifications n where n.broadcast_id=b.id)from public.admin_broadcasts b where b.id='"""+bid+"""'),
 'one_trusted_audit',(select count(*)=1 from public.security_audit_log a join public.admin_broadcasts b on b.id=a.broadcast_id where b.id='"""+bid+"""'and a.actor_id=b.sender_id and a.action='SEND_BROADCAST'),
 'customer_notices',(select count(*)from public.notifications where broadcast_id='"""+bid+"""'and user_id="""+str(customer)+"""),
 'jobs',(select count(*)from fr30_private.push_deliveries j join public.notifications n on n.id=j.notification_id where n.broadcast_id='"""+bid+"""'),
 'provider_accepted',(select count(*)from fr30_private.push_deliveries j join public.notifications n on n.id=j.notification_id where n.broadcast_id='"""+bid+"""'and j.state='PROVIDER_ACCEPTED'and j.attempts=1 and j.provider_message is not null and j.user_id="""+str(customer)+"""),
 'other_role_notices',(select count(*)from public.notifications n join public.users u on u.id=n.user_id where n.broadcast_id='"""+bid+"""'and u.role<>'customer'))as result;"""))['rows'][0]['result']
 assert row['one_broadcast']and row['count_matches']and row['one_trusted_audit']and row['other_role_notices']==0,label+' persisted isolation/audit'
 assert row['customer_notices']==(0 if label=='blocked'else 1),label+' immutable recipient eligibility'
 expected=0 if label in('denied','logout','blocked')else 1
 assert row['jobs']==expected and row['provider_accepted']==expected,label+' exact device job count'
 checks.append({'scenario':label,**row,'result':'PASS'})
os_checks=[json.loads(line)for line in(b.OUT/'push-os-evidence.jsonl').read_text(encoding='utf-8').splitlines()]
assert all(any(e.get('scenario')==label and e.get('physical_os_receipt')and e.get('passed')for e in os_checks)for label in('foreground-final','background-final','terminated-final')),'Final APK OS receipts required'
state=b.query(b.write('push-final-state.sql',"select android_push_enabled as enabled,(select count(*)from fr30_private.push_devices)as registrations,(select count(*)from fr30_private.push_devices where user_id<>"+str(customer)+")as other_owner_registrations,(select is_blocked from public.users where id="+str(customer)+")as fixture_blocked from fr30_private.limits where singleton;"))['rows'][0]
assert state['enabled']and state['registrations']==1 and state['other_owner_registrations']==0 and not state['fixture_blocked'],'Restored own device registration required'
result={'scenarios':checks,'os_checks':os_checks,'restored_test_state':state,'private_credentials_disclosed':False,'production_touched':False}
(b.OUT/'push-final-verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'persisted_scenarios_passed':len(checks),'final_apk_os_modes_passed':3,'trusted_audits_and_snapshot_counts':True,'fixture_restored':True,'one_authorized_registration':True}))
