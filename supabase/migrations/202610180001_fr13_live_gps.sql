-- Isolated TEST only. No historical GPS rewrite or accepted migration replay.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create schema fr13_private;
revoke all on schema fr13_private from public,anon,authenticated,service_role;
create table fr13_private.sessions(
 assignment_id bigint primary key references public.rider_assignments(id)on delete cascade,
 order_id bigint not null unique references public.orders(id),
 rider_id bigint not null references public.users(id),
 topic text not null unique,
 created_at timestamptz not null default clock_timestamp()
);
-- Volatile timing metadata only; never a coordinate history. Crash means safe reset.
create unlogged table fr13_private.live_state(
 assignment_id bigint primary key references public.rider_assignments(id)on delete cascade,
 received_at timestamptz not null,
 device_at timestamptz not null,
 request_id uuid not null,
 persisted_at timestamptz not null
);
create table public.delivery_latest_locations(
 assignment_id bigint primary key references public.rider_assignments(id)on delete cascade,
 order_id bigint not null unique references public.orders(id),
 rider_id bigint not null references public.users(id),
 latitude double precision not null check(latitude between -90 and 90),
 longitude double precision not null check(longitude between -180 and 180),
 accuracy double precision not null check(accuracy between 0 and 100),
 device_at timestamptz not null,
 received_at timestamptz not null
);
alter table fr13_private.sessions enable row level security;
alter table fr13_private.live_state enable row level security;
alter table public.delivery_latest_locations enable row level security;
revoke all on fr13_private.sessions,fr13_private.live_state,public.delivery_latest_locations from public,anon,authenticated,service_role;
grant select on public.delivery_latest_locations to authenticated;

create function fr13_private.eligible(oid bigint,aid bigint)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.orders o join public.rider_assignments a on a.orderid=o.id
 join public.riders r on r.userid=a.riderid join public.users u on u.id=a.riderid
 join public.users c on c.id=o.user_id
 where o.id=oid and a.id=aid and o.rider_id=a.riderid and o.order_status='on_the_way'
 and a.status='Accepted'and a.checklist_completed and a.checklist_completed_at is not null
 and exists(select 1 from public.pre_delivery_checklists p where p.assignment_id=a.id and p.rider_id=a.riderid and p.submitted_at=a.checklist_completed_at)
 and u.role='rider'and u.verification_status='approved'and not u.is_blocked and not c.is_blocked
 and r.is_online and r.last_seen>=statement_timestamp()-interval '2 minutes');
$$;
create function public.fr13_can_receive(p_topic text)returns boolean language sql stable security definer set search_path='' as $$
 select public.fr21_actor()is not null and exists(select 1 from fr13_private.sessions s join public.orders o on o.id=s.order_id
 where s.topic=p_topic and fr13_private.eligible(o.id,s.assignment_id)
 and(public.fr21_actor()=o.user_id and public.fr21_role()='customer'
 or public.fr21_actor()=s.rider_id and public.fr21_role()='rider'
 or public.fr21_role()='admin'));
$$;
create policy fr13_latest_read on public.delivery_latest_locations for select to authenticated using(
 exists(select 1 from fr13_private.sessions s where s.assignment_id=delivery_latest_locations.assignment_id and public.fr13_can_receive(s.topic))
);
-- Policy cannot directly read private tables as an ordinary client.
create function public.fr13_can_read(p_assignment bigint)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from fr13_private.sessions s where s.assignment_id=p_assignment and public.fr13_can_receive(s.topic));
$$;
alter policy fr13_latest_read on public.delivery_latest_locations using(public.fr13_can_read(assignment_id));

