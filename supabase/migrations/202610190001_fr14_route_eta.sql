-- FR14: isolated TEST only. Historical destination confirmation is never inferred.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create schema fr14_private;
revoke all on schema fr14_private from public,anon,authenticated,service_role;
alter table public.orders add column destination_confirmed_at timestamptz,
 add column destination_source text check(destination_source in('my_location','map_pin')),
 add column route_estimated_arrival_at timestamptz,
 add constraint fr14_destination_pair check((destination_source is null)=(destination_confirmed_at is null));

-- Preserve accepted FR10/FR17 transactions and exact original idempotency payloads.
alter function public.fr10_checkout(uuid,jsonb,jsonb)rename to checkout_base;
alter function public.checkout_base(uuid,jsonb,jsonb)set schema fr14_private;
create function public.fr10_checkout(p_request_id uuid,p_items jsonb,p_delivery jsonb)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();r jsonb;begin
 if actor is null or public.fr21_role()<>'customer' then return jsonb_build_object('code','FORBIDDEN');end if;
 -- Old uncertain checkouts may reconcile; no historical confirmation is fabricated.
 if exists(select 1 from public.orders where checkout_request_id=p_request_id and user_id=actor)then
  return fr14_private.checkout_base(p_request_id,p_items,p_delivery);
 end if;
 if p_delivery->'destination_confirmed' is distinct from 'true'::jsonb
 or coalesce(p_delivery->>'destination_source','')not in('my_location','map_pin')
 then return jsonb_build_object('code','DESTINATION_CONFIRMATION_REQUIRED');end if;
 r:=fr14_private.checkout_base(p_request_id,p_items,p_delivery);
 if r->>'code'='PLACED'then
  update public.orders set destination_source=p_delivery->>'destination_source',destination_confirmed_at=clock_timestamp()
  where id=(r->>'order_id')::bigint and user_id=actor;
 end if;
 return r;
end$$;

create function fr14_private.guard_destination()returns trigger language plpgsql set search_path='' as $$begin
 if current_user not in('postgres','supabase_admin')and
 ((tg_op='INSERT'and new.route_estimated_arrival_at is not null)or
 (tg_op='UPDATE'and new.route_estimated_arrival_at is distinct from old.route_estimated_arrival_at))then
  raise exception 'Server route calculation required'using errcode='42501';end if;
 if tg_op='UPDATE'and (new.delivery_lat,new.delivery_lng,new.delivery_address,new.destination_source,new.destination_confirmed_at)
 is distinct from(old.delivery_lat,old.delivery_lng,old.delivery_address,old.destination_source,old.destination_confirmed_at)then
  if old.destination_confirmed_at is not null or old.order_status in('ready','on_the_way','delivered','cancelled')then
   raise exception 'Delivery destination is locked'using errcode='42501';end if;
 end if;
 if (tg_op='INSERT'and new.destination_confirmed_at is not null)
 or (tg_op='UPDATE'and(new.destination_source,new.destination_confirmed_at)is distinct from(old.destination_source,old.destination_confirmed_at))then
  if current_user not in('postgres','supabase_admin')then raise exception 'Trusted checkout required'using errcode='42501';end if;
 end if;
 return new;
end$$;
create trigger fr14_destination_guard before insert or update on public.orders for each row execute function fr14_private.guard_destination();

create table fr14_private.configuration(
 singleton boolean primary key default true check(singleton),
 daily_limit integer not null default 2800 check(daily_limit between 1 and 3000),
 minute_limit integer not null default 120 check(minute_limit between 1 and 300),
 second_limit integer not null default 4 check(second_limit between 1 and 5),
 concurrent_limit integer not null default 4 check(concurrent_limit between 1 and 8),
 refresh_seconds integer not null default 240 check(refresh_seconds between 180 and 600),
 minimum_seconds integer not null default 60 check(minimum_seconds between 30 and 240),
 deviation_meters integer not null default 150 check(deviation_meters between 100 and 1000),
 fallback_speed_kmh numeric not null default 20 check(fallback_speed_kmh between 5 and 50));
insert into fr14_private.configuration default values;
create table fr14_private.attempts(
 order_id bigint primary key references public.orders(id)on delete cascade,
 token uuid not null,lease_until timestamptz not null,last_attempt_at timestamptz not null,
 origin_lat double precision not null,origin_lng double precision not null,
 destination_lat double precision not null,destination_lng double precision not null);
