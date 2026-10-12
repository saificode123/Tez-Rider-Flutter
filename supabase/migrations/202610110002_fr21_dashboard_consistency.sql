-- Bounded server-side dashboard aggregates and guarded vendor transitions.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create function public.fr21_dashboard_stats() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); actor_role text:=public.fr21_role(); result jsonb; rating numeric;
begin
  if actor is null or not exists(select 1 from public.users where id=actor and verification_status='approved')
    or actor_role not in ('rider','vendor') then
    raise exception 'Approved rider/vendor required' using errcode='42501'; end if;
  if actor_role='vendor' then
    select avg_rating into rating from public.get_vendor_ratings(array[actor]);
    select jsonb_build_object('total',coalesce(sum(sub_total),0),'rating',rating)
      into result from public.vendor_orders where vendor_id=actor and status='delivered';
  else
    select jsonb_build_object(
      'today',coalesce(sum(amount) filter(where created_at>=date_trunc('day',statement_timestamp())),0),
      'week',coalesce(sum(amount) filter(where created_at>=statement_timestamp()-interval '7 days'),0),
      'month',coalesce(sum(amount) filter(where created_at>=statement_timestamp()-interval '30 days'),0),
      'trips_today',count(*) filter(where created_at>=date_trunc('day',statement_timestamp())),
      'total_deliveries',count(*)) into result
      from public.orders where rider_id=actor and order_status='delivered';
  end if;
  return result;
end $$;
revoke all on function public.fr21_dashboard_stats() from public,anon;
grant execute on function public.fr21_dashboard_stats() to authenticated;

create function public.fr21_guard_vendor_transition() returns trigger
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
  end if;
  return new;
end $$;
revoke all on function public.fr21_guard_vendor_transition() from public,anon,authenticated;
create trigger fr21_guard_vendor_transition before update of status on public.vendor_orders
  for each row execute function public.fr21_guard_vendor_transition();
notify pgrst,'reload schema';
commit;
