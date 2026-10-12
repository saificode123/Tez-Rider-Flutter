-- TEST: shared-parent privacy and transactional child/parent status consistency.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
alter policy fr21_test_vendor_orders_read on public.vendor_orders using(
  vendor_id=(select public.fr21_actor()) or (select public.fr21_role())='admin'
  or ((select public.fr21_role())='customer' and exists(select 1 from public.orders o
    where o.id=order_id and o.user_id=(select public.fr21_actor())))
  or ((select public.fr21_role())='rider' and public.fr21_order_visible(order_id)));
create or replace function public.fr21_guard_vendor_transition() returns trigger
language plpgsql set search_path='' as $$
begin
  if current_user='authenticated' and new.status is distinct from old.status then
    if not exists(select 1 from public.users where id=public.fr21_actor()
      and role='vendor' and verification_status='approved') then
      raise exception 'Approved vendor required' using errcode='42501'; end if;
    if not ((new.status='accepted' and old.status='pending')
      or (new.status='preparing' and old.status='accepted')
      or (new.status='cancelled' and old.status in ('pending','accepted','preparing','ready','on_the_way'))) then
      raise exception 'Invalid vendor transition; ready/delivery require RPCs' using errcode='22023'; end if;
    if exists(select 1 from public.orders where id=old.order_id
      and (order_status in ('delivered','cancelled') or (rider_id is not null and new.status<>'cancelled'))) then
      raise exception 'Assigned/closed parent cannot move backwards' using errcode='22023'; end if;
  end if;
  return new;
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
  update public.vendor_orders set status='on_the_way' where order_id=o.id and status is distinct from 'on_the_way';
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
  update public.vendor_orders set status='delivered' where order_id=o.id and status is distinct from 'delivered';
  update public.rider_assignments set status='Delivered' where orderid=o.id and riderid=actor;
  update public.riders set is_available=true,isavailable=true where userid=actor
    and not exists(select 1 from public.orders where rider_id=actor
      and (order_status is null or order_status not in ('cancelled','delivered')));
  insert into public.delivery_proof(proofid,orderid,riderid,otpconfirmed,is_verified,verified_at)
    values('fr21-otp-'||o.id,o.id::text,auth.uid()::text,true,true,clock_timestamp());
  return true;
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
    raise exception 'Vendor order changed' using errcode='PT409'; end if;
  if coalesce(o.order_status,'') not in ('placed','pending','accepted','preparing','ready','on_the_way')
    or coalesce(vo.status,'') not in ('pending','accepted','preparing','ready','on_the_way') then
    raise exception 'Order is closed or invalid' using errcode='22023'; end if;
  -- Keep the existing trigger's parent-status propagation and notifications.
  if o.rider_id is not null then
    update public.vendor_orders set status='on_the_way' where id=vo.id and status is distinct from 'on_the_way';
    return jsonb_build_object('message','Order ready; rider already assigned.','rider_id',o.rider_id); end if;
  update public.vendor_orders set status='ready' where id=vo.id and status is distinct from 'ready';
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
  update public.vendor_orders set status='on_the_way' where id=vo.id and status is distinct from 'on_the_way';
  insert into public.notifications(user_id,title,message,type)
    values(rider.userid,'New Delivery Assigned','You have a new pickup ready for delivery.','order');
  return jsonb_build_object('message',format('Order ready; rider assigned, %s km from your shop.',round(distance::numeric,1)),
    'rider_id',rider.userid);
end $$;
notify pgrst,'reload schema';
commit;
