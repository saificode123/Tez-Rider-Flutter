-- FR16/S01: approved owner deletion behind trusted validation; direct DELETE stays denied.
begin;
create function public.final2_delete_product(p_product_id bigint,p_expected_version bigint)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();p public.products;begin
 if actor is null or public.fr21_role()is distinct from'vendor'then raise exception 'Approved owning Vendor required'using errcode='42501';end if;
 perform 1 from public.users where id=actor and role='vendor'and verification_status='approved'and not is_blocked for no key update;
 if not found then raise exception 'Approved owning Vendor required'using errcode='42501';end if;
 if p_product_id is null or p_product_id<=0 or p_expected_version is null or p_expected_version<0 then
  raise exception 'Product and confirmed stock version required'using errcode='22023';end if;
 select *into p from public.products where id=p_product_id for update;
 if p.id is null then return jsonb_build_object('code','NOT_FOUND');end if;
 if p.vendor_id is distinct from actor then raise exception 'Product unavailable for this Vendor'using errcode='42501';end if;
 if p.stock_version<>p_expected_version then return jsonb_build_object('code','VERSION_CHANGED');end if;
 if exists(select 1 from public.order_items where product_id=p.id)then return jsonb_build_object('code','PRODUCT_IN_USE');end if;
 delete from public.products where id=p.id and vendor_id=actor;
 if not found then raise exception 'Deletion was not confirmed'using errcode='40001';end if;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'product_deleted','product',p.id);
 return jsonb_build_object('code','DELETED','product_id',p.id);
end$$;
revoke all on function public.final2_delete_product(bigint,bigint)from public,anon;
grant execute on function public.final2_delete_product(bigint,bigint)to authenticated;
commit;
