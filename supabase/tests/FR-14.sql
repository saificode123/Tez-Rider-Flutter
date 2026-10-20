-- Synthetic rollback-only database/security tests. No provider calls.
begin;
create temp table fr14_results(name text,result text);
create temp table fr14_people(label text,id bigint,auth_id uuid,session_id uuid);
create temp table fr14_fixture(oid bigint,aid bigint,rid bigint,cid bigint);
create temp table fr14_quota_baseline(n bigint);
insert into fr14_quota_baseline select count(*)from fr14_private.quota_reservations;
create function pg_temp.ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'FR14 assertion: %',label;end if;
 insert into fr14_results values(label,'PASS');end$$;
do $$declare who text;uid bigint;a uuid;s uuid;mail text;begin
 foreach who in array array['customer','other-customer','vendor','rider','other-rider','admin']loop
 a:=gen_random_uuid();s:=gen_random_uuid();mail:='fr14-sql-'||a||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(a,mail,now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values(mail,'FR14 SQL SYNTHETIC',case when who like'other-%'then substr(who,7)else who end,'approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
 insert into fr14_people values(who,uid,a,s);end loop;
end$$;
create function pg_temp.claim(who text)returns void language plpgsql security definer as $$declare p fr14_people;begin
 select *into p from fr14_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id)::text,true);
