-- FR20: apply only to the authorized TEST project; never replay accepted migrations.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create extension if not exists postgis with schema extensions;
alter table public.riders add column location_updated_at timestamptz;
alter table public.riders add column assignment_location extensions.geography(Point,4326)
 generated always as (case when latitude between -90 and 90 and longitude between -180 and 180
 then extensions.st_setsrid(extensions.st_makepoint(longitude::double precision,latitude::double precision),4326)::extensions.geography end) stored;
create index fr20_rider_location_idx on public.riders using gist(assignment_location);
-- Legacy coordinates have unknown age and deliberately receive no timestamp.
create unique index fr20_one_active_rider_idx on public.rider_assignments(riderid)where status in('Pending','Accepted');
create unique index fr20_one_active_order_idx on public.rider_assignments(orderid)where status in('Pending','Accepted');
alter table public.orders add column requires_manual_assignment boolean not null default false;
alter table public.notifications add column assignment_order_id bigint references public.orders(id);
alter table public.notifications add column rider_assignment_id bigint references public.rider_assignments(id);
alter table public.notifications add column assignment_event text check(assignment_event in('rider_assigned','manual_assignment'));
create unique index fr20_notification_once_idx on public.notifications(user_id,assignment_order_id,assignment_event)where assignment_event is not null;
alter table public.security_audit_log add column assignment_order_id bigint references public.orders(id);
create unique index fr20_audit_once_idx on public.security_audit_log(assignment_order_id,action)where assignment_order_id is not null;

create function public.fr20_guard_manual_flag()returns trigger language plpgsql set search_path='' as $$begin
 if current_user in('anon','authenticated')and
 ((tg_op='INSERT'and new.requires_manual_assignment)or(tg_op='UPDATE'and new.requires_manual_assignment is distinct from old.requires_manual_assignment))then
  raise exception 'Assignment state is server managed'using errcode='42501';
 end if;return new;
end$$;
create trigger fr20_guard_manual_flag before insert or update on public.orders for each row execute function public.fr20_guard_manual_flag();

create or replace function public.fr21_update_location(p_lat numeric,p_lng numeric)
returns void language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();begin
 if actor is null or not public.fr21_approved_rider(actor)then raise exception 'Approved rider required'using errcode='42501';end if;
 if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Invalid coordinates'using errcode='22023';end if;
 -- Same user -> rider lock order as assignment, approval and FR28 blocking.
 perform 1 from public.users where id=actor and role='rider'and verification_status='approved'and not is_blocked for update;
 if not found then raise exception 'Approved rider required'using errcode='42501';end if;
 insert into public.riders(userid,latitude,longitude,location_updated_at)values(actor,p_lat,p_lng,clock_timestamp())
 on conflict(userid)do update set latitude=excluded.latitude,longitude=excluded.longitude,location_updated_at=excluded.location_updated_at;
end$$;

create function public.fr20_assignment_status(p_vendor_order_id bigint)returns jsonb
language plpgsql security definer set search_path='' as $$
declare a bigint:=public.fr21_actor();vo public.vendor_orders;o public.orders;ra public.rider_assignments;begin
 if a is null or public.fr21_role()is distinct from 'vendor'or not exists(select 1 from public.users where id=a and verification_status='approved'and not is_blocked)then return jsonb_build_object('code','FORBIDDEN');end if;
 select * into vo from public.vendor_orders where id=p_vendor_order_id and vendor_id=a;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 select * into o from public.orders where id=vo.order_id;
 if not found then return jsonb_build_object('code','INVALID_ORDER_STATE');end if;
 select * into ra from public.rider_assignments where orderid=o.id and riderid=o.rider_id and status in('Pending','Accepted');
 if ra.id is not null then return jsonb_build_object('code','ALREADY_ASSIGNED','rider_id',o.rider_id,'assignment_id',ra.id,'order_id',o.id,'message','Order ready; rider already assigned.');end if;
 if o.order_status not in('placed','pending','accepted','preparing','ready','on_the_way')or vo.status not in('pending','accepted','preparing','ready','on_the_way')or o.rider_id is not null then return jsonb_build_object('code','INVALID_ORDER_STATE');end if;
 return jsonb_build_object('code',case when o.requires_manual_assignment then 'NO_RIDER_AVAILABLE'else 'UNASSIGNED'end,'order_id',o.id,'manual_assignment',o.requires_manual_assignment);
