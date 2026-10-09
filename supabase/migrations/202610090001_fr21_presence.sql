-- FR-21. Apply to a clone first. Never run the legacy destructive schema files.
begin;

alter table public.riders add column if not exists is_online boolean not null default false;
alter table public.riders add column if not exists last_seen timestamptz;
-- Only newly introduced verification is backfilled from existing admin approval.
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
      and table_name = 'riders' and column_name = 'is_verified') then
    alter table public.riders add column is_verified boolean not null default false;
    update public.riders r set is_verified = true from public.users u
      where r.userid = u.id and u.role = 'rider' and u.verification_status = 'approved';
  end if;
end $$;
alter table public.riders add column if not exists presence_epoch bigint not null default 0;
alter table public.riders add column if not exists presence_sequence bigint not null default 0;

create index if not exists fr21_rider_presence_idx on public.riders(is_online, is_verified, last_seen);
create unique index if not exists fr21_rider_user_idx on public.riders(userid);
create index if not exists fr21_vendor_user_idx on public.vendors(user_id);
create index if not exists fr21_vendor_order_idx on public.vendor_orders(order_id, vendor_id);
create index if not exists fr21_vendor_owned_order_idx on public.vendor_orders(vendor_id, order_id);
create index if not exists fr21_order_rider_idx on public.orders(rider_id, order_status);
create index if not exists fr21_order_user_idx on public.orders(user_id);
create index if not exists fr21_assignment_order_idx on public.rider_assignments(orderid);
create index if not exists fr21_assignment_rider_idx on public.rider_assignments(riderid);
create index if not exists fr21_notification_user_idx on public.notifications(user_id);
create index if not exists fr21_available_rider_idx on public.riders(last_seen)
  where is_online and is_verified and is_available;
create index if not exists fr21_available_order_idx on public.orders(order_status,created_at desc)
  where rider_id is null;
-- users.email is already UNIQUE in schema.sql; auth.users.id and users.id are PKs.

create or replace function public.fr21_actor()
returns bigint language sql stable security definer set search_path = '' as $$
  select u.id from public.users u join auth.users a on a.email = u.email
  where a.id = (select auth.uid()) and a.email_confirmed_at is not null
$$;
create or replace function public.fr21_role()
returns text language sql stable security definer set search_path = '' as $$
  select role from public.users where id = public.fr21_actor()
$$;

-- Indexed participant lookup, independent of callers' SELECT policies.
create or replace function public.fr21_order_visible(p_order_id bigint)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.orders o where o.id = p_order_id and (
    o.user_id = public.fr21_actor() or o.rider_id = public.fr21_actor()
    or public.fr21_role() = 'admin'
    or exists (select 1 from public.vendor_orders vo where vo.order_id = o.id
      and vo.vendor_id = public.fr21_actor())
    or (o.rider_id is null and o.order_status in ('placed','accepted')
      and public.fr21_role() = 'rider' and exists (
      select 1 from public.riders r where r.userid = public.fr21_actor()
      and r.is_online and r.is_verified and r.last_seen >= now() - interval '2 minutes'))))
$$;

-- Preserve other policies; restrictive policies cannot be bypassed by a legacy
-- permissive USING(true). Definer RPCs below validate the actor explicitly.
alter table public.users enable row level security;
alter table public.riders enable row level security;
alter table public.vendors enable row level security;
alter table public.orders enable row level security;
alter table public.vendor_orders enable row level security;
alter table public.rider_assignments enable row level security;
alter table public.notifications enable row level security;
create policy fr21_self_user_read on public.users for select to authenticated
  using (id = (select public.fr21_actor()));
create policy fr21_self_profile_update on public.users for update to authenticated
  using (id = (select public.fr21_actor()) or (select public.fr21_role()) = 'admin')
  with check (id = (select public.fr21_actor()) or (select public.fr21_role()) = 'admin');