end$$;
do $$declare rid bigint;cid bigint;o bigint;a bigint;r jsonb;begin
 select id into rid from fr14_people where label='rider';select id into cid from fr14_people where label='customer';
 insert into public.riders(userid,is_online,is_available,isavailable,last_seen)values(rid,true,false,false,clock_timestamp());
 insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address,delivery_lat,delivery_lng,destination_source,destination_confirmed_at)
 values(cid,rid,'ready',1,'COD','FR14 SQL SYNTHETIC',33.71,73.06,'map_pin',clock_timestamp())returning id into o;
 insert into public.rider_assignments(orderid,riderid,status)values(o,rid,'Accepted')returning id into a;
 insert into fr14_fixture values(o,a,rid,cid);
 perform pg_temp.claim('rider');
 perform pg_temp.ok(public.fr14_route_context(o)->>'code'='FORBIDDEN','checklist required');
 perform public.submit_pre_delivery_checklist(a,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
 perform pg_temp.ok(public.fr14_route_context(o)->>'code'='FORBIDDEN','ready order not active delivery');
 perform public.start_checklisted_delivery(a);perform public.fr13_tracking_context(o,true);
 r:=public.fr13_submit_location(o,33.7,73.05,10,clock_timestamp(),gen_random_uuid());
 perform pg_temp.ok(r->>'code'='ACCEPTED','real FR13 trusted location submission reused');
end$$;
do $$declare f fr14_fixture;who text;r jsonb;again jsonb;saved jsonb;lease uuid;begin
 -- Assertion-only transaction: isolate simulated quota from real unsettled
 -- reservations, then the file's mandatory ROLLBACK restores every real row.
 -- Setup-only load fixtures stop before this block and never execute it.
 delete from fr14_private.quota_reservations;
 update fr14_quota_baseline set n=0;
 select *into f from fr14_fixture;
 foreach who in array array['customer','rider','admin']loop
  perform pg_temp.claim(who);perform pg_temp.ok(public.fr14_route_context(f.oid)->>'code'='OK',who||' authorized');end loop;
 foreach who in array array['other-customer','other-rider','vendor']loop
  perform pg_temp.claim(who);perform pg_temp.ok(public.fr14_route_context(f.oid)->>'code'='FORBIDDEN',who||' denied');end loop;
 perform set_config('request.jwt.claims','{}',true);perform pg_temp.ok(public.fr14_route_context(f.oid)->>'code'='FORBIDDEN','anonymous identity denied');
 r:=public.fr14_prepare(f.oid,f.cid,false);perform pg_temp.ok(r->>'code'='NOT_CONFIGURED','missing key avoids reservation');
 perform pg_temp.ok((select count(*)=(select n from fr14_quota_baseline)from fr14_private.quota_reservations),'missing key consumes no provider quota');
 r:=public.fr14_prepare(f.oid,f.cid,true);lease:=(r->>'lease')::uuid;
 perform pg_temp.ok(r->>'code'='COMPUTE'and r->'origin'='[73.05,33.7]'::jsonb and r->'destination'='[73.06,33.71]'::jsonb,'lease uses persisted FR13 origin and confirmed destination longitude first');
 again:=public.fr14_prepare(f.oid,f.cid,true);
 perform pg_temp.ok(again->>'code'='BUSY'and(select count(*)=(select n+1 from fr14_quota_baseline)from fr14_private.quota_reservations),'single flight reserves once');
 saved:=public.fr14_finish(f.oid,f.cid,lease,'{"geometry":{"type":"LineString","coordinates":[[73.05,33.7],[73.06,33.71]]},"distanceMeters":1600,"durationSeconds":240}');
 perform pg_temp.ok(saved->>'code'='OK','provider result accepted');
 perform pg_temp.ok((select route_estimated_arrival_at=(saved->'route'->>'estimatedArrivalAt')::timestamptz from public.orders where id=f.oid),'authoritative ETA and cache commit consistently');
 perform pg_temp.ok((saved->'route'->>'estimatedArrivalAt')::timestamptz between clock_timestamp()+interval '239 seconds'and clock_timestamp()+interval '241 seconds','ETA uses server calculation clock plus seconds');
 perform pg_temp.ok(public.fr14_prepare(f.oid,f.cid,true)->>'code'='CACHE','fresh route cache hit');
 perform pg_temp.ok(not has_function_privilege('service_role','fr14_private.prepare_locked(bigint,bigint,boolean)','EXECUTE'),'locked helper is not directly callable by service role');
 perform pg_temp.ok(public.fr14_prepare(f.oid,(select id from fr14_people where label='other-customer'),true)->>'code'='FORBIDDEN','fast cache path still checks ownership');
 update fr14_private.user_limits set requests=100,window_at=clock_timestamp()where actor=f.cid;
 perform pg_temp.ok(public.fr14_prepare(f.oid,f.cid,true)->>'code'='RATE_LIMIT','fast cache path retains per-actor rate limit');
 update fr14_private.user_limits set requests=1 where actor=f.cid;
 perform pg_temp.ok((select count(*)=(select n+1 from fr14_quota_baseline)from fr14_private.quota_reservations),'fast cache reads and denials reserve no extra provider credits');
 update public.delivery_route_cache set expires_at=clock_timestamp()-interval '1 second'where order_id=f.oid;
 perform pg_temp.ok(public.fr14_prepare(f.oid,f.cid,true)->>'code'='THROTTLED','expired cache respects minimum interval');
 update fr14_private.attempts set last_attempt_at=clock_timestamp()-interval '61 seconds'where order_id=f.oid;
 perform pg_temp.ok(public.fr14_prepare(f.oid,f.cid,true)->>'code'='COMPUTE','expiry recomputes after interval');
 perform public.fr14_finish(f.oid,f.cid,(select token from fr14_private.attempts where order_id=f.oid),null);
 perform pg_temp.ok((select units>=2800 from fr14_private.quota_reservations where token=(select token from fr14_private.attempts where order_id=f.oid)),'uncertain provider response consumes remaining daily budget conservatively');
 -- Restore only synthetic accounting within this rollback transaction so the
 -- remaining independent scenarios can be exercised without real API calls.
 update fr14_private.quota_reservations set units=2,settled=true;
 update public.delivery_route_cache set expires_at=clock_timestamp()+interval '4 minutes'where order_id=f.oid;
 update public.delivery_latest_locations set latitude=33.72 where order_id=f.oid;
 update fr14_private.attempts set last_attempt_at=clock_timestamp()-interval '61 seconds'where order_id=f.oid;
 r:=public.fr14_prepare(f.oid,f.cid,true);
 perform pg_temp.ok(r->>'code'='COMPUTE'and r->'cache'='null'::jsonb,'off-route movement does not serve misleading road geometry');
 perform public.fr14_finish(f.oid,f.cid,(r->>'lease')::uuid,null);
 update fr14_private.quota_reservations set units=2,settled=true;
 update fr14_private.attempts set last_attempt_at=clock_timestamp()-interval '61 seconds'where order_id=f.oid;
 update fr14_private.configuration set daily_limit=1;
 perform pg_temp.ok(public.fr14_prepare(f.oid,f.cid,true)->>'code'='QUOTA','rolling daily quota enforced');
 update fr14_private.configuration set daily_limit=1900,minute_limit=1;
 perform pg_temp.ok(public.fr14_prepare(f.oid,f.cid,true)->>'code'='QUOTA','rolling minute quota enforced');
 update fr14_private.configuration set minute_limit=35;
 update public.delivery_latest_locations set received_at=clock_timestamp()-interval '31 seconds'where order_id=f.oid;
 perform pg_temp.ok(public.fr14_prepare(f.oid,f.cid,true)->>'code'='LOCATION_UNAVAILABLE','30 second stale location has no route or ETA');
 update public.delivery_latest_locations set received_at=clock_timestamp()where order_id=f.oid;
end$$;
grant select on fr14_fixture,fr14_people to authenticated;
grant execute on function pg_temp.ok(boolean,text),pg_temp.claim(text)to authenticated;
select pg_temp.claim('customer');set local role authenticated;
select pg_temp.ok((select count(*)=1 from public.delivery_route_cache where order_id=(select oid from fr14_fixture)),'customer cache RLS');
do $$begin
 begin update public.delivery_route_cache set data='{}';raise exception 'cache write allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'direct cache update denied');end;
 begin perform public.fr14_prepare((select oid from fr14_fixture),(select cid from fr14_fixture),true);raise exception 'provider reservation allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'direct provider reservation denied');end;
 begin update public.orders set delivery_lat=34 where id=(select oid from fr14_fixture);raise exception 'destination change allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'active confirmed destination immutable');end;
 begin update public.orders set route_estimated_arrival_at=clock_timestamp()where id=(select oid from fr14_fixture);raise exception 'ETA write allowed';exception when insufficient_privilege then perform pg_temp.ok(true,'client cannot forge authoritative ETA');end;
end$$;
reset role;
select pg_temp.claim('other-customer');set local role authenticated;
select pg_temp.ok(not exists(select 1 from public.delivery_route_cache),'other customer cannot read routes');
reset role;
do $$declare f fr14_fixture;oid bigint;aid bigint;rid bigint;pid bigint;r jsonb;req uuid:=gen_random_uuid();items jsonb;delivery jsonb;cancel_ok boolean;begin
 select *into f from fr14_fixture;
 perform pg_temp.claim('vendor');
 r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FR14 SQL STOCKED","price":80,"is_available":true}',10,5,null);pid:=(r->>'product_id')::bigint;
 items:=jsonb_build_array(jsonb_build_object('product_id',pid,'quantity',1));
 delivery:='{"address":"FR14 CONFIRMED PIN","lat":33.71,"lng":73.06,"speed":"standard"}';
 perform pg_temp.claim('customer');
 perform pg_temp.ok(public.fr10_checkout(req,items,delivery)->>'code'='DESTINATION_CONFIRMATION_REQUIRED','new checkout requires explicit confirmation');
 delivery:=delivery||'{"destination_confirmed":true,"destination_source":"map_pin"}'::jsonb;
 r:=public.fr10_checkout(req,items,delivery);oid:=(r->>'order_id')::bigint;
 perform pg_temp.ok(r->>'code'='PLACED','confirmed checkout succeeds');
 perform pg_temp.ok((select destination_source='map_pin'and destination_confirmed_at is not null and delivery_lat=33.71 and delivery_lng=73.06 and user_id=f.cid from public.orders where id=oid),'coordinates source server timestamp and owner persist');
 perform pg_temp.ok((select stock_qty=9 from public.products where id=pid),'FR17 stock decrement preserved');
 perform pg_temp.ok(public.fr10_checkout(req,items,delivery)->>'code'='ALREADY_PLACED','FR10 idempotency preserved');
 perform pg_temp.ok((select count(*)=1 from public.orders where checkout_request_id=req),'one order per checkout');
 perform pg_temp.claim('other-customer');
 r:=public.fr10_checkout(req,items,delivery);perform pg_temp.ok(r->>'code'<>'PLACED'and r->>'code'<>'ALREADY_PLACED','cannot confirm another customer checkout');
 -- Legacy records remain unconfirmed. No historical mutation workflow is invented.
 insert into public.orders(user_id,order_status,amount,delivery_lat,delivery_lng)values(f.cid,'pending',1,33.71,73.06)returning id into oid;
 perform pg_temp.ok((select destination_confirmed_at is null and destination_source is null from public.orders where id=oid),'historical coordinates never imply confirmation');
 -- Exercise absent provenance using another genuine authorized legacy flow.
 select id into rid from fr14_people where label='other-rider';
 insert into public.riders(userid,is_online,is_available,isavailable,last_seen)values(rid,true,false,false,clock_timestamp());
 insert into public.orders(user_id,rider_id,order_status,amount,delivery_lat,delivery_lng)values(f.cid,rid,'ready',1,33.71,73.06)returning id into oid;
 insert into public.rider_assignments(orderid,riderid,status)values(oid,rid,'Accepted')returning id into aid;
 perform pg_temp.claim('other-rider');
 perform public.submit_pre_delivery_checklist(aid,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
 perform public.start_checklisted_delivery(aid);perform public.fr13_tracking_context(oid,true);
 perform public.fr13_submit_location(oid,33.7,73.05,10,clock_timestamp(),gen_random_uuid());
 perform pg_temp.ok(public.fr14_prepare(oid,f.cid,true)->>'code'='DESTINATION_UNCONFIRMED','eligible historical order has no ETA');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 update public.users set is_blocked=true where id=f.cid;
 perform pg_temp.claim('customer');perform pg_temp.ok(public.fr14_route_context(f.oid)->>'code'='FORBIDDEN','blocked customer denied');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);update public.users set is_blocked=false where id=f.cid;
 perform pg_temp.claim('customer');
 begin update public.orders set order_status='cancelled'where id=f.oid;
  cancel_ok:=public.fr14_route_context(f.oid)->>'code'='FORBIDDEN'
    and not exists(select 1 from public.delivery_route_cache where order_id=f.oid)
    and(select route_estimated_arrival_at is null from public.orders where id=f.oid);
  raise exception 'rollback cancellation'using errcode='P0002';exception when no_data_found then null;end;
 perform pg_temp.ok(cancel_ok,'cancelled order denied; cache and ETA invalidated');
 update public.orders set order_status='delivered'where id=f.oid;
 perform pg_temp.ok(public.fr14_route_context(f.oid)->>'code'='FORBIDDEN','delivered order denied');
 perform pg_temp.ok(not exists(select 1 from public.delivery_route_cache where order_id=f.oid),'completion invalidates cache');
 perform pg_temp.ok((select route_estimated_arrival_at is null from public.orders where id=f.oid),'completion clears authoritative ETA');
 perform fr14_private.cleanup();
 perform pg_temp.ok(not exists(select 1 from fr14_private.attempts where order_id=f.oid),'completion/retention clears leases');
 insert into public.delivery_route_cache values(oid,'{}',33.7,73.05,33.71,73.06,clock_timestamp()-interval '21 minutes',clock_timestamp()-interval '17 minutes');
 update public.orders set route_estimated_arrival_at=clock_timestamp()where id=oid;
 perform fr14_private.cleanup();
 perform pg_temp.ok(not exists(select 1 from public.delivery_route_cache where order_id=oid),'abandoned cache removed by bounded retention');
 perform pg_temp.ok((select route_estimated_arrival_at is null from public.orders where id=oid),'retention clears orphaned authoritative ETA');
 perform pg_temp.ok(not has_table_privilege('authenticated','public.delivery_route_cache','INSERT'),'cache insert grant absent');
 perform pg_temp.ok(not has_function_privilege('anon','public.fr14_route_context(bigint)','EXECUTE'),'anonymous RPC grant absent');
end$$;
select jsonb_agg(to_jsonb(r))as results from fr14_results r;
rollback;
