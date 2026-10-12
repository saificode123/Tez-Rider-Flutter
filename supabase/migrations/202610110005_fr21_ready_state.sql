-- Ready is not on-the-way until a rider is reserved. Retried matching emits its actual transition.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create or replace function public.fr21_order_visible(p_id bigint)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.orders o where o.id=p_id and (
    o.user_id=public.fr21_actor() or o.rider_id=public.fr21_actor() or public.fr21_role()='admin'
    or exists(select 1 from public.vendor_orders vo where vo.order_id=o.id and vo.vendor_id=public.fr21_actor())
    or (o.rider_id is null and o.order_status in ('placed','accepted','ready')
      and public.fr21_approved_rider(public.fr21_actor()) and exists(select 1 from public.riders r
        where r.userid=public.fr21_actor() and r.is_online is true and r.is_available is true and r.isavailable is true
        and r.last_seen>=statement_timestamp()-interval '2 minutes'))))
$$;
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