create table fr14_private.quota_reservations(id bigint generated always as identity primary key,token uuid not null unique,
 units integer not null check(units>0),reserved_at timestamptz not null default clock_timestamp(),settled boolean not null default false);
create index fr14_quota_time on fr14_private.quota_reservations(reserved_at);
create table fr14_private.user_limits(actor bigint primary key references public.users(id)on delete cascade,window_at timestamptz not null,requests integer not null);
create table public.delivery_route_cache(
 order_id bigint primary key references public.orders(id)on delete cascade,
 data jsonb not null,origin_lat double precision not null,origin_lng double precision not null,
 destination_lat double precision not null,destination_lng double precision not null,
 computed_at timestamptz not null,expires_at timestamptz not null);
alter table public.delivery_route_cache enable row level security;
alter table fr14_private.configuration enable row level security;
alter table fr14_private.attempts enable row level security;
alter table fr14_private.quota_reservations enable row level security;
alter table fr14_private.user_limits enable row level security;
revoke all on all tables in schema fr14_private from public,anon,authenticated,service_role;
revoke all on public.delivery_route_cache from public,anon,authenticated,service_role;
grant select on public.delivery_route_cache to authenticated;

create function fr14_private.allowed(oid bigint,actor bigint)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.orders o join public.rider_assignments a on a.orderid=o.id
 join public.users u on u.id=actor where o.id=oid and not u.is_blocked and
 (u.role='customer'and o.user_id=actor or u.role='rider'and a.riderid=actor or u.role='admin'and u.verification_status='approved')
 and fr13_private.eligible(o.id,a.id));
$$;
create function public.fr14_can_read(p_order_id bigint)returns boolean language sql stable security definer set search_path='' as $$
 select public.fr21_actor()is not null and fr14_private.allowed(p_order_id,public.fr21_actor());$$;
create policy fr14_cache_read on public.delivery_route_cache for select to authenticated using(public.fr14_can_read(order_id));

