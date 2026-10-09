-- FR-21. Apply this file alone only after backup/recovery validation and approval.
-- Verification remains users.verification_status; no account or approval backfill.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
alter table public.riders add column if not exists is_online boolean not null default false;
alter table public.riders add column if not exists last_seen timestamptz;
alter table public.riders add column if not exists presence_epoch bigint not null default 0;
alter table public.riders add column if not exists presence_sequence bigint not null default 0;
do $$ begin
  if exists(select 1 from public.riders where userid is not null group by userid having count(*)>1) then
    raise exception 'Duplicate rider profiles require owner review'; end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='riders'
    and ((column_name='is_online' and udt_name<>'bool') or (column_name='last_seen' and udt_name<>'timestamptz')
      or (column_name in ('presence_epoch','presence_sequence') and udt_name<>'int8'))) then
    raise exception 'Existing presence columns have incompatible types'; end if;
end $$;
create unique index if not exists fr21_rider_user_idx on public.riders(userid);
create index if not exists fr21_rider_presence_idx on public.riders(is_online,last_seen);
create index if not exists fr21_user_verification_idx on public.users(role,verification_status,id);
-- vendors.user_id already has a unique index in the inspected live schema.
create index if not exists fr21_vendor_order_idx on public.vendor_orders(order_id,vendor_id);
create index if not exists fr21_vendor_owned_order_idx on public.vendor_orders(vendor_id,order_id);
create index if not exists fr21_order_rider_idx on public.orders(rider_id,order_status);
create index if not exists fr21_available_order_idx on public.orders(order_status,created_at desc)
  where rider_id is null;
create index if not exists fr21_assignment_order_idx on public.rider_assignments(orderid);
create index if not exists fr21_assignment_rider_idx on public.rider_assignments(riderid);

create or replace function public.fr21_actor()
returns bigint language sql stable security definer set search_path='' as $$
  select u.id from public.users u join auth.users a on a.email=u.email
  where a.id=(select auth.uid()) and a.email_confirmed_at is not null
$$;
create or replace function public.fr21_role()
returns text language sql stable security definer set search_path='' as $$
  select case when role='admin' and verification_status is distinct from 'approved'
    then null else role end from public.users where id=public.fr21_actor()
$$;
create or replace function public.fr21_approved_rider(p_id bigint)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.users where id=p_id and role='rider' and verification_status='approved')
$$;
create or replace function public.fr21_order_visible(p_id bigint)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.orders o where o.id=p_id and (
    o.user_id=public.fr21_actor() or o.rider_id=public.fr21_actor() or public.fr21_role()='admin'
    or exists(select 1 from public.vendor_orders vo where vo.order_id=o.id and vo.vendor_id=public.fr21_actor())
    or (o.rider_id is null and o.order_status in ('placed','accepted')
      and public.fr21_approved_rider(public.fr21_actor()) and exists(select 1 from public.riders r
        where r.userid=public.fr21_actor() and r.is_online is true
        and r.last_seen>=statement_timestamp()-interval '2 minutes'))))
$$;
alter table public.users enable row level security;
alter table public.riders enable row level security;
alter table public.orders enable row level security;
alter table public.vendor_orders enable row level security;
alter table public.rider_assignments enable row level security;
alter table public.vendors enable row level security;
alter table public.notifications enable row level security;
-- Only FR-21 policy names are managed; legacy policies remain intact.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='riders' and policyname='fr21_presence_owner') then
    create policy fr21_presence_owner on public.riders for update to authenticated
      using(userid=(select public.fr21_actor()) and (select public.fr21_role())='rider')
      with check(userid=(select public.fr21_actor()) and (select public.fr21_role())='rider'); end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='riders' and policyname='fr21_presence_owner_guard') then
    create policy fr21_presence_owner_guard on public.riders as restrictive for update to authenticated
      using(userid=(select public.fr21_actor()) and (select public.fr21_role())='rider')
      with check(userid=(select public.fr21_actor()) and (select public.fr21_role())='rider'); end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='riders' and policyname='fr21_presence_read') then
    create policy fr21_presence_read on public.riders for select to authenticated using(userid=(select public.fr21_actor())); end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='users' and policyname='fr21_profile_owner_guard') then
    create policy fr21_profile_owner_guard on public.users as restrictive for update to authenticated
      using(id=(select public.fr21_actor()) or (select public.fr21_role())='admin')
      with check(id=(select public.fr21_actor()) or (select public.fr21_role())='admin'); end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='vendor_orders' and policyname='fr21_vendor_owner_guard') then
    create policy fr21_vendor_owner_guard on public.vendor_orders as restrictive for update to authenticated
      using(vendor_id=(select public.fr21_actor()) or (select public.fr21_role())='admin')
      with check(vendor_id=(select public.fr21_actor()) or (select public.fr21_role())='admin'); end if;
