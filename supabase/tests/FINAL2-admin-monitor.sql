-- Authenticated-role SQL fixtures only; all data and candidate DDL roll back.
-- Synthetic locations do not constitute physical movement evidence.
begin;
-- FINAL2_CANDIDATE
create temporary table monitor_people(label text primary key,id bigint,auth_id uuid,session_id uuid,email text);
create temporary table monitor_results(label text);
create temporary table monitor_state(order_id bigint,portion_id bigint,request_id uuid,assignment_id bigint);
insert into monitor_state(request_id)values(gen_random_uuid());
do $$declare label text;aid uuid;uid bigint;sid uuid;mail text;begin
 foreach label in array array['customer','vendor','rider','rider2','admin']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();mail:='final2-monitor-'||label||'-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,mail,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{}');
  insert into public.users(auth_user_id,email,name,phone,role,verification_status)
   values(aid,mail,'FINAL2 MONITOR SQL ONLY','123456',case when label='rider2'then'rider'else label end,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after)values(sid,aid,now(),now(),clock_timestamp()+interval '1 hour');
  insert into monitor_people values(label,uid,aid,sid,mail);
 end loop;
 insert into public.vendors(user_id,store_name,latitude,longitude)
  select id,'FINAL2 MONITOR SQL ONLY',-60,-140 from monitor_people mp where mp.label='vendor';
 insert into public.riders(userid,is_online,is_available,isavailable,last_seen,latitude,longitude,location_updated_at)
  select id,true,true,true,clock_timestamp(),-59.88,-140,clock_timestamp()from monitor_people mp where mp.label in('rider','rider2');
 update public.riders set latitude=-59.87 where userid=(select id from monitor_people mp where mp.label='rider2');
end$$;
create function pg_temp.monitor_claim(who text)returns void language plpgsql security definer as $$declare person monitor_people;begin
 select *into person from monitor_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_id,'role','authenticated','session_id',person.session_id,
  'email',person.email,'exp',extract(epoch from clock_timestamp()+interval '1 hour')::bigint)::text,true);
end$$;
create function pg_temp.monitor_ok(value boolean,label text)returns void language plpgsql security definer as $$begin
 if value is distinct from true then raise exception 'Admin monitor assertion failed: %',label;end if;
 insert into monitor_results values(label);end$$;
create function pg_temp.monitor_ready()returns bigint language plpgsql security definer as $$declare oid bigint;begin
 insert into public.orders(user_id,order_status,amount,payment_method,delivery_address,requires_manual_assignment)
  values((select id from monitor_people where label='customer'),'ready',12.25,'COD','FINAL2 SQL MONITOR NEGATIVE ONLY',true)returning id into oid;
 insert into public.vendor_orders(order_id,vendor_id,status,sub_total)
  values(oid,(select id from monitor_people where label='vendor'),'ready',12.25);
 return oid;end$$;
grant execute on function pg_temp.monitor_claim(text),pg_temp.monitor_ok(boolean,text)to authenticated,anon;
grant execute on function pg_temp.monitor_ready()to authenticated;
grant select on monitor_people to authenticated;
grant all on monitor_state to authenticated;

do $$declare oid bigint;vo bigint;begin
 insert into public.orders(user_id,order_status,amount,payment_method,delivery_address)
  values((select id from monitor_people where label='customer'),'preparing',25.75,'COD','FINAL2 SQL MONITOR ONLY')returning id into oid;
 insert into public.vendor_orders(order_id,vendor_id,status,sub_total)
  values(oid,(select id from monitor_people mp where mp.label='vendor'),'preparing',25.75)returning id into vo;
 update monitor_state set order_id=oid,portion_id=vo;
end$$;
set local role authenticated;
select pg_temp.monitor_claim('vendor');
do $$declare r jsonb;begin
 r:=public.fr21_ready_and_assign((select portion_id from monitor_state));
 perform pg_temp.monitor_ok(r->>'code'='NO_RIDER_AVAILABLE'and(r->>'manual_assignment')::boolean,'real 5/10km matching escalates before Admin intervention');