-- Authenticated caller identity is derived here, never accepted in the HTTP body.
create function public.fr14_route_context(p_order_id bigint)returns jsonb language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();begin
 if actor is null or not fr14_private.allowed(p_order_id,actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 return jsonb_build_object('code','OK','actor',actor);
end$$;

-- Distance to a road polyline uses PostGIS geography, not origin displacement.
create function public.fr14_prepare(p_order_id bigint,p_actor bigint,p_configured boolean)returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders;l public.delivery_latest_locations;c public.delivery_route_cache;a fr14_private.attempts;
 cfg fr14_private.configuration;u fr14_private.user_limits;stamp timestamptz:=clock_timestamp();v_token uuid;ctx jsonb;offroute boolean:=false;begin
 select *into o from public.orders where id=p_order_id for update;
 if not fr14_private.allowed(p_order_id,p_actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 if o.destination_confirmed_at is null or o.delivery_lat is null or o.delivery_lng is null
 or o.delivery_lat not between -90 and 90 or o.delivery_lng not between -180 and 180 then return jsonb_build_object('code','DESTINATION_UNCONFIRMED');end if;
 select *into l from public.delivery_latest_locations where order_id=o.id;
 if l.order_id is null or l.received_at<stamp-interval '30 seconds'or l.device_at<stamp-interval '30 seconds'or l.accuracy>100 then return jsonb_build_object('code','LOCATION_UNAVAILABLE');end if;
 insert into fr14_private.user_limits values(p_actor,stamp,1)on conflict(actor)do update
 set window_at=case when fr14_private.user_limits.window_at<stamp-interval '1 minute'then stamp else fr14_private.user_limits.window_at end,
 requests=case when fr14_private.user_limits.window_at<stamp-interval '1 minute'then 1 else fr14_private.user_limits.requests+1 end returning *into u;
 if u.requests>100 then return jsonb_build_object('code','RATE_LIMIT');end if;
 select *into cfg from fr14_private.configuration;
 select *into c from public.delivery_route_cache where order_id=o.id;
 select *into a from fr14_private.attempts where order_id=o.id;
 if c.order_id is not null then
  offroute:=not extensions.st_dwithin(extensions.st_setsrid(extensions.st_makepoint(l.longitude,l.latitude),4326)::extensions.geography,
    extensions.st_geomfromgeojson((c.data->'geometry')::text)::extensions.geography,cfg.deviation_meters);
 end if;
 ctx:=jsonb_build_object('orderId',o.id,'origin',jsonb_build_array(l.longitude,l.latitude),'destination',jsonb_build_array(o.delivery_lng,o.delivery_lat),
  'locationAt',l.received_at,'speedKmh',cfg.fallback_speed_kmh,'refreshSeconds',cfg.refresh_seconds,'minimumSeconds',cfg.minimum_seconds,
  'deviationMeters',cfg.deviation_meters,'serverNow',stamp,'cache',case when c.destination_lat=o.delivery_lat and c.destination_lng=o.delivery_lng and c.computed_at>stamp-interval '15 minutes'and not offroute then c.data end);
 if c.order_id is not null and c.expires_at>stamp and not offroute and c.destination_lat=o.delivery_lat and c.destination_lng=o.delivery_lng then
  return ctx||jsonb_build_object('code','CACHE');end if;
 if a.lease_until>stamp then return ctx||jsonb_build_object('code','BUSY');end if;
 if a.last_attempt_at>stamp-make_interval(secs=>cfg.minimum_seconds)then return ctx||jsonb_build_object('code','THROTTLED');end if;
 if not p_configured then return ctx||jsonb_build_object('code','NOT_CONFIGURED');end if;
 -- Short transaction only. Reservation survives errors/uncertain HTTP responses.
 perform pg_advisory_xact_lock(141419);
 delete from fr14_private.quota_reservations where reserved_at<stamp-interval '26 hours';
 -- Geoapify uses credits, not requests: pessimistically reserve 10 credits.
 -- Only accepted <=1000km responses are settled down; uncertain attempts burn
 -- the remaining budget, including leases whose worker never finishes.
 if exists(select 1 from fr14_private.quota_reservations q where not settled and q.reserved_at<stamp-interval '25 seconds'and q.reserved_at>stamp-interval '24 hours')
 or(select coalesce(sum(units),0)from fr14_private.quota_reservations where reserved_at>stamp-interval '24 hours')+10>cfg.daily_limit
 or(select count(*)from fr14_private.quota_reservations where reserved_at>stamp-interval '60 seconds')>=cfg.minute_limit
 or(select count(*)from fr14_private.quota_reservations where reserved_at>stamp-interval '1 second')>=cfg.second_limit
 or(select count(*)from fr14_private.attempts where lease_until>stamp)>=cfg.concurrent_limit then
  return ctx||jsonb_build_object('code','QUOTA');end if;
 v_token:=extensions.gen_random_uuid();
 insert into fr14_private.quota_reservations(token,units,reserved_at)values(v_token,10,stamp);
 insert into fr14_private.attempts values(o.id,v_token,stamp+interval '25 seconds',stamp,l.latitude,l.longitude,o.delivery_lat,o.delivery_lng)
 on conflict(order_id)do update set token=excluded.token,lease_until=excluded.lease_until,last_attempt_at=excluded.last_attempt_at,
 origin_lat=excluded.origin_lat,origin_lng=excluded.origin_lng,destination_lat=excluded.destination_lat,destination_lng=excluded.destination_lng;
 return ctx||jsonb_build_object('code','COMPUTE','lease',v_token);
end$$;

create function public.fr14_finish(p_order_id bigint,p_actor bigint,p_lease uuid,p_route jsonb)returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders;a fr14_private.attempts;cfg fr14_private.configuration;stamp timestamptz:=clock_timestamp();arrival timestamptz;data jsonb;begin
 select *into o from public.orders where id=p_order_id for update;
 select *into a from fr14_private.attempts where order_id=o.id for update;
 if a.token is distinct from p_lease or a.lease_until<stamp or not fr14_private.allowed(o.id,p_actor)
 or o.destination_confirmed_at is null or(o.delivery_lat,o.delivery_lng)is distinct from(a.destination_lat,a.destination_lng)
 or not exists(select 1 from public.delivery_latest_locations where order_id=o.id and received_at>stamp-interval '30 seconds'and device_at>stamp-interval '30 seconds')then
  return jsonb_build_object('code','UNAVAILABLE');end if;
 update fr14_private.attempts set lease_until=stamp where order_id=o.id;
 if p_route is null then
  update fr14_private.quota_reservations set units=(select daily_limit from fr14_private.configuration),settled=true where token=p_lease;
  return jsonb_build_object('code','RELEASED');end if;
 if p_route->'geometry'->>'type' is distinct from 'LineString'
 or jsonb_typeof(p_route->'geometry'->'coordinates')is distinct from 'array'
 or jsonb_array_length(p_route->'geometry'->'coordinates')not between 2 and 20000
 or jsonb_typeof(p_route->'distanceMeters')is distinct from 'number'or jsonb_typeof(p_route->'durationSeconds')is distinct from 'number'
 or(p_route->>'distanceMeters')::numeric not between 0 and 1000000 or(p_route->>'durationSeconds')::numeric not between 0 and 86400 then
  raise exception 'Invalid route'using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(p_route->'geometry'->'coordinates')p where jsonb_array_length(p)<>2
 or(p->>0)::numeric not between -180 and 180 or(p->>1)::numeric not between -90 and 90)then raise exception 'Invalid route geometry'using errcode='22023';end if;
 select *into cfg from fr14_private.configuration;
 -- Round up plus one extra credit to cover the documented long-distance
 -- surcharge conservatively. Request has exactly two waypoints, no extras.
 update fr14_private.quota_reservations set units=greatest(1,ceil((p_route->>'distanceMeters')::numeric/500000)::integer+1),settled=true where token=p_lease;
 arrival:=stamp+make_interval(secs=>(p_route->>'durationSeconds')::double precision);
 data:=jsonb_build_object('orderId',o.id,'geometry',p_route->'geometry','distanceMeters',p_route->'distanceMeters','durationSeconds',p_route->'durationSeconds',
 'estimatedArrivalAt',arrival,'computedAt',stamp,'expiresAt',stamp+make_interval(secs=>cfg.refresh_seconds),'source','geoapify',
 'isApproximate',false,'isStale',false,'routeVersion',p_lease,'deviationMeters',cfg.deviation_meters,'minimumSeconds',cfg.minimum_seconds);
 insert into public.delivery_route_cache values(o.id,data,a.origin_lat,a.origin_lng,a.destination_lat,a.destination_lng,stamp,stamp+make_interval(secs=>cfg.refresh_seconds))
 on conflict(order_id)do update set data=excluded.data,origin_lat=excluded.origin_lat,origin_lng=excluded.origin_lng,destination_lat=excluded.destination_lat,
 destination_lng=excluded.destination_lng,computed_at=excluded.computed_at,expires_at=excluded.expires_at;
 update public.orders set route_estimated_arrival_at=arrival where id=o.id;
 return jsonb_build_object('code','OK','route',data);
end$$;

create function fr14_private.invalidate()returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.order_status in('delivered','cancelled')then
  delete from public.delivery_route_cache where order_id=new.id;
  delete from fr14_private.attempts where order_id=new.id;
  new.route_estimated_arrival_at:=null;
 end if;return new;
end$$;
create trigger fr14_delivery_end before update of order_status on public.orders for each row execute function fr14_private.invalidate();
create function fr14_private.cleanup()returns void language plpgsql security definer set search_path='' as $$begin
 -- Acquire parent locks before cache rows, matching prepare/finish and end triggers.
 perform 1 from public.orders o where o.route_estimated_arrival_at is not null order by o.id for update skip locked;
 delete from public.delivery_route_cache c where c.computed_at<clock_timestamp()-interval '15 minutes'
 or not exists(select 1 from public.orders o where o.id=c.order_id and o.order_status='on_the_way');
 update public.orders o set route_estimated_arrival_at=null where route_estimated_arrival_at is not null and not exists(select 1 from public.delivery_route_cache c where c.order_id=o.id);
 delete from fr14_private.attempts where last_attempt_at<clock_timestamp()-interval '15 minutes';
 delete from fr14_private.quota_reservations where reserved_at<clock_timestamp()-interval '26 hours';
 delete from fr14_private.user_limits where window_at<clock_timestamp()-interval '1 day';
end$$;
select cron.schedule('fr14-route-cleanup','*/5 * * * *','select fr14_private.cleanup();');
revoke all on all functions in schema fr14_private from public,anon,authenticated,service_role;
revoke all on function public.fr14_can_read(bigint),public.fr14_route_context(bigint),public.fr10_checkout(uuid,jsonb,jsonb)from public,anon;
grant execute on function public.fr14_can_read(bigint),public.fr14_route_context(bigint),public.fr10_checkout(uuid,jsonb,jsonb)to authenticated;
revoke all on function public.fr14_prepare(bigint,bigint,boolean),public.fr14_finish(bigint,bigint,uuid,jsonb)from public,anon,authenticated;
grant execute on function public.fr14_prepare(bigint,bigint,boolean),public.fr14_finish(bigint,bigint,uuid,jsonb)to service_role;
notify pgrst,'reload schema';
commit;
