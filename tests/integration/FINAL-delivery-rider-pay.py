"""TEST-only reviewed additive migration and rollback/authenticated verification.

Reuses accepted secured checkout/checklist/OTP fixture; no actual email/GPS/cash.
Credentials and JWT-bearing generated SQL remain in ignored private evidence.
"""
import base64,hashlib,importlib.util,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'.fr21-local/final-delivery';OUT.mkdir(parents=True,exist_ok=True)
REF='igeisilhtmglgnqvllrx';VERSION='202610250006'
def module(name,file):
 s=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
b=module('pay_backend','FR-04-hosted.py');db=module('pay_guarded_db','FINAL-security.py');db.OUT=OUT
b.target();action=sys.argv[1];assert action in('review','deploy','post','hosted')
migration=ROOT/'supabase/migrations/202610250006_final_delivery_rider_earnings.sql'
digest=hashlib.sha256(migration.read_bytes()).hexdigest();checks=[]
def check(ok,label,surface='actual authenticated TEST HTTP'):
 assert ok,label
 checks.append({'check':label,'result':'PASS','surface':surface})
 print(json.dumps(checks[-1]),flush=True)
 (OUT/('rider-pay-'+action+'-results.json')).write_text(json.dumps(checks,indent=2)+'\n',encoding='utf-8')
history=OUT/'rider-pay-history.sql'
history.write_text('begin read only; select version from supabase_migrations.schema_migrations order by version; rollback;',encoding='utf-8')
actual=[r['version']for r in db.query(history)]
known=sorted(p.name.split('_')[0]for p in(ROOT/'supabase/migrations').glob('*.sql'))
assert actual==known[:len(actual)],'Unexpected migration prefix; stop instead of replay'
if action in('review','deploy'):assert VERSION not in actual and actual==[v for v in known if v<VERSION]
else:assert VERSION in actual
if action=='deploy':
 proof=json.loads((OUT/'rider-pay-review-proof.json').read_text())
 assert proof['rolled_back']and proof['migration_sha256']==digest and proof['passed']>=25
 source=migration.read_text(encoding='utf-8');assert source.count('commit;')==1
 assert not re.search(r'\b(drop|truncate)\b|disable\s+row',source,re.I)
 source=source.replace('commit;',"insert into supabase_migrations.schema_migrations(version,name)values('"+VERSION+"','final_delivery_rider_earnings');commit;")
 path=OUT/'rider-pay-deploy.sql';path.write_text(source,encoding='utf-8');db.query(path)
 assert [r['version']for r in db.query(history)]==[v for v in known if v<=VERSION]
 (OUT/'rider-pay-deployment.json').write_text(json.dumps({'project':REF,'version':VERSION,'migration_sha256':digest,'versions':len(actual)+1,'production_modified':False,'replayed':False},indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'deployment':'CONFIRMED','project':REF,'version':VERSION,'versions':len(actual)+1}));sys.exit(0)
state=json.loads(b.crypt((ROOT/'.fr21-local/final2/onboarding-accounts.dpapi').read_bytes(),True))
legacy=json.loads(b.crypt((b.PRIVATE/'fr28-accounts.bin').read_bytes(),True))['accounts']
tokens={
 'VENDOR':b.login(state['accounts']['live-vendor']),
 'CUSTOMER':b.login(state['accounts']['review-customer']),
 'ADMIN':b.login(legacy['admin']),'OTHER':b.login(legacy['customer']),
 'OTHER_VENDOR':b.login(legacy['vendor']),'RIDER':b.login(legacy['rider']),
}
def claims(token):
 p=token.split('.')[1];return json.loads(base64.urlsafe_b64decode(p+'='*(-len(p)%4)))
def gateway(name,token,data):
 return b.api('/functions/v1/security-gateway','POST',{'method':'POST','path':'/rpc/'+name,'query':'','headers':{'content-type':'application/json'},'body':json.dumps(data)},token)