end $$;
revoke insert,update,delete,truncate,trigger on public.riders from public,anon,authenticated;
revoke truncate,trigger on public.users,public.orders,public.vendor_orders,
  public.rider_assignments,public.vendors,public.notifications from public,anon,authenticated;
do $$ declare c record; begin
  for c in select column_name from information_schema.columns where table_schema='public' and table_name='riders' loop
    execute format('revoke update (%I),insert (%I) on public.riders from public,anon,authenticated',c.column_name,c.column_name);
  end loop;
end $$;
grant select(is_online,last_seen,userid) on public.riders to authenticated;
grant update(is_online,last_seen) on public.riders to authenticated;

create or replace function public.fr21_guard_rider()
returns trigger language plpgsql set search_path='' as $$
begin
  if current_user in ('authenticated','anon') then
    if public.fr21_role() is distinct from 'rider' or new.userid is distinct from public.fr21_actor()
      or (to_jsonb(new)-array['is_online','last_seen']) is distinct from
         (to_jsonb(old)-array['is_online','last_seen']) then
      raise exception 'Only own presence may be updated' using errcode='42501'; end if;
    if new.is_online is true and not public.fr21_approved_rider(old.userid) then
      raise exception 'Rider approval required' using errcode='42501'; end if;
    new.last_seen:=clock_timestamp();
  end if;
  return new;
end $$;
create or replace trigger fr21_guard_rider before update on public.riders
  for each row execute function public.fr21_guard_rider();
create or replace function public.fr21_guard_identity()
returns trigger language plpgsql set search_path='' as $$
begin
  if current_user in ('authenticated','anon') then
    if tg_op='INSERT' then
      if auth.uid() is null or new.role is null or new.role not in ('customer','vendor','rider')
        or new.email is distinct from (auth.jwt()->>'email') then
        raise exception 'Invalid account identity' using errcode='42501'; end if;
      new.verification_status:=case when new.role='customer' then 'approved' else 'pending' end;
    else
      if new.id is distinct from old.id or new.email is distinct from old.email or new.role is distinct from old.role then
        raise exception 'Account identity is server managed' using errcode='42501'; end if;
      if new.verification_status is distinct from old.verification_status then
        if public.fr21_role() is distinct from 'admin' then
          raise exception 'Approval is admin managed' using errcode='42501'; end if;
        if new.verification_status is null or new.verification_status not in ('pending','approved','rejected','suspended') then
          raise exception 'Invalid approval status' using errcode='22023'; end if;
      end if;
    end if;
  end if;
  return new;
end $$;
create or replace trigger fr21_guard_identity before insert or update on public.users
  for each row execute function public.fr21_guard_identity();

create or replace function public.fr21_begin_presence()
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.riders; actor bigint:=public.fr21_actor(); begin
  if actor is null or public.fr21_role() is distinct from 'rider' then
    raise exception 'Rider authentication required' using errcode='42501'; end if;
  -- Signup omitted rider rows. Provision only the caller; never repair legacy identities.
  insert into public.riders(userid) values(actor) on conflict(userid) do nothing;
  update public.riders set presence_epoch=coalesce(presence_epoch,0)+1,presence_sequence=0,
    is_online=coalesce(is_online and public.fr21_approved_rider(actor)
      and last_seen>=clock_timestamp()-interval '2 minutes',false),
    last_seen=case when is_online and public.fr21_approved_rider(actor)
      and last_seen>=clock_timestamp()-interval '2 minutes' then clock_timestamp() else last_seen end
    where userid=actor returning * into r;
  return jsonb_build_object('epoch',r.presence_epoch,'is_online',r.is_online,'last_seen',r.last_seen);
