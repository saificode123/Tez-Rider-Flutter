-- TEST-only pickup navigation. Separate geometry; shared FR14 budgets/leases.
-- No order, payment, earning, consent or delivery-cache mutation.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create table fr14_private.pickup_cache(
 order_id bigint primary key references public.orders(id)on delete cascade,
 actor_id bigint not null, assignment_id bigint not null,
 destination_lat double precision not null,destination_lng double precision not null,
 data jsonb not null,expires_at timestamptz not null);
create table fr14_private.pickup_attempts(
 order_id bigint primary key references public.orders(id)on delete cascade,
 actor_id bigint not null,assignment_id bigint not null,token uuid not null);
alter table fr14_private.pickup_cache enable row level security;
alter table fr14_private.pickup_attempts enable row level security;
revoke all on fr14_private.pickup_cache,fr14_private.pickup_attempts from public,anon,authenticated,service_role;

create function fr14_private.pickup_allowed(oid bigint,actor bigint)returns boolean
language sql stable security definer set search_path=''as $$
 select exists(select 1 from public.orders o join public.users u on u.id=actor
 join public.riders r on r.userid=actor join public.rider_assignments a on a.orderid=o.id and a.riderid=actor
 where o.id=oid and o.rider_id=actor and o.order_status='ready'and a.status in('Pending','Accepted')
 and u.role='rider'and u.verification_status='approved'and not u.is_blocked
 and r.is_online and r.last_seen>clock_timestamp()-interval '2 minutes'
 and r.location_updated_at>clock_timestamp()-interval '2 minutes'
 and r.latitude between -90 and 90 and r.longitude between -180 and 180);
