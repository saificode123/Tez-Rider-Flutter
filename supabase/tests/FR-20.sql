-- Run on an isolated schema/TEST in one rollback transaction. Genuine races
-- are separate HTTP/session tests; these assertions do not simulate concurrency.
begin;
create temp table fr20_results(name text,result text);
create function pg_temp.ok(value boolean,label text)returns void language plpgsql security definer as $$begin
 if value is distinct from true then raise exception 'FR20 assertion failed: %',label;end if;
 insert into fr20_results values(label,'PASS');end$$;
create temp table fr20_people(label text,id bigint,auth_id uuid,session_id uuid,email text);
do $$declare fixture_label text;aid uuid;uid bigint;sid uuid;email text;begin
 foreach fixture_label in array array['vendor','other-vendor','customer','rider','rider2','admin']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();email:='fr20-sql-'||fixture_label||'-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
   values(aid,email,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"fr20_fixture":true}');
  insert into public.users(email,name,role,verification_status)values(email,'FR20 SQL SYNTHETIC',case when fixture_label='other-vendor'then 'vendor'when fixture_label='rider2'then 'rider'else fixture_label end,'approved')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,now(),now());
  insert into fr20_people values(fixture_label,uid,aid,sid,email);
 end loop;
 insert into public.vendors(user_id,store_name,latitude,longitude)select id,'FR20 SQL SYNTHETIC',-60,-140 from fr20_people where label='vendor';
 insert into public.riders(userid,is_online,last_seen,latitude,longitude,location_updated_at)
  select id,true,clock_timestamp(),-60,-140,clock_timestamp()from fr20_people where label in('rider','rider2');
end$$;
create function pg_temp.claim(label text)returns void language plpgsql security definer as $$declare person fr20_people;begin
 select * into person from fr20_people p where p.label=claim.label;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',person.auth_id,'role','authenticated','session_id',person.session_id,'email',person.email)::text,true);
end$$;
create function pg_temp.neworder()returns bigint language plpgsql security definer as $$declare o bigint;vo bigint;begin
 insert into public.orders(user_id,order_status,amount,payment_method,delivery_address)
  values((select id from fr20_people where label='customer'),'preparing',25,'COD','FR20 SQL SYNTHETIC')returning id into o;
 insert into public.vendor_orders(order_id,vendor_id,status,sub_total)values(o,(select id from fr20_people where label='vendor'),'preparing',25)returning id into vo;
 return vo;end$$;
create function pg_temp.position(meters double precision,which text default 'rider')returns void language plpgsql security definer as $$declare point extensions.geometry;claims text:=current_setting('request.jwt.claims',true);begin
 point:=extensions.st_project(extensions.st_setsrid(extensions.st_makepoint(-140,-60),4326)::extensions.geography,meters,0)::extensions.geometry;
 update public.riders set latitude=extensions.st_y(point),longitude=extensions.st_x(point),is_online=true,is_available=true,isavailable=true,last_seen=clock_timestamp(),location_updated_at=clock_timestamp()where userid=(select id from fr20_people where label=which);
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set verification_status='approved',is_blocked=false where id=(select id from fr20_people where label=which);
 perform set_config('request.jwt.claims',coalesce(claims,'{}'),true);
end$$;
create function pg_temp.cancel(vo bigint)returns void language plpgsql security definer as $$begin
 update public.orders set order_status='cancelled'where id=(select order_id from public.vendor_orders where id=vo);
end$$;
grant execute on function pg_temp.ok(boolean,text),pg_temp.claim(text),pg_temp.neworder(),pg_temp.position(double precision,text),pg_temp.cancel(bigint)to authenticated,anon;
grant select on fr20_people to authenticated;

do $$declare who text;vo bigint:=pg_temp.neworder();res jsonb;begin
 foreach who in array array['other-vendor','customer','rider','admin']loop
  perform pg_temp.claim(who);res:=public.fr21_ready_and_assign(vo);perform pg_temp.ok(res->>'code'='FORBIDDEN',who||' cannot invoke vendor assignment');
 end loop;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);update public.users set is_blocked=true where id=(select id from fr20_people where label='vendor');perform pg_temp.claim('vendor');
 res:=public.fr21_ready_and_assign(vo);perform pg_temp.ok(res->>'code'='FORBIDDEN','blocked vendor denied');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);update public.users set is_blocked=false where id=(select id from fr20_people where label='vendor');perform pg_temp.claim('vendor');
