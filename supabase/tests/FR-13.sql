-- Actual database/RLS rollback checks; no external email or production data.
begin;
create temp table fr13_results(name text,result text);
create temp table fr13_people(label text,id bigint,auth_id uuid,session_id uuid);
create temp table fr13_fixture(oid bigint,aid bigint,rid bigint);
create function pg_temp.ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'FR13 assertion: %',label;end if;
 insert into fr13_results values(label,'PASS');end$$;
do $$declare who text;uid bigint;a uuid;s uuid;mail text;begin
 foreach who in array array['customer','other-customer','vendor','rider','other-rider','admin']loop
 a:=gen_random_uuid();s:=gen_random_uuid();mail:='fr13-sql-'||a||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(a,mail,now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values(mail,'FR13 SQL SYNTHETIC',case when who like'other-%'then substr(who,7)else who end,'approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
 insert into fr13_people values(who,uid,a,s);end loop;
end$$;
create function pg_temp.claim(who text)returns void language plpgsql security definer as $$declare p fr13_people;begin
 select *into p from fr13_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id)::text,true);
end$$;
do $$declare rid bigint;cid bigint;o bigint;a bigint;begin
 select id into rid from fr13_people where label='rider';select id into cid from fr13_people where label='customer';
 insert into public.riders(userid,is_online,is_available,isavailable,last_seen)values(rid,true,false,false,clock_timestamp());
 insert into public.orders(user_id,rider_id,order_status,amount,payment_method,delivery_address)values(cid,rid,'ready',1,'COD','FR13 SQL SYNTHETIC')returning id into o;
 insert into public.rider_assignments(orderid,riderid,status)values(o,rid,'Accepted')returning id into a;
 insert into fr13_fixture values(o,a,rid);
end$$;
create function pg_temp.send(lat double precision default 33.7,lng double precision default 73.05,acc double precision default 10,stamp timestamptz default clock_timestamp(),request uuid default gen_random_uuid())returns jsonb language sql as $$
 select public.fr13_submit_location((select oid from fr13_fixture),lat,lng,acc,stamp,request);$$;