end$$;

create or replace function public.fr21_ready_and_assign(p_vendor_order_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();vo public.vendor_orders;o public.orders;r public.riders;u public.users;
 pickup extensions.geography;lat numeric;lng numeric;candidate record;radius integer;dist double precision;assignment bigint;begin
 if actor is null or public.fr21_role()is distinct from 'vendor'or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then return jsonb_build_object('code','FORBIDDEN');end if;
 select * into vo from public.vendor_orders where id=p_vendor_order_id and vendor_id=actor;
 if not found or vo.order_id is null then return jsonb_build_object('code','FORBIDDEN');end if;
 -- Parent -> child -> vendor identity/pickup -> candidate user -> candidate rider.
 select * into o from public.orders where id=vo.order_id for update;
 select * into vo from public.vendor_orders where id=p_vendor_order_id for update;
 if o.id is null or vo.vendor_id is distinct from actor or vo.order_id is distinct from o.id then return jsonb_build_object('code','FORBIDDEN');end if;
 perform 1 from public.users where id=actor and verification_status='approved'and role='vendor'and not is_blocked for share;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if coalesce(o.order_status,'')not in('placed','pending','accepted','preparing','ready','on_the_way')or coalesce(vo.status,'')not in('pending','accepted','preparing','ready','on_the_way')then return jsonb_build_object('code','INVALID_ORDER_STATE');end if;
 if o.rider_id is not null then return public.fr20_assignment_status(p_vendor_order_id);end if;
 select latitude,longitude into lat,lng from public.vendors where user_id=actor for share;
 if lat is null or lng is null or lat not between -90 and 90 or lng not between -180 and 180 then return jsonb_build_object('code','PICKUP_LOCATION_REQUIRED','message','Set your store location before matching a rider.');end if;
 pickup:=extensions.st_setsrid(extensions.st_makepoint(lng::double precision,lat::double precision),4326)::extensions.geography;
 update public.vendor_orders set status='ready'where id=vo.id and status is distinct from 'ready';
 foreach radius in array array[5000,10000]loop
  -- Indexed geographic bound, exact spheroid meters, all candidates ordered
  -- by distance then stable user id. 1 micrometer covers FP boundary roundoff.
  for candidate in select rr.userid,extensions.st_distance(rr.assignment_location,pickup)as meters
   from public.riders rr join public.users uu on uu.id=rr.userid
   where rr.is_online and rr.is_available and rr.isavailable
    and rr.last_seen>=clock_timestamp()-interval '2 minutes'and rr.location_updated_at>=clock_timestamp()-interval '2 minutes'
    and uu.role='rider'and uu.verification_status='approved'and not uu.is_blocked
    and extensions.st_dwithin(rr.assignment_location,pickup,radius+0.000001)
    and not exists(select 1 from public.orders busy where busy.rider_id=rr.userid and(busy.order_status is null or busy.order_status not in('delivered','cancelled')))
    and not exists(select 1 from public.rider_assignments busy where busy.riderid=rr.userid and busy.status in('Pending','Accepted'))
   order by meters,rr.userid
  loop
   select * into u from public.users where id=candidate.userid for update skip locked;
   if not found then continue;end if;
   select * into r from public.riders where userid=candidate.userid for update skip locked;
   if not found then continue;end if;
   if u.role<>'rider'or u.verification_status is distinct from 'approved'or u.is_blocked
    or r.is_online is distinct from true or r.is_available is distinct from true or r.isavailable is distinct from true
    or r.last_seen is null or r.last_seen<clock_timestamp()-interval '2 minutes'
    or r.location_updated_at is null or r.location_updated_at<clock_timestamp()-interval '2 minutes'
    or r.assignment_location is null then continue;end if;
   dist:=extensions.st_distance(r.assignment_location,pickup);
   if dist>radius+0.000001 or exists(select 1 from public.orders busy where busy.rider_id=r.userid and(busy.order_status is null or busy.order_status not in('delivered','cancelled')))
    or exists(select 1 from public.rider_assignments busy where busy.riderid=r.userid and busy.status in('Pending','Accepted'))then continue;end if;
   insert into public.rider_assignments(riderid,orderid,status)values(r.userid,o.id,'Pending')returning id into assignment;
   update public.orders set rider_id=r.userid,requires_manual_assignment=false,delivery_otp=null where id=o.id;
   update public.riders set is_available=false,isavailable=false where id=r.id;
   update public.vendor_orders set status='on_the_way'where id=vo.id and status is distinct from 'on_the_way';
   insert into public.notifications(user_id,title,message,type,assignment_order_id,rider_assignment_id,assignment_event)
    values(r.userid,'New Delivery Assigned','New delivery job assigned.','order',o.id,assignment,'rider_assigned');
   insert into public.security_audit_log(actor_id,action,target_type,target_id,assignment_order_id)
    values(actor,'RIDER_ASSIGNED','order',o.id,o.id);
   return jsonb_build_object('code',case radius when 5000 then 'ASSIGNED_5KM'else 'ASSIGNED_10KM'end,'rider_id',r.userid,'assignment_id',assignment,'order_id',o.id,'search_radius_m',radius,'distance_m',dist,
    'message',case radius when 5000 then 'Order ready; rider assigned within 5 km.'else 'Order ready; rider assigned after expanding the search to 10 km.'end);
  end loop;
 end loop;
 update public.orders set requires_manual_assignment=true where id=o.id and not requires_manual_assignment;
 insert into public.notifications(user_id,title,message,type,assignment_order_id,assignment_event)
  select id,'Manual rider assignment required','No eligible rider within 10 km for order #'||o.id||'. Manual assignment required.','order',o.id,'manual_assignment'
  from public.users where role='admin'and verification_status='approved'and not is_blocked
  on conflict(user_id,assignment_order_id,assignment_event)where assignment_event is not null do nothing;
 insert into public.security_audit_log(actor_id,action,target_type,target_id,assignment_order_id)
  values(actor,'RIDER_ASSIGNMENT_ESCALATED','order',o.id,o.id)
  on conflict(assignment_order_id,action)where assignment_order_id is not null do nothing;
 return jsonb_build_object('code','NO_RIDER_AVAILABLE','order_id',o.id,'manual_assignment',true,'search_radius_m',10000,'message','Order ready. No eligible rider within 10 km. Administrators notified for manual assignment.');
exception when lock_not_available or deadlock_detected or unique_violation or serialization_failure then
 return jsonb_build_object('code','RETRYABLE_CONFLICT','message','Assignment is busy. Refresh the result and retry.');
end$$;

-- Existing rider acceptance remains available; recheck blocked state after the
-- same user lock, and let the active unique indexes protect every insert path.
do $$declare source text;begin
 source:=pg_get_functiondef('public.fr21_accept_order(bigint)'::regprocedure);
 if position('where id=actor and role=''rider'' and verification_status=''approved'' for update'in source)=0 then raise exception 'Review changed rider acceptance implementation';end if;
 source:=replace(source,'where id=actor and role=''rider'' and verification_status=''approved'' for update','where id=actor and role=''rider'' and verification_status=''approved'' and not is_blocked for update');
 execute source;
end$$;
revoke all on function public.fr20_guard_manual_flag(),public.fr20_assignment_status(bigint),public.fr21_ready_and_assign(bigint),public.fr21_update_location(numeric,numeric)from public,anon;
grant execute on function public.fr20_assignment_status(bigint),public.fr21_ready_and_assign(bigint),public.fr21_update_location(numeric,numeric)to authenticated,service_role;
notify pgrst,'reload schema';
commit;