end $$;
create or replace function public.fr21_set_presence(p_online boolean,p_epoch bigint,p_sequence bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.riders; actor bigint:=public.fr21_actor(); begin
  if actor is null or public.fr21_role() is distinct from 'rider' then
    raise exception 'Rider authentication required' using errcode='42501'; end if;
  if p_online is null or p_epoch is null or p_epoch<1 or p_sequence is null or p_sequence<1 then
    raise exception 'Invalid presence request' using errcode='22023'; end if;
  select * into r from public.riders where userid=actor for update;
  if not found then raise exception 'Rider profile missing' using errcode='P0002'; end if;
  if coalesce(r.presence_epoch,0)<>p_epoch or p_sequence<coalesce(r.presence_sequence,0) then
    raise exception 'Stale presence request' using errcode='40001'; end if;
  if p_sequence=coalesce(r.presence_sequence,0) then
    if p_online is distinct from r.is_online then
      raise exception 'Sequence reused with different intent' using errcode='22023'; end if;
    return jsonb_build_object('is_online',r.is_online,'last_seen',r.last_seen);
  end if;
  if p_online and not public.fr21_approved_rider(actor) then
    raise exception 'Rider approval required' using errcode='42501'; end if;
  update public.riders set is_online=p_online,last_seen=clock_timestamp(),presence_sequence=p_sequence
    where id=r.id returning * into r;
  return jsonb_build_object('is_online',r.is_online,'last_seen',r.last_seen);
end $$;
create or replace function public.fr21_update_location(p_lat numeric,p_lng numeric)
returns void language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); begin
  if actor is null or not public.fr21_approved_rider(actor) then
    raise exception 'Approved rider required' using errcode='42501'; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Invalid coordinates' using errcode='22023'; end if;
  insert into public.riders(userid,latitude,longitude) values(actor,p_lat,p_lng)
    on conflict(userid) do update set latitude=excluded.latitude,longitude=excluded.longitude;
end $$;
create or replace function public.fr21_ready_and_assign(p_vendor_order_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); vo public.vendor_orders; o public.orders;
  rider public.riders; lat numeric; lng numeric; distance double precision; begin
  if actor is null or public.fr21_role() is distinct from 'vendor' or not exists(select 1
    from public.users where id=actor and verification_status='approved') then
    raise exception 'Approved vendor required' using errcode='42501'; end if;
  if p_vendor_order_id is null then raise exception 'Missing order' using errcode='22023'; end if;
  select * into vo from public.vendor_orders where id=p_vendor_order_id;
  if not found or vo.vendor_id is distinct from actor then
    raise exception 'Vendor order forbidden' using errcode='42501'; end if;
  if vo.order_id is null then raise exception 'Missing parent order' using errcode='22023'; end if;
  -- Parent -> vendor order -> rider. Duplicate/multi-vendor calls serialize.
  select * into o from public.orders where id=vo.order_id for update;
  if not found then raise exception 'Parent order missing' using errcode='P0002'; end if;
  select * into vo from public.vendor_orders where id=p_vendor_order_id for update;
  if vo.vendor_id is distinct from actor or vo.order_id is distinct from o.id then
    raise exception 'Vendor order changed' using errcode='40001'; end if;
  if coalesce(o.order_status,'') not in ('placed','pending','accepted','preparing','ready','on_the_way')
    or coalesce(vo.status,'') not in ('pending','accepted','preparing','ready','on_the_way') then
    raise exception 'Order is closed or invalid' using errcode='22023'; end if;
  -- Keep the existing trigger's parent-status propagation and notifications.
  update public.vendor_orders set status='on_the_way' where id=vo.id and status is distinct from 'on_the_way';
  if o.rider_id is not null then
    return jsonb_build_object('message','Order ready; rider already assigned.','rider_id',o.rider_id); end if;
  select latitude,longitude into lat,lng from public.vendors where user_id=actor;
  if lat is null or lng is null then
    return jsonb_build_object('message','Order ready. Set your store location to match a rider.'); end if;
  if lat not between -90 and 90 or lng not between -180 and 180 then
    raise exception 'Invalid store coordinates' using errcode='22023'; end if;
  select r.* into rider from public.riders r join public.users u on u.id=r.userid
    where r.is_online is true and r.is_available is true and r.isavailable is true
      and r.last_seen>=statement_timestamp()-interval '2 minutes'
      and u.role='rider' and u.verification_status='approved'
      and r.latitude between -90 and 90 and r.longitude between -180 and 180
      and not exists(select 1 from public.orders busy where busy.rider_id=r.userid
        and (busy.order_status is null or busy.order_status not in ('cancelled','delivered')))
    order by (sin(radians((r.latitude-lat)::double precision)/2)^2
      + cos(radians(lat::double precision))*cos(radians(r.latitude::double precision))
      * sin(radians((r.longitude-lng)::double precision)/2)^2),r.id
    limit 1 for update of r,u skip locked;
  if not found then return jsonb_build_object('message','Order ready. No online approved fresh rider is available.'); end if;
  if rider.last_seen<clock_timestamp()-interval '2 minutes' then
    return jsonb_build_object('message','Order ready. Rider heartbeat expired; retry matching.'); end if;
  distance:=6371*2*asin(sqrt(least(1::double precision,
    sin(radians((rider.latitude-lat)::double precision)/2)^2
    + cos(radians(lat::double precision))*cos(radians(rider.latitude::double precision))
    * sin(radians((rider.longitude-lng)::double precision)/2)^2)));
  -- Existing ready-status trigger exposes this as the rider's active delivery;
  -- issue its OTP in the same transaction rather than require a second accept.
  update public.orders set rider_id=rider.userid,
    delivery_otp=coalesce(delivery_otp,lpad(floor(random()*1000000)::int::text,6,'0')) where id=o.id;
  insert into public.rider_assignments(riderid,orderid,status) values(rider.userid,o.id,'Pending');
  update public.riders set is_available=false,isavailable=false where id=rider.id;
  insert into public.notifications(user_id,title,message,type)
    values(rider.userid,'New Delivery Assigned','You have a new pickup ready for delivery.','order');
  return jsonb_build_object('message',format('Order ready; rider assigned, %s km from your shop.',round(distance::numeric,1)),
    'rider_id',rider.userid);
