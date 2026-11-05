-- Owner approved docs/FINAL-DELIVERY/FAVORITE-RELATIONSHIPS-PROPOSAL.md, 2026-11-05.
-- Existing UUID table; all client access stays behind role/history-checked RPCs.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
do $$begin
 if exists(select 1 from public.favorites where type not in('vendor','rider') or user_id is null or favorite_user_id is null)then
  raise exception 'Legacy favorite identities require review; no rows were changed';end if;
end$$;
alter table public.favorites add constraint final_customer_favorite_kind check(type in('vendor','rider'));
alter table public.favorites alter column user_id set not null,alter column favorite_user_id set not null;
revoke all on public.favorites from anon,authenticated;
create function public.final_customer_order_favorite_targets(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;items jsonb;begin
 if actor is null or public.fr21_role()is distinct from'customer'or not public.is_current_user_allowed()then
 raise exception 'Customer required'using errcode='42501';end if;
 select *into o from public.orders where id=p_order_id and user_id=actor;
 if o.id is null then raise exception 'Owned order required'using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by role,target_id),'[]')into items from(
 select u.id as target_id,u.role,coalesce(nullif(v.store_name,''),nullif(u.name,''),'Name unavailable')as display_name,u.profile_image,
 exists(select 1 from public.favorites f where f.user_id=auth.uid()and f.favorite_user_id=u.auth_user_id and f.type=u.role)as saved
 from public.users u left join public.vendors v on v.user_id=u.id and u.role='vendor'
 where u.auth_user_id is not null and not u.is_blocked and u.verification_status='approved'and(
 (u.role='vendor'and(u.id=o.vendor_id or exists(select 1 from public.vendor_orders vo where vo.order_id=o.id and vo.vendor_id=u.id)))or
 (u.role='rider'and o.order_status='delivered'and o.rider_id=u.id)))x;
 return jsonb_build_object('items',items);end$$;
create function public.final_customer_set_related_favorite(p_target_id bigint,p_role text,p_saved boolean)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();target public.users;begin
 if actor is null or public.fr21_role()is distinct from'customer'or not public.is_current_user_allowed()then
 raise exception 'Customer required'using errcode='42501';end if;
 if p_role is null or p_role not in('vendor','rider')or p_saved is null then raise exception 'Invalid favorite request'using errcode='22023';end if;
 select *into target from public.users where id=p_target_id and role=p_role and auth_user_id is not null;
 if target.id is null then raise exception 'Favorite target unavailable'using errcode='42501';end if;
 if p_saved then
  if target.is_blocked or target.verification_status<>'approved'or not exists(select 1 from public.orders o where o.user_id=actor and(
   (p_role='vendor'and(o.vendor_id=target.id or exists(select 1 from public.vendor_orders vo where vo.order_id=o.id and vo.vendor_id=target.id)))or
   (p_role='rider'and o.order_status='delivered'and o.rider_id=target.id)))then
   raise exception 'Authorized order history required'using errcode='42501';end if;
  insert into public.favorites(user_id,favorite_user_id,type)values(auth.uid(),target.auth_user_id,p_role)
   on conflict(user_id,favorite_user_id)do update set type=excluded.type;
 else delete from public.favorites where user_id=auth.uid()and favorite_user_id=target.auth_user_id and type=p_role;end if;
 return jsonb_build_object('target_id',p_target_id,'role',p_role,'saved',p_saved);end$$;
create function public.final_customer_related_favorites(p_before_at timestamptz default null,p_before_id uuid default null,p_limit integer default 50)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();items jsonb;cursor_at timestamptz;cursor_id uuid;more boolean;begin
 if actor is null or public.fr21_role()is distinct from'customer'or not public.is_current_user_allowed()then
 raise exception 'Customer required'using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or(p_before_at is null)<>(p_before_id is null)then
 raise exception 'Invalid favorite page'using errcode='22023';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by created_at desc,id desc),'[]')into items from(
 select f.id,f.type as role,u.id as target_id,
 case when u.role=f.type and not u.is_blocked and u.verification_status='approved'then coalesce(nullif(v.store_name,''),nullif(u.name,''),'Name unavailable')else'Unavailable'end as display_name,
 case when u.role=f.type and not u.is_blocked and u.verification_status='approved'then u.profile_image end as profile_image,
 coalesce(u.role=f.type and not u.is_blocked and u.verification_status='approved',false)as available,f.created_at
 from public.favorites f left join public.users u on u.auth_user_id=f.favorite_user_id
 left join public.vendors v on v.user_id=u.id and u.role='vendor'
 where f.user_id=auth.uid()and(p_before_at is null or(f.created_at,f.id)<(p_before_at,p_before_id))
 order by f.created_at desc,f.id desc limit p_limit)x;
 if jsonb_array_length(items)>0 then cursor_at:=(items->-1->>'created_at')::timestamptz;cursor_id:=(items->-1->>'id')::uuid;end if;
 select exists(select 1 from public.favorites where user_id=auth.uid()and(created_at,id)<(cursor_at,cursor_id))into more;
 return jsonb_build_object('items',items,'has_more',more,'cursor_at',cursor_at,'cursor_id',cursor_id);end$$;
create function public.final_customer_remove_related_favorite(p_id uuid)returns jsonb
language plpgsql security definer set search_path=''as $$begin
 if public.fr21_actor()is null or public.fr21_role()is distinct from'customer'or not public.is_current_user_allowed()then
 raise exception 'Customer required'using errcode='42501';end if;
 if p_id is null then raise exception 'Favorite identity required'using errcode='22023';end if;
 delete from public.favorites where id=p_id and user_id=auth.uid();
 return jsonb_build_object('id',p_id,'saved',false);end$$;
revoke all on function public.final_customer_order_favorite_targets(bigint),public.final_customer_set_related_favorite(bigint,text,boolean),public.final_customer_related_favorites(timestamptz,uuid,integer),public.final_customer_remove_related_favorite(uuid)from public,anon;
grant execute on function public.final_customer_order_favorite_targets(bigint),public.final_customer_set_related_favorite(bigint,text,boolean),public.final_customer_related_favorites(timestamptz,uuid,integer),public.final_customer_remove_related_favorite(uuid)to authenticated;
notify pgrst,'reload schema';
commit;
