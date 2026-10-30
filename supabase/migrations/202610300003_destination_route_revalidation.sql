-- Fresh authorization and destination belong to one read snapshot.
-- Apply to TEST before the updated route handler; no order mutation.
begin;
set local lock_timeout='5s';
create or replace function public.fr14_route_context(p_order_id bigint)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();result jsonb;begin
 if actor is null then return jsonb_build_object('code','FORBIDDEN');end if;
 select jsonb_build_object('code','OK','actor',actor,
  'destination',jsonb_build_array(o.delivery_lng,o.delivery_lat),
  'destination_revision',o.destination_confirmed_at)
 into result from public.orders o where o.id=p_order_id and fr14_private.allowed(o.id,actor);
 return coalesce(result,jsonb_build_object('code','FORBIDDEN'));
end$$;
revoke all on function public.fr14_route_context(bigint)from public,anon,service_role;
grant execute on function public.fr14_route_context(bigint)to authenticated;
notify pgrst,'reload schema';
commit;