create policy fr21_participant_order_read on public.orders for select to authenticated
  using (public.fr21_order_visible(id));
create policy fr21_participant_vendor_order_read on public.vendor_orders for select to authenticated
  using (public.fr21_order_visible(order_id));
create policy fr21_self_vendor_read on public.vendors for select to authenticated
  using (user_id = (select public.fr21_actor()));
create policy fr21_self_notification_read on public.notifications for select to authenticated
  using (user_id = (select public.fr21_actor()));
create policy fr21_self_rider_read on public.riders for select to authenticated
  using (userid = (select public.fr21_actor()));
create policy fr21_self_rider_update on public.riders for update to authenticated
  using (userid = (select public.fr21_actor()) and (select public.fr21_role()) = 'rider')
  with check (userid = (select public.fr21_actor()) and (select public.fr21_role()) = 'rider');
create policy fr21_rider_owner_guard on public.riders as restrictive for update to authenticated
  using (userid = (select public.fr21_actor()) and (select public.fr21_role()) = 'rider')
  with check (userid = (select public.fr21_actor()) and (select public.fr21_role()) = 'rider');
create policy fr21_assignment_write_guard on public.rider_assignments as restrictive for all to authenticated
  using (riderid = (select public.fr21_actor())) with check (false);
create policy fr21_assignment_read on public.rider_assignments for select to authenticated
  using (riderid = (select public.fr21_actor()));

-- Table grants alone do not revoke existing column grants.
revoke insert, update, delete on public.riders from public, anon, authenticated;
do $$ declare c record; begin
  for c in select column_name from information_schema.columns
    where table_schema = 'public' and table_name = 'riders' loop
    execute format('revoke update (%I) on public.riders from public, anon, authenticated', c.column_name);
    execute format('revoke insert (%I) on public.riders from public, anon, authenticated', c.column_name);
  end loop;
end $$;
grant select(is_online, last_seen, userid) on public.riders to authenticated;
grant update(is_online, last_seen) on public.riders to authenticated;

create or replace function public.fr21_guard_rider()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon') then
    if public.fr21_role() <> 'rider' or new.userid is distinct from public.fr21_actor()
      or (to_jsonb(new) - array['is_online','last_seen']) is distinct from
         (to_jsonb(old) - array['is_online','last_seen']) then
      raise exception 'Only own presence may be updated' using errcode = '42501';
    end if;
    if new.is_online and (old.is_verified is distinct from true or not exists (
      select 1 from public.users where id = old.userid and verification_status = 'approved')) then
      raise exception 'Rider is not verified' using errcode = '42501';
    end if;
    new.last_seen := clock_timestamp();
  end if;
  return new;
end $$;
create trigger fr21_guard_rider before update on public.riders
for each row execute function public.fr21_guard_rider();

-- Stop client role/approval escalation that would invalidate RPC authorization.
create or replace function public.fr21_guard_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated','anon') then
    if tg_op = 'INSERT' then
      if auth.uid() is null or new.role not in ('customer','vendor','rider')
        or new.email is distinct from (auth.jwt()->>'email') then
        raise exception 'Invalid account identity' using errcode = '42501';
      end if;
      if new.role in ('rider','vendor') then new.verification_status := 'pending'; end if;
    elsif public.fr21_role() is distinct from 'admin' and (
      new.role is distinct from old.role or new.email is distinct from old.email
      or new.id is distinct from old.id or new.verification_status is distinct from old.verification_status) then
      raise exception 'Identity/approval is server managed' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger fr21_guard_identity before insert or update on public.users
for each row execute function public.fr21_guard_identity();

create or replace function public.fr21_sync_verification()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.riders set is_verified = (new.role = 'rider' and new.verification_status = 'approved'),
    is_online = case when new.role = 'rider' and new.verification_status = 'approved'
      then is_online else false end where userid = new.id;
  return new;