create function public.fr13_tracking_context(p_order_id bigint,p_enable boolean default null)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;s fr13_private.sessions;begin
 if actor is null then return jsonb_build_object('code','FORBIDDEN');end if;
 -- Writes follow parent -> assignment -> user -> rider -> session hierarchy.
 if p_enable is not null then select *into o from public.orders where id=p_order_id for update;
 else select *into o from public.orders where id=p_order_id;end if;
 if o.id is null or not((public.fr21_role()='customer'and o.user_id=actor)or(public.fr21_role()='rider'and o.rider_id=actor)or public.fr21_role()='admin')then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_enable is not null and(public.fr21_role()<>'rider'or o.rider_id<>actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_enable is not null then
  select *into a from public.rider_assignments where orderid=o.id and riderid=actor and status='Accepted'for update;
  perform 1 from public.users where id in(actor,o.user_id)order by id for share;
  perform 1 from public.riders where userid=actor for share;
 else select *into a from public.rider_assignments where orderid=o.id and riderid=o.rider_id and status='Accepted';end if;
 if p_enable is false then
  delete from fr13_private.live_state where assignment_id in(select assignment_id from fr13_private.sessions where order_id=o.id);
  delete from public.delivery_latest_locations where order_id=o.id;
  delete from fr13_private.sessions where order_id=o.id;
  return jsonb_build_object('code','STOPPED');
 end if;
 if a.id is null or not fr13_private.eligible(o.id,a.id)then return jsonb_build_object('code','INELIGIBLE');end if;
 if p_enable is true then
  insert into fr13_private.sessions(assignment_id,order_id,rider_id,topic)
  values(a.id,o.id,actor,'fr13:'||o.id||':'||a.id||':'||extensions.gen_random_uuid())on conflict(assignment_id)do nothing;
 end if;
 select *into s from fr13_private.sessions where assignment_id=a.id;
 return jsonb_build_object('code','OK','order_id',o.id,'assignment_id',a.id,'rider_id',a.riderid,'sharing',s.topic is not null,'topic',s.topic,
 'server_now',clock_timestamp(),'latest',(select to_jsonb(l)from public.delivery_latest_locations l where l.assignment_id=a.id));
end$$;

create function public.fr13_submit_location(p_order_id bigint,p_lat double precision,p_lng double precision,p_accuracy double precision,p_device_at timestamptz,p_request_id uuid)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;s fr13_private.sessions;v fr13_private.live_state;moment timestamptz;persist boolean;payload jsonb;begin
 if actor is null or public.fr21_role()is distinct from'rider'or not public.fr21_approved_rider(actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or p_lat is null or p_lat not between -90 and 90 or p_lng is null or p_lng not between -180 and 180
 or p_accuracy is null or p_accuracy not between 0 and 100 then return jsonb_build_object('code','INVALID_LOCATION');end if;
 if p_device_at is null or not isfinite(p_device_at)or p_device_at<clock_timestamp()-interval '30 seconds'or p_device_at>clock_timestamp()+interval '5 seconds'then return jsonb_build_object('code','STALE_FIX');end if;
 select *into o from public.orders where id=p_order_id for update;
 if o.id is null or o.rider_id is distinct from actor then return jsonb_build_object('code','FORBIDDEN');end if;
 select *into a from public.rider_assignments where orderid=o.id and riderid=actor and status='Accepted'for update;
 perform 1 from public.users where id in(actor,o.user_id)order by id for share;
 perform 1 from public.riders where userid=actor for share;
 if not public.fr21_approved_rider(actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 if a.id is null or not fr13_private.eligible(o.id,a.id)then return jsonb_build_object('code','INELIGIBLE');end if;
 select *into s from fr13_private.sessions where assignment_id=a.id for update;
 if s.assignment_id is null then return jsonb_build_object('code','SHARING_STOPPED');end if;
 select *into v from fr13_private.live_state where assignment_id=a.id;
 moment:=clock_timestamp();
 if v.request_id=p_request_id then return jsonb_build_object('code','REPLAYED');end if;
 if v.received_at>moment-interval '2 seconds'then return jsonb_build_object('code','RATE_LIMIT','retry_after_ms',2000);end if;
 if v.device_at>=p_device_at then return jsonb_build_object('code','STALE_FIX');end if;
 persist:=v.persisted_at is null or v.persisted_at<=moment-interval '15 seconds';
 insert into fr13_private.live_state values(a.id,moment,p_device_at,p_request_id,case when persist then moment else v.persisted_at end)
 on conflict(assignment_id)do update set received_at=excluded.received_at,device_at=excluded.device_at,request_id=excluded.request_id,persisted_at=excluded.persisted_at;
 if persist then
  insert into public.delivery_latest_locations values(a.id,o.id,actor,p_lat,p_lng,p_accuracy,p_device_at,moment)
  on conflict(assignment_id)do update set latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,device_at=excluded.device_at,received_at=excluded.received_at;
  -- Keep the existing FR20 assignment coordinates fresh, at the same coarse interval.
  update public.riders set latitude=p_lat,longitude=p_lng,location_updated_at=moment where userid=actor;
 end if;
 payload:=jsonb_build_object('order_id',o.id,'assignment_id',a.id,'latitude',p_lat,'longitude',p_lng,'accuracy',p_accuracy,'device_at',p_device_at,'received_at',moment,'request_id',p_request_id);
 return jsonb_build_object('code','ACCEPTED','topic',s.topic,'payload',payload,'persisted',persist);
end$$;

create function fr13_private.close_session()returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_table_name='orders'then
  if new.order_status is distinct from'on_the_way'or new.rider_id is distinct from old.rider_id then
   delete from fr13_private.live_state where assignment_id in(select assignment_id from fr13_private.sessions where order_id=new.id);
   delete from public.delivery_latest_locations where order_id=new.id;delete from fr13_private.sessions where order_id=new.id;
  end if;
 elsif tg_table_name='riders'then
  if not new.is_online then
   delete from fr13_private.live_state where assignment_id in(select assignment_id from fr13_private.sessions where rider_id=new.userid);
   delete from public.delivery_latest_locations where rider_id=new.userid;delete from fr13_private.sessions where rider_id=new.userid;
  end if;
 elsif tg_table_name='users'then
  if new.is_blocked or new.verification_status is distinct from'approved'and new.role='rider'then
   delete from fr13_private.live_state where assignment_id in(select s.assignment_id from fr13_private.sessions s join public.orders o on o.id=s.order_id where s.rider_id=new.id or o.user_id=new.id);
   delete from public.delivery_latest_locations where order_id in(select o.id from public.orders o where o.rider_id=new.id or o.user_id=new.id);
   delete from fr13_private.sessions where order_id in(select o.id from public.orders o where o.rider_id=new.id or o.user_id=new.id);
  end if;
 elsif tg_table_name='rider_assignments'then
  if new.status is distinct from'Accepted'or new.riderid is distinct from old.riderid or not new.checklist_completed then
   delete from fr13_private.live_state where assignment_id=new.id;delete from public.delivery_latest_locations where assignment_id=new.id;delete from fr13_private.sessions where assignment_id=new.id;
  end if;
 end if;return new;end$$;
create trigger fr13_order_end after update of order_status,rider_id on public.orders for each row execute function fr13_private.close_session();
create trigger fr13_rider_offline after update of is_online on public.riders for each row execute function fr13_private.close_session();
create trigger fr13_user_restriction after update of is_blocked,verification_status on public.users for each row execute function fr13_private.close_session();
create trigger fr13_assignment_end after update of status,riderid,checklist_completed on public.rider_assignments for each row execute function fr13_private.close_session();

-- No client-originated FR13 Broadcast, even if a future permissive policy is added.
create policy fr13_subscribe on realtime.messages for select to authenticated using(extension='broadcast'and public.fr13_can_receive(realtime.topic()));
create policy fr13_no_client_publish on realtime.messages as restrictive for insert to authenticated with check(coalesce(realtime.topic(),'')not like'fr13:%');
-- Retire only the unsafe legacy API; keep all historical rows untouched.
revoke all on public.gps_locations from anon,authenticated;
create policy fr13_legacy_closed on public.gps_locations as restrictive for all to anon,authenticated using(false)with check(false);

create function fr13_private.cleanup()returns void language plpgsql security definer set search_path='' as $$declare oid bigint;begin
 -- Parent first, bounded and SKIP LOCKED: never invert submit's session/rate locks.
 for oid in select o.id from public.orders o where exists(select 1 from fr13_private.sessions s left join fr13_private.live_state v using(assignment_id)
  where s.order_id=o.id and(not fr13_private.eligible(s.order_id,s.assignment_id)or coalesce(v.received_at,s.created_at)<clock_timestamp()-interval '1 day'))
  order by o.id limit 100 for update of o skip locked loop
  if exists(select 1 from fr13_private.sessions s left join fr13_private.live_state v using(assignment_id)
   where s.order_id=oid and(not fr13_private.eligible(s.order_id,s.assignment_id)or coalesce(v.received_at,s.created_at)<clock_timestamp()-interval '1 day'))then
   delete from fr13_private.live_state where assignment_id in(select assignment_id from fr13_private.sessions where order_id=oid);
   delete from public.delivery_latest_locations where order_id=oid;
   delete from fr13_private.sessions where order_id=oid;
  end if;
 end loop;
end$$;
revoke all on all functions in schema fr13_private from public,anon,authenticated,service_role;
revoke all on function public.fr13_can_receive(text),public.fr13_can_read(bigint),public.fr13_tracking_context(bigint,boolean),public.fr13_submit_location(bigint,double precision,double precision,double precision,timestamptz,uuid)from public,anon,authenticated,service_role;
grant execute on function public.fr13_can_receive(text),public.fr13_can_read(bigint),public.fr13_tracking_context(bigint,boolean),public.fr13_submit_location(bigint,double precision,double precision,double precision,timestamptz,uuid)to authenticated;
select cron.schedule('fr13-location-cleanup','*/30 * * * *','select fr13_private.cleanup();');
commit;
