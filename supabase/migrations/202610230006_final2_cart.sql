-- FR07 account-scoped cart persistence. Reservation policy is intentionally
-- unconfigured pending the business decision; this does not claim reservation acceptance.
begin;
create schema if not exists final2_private;
revoke all on schema final2_private from public,anon,authenticated;
create table final2_private.cart_versions(
 user_id uuid primary key references auth.users(id), revision bigint not null default 0 check(revision>=0),
 last_request uuid, last_items jsonb
);
alter table final2_private.cart_versions enable row level security;
revoke all on final2_private.cart_versions from public,anon,authenticated;
-- Preserve existing values while allowing canonical fractional product prices.
alter table public.cart_items alter column price type numeric using price::numeric;
revoke insert,update,delete on public.cart_items from anon,authenticated;

create function final2_private.cart_snapshot(p_user uuid)returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('code','OK','revision',coalesce((select revision from final2_private.cart_versions where user_id=p_user),0),
 'items',coalesce((select jsonb_agg(jsonb_build_object('product_id',c.product_id,'id',c.product_id,'qty',c.quantity,
  'name',coalesce(p.name,c.name),'price',coalesce(p.price,c.price),'vendor_id',p.vendor_id,
  'image_url',coalesce(p.image_url,c.image),'is_available',coalesce(p.is_available,false),
  'stock_qty',coalesce(p.stock_qty,0),'stock_confirmed',coalesce(p.stock_confirmed,false),
  'low_stock_threshold',p.low_stock_threshold,'stock_version',p.stock_version)
  order by c.created_at,c.id)from public.cart_items c left join public.products p on p.id::text=c.product_id
   and public.final2_catalog_vendor_visible(p.vendor_id)where c.user_id=p_user),'[]'::jsonb))
$$;
revoke all on function final2_private.cart_snapshot(uuid)from public,anon,authenticated;

create function public.final2_cart_get()returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if public.fr21_role()is distinct from'customer'or not exists(select 1 from public.users where id=public.fr21_actor()and not is_blocked and verification_status='approved')then
  raise exception 'Approved customer required'using errcode='42501';end if;
 return final2_private.cart_snapshot(auth.uid());
end$$;
revoke all on function public.final2_cart_get()from public,anon;
grant execute on function public.final2_cart_get()to authenticated;

create function public.final2_cart_replace(p_revision bigint,p_request_id uuid,p_items jsonb)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();uid uuid:=auth.uid();v final2_private.cart_versions;entry jsonb;p public.products;seen bigint[]:='{}';pid bigint;qty integer;begin
 if public.fr21_role()is distinct from'customer'or not exists(select 1 from public.users where id=actor and not is_blocked and verification_status='approved')then
  raise exception 'Approved customer required'using errcode='42501';end if;
 if p_revision is null or p_revision<0 or p_request_id is null or jsonb_typeof(p_items)is distinct from'array'then
  raise exception 'Invalid cart request'using errcode='22023';end if;
 if jsonb_array_length(p_items)>100 then raise exception 'Cart limit exceeded'using errcode='22023';end if;
 -- Serialize separate devices as well as retries; no last-writer-wins overwrite.
 insert into final2_private.cart_versions(user_id)values(uid)on conflict do nothing;
 select * into v from final2_private.cart_versions where user_id=uid for update;
 if v.last_request=p_request_id then
  if v.last_items is distinct from p_items then raise exception 'Request payload changed'using errcode='PT409';end if;
  return final2_private.cart_snapshot(uid)||jsonb_build_object('code','ALREADY_APPLIED');
 end if;
 if p_revision<>v.revision then return final2_private.cart_snapshot(uid)||jsonb_build_object('code','CART_CHANGED');end if;
 -- Validate all input and real inventory before replacing any saved rows.
 for entry in select value from jsonb_array_elements(p_items)loop
  if jsonb_typeof(entry)is distinct from'object'then raise exception 'Invalid cart item'using errcode='22023';end if;
  if exists(select 1 from jsonb_object_keys(entry)k where k not in('product_id','qty'))
   or jsonb_typeof(entry->'product_id')is distinct from'number'or jsonb_typeof(entry->'qty')is distinct from'number'
   or(entry->>'product_id')!~'^[1-9][0-9]{0,18}$'or(entry->>'qty')!~'^[1-9][0-9]{0,2}$'then
   raise exception 'Invalid cart item'using errcode='22023';end if;
  begin pid:=(entry->>'product_id')::bigint;qty:=(entry->>'qty')::integer;
  exception when numeric_value_out_of_range then raise exception 'Invalid cart item'using errcode='22023';end;
  if qty>100 or pid=any(seen)then raise exception 'Duplicate or oversized cart item'using errcode='22023';end if;
  seen:=array_append(seen,pid);
 end loop;
 -- Consistent product lock ordering, compatible with transactional checkout.
 perform 1 from public.products where id=any(seen)order by id for share;
 for entry in select value from jsonb_array_elements(p_items)loop
  pid:=(entry->>'product_id')::bigint;qty:=(entry->>'qty')::integer;
  select * into p from public.products where id=pid and public.final2_catalog_vendor_visible(vendor_id);
  if not found or not p.is_available or not p.stock_confirmed or p.stock_qty<qty then
   return final2_private.cart_snapshot(uid)||jsonb_build_object('code','UNAVAILABLE','product_id',pid);
  end if;
 end loop;
 delete from public.cart_items where user_id=uid;
 for entry in select value from jsonb_array_elements(p_items)loop
  select * into strict p from public.products where id=(entry->>'product_id')::bigint;
  insert into public.cart_items(user_id,product_id,name,price,quantity,image)
  values(uid,p.id::text,p.name,p.price,(entry->>'qty')::integer,p.image_url);
 end loop;
 update final2_private.cart_versions set revision=revision+1,last_request=p_request_id,last_items=p_items where user_id=uid;
 return final2_private.cart_snapshot(uid);
end$$;
revoke all on function public.final2_cart_replace(bigint,uuid,jsonb)from public,anon;
grant execute on function public.final2_cart_replace(bigint,uuid,jsonb)to authenticated;
commit;