end$$;
set local role anon;
do $$begin begin perform public.fr21_ready_and_assign(1);raise exception 'Anonymous allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'anonymous execute denied');end;end$$;
reset role;
select pg_temp.claim('vendor');
set local role authenticated;
do $$begin
 begin insert into public.rider_assignments(riderid,orderid)values(1,1);raise exception 'Direct insert allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'direct assignment insert denied');end;
 begin insert into public.notifications(user_id,title,message)values(1,'forged','forged');raise exception 'Forged notification allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'notification forgery denied');end;
 begin insert into public.security_audit_log(action,target_type,target_id)values('forged','order',1);raise exception 'Forged audit allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'audit forgery denied');end;
end$$;
reset role;

do $$declare meters double precision;vo bigint;res jsonb;oid bigint;rid bigint;count_before bigint;begin
 select id into rid from fr20_people where label='rider';perform pg_temp.position(20000,'rider2');
 foreach meters in array array[4900,5000,5100,7000,10000,10001]loop
  perform pg_temp.position(meters);vo:=pg_temp.neworder();res:=public.fr21_ready_and_assign(vo);select order_id into oid from public.vendor_orders where id=vo;
  perform pg_temp.ok(res->>'code'=case when meters<=5000 then 'ASSIGNED_5KM'when meters<=10000 then 'ASSIGNED_10KM'else 'NO_RIDER_AVAILABLE'end,'distance '||meters||' meters');
  if meters<=10000 then
   perform pg_temp.ok((select count(*)=1 from public.rider_assignments where orderid=oid and riderid=rid),'one assignment at '||meters);
   perform pg_temp.ok((select count(*)=1 from public.notifications where assignment_order_id=oid and user_id=rid and message='New delivery job assigned.'and rider_assignment_id=(res->>'assignment_id')::bigint),'exact rider notification at '||meters);
   perform pg_temp.ok((select order_status='on_the_way'and rider_id=rid and delivery_otp is null from public.orders where id=oid),'atomic parent/OTP status at '||meters);
   perform pg_temp.ok(public.fr21_ready_and_assign(vo)->>'code'='ALREADY_ASSIGNED','idempotent assignment at '||meters);
   perform pg_temp.ok((select count(*)=1 from public.security_audit_log where assignment_order_id=oid and action='RIDER_ASSIGNED'and actor_id=(select id from fr20_people where label='vendor')),'assignment audit at '||meters);
  else
   perform pg_temp.ok((res->>'admin_notified')::boolean,'escalation receipt confirms persisted recipient notification');
   perform pg_temp.ok((select requires_manual_assignment and rider_id is null and order_status='ready'from public.orders where id=oid),'no-rider preserves ready state');
   select count(*)into count_before from public.notifications where assignment_order_id=oid and assignment_event='manual_assignment';
   perform pg_temp.ok(count_before=(select count(*)from public.users where role='admin'and verification_status='approved'and not is_blocked),'every eligible admin notified');
   perform public.fr21_ready_and_assign(vo);
   perform pg_temp.ok((select count(*)=count_before from public.notifications where assignment_order_id=oid and assignment_event='manual_assignment'),'escalation retry deduplicated');
   perform pg_temp.ok((select count(*)=1 from public.security_audit_log where assignment_order_id=oid and action='RIDER_ASSIGNMENT_ESCALATED'),'escalation audit once');
   perform pg_temp.position(4900);res:=public.fr21_ready_and_assign(vo);
   perform pg_temp.ok(res->>'code'='ASSIGNED_5KM'and(select not requires_manual_assignment from public.orders where id=oid),'later success clears manual flag');
  end if;
  perform pg_temp.cancel(vo);
 end loop;
end$$;