$$;
create function public.fr14_pickup_context(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();begin
 if actor is null or not public.is_current_user_allowed()or not fr14_private.pickup_allowed(p_order_id,actor)then
  return jsonb_build_object('code','FORBIDDEN');end if;
 return jsonb_build_object('code','OK','actor',actor);
end$$;

create function public.fr14_pickup_prepare(p_order_id bigint,p_actor bigint,p_configured boolean)returns jsonb
language plpgsql security definer set search_path=''as $$
declare o public.orders;r public.riders;v public.vendors;a fr14_private.attempts;c fr14_private.pickup_cache;
 cfg fr14_private.configuration;u fr14_private.user_limits;aid bigint;ctx jsonb;stamp timestamptz:=clock_timestamp();lease uuid;begin
 select *into o from public.orders where id=p_order_id for update;
 if not fr14_private.pickup_allowed(p_order_id,p_actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 select *into r from public.riders where userid=p_actor;
 select id into aid from public.rider_assignments where orderid=o.id and riderid=p_actor and status in('Pending','Accepted')order by id desc limit 1;
 select x.*into v from public.vendor_orders vo join public.vendors x on x.user_id=vo.vendor_id where vo.order_id=o.id order by vo.id limit 1;
 if v.latitude is null or v.longitude is null or v.latitude not between -90 and 90 or v.longitude not between -180 and 180 then
  return jsonb_build_object('code','LOCATION_UNAVAILABLE');end if;
 select *into cfg from fr14_private.configuration;
 -- Same per-actor read budget, including cached pickup responses.
 insert into fr14_private.user_limits values(p_actor,stamp,1)on conflict(actor)do update set
 window_at=case when fr14_private.user_limits.window_at<stamp-interval '1 minute'then stamp else fr14_private.user_limits.window_at end,
 requests=case when fr14_private.user_limits.window_at<stamp-interval '1 minute'then 1 else fr14_private.user_limits.requests+1 end returning *into u;
 if u.requests>100 then return jsonb_build_object('code','RATE_LIMIT');end if;
 select *into c from fr14_private.pickup_cache where order_id=o.id and actor_id=p_actor and assignment_id=aid
 and destination_lat=v.latitude and destination_lng=v.longitude and expires_at>stamp
 and extensions.st_dwithin(r.assignment_location,extensions.st_geomfromgeojson((data->'geometry')::text)::extensions.geography,cfg.deviation_meters);
 ctx:=jsonb_build_object('orderId',o.id,'origin',jsonb_build_array(r.longitude,r.latitude),
 'destination',jsonb_build_array(v.longitude,v.latitude),'minimumSeconds',cfg.minimum_seconds,
 'deviationMeters',cfg.deviation_meters,'cache',c.data);
 if c.order_id is not null then return ctx||jsonb_build_object('code','CACHE');end if;
 select *into a from fr14_private.attempts where order_id=o.id;
 if a.lease_until>stamp then return ctx||jsonb_build_object('code','BUSY');end if;
 if a.last_attempt_at>stamp-make_interval(secs=>cfg.minimum_seconds)then return ctx||jsonb_build_object('code','THROTTLED');end if;
 if not p_configured then return ctx||jsonb_build_object('code','NOT_CONFIGURED');end if;
 -- Identical shared advisory lock and quota accounting to delivery routing.
 perform pg_advisory_xact_lock(141419);
 delete from fr14_private.quota_reservations where reserved_at<stamp-interval '26 hours';
 if exists(select 1 from fr14_private.quota_reservations q where not settled and q.reserved_at<stamp-interval '25 seconds'and q.reserved_at>stamp-interval '24 hours')
 or(select coalesce(sum(units),0)from fr14_private.quota_reservations where reserved_at>stamp-interval '24 hours')+10>cfg.daily_limit
 or(select count(*)from fr14_private.quota_reservations where reserved_at>stamp-interval '60 seconds')>=cfg.minute_limit
 or(select count(*)from fr14_private.quota_reservations where reserved_at>stamp-interval '1 second')>=cfg.second_limit
 or(select count(*)from fr14_private.attempts where lease_until>stamp)>=cfg.concurrent_limit then
 return ctx||jsonb_build_object('code','QUOTA');end if;
 lease:=extensions.gen_random_uuid();
 insert into fr14_private.quota_reservations(token,units,reserved_at)values(lease,10,stamp);
 insert into fr14_private.attempts values(o.id,lease,stamp+interval '25 seconds',stamp,r.latitude,r.longitude,v.latitude,v.longitude)
 on conflict(order_id)do update set token=excluded.token,lease_until=excluded.lease_until,last_attempt_at=excluded.last_attempt_at,
 origin_lat=excluded.origin_lat,origin_lng=excluded.origin_lng,destination_lat=excluded.destination_lat,destination_lng=excluded.destination_lng;
 insert into fr14_private.pickup_attempts values(o.id,p_actor,aid,lease)on conflict(order_id)do update set actor_id=excluded.actor_id,assignment_id=excluded.assignment_id,token=excluded.token;
 return ctx||jsonb_build_object('code','COMPUTE','lease',lease);
end$$;

create function public.fr14_pickup_finish(p_order_id bigint,p_actor bigint,p_lease uuid,p_route jsonb)returns jsonb
language plpgsql security definer set search_path=''as $$
declare o public.orders;a fr14_private.attempts;p fr14_private.pickup_attempts;v public.vendors;
 cfg fr14_private.configuration;stamp timestamptz:=clock_timestamp();data jsonb;begin
 select *into o from public.orders where id=p_order_id for update;
 select *into p from fr14_private.pickup_attempts where order_id=p_order_id and actor_id=p_actor and token=p_lease;
 if p.order_id is null then return jsonb_build_object('code','UNAVAILABLE');end if;
 select *into cfg from fr14_private.configuration;
 if p_route is not null then
  if p_route->'geometry'->>'type'is distinct from 'LineString'or jsonb_typeof(p_route->'geometry'->'coordinates')is distinct from 'array'
  or jsonb_array_length(p_route->'geometry'->'coordinates')not between 2 and 20000
  or jsonb_typeof(p_route->'distanceMeters')is distinct from 'number'or jsonb_typeof(p_route->'durationSeconds')is distinct from 'number'
  or(p_route->>'distanceMeters')::numeric not between 0 and 1000000 or(p_route->>'durationSeconds')::numeric not between 0 and 86400 then
   raise exception 'Invalid route'using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements(p_route->'geometry'->'coordinates')x where jsonb_typeof(x)<>'array'or jsonb_array_length(x)<>2
  or jsonb_typeof(x->0)<>'number'or jsonb_typeof(x->1)<>'number'or(x->>0)::numeric not between -180 and 180 or(x->>1)::numeric not between -90 and 90)then
   raise exception 'Invalid route geometry'using errcode='22023';end if;
 end if;
 -- Settle the original request even if fulfillment changed while HTTP ran.
 -- Never settle a new delivery lease or write the delivery/pay route cache.
 update fr14_private.quota_reservations set units=case when p_route is null then cfg.daily_limit else
 greatest(1,ceil((p_route->>'distanceMeters')::numeric/500000)::integer+1)end,settled=true where token=p_lease;
 select *into a from fr14_private.attempts where order_id=p_order_id and token=p_lease for update;
 if a.order_id is null or a.lease_until<stamp or not fr14_private.pickup_allowed(p_order_id,p_actor)then
  return jsonb_build_object('code','UNAVAILABLE');end if;
 update fr14_private.attempts set lease_until=stamp where order_id=p_order_id and token=p_lease;
 if p_route is null then return jsonb_build_object('code','RELEASED');end if;
 select x.*into v from public.vendor_orders vo join public.vendors x on x.user_id=vo.vendor_id where vo.order_id=o.id order by vo.id limit 1;
 if(v.latitude,v.longitude)is distinct from(a.destination_lat,a.destination_lng)then return jsonb_build_object('code','UNAVAILABLE');end if;
 data:=p_route||jsonb_build_object('orderId',o.id,'target','pickup','source','geoapify','computedAt',stamp,
 'expiresAt',stamp+make_interval(secs=>cfg.refresh_seconds),'isApproximate',false,'isStale',false,
 'routeVersion',p_lease,'deviationMeters',cfg.deviation_meters,'minimumSeconds',cfg.minimum_seconds);
 insert into fr14_private.pickup_cache values(o.id,p_actor,p.assignment_id,v.latitude,v.longitude,data,stamp+make_interval(secs=>cfg.refresh_seconds))
 on conflict(order_id)do update set actor_id=excluded.actor_id,assignment_id=excluded.assignment_id,destination_lat=excluded.destination_lat,
 destination_lng=excluded.destination_lng,data=excluded.data,expires_at=excluded.expires_at;
 return jsonb_build_object('code','OK','route',data);
end$$;

-- Remove pickup geometry/its lease on a genuine phase change. Keep the token
-- marker until completion so an in-flight provider result can settle its quota.
create function fr14_private.end_pickup()returns trigger language plpgsql security definer set search_path=''as $$begin
 if new.order_status is distinct from old.order_status and new.order_status<>'ready'then
  delete from fr14_private.attempts a using fr14_private.pickup_attempts p where a.order_id=new.id and p.order_id=a.order_id and p.token=a.token;
  delete from fr14_private.pickup_cache where order_id=new.id;
 end if;return new;
end$$;
create trigger fr14_pickup_phase_end before update of order_status on public.orders for each row execute function fr14_private.end_pickup();
-- Keep the existing cleanup schedule and its accepted delivery cleanup intact.
alter function fr14_private.cleanup()rename to cleanup_delivery;
create function fr14_private.cleanup()returns void language plpgsql security definer set search_path=''as $$begin
 perform fr14_private.cleanup_delivery();
 delete from fr14_private.pickup_cache where expires_at<clock_timestamp()-interval '15 minutes';
 delete from fr14_private.pickup_attempts p where not exists(select 1 from fr14_private.attempts a where a.token=p.token)
 and not exists(select 1 from fr14_private.quota_reservations q where q.token=p.token and not q.settled and q.reserved_at>clock_timestamp()-interval '24 hours');
end$$;
revoke all on function fr14_private.cleanup(),fr14_private.cleanup_delivery()from public,anon,authenticated,service_role;
revoke all on function fr14_private.pickup_allowed(bigint,bigint),fr14_private.end_pickup()from public,anon,authenticated,service_role;
revoke all on function public.fr14_pickup_context(bigint)from public,anon,service_role;
grant execute on function public.fr14_pickup_context(bigint)to authenticated;
revoke all on function public.fr14_pickup_prepare(bigint,bigint,boolean),public.fr14_pickup_finish(bigint,bigint,uuid,jsonb)from public,anon,authenticated;
grant execute on function public.fr14_pickup_prepare(bigint,bigint,boolean),public.fr14_pickup_finish(bigint,bigint,uuid,jsonb)to service_role;
notify pgrst,'reload schema';
commit;