end $$;
create or replace function public.fr21_accept_order(p_order_id bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); o public.orders; r public.riders; otp text; begin
  if not public.fr21_approved_rider(actor) then raise exception 'Approved rider required' using errcode='42501'; end if;
  select * into o from public.orders where id=p_order_id for update;
  if not found then raise exception 'Order missing' using errcode='P0002'; end if;
  if o.rider_id is not null and o.rider_id<>actor then raise exception 'Order assigned to another rider' using errcode='42501'; end if;
  if coalesce(o.order_status,'') not in ('placed','accepted','ready','on_the_way') then
    raise exception 'Order cannot be accepted' using errcode='22023'; end if;
  perform 1 from public.users where id=actor and role='rider' and verification_status='approved' for update;
  if not found then raise exception 'Rider approval changed' using errcode='42501'; end if;
  select * into r from public.riders where userid=actor for update;
  if not found or r.is_online is distinct from true or r.last_seen is null
    or r.last_seen<clock_timestamp()-interval '2 minutes' then
    raise exception 'Fresh online presence required' using errcode='42501'; end if;
  if exists(select 1 from public.orders where rider_id=actor and id<>o.id
    and (order_status is null or order_status not in ('cancelled','delivered'))) then
    raise exception 'Another delivery is active' using errcode='22023'; end if;
  if o.rider_id is null then
    if r.is_available is distinct from true or r.isavailable is distinct from true then
      raise exception 'Rider unavailable' using errcode='22023'; end if;
    insert into public.rider_assignments(riderid,orderid,status) values(actor,o.id,'Accepted');
  else
    update public.rider_assignments set status='Accepted' where orderid=o.id and riderid=actor and status='Pending';
  end if;
  otp:=coalesce(o.delivery_otp,lpad(floor(random()*1000000)::int::text,6,'0'));
  update public.orders set rider_id=actor,order_status='on_the_way',delivery_otp=otp where id=o.id;
  update public.riders set is_available=false,isavailable=false where id=r.id;
  return jsonb_build_object('delivery_otp',otp,'order_status','on_the_way','rider_id',actor);
end $$;
create or replace function public.fr21_complete_delivery(p_order_id bigint,p_otp text)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); o public.orders; begin
  if actor is null or public.fr21_role() is distinct from 'rider' then
    raise exception 'Rider required' using errcode='42501'; end if;
  select * into o from public.orders where id=p_order_id for update;
  if not found or o.rider_id is distinct from actor then raise exception 'Delivery forbidden' using errcode='42501'; end if;
  if p_otp is null or p_otp !~ '^[0-9]{6}$' or o.delivery_otp is distinct from p_otp then return false; end if;
  if o.order_status='delivered' then return true; end if;
  if o.order_status is distinct from 'on_the_way' then raise exception 'Delivery is not active' using errcode='22023'; end if;
  perform 1 from public.riders where userid=actor for update;
  update public.orders set order_status='delivered' where id=o.id;
  update public.rider_assignments set status='Delivered' where orderid=o.id and riderid=actor;
  update public.riders set is_available=true,isavailable=true where userid=actor
    and not exists(select 1 from public.orders where rider_id=actor
      and (order_status is null or order_status not in ('cancelled','delivered')));
  return true;
end $$;
create or replace function public.fr21_guard_assignment()
returns trigger language plpgsql set search_path='' as $$
begin
  if current_user in ('authenticated','anon') then
    raise exception 'Use transactional rider assignment' using errcode='42501'; end if;
  return coalesce(new,old);