do $$declare f fr13_fixture;who text;r jsonb;topic text;at timestamptz;req uuid:=gen_random_uuid();begin
 select *into f from fr13_fixture;perform pg_temp.claim('rider');
 perform pg_temp.ok(pg_temp.send()->>'code'='INELIGIBLE','missing checklist blocks GPS');
 perform pg_temp.ok(public.fr13_tracking_context(f.oid,true)->>'code'='INELIGIBLE','cannot enable at pickup');
 perform public.submit_pre_delivery_checklist(f.aid,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
 perform pg_temp.ok(pg_temp.send()->>'code'='INELIGIBLE','completed checklist alone does not start GPS');
 perform pg_temp.ok(public.start_checklisted_delivery(f.aid)->>'code'='STARTED','existing protected start retained');
 perform pg_temp.ok(pg_temp.send()->>'code'='SHARING_STOPPED','explicit sharing session required');
 r:=public.fr13_tracking_context(f.oid,true);topic:=r->>'topic';
 perform pg_temp.ok(r->>'code'='OK'and(r->>'sharing')::boolean and topic like'fr13:%','assigned rider enables private session');
 perform pg_temp.ok(public.fr13_tracking_context(f.oid,true)->>'topic'=topic,'duplicate start does not rotate or duplicate session');
 foreach who in array array['customer','other-customer','vendor','other-rider','admin']loop
 perform pg_temp.claim(who);perform pg_temp.ok(pg_temp.send()->>'code'='FORBIDDEN',who||' cannot publish');end loop;
 perform set_config('request.jwt.claims','{}',true);perform pg_temp.ok(pg_temp.send()->>'code'='FORBIDDEN','anonymous identity denied');
 foreach who in array array['rider','customer','admin']loop
 perform pg_temp.claim(who);perform pg_temp.ok(public.fr13_can_receive(topic),who||' can receive active topic');end loop;
 foreach who in array array['other-rider','other-customer','vendor']loop
 perform pg_temp.claim(who);perform pg_temp.ok(not public.fr13_can_receive(topic),who||' cannot receive active topic');end loop;
 perform pg_temp.claim('rider');
 perform pg_temp.ok(pg_temp.send(91)->>'code'='INVALID_LOCATION','latitude rejected');
 perform pg_temp.ok(pg_temp.send(33,181)->>'code'='INVALID_LOCATION','longitude rejected');
 perform pg_temp.ok(pg_temp.send('NaN'::float8)->>'code'='INVALID_LOCATION','NaN rejected');
 perform pg_temp.ok(pg_temp.send('Infinity'::float8)->>'code'='INVALID_LOCATION','infinity rejected');
 perform pg_temp.ok(pg_temp.send(33,73,-1)->>'code'='INVALID_LOCATION','negative accuracy rejected');
 perform pg_temp.ok(pg_temp.send(33,73,101)->>'code'='INVALID_LOCATION','poor accuracy rejected');
 perform pg_temp.ok(pg_temp.send(33,73,1,clock_timestamp()-interval '31 seconds')->>'code'='STALE_FIX','old timestamp rejected');
 perform pg_temp.ok(pg_temp.send(33,73,1,clock_timestamp()+interval '6 seconds')->>'code'='STALE_FIX','future timestamp rejected');
 perform pg_temp.ok(pg_temp.send(33,73,1,'infinity')->>'code'='STALE_FIX','infinite timestamp rejected');
 r:=pg_temp.send(33.7,73.05,10,clock_timestamp(),req);
 perform pg_temp.ok(r->>'code'='ACCEPTED'and(r->>'persisted')::boolean,'valid real protocol update accepted and first latest persisted');
 perform pg_temp.ok((select count(*)=1 from public.delivery_latest_locations where assignment_id=f.aid),'single latest record');
 select received_at into at from public.delivery_latest_locations where assignment_id=f.aid;
 perform pg_temp.ok(pg_temp.send(33.7,73.05,10,clock_timestamp(),req)->>'code'='REPLAYED','retry does not duplicate publication');
 perform pg_temp.ok(pg_temp.send()->>'code'='RATE_LIMIT','excess frequency rejected');
 update fr13_private.live_state set received_at=clock_timestamp()-interval '3 seconds'where assignment_id=f.aid;
 r:=pg_temp.send();perform pg_temp.ok(r->>'code'='ACCEPTED'and not(r->>'persisted')::boolean,'new fix after minimum interval broadcasts without durable write');
 perform pg_temp.ok((select received_at=at from public.delivery_latest_locations where assignment_id=f.aid),'latest persistence throttled');
 update fr13_private.live_state set received_at=clock_timestamp()-interval '3 seconds',persisted_at=clock_timestamp()-interval '16 seconds'where assignment_id=f.aid;
 r:=pg_temp.send();perform pg_temp.ok(r->>'code'='ACCEPTED'and(r->>'persisted')::boolean,'coarse interval persists latest');
 perform pg_temp.ok((select count(*)=1 and min(received_at)>at from public.delivery_latest_locations where assignment_id=f.aid),'upsert replaces single latest record');
 perform pg_temp.ok((select latitude=33.7 and location_updated_at>=at from public.riders where userid=f.rid),'FR20 authorized location refreshed');
 perform pg_temp.ok((select is_online and last_seen>clock_timestamp()-interval '2 minutes'from public.riders where userid=f.rid),'FR21 heartbeat unaffected');
end$$;
grant select on fr13_fixture,fr13_people to authenticated;
select pg_temp.claim('customer');
set local role authenticated;
select pg_temp.ok((select count(*)=1 from public.delivery_latest_locations where order_id=(select oid from fr13_fixture)),'owner reads permitted latest');
reset role;
select pg_temp.claim('other-customer');set local role authenticated;
select pg_temp.ok(not exists(select 1 from public.delivery_latest_locations),'cross-customer RLS denies latest');
do $$begin
 begin update public.delivery_latest_locations set latitude=0;raise exception 'Direct write permitted';exception when insufficient_privilege then perform pg_temp.ok(true,'direct client latest write denied');end;
 begin insert into public.gps_locations(rider_id,latitude,longitude)values('fr13-spy',0,0);raise exception 'Legacy write permitted';exception when insufficient_privilege then perform pg_temp.ok(true,'legacy arbitrary GPS write denied');end;
end$$;
reset role;
do $$declare f fr13_fixture;topic text;begin
 select *into f from fr13_fixture;select s.topic into topic from fr13_private.sessions s where s.assignment_id=f.aid;
 perform pg_temp.claim('rider');
 perform pg_temp.ok(public.fr13_tracking_context(f.oid,false)->>'code'='STOPPED','explicit stop confirmed');
 perform pg_temp.ok(not public.fr13_can_receive(topic)and pg_temp.send()->>'code'='SHARING_STOPPED','stop revokes topic and submission');
 perform public.fr13_tracking_context(f.oid,true);
 perform pg_temp.ok(public.fr13_tracking_context(f.oid)->>'topic'<>topic,'restart rotates topic');
 update public.riders set is_online=false where userid=f.rid;
 perform pg_temp.ok(pg_temp.send()->>'code'='INELIGIBLE'and not exists(select 1 from public.delivery_latest_locations where assignment_id=f.aid),'offline closes location session');
 update public.riders set is_online=true,last_seen=clock_timestamp()where userid=f.rid;
 perform public.fr13_tracking_context(f.oid,true);
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);update public.users set is_blocked=true where id=f.rid;
 perform pg_temp.claim('rider');perform pg_temp.ok(pg_temp.send()->>'code'='FORBIDDEN','blocked rider rejected');
 perform pg_temp.ok(not exists(select 1 from fr13_private.sessions where assignment_id=f.aid),'block removes session');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);update public.users set is_blocked=false where id=f.rid;
 perform pg_temp.claim('rider');perform public.fr13_tracking_context(f.oid,true);
 begin
 update public.orders set order_status='cancelled'where id=f.oid;
 if pg_temp.send()->>'code'<>'INELIGIBLE'or exists(select 1 from fr13_private.sessions where assignment_id=f.aid)then raise exception 'Cancellation bypass';end if;
 raise sqlstate'PT001';exception when sqlstate'PT001'then null;end;
 perform pg_temp.ok(true,'cancellation closes session and rejects updates (rollback fixture)');
 update public.orders set order_status='delivered'where id=f.oid;
 perform pg_temp.ok(pg_temp.send()->>'code'='INELIGIBLE'and not exists(select 1 from fr13_private.sessions where assignment_id=f.aid),'delivery closes session and rejects updates');
 perform pg_temp.ok(not public.fr13_can_receive(topic),'ended topic cannot authorize new subscribers');
 perform fr13_private.cleanup();perform pg_temp.ok(not exists(select 1 from public.delivery_latest_locations where assignment_id=f.aid),'bounded cleanup leaves no ended latest');
 perform pg_temp.ok(not has_function_privilege('anon','public.fr13_submit_location(bigint,double precision,double precision,double precision,timestamptz,uuid)','execute'),'anon RPC grant revoked');
 perform pg_temp.ok(not has_schema_privilege('authenticated','fr13_private','usage'),'private state inaccessible');
 perform pg_temp.ok((select relpersistence='u'from pg_class where oid='fr13_private.live_state'::regclass),'rate state is unlogged, not durable coordinates');
end$$;
select jsonb_agg(to_jsonb(r))as results from fr13_results r;
rollback;