end$$;
select pg_temp.monitor_claim('admin');
do $$declare r jsonb;oid bigint:=(select order_id from monitor_state);begin
 r:=public.final2_admin_assignment_candidates(oid);
 perform pg_temp.monitor_ok(r->>'code'='OK'and jsonb_array_length(r->'candidates')=2
  and(r#>>'{candidates,0,rider_id}')::bigint=(select id from monitor_people where label='rider')
  and(r#>>'{candidates,0,distance_m}')::numeric>10000,'escalated order returns eligible Riders in actual nearest-distance order beyond automatic radius');
 r:=public.final2_admin_order_monitor(p_limit=>1);
 perform pg_temp.monitor_ok(r->>'code'='OK'and jsonb_array_length(r->'orders')=1 and(r->>'has_more')::boolean,'bounded monitoring page returns truthful continuation');
 r:=public.final2_admin_order_monitor(p_status=>'preparing');
 perform pg_temp.monitor_ok(not exists(select 1 from jsonb_array_elements(r->'orders')v where v->>'status'<>'preparing'),'status filter applies to actual rows');
 r:=public.final2_admin_order_monitor(p_from=>clock_timestamp()+interval '1 day');
 perform pg_temp.monitor_ok((r#>>'{summary,total_orders}')::bigint=0 and jsonb_array_length(r->'orders')=0,'empty date window has zero actual orders');
 r:=public.final2_admin_order_monitor(p_from=>clock_timestamp()-interval '1 day',p_export=>true);
 perform pg_temp.monitor_ok((r->>'export_complete')::boolean and jsonb_array_length(r->'orders')=(r#>>'{summary,total_orders}')::bigint,'single-snapshot full filtered export reconciles exactly with counts');
 begin perform public.final2_admin_order_monitor(p_status=>'not-a-status');raise exception 'Invalid filter permitted';exception when invalid_parameter_value then null;end;
 begin perform public.final2_admin_order_monitor(p_limit=>201);raise exception 'Unbounded page permitted';exception when invalid_parameter_value then null;end;
 perform pg_temp.monitor_ok(true,'server rejects unknown filters and excessive page limits');
 r:=public.final2_admin_assign_rider(oid,(select id from monitor_people where label='rider'),(select request_id from monitor_state));
 perform pg_temp.monitor_ok(r->>'code'='ASSIGNED','approved Admin explicitly assigns eligible Rider after escalation');
 update monitor_state set assignment_id=(r->>'assignment_id')::bigint;
 r:=public.final2_admin_assign_rider(oid,(select id from monitor_people where label='rider'),(select request_id from monitor_state));
 perform pg_temp.monitor_ok(r->>'code'='ALREADY_APPLIED'and(r->>'assignment_id')::bigint=(select assignment_id from monitor_state),'unchanged uncertain-result retry returns the original assignment receipt');
 begin perform public.final2_admin_assign_rider(oid,(select id from monitor_people mp where mp.label='rider2'),(select request_id from monitor_state));raise exception 'Changed retry permitted';exception when sqlstate 'PT409'then null;end;
 perform pg_temp.monitor_ok(true,'same request cannot replace the originally selected Rider');
 r:=public.final2_admin_assign_rider(oid,(select id from monitor_people mp where mp.label='rider2'),gen_random_uuid());
 perform pg_temp.monitor_ok(r->>'code'='ORDER_CHANGED','second Admin decision cannot overwrite the existing assignment');
end$$;
reset role;
do $$declare oid bigint:=(select order_id from monitor_state);aid bigint:=(select assignment_id from monitor_state);begin
 perform pg_temp.monitor_ok((select count(*)from public.rider_assignments where orderid=oid and status='Pending')=1
  and(select order_status from public.orders where id=oid)='ready'
  and not(select requires_manual_assignment from public.orders where id=oid),'manual assignment reserves exactly one Pending request without fabricating acceptance/departure');
 perform pg_temp.monitor_ok((select count(*)from public.notifications where rider_assignment_id=aid)=1
  and(select count(*)from public.security_audit_log where target_type='orders'and target_id=oid and action='RIDER_MANUALLY_ASSIGNED')=1,
  'exactly one assignment notice and one canonical critical Admin audit survive retries');
 perform pg_temp.monitor_ok((select actor_id from public.security_audit_log where target_type='orders'and target_id=oid and action='RIDER_MANUALLY_ASSIGNED')=(select id from monitor_people where label='admin'),
  'manual assignment audit actor is the real canonical Admin');
 update public.riders set location_updated_at=clock_timestamp()-interval '3 minutes'where userid=(select id from monitor_people mp where mp.label='rider2');
end$$;
set local role authenticated;
select pg_temp.monitor_claim('admin');
do $$declare r jsonb;begin
 r:=public.final2_admin_order_monitor();
 perform pg_temp.monitor_ok(not exists(select 1 from jsonb_array_elements(r->'rider_locations')v where(v->>'rider_id')::bigint=(select id from monitor_people mp where mp.label='rider2')),
  'stale Rider coordinates are excluded from the live map');
 begin perform 1 from final2_private.manual_assignments;raise exception 'Raw receipt access permitted';exception when insufficient_privilege then null;end;
 perform pg_temp.monitor_ok(true,'even Admin client cannot read the raw private assignment ledger');
end$$;
do $$declare who text;begin
 foreach who in array array['customer','vendor','rider']loop
  perform pg_temp.monitor_claim(who);
  begin perform public.final2_admin_order_monitor();raise exception 'Non-Admin monitor permitted';exception when insufficient_privilege then null;end;
  begin perform public.final2_admin_assignment_candidates((select order_id from monitor_state));raise exception 'Non-Admin candidates permitted';exception when insufficient_privilege then null;end;
  begin perform public.final2_admin_assign_rider((select order_id from monitor_state),(select id from monitor_people mp where mp.label='rider2'),gen_random_uuid());raise exception 'Non-Admin assignment permitted';exception when insufficient_privilege then null;end;
  perform pg_temp.monitor_ok(true,who||' cannot read protected monitoring/candidates or assign Riders');
 end loop;end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=(select id from monitor_people where label='admin');
set local role authenticated;
select pg_temp.monitor_claim('admin');
do $$begin begin perform public.final2_admin_order_monitor();raise exception 'Blocked Admin permitted';exception when insufficient_privilege then null;end;
 perform pg_temp.monitor_ok(true,'blocked Admin loses protected monitoring access');end$$;
reset role;
do $$declare oid bigint;r jsonb;which text;rid bigint:=(select id from monitor_people where label='rider2');begin
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set is_blocked=false where id=(select id from monitor_people where label='admin');
 perform pg_temp.monitor_claim('admin');
 oid:=pg_temp.monitor_ready();
 r:=public.final2_admin_assign_rider(oid,(select id from monitor_people where label='rider'),gen_random_uuid());
 perform pg_temp.monitor_ok(r->>'code'='RIDER_CHANGED','busy Rider cannot be assigned to a second active order');
 update public.orders set requires_manual_assignment=false where id=oid;
 r:=public.final2_admin_assign_rider(oid,rid,gen_random_uuid());
 perform pg_temp.monitor_ok(r->>'code'='ORDER_CHANGED','Admin cannot bypass the required prior escalation');
 update public.orders set requires_manual_assignment=true where id=oid;
 foreach which in array array['offline','blocked','stale','missing-location']loop
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  update public.users set is_blocked=(which='blocked')where id=rid;
  update public.riders set is_online=(which<>'offline'),last_seen=clock_timestamp(),
   location_updated_at=case when which='stale'then clock_timestamp()-interval '3 minutes'else clock_timestamp()end,
   latitude=case when which='missing-location'then null else -59.87 end where userid=rid;
  perform pg_temp.monitor_claim('admin');
  r:=public.final2_admin_assign_rider(oid,rid,gen_random_uuid());
  perform pg_temp.monitor_ok(r->>'code'='RIDER_CHANGED',which||' Rider fails confirmation-time eligibility recheck');
 end loop;
 begin perform public.final2_admin_assign_rider(oid,rid,null);raise exception 'Missing request accepted';exception when invalid_parameter_value then null;end;
 perform pg_temp.monitor_ok((select count(*)from final2_private.manual_assignments where order_id=oid)=0
  and(select rider_id from public.orders where id=oid)is null,'validation and eligibility failures leave order and private receipts unchanged');
end$$;
set local role anon;
do $$begin begin perform public.final2_admin_order_monitor();raise exception 'Anonymous monitoring permitted';exception when insufficient_privilege then null;end;end$$;
reset role;
insert into monitor_results values('anonymous monitoring denied');
set local role authenticated;
select pg_temp.monitor_claim('customer');
do $$begin perform pg_temp.monitor_ok((select count(*)from public.riders where userid in(select id from monitor_people where label in('rider','rider2')))=0,
 'Customer RLS cannot observe private Rider publication rows');end$$;
select pg_temp.monitor_claim('vendor');
do $$begin perform pg_temp.monitor_ok((select count(*)from public.riders where userid in(select id from monitor_people where label in('rider','rider2')))=0,
 'Vendor RLS cannot observe private Rider publication rows');end$$;
select pg_temp.monitor_claim('rider');
do $$begin perform pg_temp.monitor_ok((select count(*)from public.riders where userid in(select id from monitor_people where label in('rider','rider2')))=1,
 'Rider RLS can observe only its own publication row');end$$;
select pg_temp.monitor_claim('admin');
do $$begin perform pg_temp.monitor_ok((select count(*)from public.riders where userid in(select id from monitor_people where label in('rider','rider2')))=2,
 'approved Admin RLS can observe monitored Rider publication rows');end$$;
reset role;
do $$begin perform pg_temp.monitor_ok(exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='public'and tablename='riders')
 and exists(select 1 from pg_policies where schemaname='public'and tablename='riders'and policyname='fr21_test_riders_read'and permissive='RESTRICTIVE')
 and exists(select 1 from pg_policies where schemaname='public'and tablename='riders'and policyname='fr28_session_guard'and permissive='RESTRICTIVE'),
 'Rider publication retains restrictive ownership/Admin and current-session policies');end$$;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated-role TEST SQL rollback'))as results from monitor_results;
rollback;