end $$;
create or replace trigger fr21_guard_assignment before insert or update or delete on public.rider_assignments
  for each row execute function public.fr21_guard_assignment();
create or replace function public.fr21_guard_order_assignment()
returns trigger language plpgsql set search_path='' as $$
begin
  if current_user in ('authenticated','anon') then
    if (tg_op='INSERT' and new.rider_id is not null) or
      (tg_op='UPDATE' and (new.rider_id is distinct from old.rider_id or new.delivery_otp is distinct from old.delivery_otp)) then
      raise exception 'Use transactional rider assignment' using errcode='42501'; end if;
    if tg_op='UPDATE' and public.fr21_role()='rider' and new.order_status is distinct from old.order_status then
      raise exception 'Use transactional delivery completion' using errcode='42501'; end if;
    if tg_op='UPDATE' and new.order_status='cancelled' and old.order_status is distinct from 'cancelled'
      and public.fr21_role() is distinct from 'admin' and not coalesce((
        (public.fr21_role()='customer' and old.user_id=public.fr21_actor()) or
        (public.fr21_role()='vendor' and exists(select 1 from public.vendor_orders
          where order_id=old.id and vendor_id=public.fr21_actor()))),false) then
      raise exception 'Order cancellation forbidden' using errcode='42501'; end if;
  end if;
  return new;
end $$;
create or replace trigger fr21_guard_order_assignment before insert or update on public.orders
  for each row execute function public.fr21_guard_order_assignment();
-- Ownership cannot be forged before invoking the vendor assignment RPC.
create or replace function public.fr21_guard_vendor_order()
returns trigger language plpgsql set search_path='' as $$
begin
  if current_user in ('authenticated','anon') then
    if tg_op='UPDATE' and (new.id is distinct from old.id or new.order_id is distinct from old.order_id
      or new.vendor_id is distinct from old.vendor_id) then
      raise exception 'Vendor order ownership is immutable' using errcode='42501'; end if;
    if tg_op='INSERT' and public.fr21_role() is distinct from 'admin' and not exists(
      select 1 from public.orders where id=new.order_id and user_id=public.fr21_actor()) then
      raise exception 'Only the order customer may create vendor orders' using errcode='42501'; end if;
  end if;
  return new;
end $$;
create or replace trigger fr21_guard_vendor_order before insert or update on public.vendor_orders
  for each row execute function public.fr21_guard_vendor_order();
-- Existing cancellation flows must release a reservation without client access
-- to protected availability fields. This runs in the cancelling transaction.
create or replace function public.fr21_release_cancelled()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.order_status='cancelled' and old.order_status is distinct from 'cancelled'
    and new.rider_id is not null and exists(select 1 from public.rider_assignments
      where orderid=new.id and riderid=new.rider_id and status in ('Pending','Accepted')) then
    perform 1 from public.riders where userid=new.rider_id for update;
    update public.rider_assignments set status='Cancelled' where orderid=new.id and riderid=new.rider_id
      and status in ('Pending','Accepted');
    update public.riders set is_available=true,isavailable=true where userid=new.rider_id
      and not exists(select 1 from public.orders where rider_id=new.rider_id
        and (order_status is null or order_status not in ('cancelled','delivered')));
  end if;
  return new;
end $$;
create or replace trigger fr21_release_cancelled after update of order_status on public.orders
  for each row execute function public.fr21_release_cancelled();
revoke all on function public.fr21_actor(),public.fr21_role(),public.fr21_approved_rider(bigint),
  public.fr21_order_visible(bigint),public.fr21_begin_presence(),public.fr21_set_presence(boolean,bigint,bigint),
  public.fr21_update_location(numeric,numeric),public.fr21_ready_and_assign(bigint),public.fr21_accept_order(bigint),
  public.fr21_complete_delivery(bigint,text) from public,anon;
grant execute on function public.fr21_actor(),public.fr21_role(),public.fr21_approved_rider(bigint),
  public.fr21_order_visible(bigint),public.fr21_begin_presence(),public.fr21_set_presence(boolean,bigint,bigint),
  public.fr21_update_location(numeric,numeric),public.fr21_ready_and_assign(bigint),public.fr21_accept_order(bigint),
  public.fr21_complete_delivery(bigint,text) to authenticated;
revoke all on function public.fr21_guard_rider(),public.fr21_guard_identity(),
  public.fr21_guard_assignment(),public.fr21_guard_order_assignment(),public.fr21_guard_vendor_order(),
  public.fr21_release_cancelled() from public,anon,authenticated;
-- Make the new RPC signatures visible immediately after the transaction commits.
notify pgrst, 'reload schema';
commit;
