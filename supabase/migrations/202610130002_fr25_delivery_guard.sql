-- Review found that the legacy customer INSERT policy permits forged statuses.
-- Ensure only a server operation can establish an authoritative delivery time.
begin;
set local lock_timeout='5s';
create or replace function public.fr25_delivery_timestamp() returns trigger
language plpgsql set search_path='' as $$ begin
 if current_user in ('authenticated','anon') and new.order_status='delivered' then
   raise exception 'Delivery must be confirmed by the server.' using errcode='42501'; end if;
 if TG_OP='INSERT' then
   if new.order_status='delivered' then new.delivered_at:=clock_timestamp();
   else new.delivered_at:=null; end if;
 elsif old.order_status is distinct from 'delivered' and new.order_status='delivered' then
   new.delivered_at:=clock_timestamp();
 else new.delivered_at:=old.delivered_at; end if;
 return new;
end $$;
notify pgrst,'reload schema';
commit;
