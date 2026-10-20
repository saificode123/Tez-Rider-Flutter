-- Keep parent -> cache lock order even when a parent is busy. Never replay 001.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create or replace function fr14_private.cleanup()returns void language plpgsql security definer set search_path='' as $$
declare item record;begin
 for item in
  select o.id from public.orders o left join public.delivery_route_cache c on c.order_id=o.id
  where(c.order_id is not null and(c.computed_at<clock_timestamp()-interval '15 minutes'or o.order_status is distinct from 'on_the_way'))
  or(o.route_estimated_arrival_at is not null and c.order_id is null)
  order by o.id limit 500 for update of o skip locked
 loop
  delete from public.delivery_route_cache where order_id=item.id;
  update public.orders set route_estimated_arrival_at=null where id=item.id and route_estimated_arrival_at is not null;
 end loop;
 delete from fr14_private.attempts where last_attempt_at<clock_timestamp()-interval '15 minutes';
 delete from fr14_private.quota_reservations where reserved_at<clock_timestamp()-interval '26 hours';
 delete from fr14_private.user_limits where window_at<clock_timestamp()-interval '1 day';
end$$;
revoke all on function fr14_private.cleanup()from public,anon,authenticated,service_role;
commit;