do $$declare reason text;vo bigint;res jsonb;rid bigint;busy bigint;begin
 select id into rid from fr20_people where label='rider';perform pg_temp.position(20000,'rider2');
 foreach reason in array array['offline','unverified','blocked','stale-heartbeat','stale-location','missing-location','unavailable','busy']loop
  perform pg_temp.position(4900);vo:=pg_temp.neworder();
  if reason='offline'then update public.riders set is_online=false where userid=rid;
  elsif reason='unverified'then update public.users set verification_status='pending'where id=rid;
  elsif reason='blocked'then perform set_config('request.jwt.claims','{"role":"service_role"}',true);update public.users set is_blocked=true where id=rid;perform pg_temp.claim('vendor');
  elsif reason='stale-heartbeat'then update public.riders set last_seen=clock_timestamp()-interval '121 seconds'where userid=rid;
  elsif reason='stale-location'then update public.riders set location_updated_at=clock_timestamp()-interval '121 seconds'where userid=rid;
  elsif reason='missing-location'then update public.riders set latitude=null where userid=rid;
  elsif reason='unavailable'then update public.riders set isavailable=false where userid=rid;
  else insert into public.orders(user_id,rider_id,order_status,amount,delivery_address)values((select id from fr20_people where label='customer'),rid,'on_the_way',25,'FR20 SQL SYNTHETIC')returning id into busy;end if;
  res:=public.fr21_ready_and_assign(vo);perform pg_temp.ok(res->>'code'='NO_RIDER_AVAILABLE',reason||' rider excluded');
  perform pg_temp.cancel(vo);if busy is not null then update public.orders set order_status='cancelled'where id=busy;busy:=null;end if;
 end loop;
end$$;

do $$declare vo bigint;res jsonb;oid bigint;rid bigint;rid2 bigint;other_vo bigint;begin
 select id into rid from fr20_people where label='rider';select id into rid2 from fr20_people where label='rider2';
 perform pg_temp.position(4900);perform pg_temp.position(4800,'rider2');vo:=pg_temp.neworder();res:=public.fr21_ready_and_assign(vo);
 perform pg_temp.ok((res->>'rider_id')::bigint=rid2,'nearest rider selected');perform pg_temp.cancel(vo);
 perform pg_temp.position(4900);perform pg_temp.position(4900,'rider2');vo:=pg_temp.neworder();res:=public.fr21_ready_and_assign(vo);
 perform pg_temp.ok((res->>'rider_id')::bigint=least(rid,rid2),'stable identifier tie break');
 oid:=(res->>'order_id')::bigint;
 insert into public.vendor_orders(order_id,vendor_id,status,sub_total)values(oid,(select id from fr20_people where label='other-vendor'),'accepted',25)returning id into other_vo;
 perform pg_temp.claim('other-vendor');res:=public.fr21_ready_and_assign(other_vo);
 perform pg_temp.ok(res->>'code'='ALREADY_ASSIGNED'and(select status='on_the_way'from public.vendor_orders where id=other_vo),'own second vendor child advances on assigned shared parent');
 perform pg_temp.ok((select count(*)=1 from public.rider_assignments where orderid=oid)and(select count(*)=1 from public.notifications where assignment_order_id=oid and assignment_event='rider_assigned'),'shared-parent ready emits no duplicate assignment/notice');
 perform pg_temp.claim('vendor');
 begin insert into public.rider_assignments(riderid,orderid,status)values(greatest(rid,rid2),oid,'Pending');raise exception 'Duplicate active order allowed';exception when unique_violation then perform pg_temp.ok(true,'active order unique invariant');end;
 begin insert into public.rider_assignments(riderid,orderid,status)values(least(rid,rid2),(select order_id from public.vendor_orders where id=pg_temp.neworder()),'Pending');raise exception 'Duplicate active rider allowed';exception when unique_violation then perform pg_temp.ok(true,'active rider unique invariant');end;
 perform pg_temp.cancel(vo);vo:=pg_temp.neworder();select order_id into oid from public.vendor_orders where id=vo;
 update public.orders set order_status='delivered'where id=oid;res:=public.fr21_ready_and_assign(vo);
 perform pg_temp.ok(res->>'code'='INVALID_ORDER_STATE'and(select order_status='delivered'from public.orders where id=oid),'closed order unchanged');
 vo:=pg_temp.neworder();update public.vendors set latitude=null where user_id=(select id from fr20_people where label='vendor');res:=public.fr21_ready_and_assign(vo);
 perform pg_temp.ok(res->>'code'='PICKUP_LOCATION_REQUIRED'and(select status='preparing'from public.vendor_orders where id=vo),'missing pickup no false escalation/transition');
 perform pg_temp.ok(public.fr20_assignment_status(vo)->>'code'='UNASSIGNED','read-only reconciliation does not assign');
end$$;
select jsonb_agg(jsonb_build_object('name',name,'result',result))as results from fr20_results;
rollback;
