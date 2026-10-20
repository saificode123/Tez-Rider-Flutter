-- Cache reads need authorization and rate accounting, not an order write lock.
-- Preserve the accepted locked implementation for every miss/recompute.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
alter function public.fr14_prepare(bigint,bigint,boolean) rename to prepare_locked;
alter function public.prepare_locked(bigint,bigint,boolean) set schema fr14_private;
revoke all on function fr14_private.prepare_locked(bigint,bigint,boolean) from public,anon,authenticated,service_role;

create function public.fr14_prepare(p_order_id bigint,p_actor bigint,p_configured boolean)returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders;l public.delivery_latest_locations;c public.delivery_route_cache;
 cfg fr14_private.configuration;u fr14_private.user_limits;stamp timestamptz:=clock_timestamp();
begin
 select *into c from public.delivery_route_cache where order_id=p_order_id and expires_at>stamp;
 if c.order_id is not null then
  select *into o from public.orders where id=p_order_id;
  select *into l from public.delivery_latest_locations where order_id=p_order_id;
  select *into cfg from fr14_private.configuration;
  if o.destination_confirmed_at is not null and c.destination_lat=o.delivery_lat and c.destination_lng=o.delivery_lng
  and l.received_at>=stamp-interval '30 seconds'and l.device_at>=stamp-interval '30 seconds'and l.accuracy<=100
  and fr14_private.allowed(p_order_id,p_actor)
  and extensions.st_dwithin(extensions.st_setsrid(extensions.st_makepoint(l.longitude,l.latitude),4326)::extensions.geography,
   extensions.st_geomfromgeojson((c.data->'geometry')::text)::extensions.geography,cfg.deviation_meters) then
   -- Same per-actor limit as the locked path. Never reserve provider credits on a hit.
   insert into fr14_private.user_limits values(p_actor,stamp,1)on conflict(actor)do update
   set window_at=case when fr14_private.user_limits.window_at<stamp-interval '1 minute'then stamp else fr14_private.user_limits.window_at end,
   requests=case when fr14_private.user_limits.window_at<stamp-interval '1 minute'then 1 else fr14_private.user_limits.requests+1 end returning *into u;
   if u.requests>100 then return jsonb_build_object('code','RATE_LIMIT');end if;
   -- The Edge handler rechecks current JWT/session/order access before disclosure,
   -- including terminal/blocked races after this read. No authorization is cached.
   return jsonb_build_object('code','CACHE','orderId',o.id,'origin',jsonb_build_array(l.longitude,l.latitude),
    'destination',jsonb_build_array(o.delivery_lng,o.delivery_lat),'locationAt',l.received_at,
    'speedKmh',cfg.fallback_speed_kmh,'refreshSeconds',cfg.refresh_seconds,'minimumSeconds',cfg.minimum_seconds,
    'deviationMeters',cfg.deviation_meters,'serverNow',stamp,'cache',c.data);
  end if;
 end if;
 return fr14_private.prepare_locked(p_order_id,p_actor,p_configured);
end$$;
revoke all on function public.fr14_prepare(bigint,bigint,boolean)from public,anon,authenticated;
grant execute on function public.fr14_prepare(bigint,bigint,boolean)to service_role;
notify pgrst,'reload schema';
commit;
