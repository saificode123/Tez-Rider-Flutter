-- TEST rollback; restore route handler v10 before this metadata contract.
begin;
create or replace function public.fr14_route_context(p_order_id bigint)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();begin
 if actor is null or not fr14_private.allowed(p_order_id,actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 return jsonb_build_object('code','OK','actor',actor);
end$$;
commit;
