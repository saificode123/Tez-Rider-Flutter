-- FR06: literal keyword/category catalogue with bounded, stable keyset pages.
begin;
create or replace function public.final2_catalog_vendor_visible(p_vendor bigint)
returns boolean language sql stable security definer set search_path='' as $$
 select public.fr21_actor()is not null and exists(
  select 1 from public.users u join auth.users a on a.id=u.auth_user_id
  where u.id=p_vendor and u.role='vendor'and u.verification_status='approved'
  and not u.is_blocked and a.email_confirmed_at is not null)
$$;
revoke all on function public.final2_catalog_vendor_visible(bigint)from public,anon;
grant execute on function public.final2_catalog_vendor_visible(bigint)to authenticated;
create policy final2_products_catalog_visibility on public.products as restrictive for select to authenticated
 using(public.fr21_role()='admin'or(vendor_id=public.fr21_actor()and public.fr21_role()='vendor')
  or public.final2_catalog_vendor_visible(vendor_id));
create index if not exists final2_products_catalog_keyset on public.products(lower(name),id);

create or replace function public.final2_catalog(p_query text default'',p_category text default null,
 p_after jsonb default null,p_limit integer default 40)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare q text;category_key text;after_id bigint;after_name text;item public.products;
 items jsonb:='[]';cursor jsonb;more boolean:=false;n integer:=0;begin
 if public.fr21_actor()is null then raise exception 'Authentication required'using errcode='42501';end if;
 if p_query is null or char_length(btrim(p_query))>120 or p_query~'[[:cntrl:]]'
  or(p_category is not null and(char_length(btrim(p_category))>80 or p_category~'[[:cntrl:]]'))
  or p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid catalogue request'using errcode='22023';end if;
 q:=lower(btrim(p_query));category_key:=nullif(lower(btrim(p_category)),'');
 if p_after is not null then
  if jsonb_typeof(p_after)is distinct from'object'then raise exception 'Invalid page cursor'using errcode='22023';end if;
  if exists(select 1 from jsonb_object_keys(p_after)k where k not in('id','name'))
   or jsonb_typeof(p_after->'id')is distinct from'number'or jsonb_typeof(p_after->'name')is distinct from'string'
   or(p_after->>'id')!~'^[1-9][0-9]{0,18}$'or char_length(p_after->>'name')>2048 then
   raise exception 'Invalid page cursor'using errcode='22023';end if;
  begin after_id:=(p_after->>'id')::bigint;
  exception when numeric_value_out_of_range then raise exception 'Invalid page cursor'using errcode='22023';end;
  after_name:=lower(p_after->>'name');
 end if;
 for item in select p.* from public.products p
  where public.final2_catalog_vendor_visible(p.vendor_id)
  and(category_key is null or lower(btrim(p.category))=category_key)
  and(q=''or strpos(lower(p.name),q)>0 or strpos(lower(coalesce(p.description,'')),q)>0
   or strpos(lower(coalesce(p.category,'')),q)>0 or exists(select 1 from public.vendors v where v.user_id=p.vendor_id and strpos(lower(v.store_name),q)>0))
  and(after_id is null or(lower(p.name),p.id)>(after_name,after_id))
  order by lower(p.name),p.id limit p_limit+1
 loop
  n:=n+1;if n>p_limit then more:=true;exit;end if;
  items:=items||jsonb_build_array(to_jsonb(item));
  cursor:=jsonb_build_object('name',item.name,'id',item.id);
 end loop;
 return jsonb_build_object('items',items,'has_more',more,'next_cursor',case when more then cursor else null end);
end$$;
revoke all on function public.final2_catalog(text,text,jsonb,integer)from public,anon;
grant execute on function public.final2_catalog(text,text,jsonb,integer)to authenticated;
create or replace function public.final2_catalog_categories()
returns table(name text,image_url text)language plpgsql stable security invoker set search_path='' as $$
begin
 if public.fr21_actor()is null then raise exception 'Authentication required'using errcode='42501';end if;
 return query with labels as(
  select c.name as label,c.image_url as image from public.categories c
  union all select p.category,null::text from public.products p where public.final2_catalog_vendor_visible(p.vendor_id))
 select min(btrim(l.label)),max(l.image)from labels l where nullif(btrim(l.label),'')is not null
 group by lower(btrim(l.label))order by lower(min(btrim(l.label)));
end$$;
revoke all on function public.final2_catalog_categories()from public,anon;
grant execute on function public.final2_catalog_categories()to authenticated;
commit;