end $$;
create trigger fr21_sync_verification after update of verification_status, role on public.users
for each row execute function public.fr21_sync_verification();

create or replace function public.fr21_begin_presence()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.riders; actor bigint := public.fr21_actor(); begin
  if actor is null or public.fr21_role() is distinct from 'rider' then
    raise exception 'Rider authentication required' using errcode = '42501'; end if;
  update public.riders set presence_epoch = presence_epoch + 1, presence_sequence = 0,
    last_seen = case when is_online and is_verified and last_seen >= clock_timestamp() - interval '2 minutes'
      then clock_timestamp() else last_seen end,
    is_online = coalesce(is_online and is_verified and last_seen >= clock_timestamp() - interval '2 minutes', false)
    where userid = actor returning * into r;
  if not found then raise exception 'Rider profile missing' using errcode = 'P0002'; end if;
  return jsonb_build_object('epoch', r.presence_epoch, 'is_online', r.is_online, 'last_seen', r.last_seen);
end $$;

create or replace function public.fr21_set_presence(p_online boolean, p_epoch bigint, p_sequence bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.riders; actor bigint := public.fr21_actor(); begin
  if actor is null or public.fr21_role() is distinct from 'rider' then
    raise exception 'Rider authentication required' using errcode = '42501'; end if;
  if p_online is null or p_epoch is null or p_sequence is null or p_sequence < 1 then
    raise exception 'Invalid presence request' using errcode = '22023'; end if;
  select * into r from public.riders where userid = actor for update;
  if not found then raise exception 'Rider profile missing' using errcode = 'P0002'; end if;
  if r.presence_epoch <> p_epoch or p_sequence < r.presence_sequence then
    raise exception 'Stale presence request' using errcode = '40001'; end if;
  if p_sequence = r.presence_sequence then
    return jsonb_build_object('is_online', r.is_online, 'last_seen', r.last_seen);
  end if;
  if p_online and (r.is_verified is distinct from true or not exists (select 1 from public.users
    where id = actor and verification_status = 'approved')) then
    raise exception 'Rider is not verified' using errcode = '42501'; end if;
  update public.riders set is_online = p_online, last_seen = clock_timestamp(),
    presence_sequence = p_sequence where userid = actor returning * into r;
  return jsonb_build_object('is_online', r.is_online, 'last_seen', r.last_seen);
end $$;

create or replace function public.fr21_ready_and_assign(p_vendor_order_id bigint)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor bigint := public.fr21_actor(); vo public.vendor_orders; o public.orders;
  rider public.riders; lat numeric; lng numeric; distance double precision; begin
  if actor is null or public.fr21_role() is distinct from 'vendor' then
    raise exception 'Vendor authentication required' using errcode = '42501'; end if;
  if not exists (select 1 from public.users where id = actor and verification_status = 'approved') then
    raise exception 'Vendor approval required' using errcode = '42501'; end if;
  select * into vo from public.vendor_orders where id = p_vendor_order_id;
  if not found or vo.vendor_id <> actor then
    raise exception 'Vendor order forbidden' using errcode = '42501'; end if;
  if vo.order_id is null then
    raise exception 'Vendor order has no parent' using errcode = '22023'; end if;
  -- All callers lock the parent first: duplicate and multi-vendor calls serialize.
  select * into o from public.orders where id = vo.order_id for update;
  if not found then raise exception 'Parent order missing' using errcode = 'P0002'; end if;
  select * into vo from public.vendor_orders where id = p_vendor_order_id for update;
  if not found or vo.vendor_id <> actor then
    raise exception 'Vendor order forbidden' using errcode = '42501'; end if;
  if o.order_status in ('cancelled','delivered') or vo.status in ('cancelled','delivered') then
    raise exception 'Order is closed' using errcode = '22023'; end if;
  update public.vendor_orders set status = 'on_the_way' where id = vo.id;
  if o.rider_id is not null then
    return jsonb_build_object('message','Order ready; rider already assigned.', 'rider_id', o.rider_id);
  end if;
  -- Legacy checked-in vendor DDL has no coordinates. Missing keys stay null;
  -- reuse existing location columns when present instead of adding new ones.
  select (to_jsonb(v)->>'latitude')::numeric, (to_jsonb(v)->>'longitude')::numeric
    into lat, lng from public.vendors v where v.user_id = actor order by v.id limit 1;
  if lat is null or lng is null then
    return jsonb_build_object('message','Order ready. Set your store location to match a rider.'); end if;
  if lat not between -90 and 90 or lng not between -180 and 180 then
    raise exception 'Invalid store coordinates' using errcode = '22023'; end if;
  select r.* into rider from public.riders r join public.users u on u.id = r.userid
    where r.is_online and r.is_verified and r.is_available
      and r.last_seen >= clock_timestamp() - interval '2 minutes'
      and u.role = 'rider' and u.verification_status = 'approved'
      and r.latitude between -90 and 90 and r.longitude between -180 and 180
      and not exists (select 1 from public.orders busy where busy.rider_id = r.userid
        and busy.order_status not in ('cancelled','delivered'))
    order by (sin(radians((r.latitude-lat)::double precision)/2)^2
      + cos(radians(lat::double precision))*cos(radians(r.latitude::double precision))
      * sin(radians((r.longitude-lng)::double precision)/2)^2), r.id
    limit 1 for update of r skip locked;
  if not found then
    return jsonb_build_object('message','Order ready. No online verified fresh rider is available.'); end if;
  distance := 6371 * 2 * asin(sqrt(least(1::double precision,
    sin(radians((rider.latitude-lat)::double precision)/2)^2
    + cos(radians(lat::double precision))*cos(radians(rider.latitude::double precision))
    * sin(radians((rider.longitude-lng)::double precision)/2)^2)));
  update public.orders set rider_id = rider.userid where id = o.id;
  insert into public.rider_assignments(riderid,orderid,status) values(rider.userid,o.id,'Pending');
  update public.riders set is_available = false, isavailable = false where id = rider.id;
  insert into public.notifications(user_id,title,message,type)
    values(rider.userid,'New Delivery Assigned','You have a new pickup ready for delivery.','order');
  return jsonb_build_object('message',format('Order ready; rider assigned, %s km from your shop.',round(distance::numeric,1)),
    'rider_id', rider.userid);
end $$;

-- Vendors cannot bypass the transactional RPC with direct assignment writes.
create or replace function public.fr21_guard_order_assignment()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user in ('authenticated','anon') and new.rider_id is distinct from old.rider_id then
    if public.fr21_role() is distinct from 'rider' or old.rider_id is not null
      or new.rider_id is distinct from public.fr21_actor() or not exists (
        select 1 from public.riders where userid = new.rider_id and is_online and is_verified
        and last_seen >= clock_timestamp() - interval '2 minutes') then
      raise exception 'Use authorized assignment' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger fr21_guard_order_assignment before update of rider_id on public.orders
for each row execute function public.fr21_guard_order_assignment();

revoke all on function public.fr21_actor(), public.fr21_role(), public.fr21_begin_presence(),
  public.fr21_set_presence(boolean,bigint,bigint), public.fr21_ready_and_assign(bigint) from public, anon;
grant execute on function public.fr21_actor(), public.fr21_role(), public.fr21_begin_presence(),
  public.fr21_set_presence(boolean,bigint,bigint), public.fr21_ready_and_assign(bigint) to authenticated;
revoke all on function public.fr21_order_visible(bigint) from public, anon;
grant execute on function public.fr21_order_visible(bigint) to authenticated;
revoke all on function public.fr21_guard_rider(), public.fr21_guard_identity(),
  public.fr21_sync_verification(), public.fr21_guard_order_assignment() from public, anon, authenticated;
commit;