if action in('review','post'):
 source=(ROOT/'supabase/tests/FINAL2-order-detail.sql').read_text(encoding='utf-8-sig')
 setup="""
-- Synthetic pickup coordinates only inside rollback; not physical GPS evidence.
update public.vendors set latitude=33.68,longitude=73.04 where user_id in(
 select id from public.users where auth_user_id in((__VENDOR_CLAIMS__::jsonb->>'sub')::uuid,(__OTHER_VENDOR_CLAIMS__::jsonb->>'sub')::uuid));
"""
 candidate=re.sub(r'(?m)^(begin|commit);\s*$','',migration.read_text(encoding='utf-8'))if action=='review'else''
 source=source.replace('-- FINAL2_CANDIDATE',candidate+'\n'+setup)
 prequote="""
-- Older accepted fixture Vendor may lack its later-onboarding store row.
-- Supply synthetic store coordinates only within this rolled-back test.
insert into public.vendors(user_id,store_name,latitude,longitude,address)
 select p.vendor_id,'Synthetic rollback pickup',33.68,73.04,'Synthetic rollback only'
 from public.vendor_orders p where p.order_id=(select oid from final2_history_state)
 and not exists(select 1 from public.vendors v where v.user_id=p.vendor_id);
update public.vendors set latitude=33.68,longitude=73.04 where user_id in(
 select vendor_id from public.vendor_orders where order_id=(select oid from final2_history_state));
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$declare q jsonb;begin
 q:=public.final_delivery_rider_quote((select oid from final2_history_state));
 if q->>'code'is distinct from'OK'then raise exception 'Pre-accept quote unavailable: %',q->>'reason';end if;
 if(q->>'frozen')::boolean then raise exception 'Pre-start quote incorrectly frozen';end if;
 if(q->>'expected_amount')::numeric<>80 then raise exception 'Synthetic minimum quote mismatch';end if;
 if q->>'distance_method'<>'straight_line'then raise exception 'Pre-start method incorrect';end if;
 insert into final2_history_results values('assigned Rider sees server-side minimum PKR80 quote before accepting; synthetic identical vendor/destination, no road claim');
end$$;
reset role;
-- Synthetic provider-cache fixture tests pricing only, not routing/GPS acceptance.
insert into public.delivery_route_cache(order_id,data,origin_lat,origin_lng,destination_lat,destination_lng,computed_at,expires_at)
 select oid,'{"source":"geoapify","isApproximate":false,"distanceMeters":2125,"geometry":{"type":"LineString","coordinates":[[73.04,33.68],[73.05,33.68],[73.04,33.68]]}}',
 33.68,73.04,33.68,73.04,clock_timestamp(),clock_timestamp()+interval '1 minute'from final2_history_state;
do $$declare q jsonb;begin
 q:=final_delivery_private.calculate_quote((select oid from final2_history_state),1);
 if q->>'distance_method'<>'route'or(q->>'expected_amount')::numeric<>103
  or(q->>'distance_amount')::numeric<>42.5 then raise exception 'Route rate or nearest-PKR rounding incorrect';end if;
 insert into final2_history_results values('synthetic vendor-origin FR14 cache uses base60 plus 20/km and rounds 2.125km from102.5 to103 PKR; no provider/GPS claim');
end$$;
delete from public.delivery_route_cache where order_id=(select oid from final2_history_state);
update public.rider_assignments set status='Accepted'where id=(select assignment from final2_history_state);
"""
 needle='update final2_history_state set assignment=aid;\nend$$;'
 assert needle in source;source=source.replace(needle,needle+'\n'+prequote,1)
 source=source.replace("values(s.oid,rider,'Accepted')returning id into aid;","values(s.oid,rider,'Pending')returning id into aid;",1)
 cancel_prefix=source.split('-- A controlled accepted challenge tests only the existing trusted verification',1)[0]
 extension=(ROOT/'supabase/tests/FINAL-delivery-rider-pay.sql').read_text(encoding='utf-8')
 source=source.replace("select jsonb_agg(jsonb_build_object('check',label",extension+"\nselect jsonb_agg(jsonb_build_object('check',label",1)
 for key,token in tokens.items():source=source.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
 source=source.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
 path=OUT/'rider-pay-review.private.sql';path.write_text(source,encoding='utf-8')
 for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 for cancel_role in('CUSTOMER','VENDOR'):
  cancellation=cancel_prefix+(ROOT/'supabase/tests/FINAL-delivery-rider-cancel.sql').read_text(encoding='utf-8')
  cancellation=cancellation.replace('__CANCEL_CLAIMS__','__'+cancel_role+'_CLAIMS__').replace('__CANCEL_ROLE_NAME__',cancel_role)
  for key,token in tokens.items():cancellation=cancellation.replace('__'+key+'_CLAIMS__',"'"+json.dumps(claims(token)).replace("'","''")+"'")
  cancellation=cancellation.replace('__VENDOR_ID__',str(state['live_vendor_profile_id']))
  path=OUT/('rider-pay-cancel-'+cancel_role.lower()+'.private.sql');path.write_text(cancellation,encoding='utf-8')
  for row in db.query(path)[0]['results']:check(row['result']=='PASS',row['check'],row['surface'])
 (OUT/('rider-pay-'+action+'-proof.json')).write_text(json.dumps({'project':REF,'passed':len(checks),'migration_sha256':digest,'rolled_back':True},indent=2)+'\n',encoding='utf-8')
elif action=='hosted':
 code,value=gateway('final_delivery_rider_earnings',tokens['RIDER'],{})
 check(code==200 and value['code']=='OK'and value['earnings_only']is True,'live approved Rider reads own actual earnings ledger without payout claim')
 rid=value['rider_id'];total=value['total_amount']
 code,value2=gateway('final_delivery_rider_earnings',tokens['ADMIN'],{'p_rider_id':rid})
 check(code==200 and value2['total_amount']==total,'approved Admin selected Rider total agrees with owner endpoint')
 for key in('CUSTOMER','VENDOR','OTHER_VENDOR'):
  code,_=gateway('final_delivery_rider_earnings',tokens[key],{'p_rider_id':rid});check(code==403,key+' earnings access denied')
 code,_=gateway('final_delivery_rider_earnings',None,{});check(code in(401,403),'anonymous earnings access denied')
 code,_=gateway('final_delivery_rider_earnings',tokens['RIDER'],{'p_rider_id':state['live_vendor_profile_id']});check(code==403,'Rider cannot select unrelated private account')
 code,_=gateway('final_delivery_rider_earnings',tokens['RIDER'],{'p_limit':0});check(code==400,'invalid earnings page rejected server-side')
 code,metrics=gateway('final2_rider_performance',tokens['RIDER'],{})
 check(code==200 and metrics['earned_fee_cents']==round(total*100)and metrics['fee_status'].startswith('RECORDED'),'existing performance returns actual recorded earnings with explicit historical gaps')
