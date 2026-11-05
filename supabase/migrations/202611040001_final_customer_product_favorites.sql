-- Restore the existing Customer product-favorites feature, preserving rows.
-- No Vendor/Rider relationship model or public access is introduced.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
do $$begin
 if exists(select 1 from public.favourite group by user_id,product_id having count(*)>1
   and user_id is not null and product_id is not null)then
  raise exception 'Favorite duplicates require owner review; no rows were deleted';
 end if;
end$$;
create unique index final_customer_favourite_owner_product
 on public.favourite(user_id,product_id);
alter table public.favourite enable row level security;
drop policy if exists fav_read on public.favourite;
drop policy if exists fav_insert on public.favourite;
drop policy if exists fav_delete on public.favourite;
create policy final_customer_favourite_read on public.favourite for select to authenticated
 using(user_id=(select public.fr21_actor()) and (select public.fr21_role())='customer');
create policy final_customer_favourite_insert on public.favourite for insert to authenticated
 with check(user_id=(select public.fr21_actor()) and (select public.fr21_role())='customer');
create policy final_customer_favourite_delete on public.favourite for delete to authenticated
 using(user_id=(select public.fr21_actor()) and (select public.fr21_role())='customer');
-- Keep the existing restrictive live-session/account guard. UPDATE stays denied.
revoke all on public.favourite from anon,authenticated;
grant select,insert,delete on public.favourite to authenticated;
grant usage on sequence public.favourite_id_seq to authenticated;
commit;
