-- Confirmed OTP receipt is part of delivery's transaction, never a hidden client failure.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create unique index fr21_otp_receipt_idx on public.delivery_proof(orderid)
  where proofid like 'fr21-otp-%';
create policy fr21_receipt_owner on public.delivery_proof for select to authenticated
  using(riderid=(select auth.uid())::text or (select public.fr21_role())='admin');
grant select on public.delivery_proof to authenticated;
create or replace function public.fr21_complete_delivery(p_order_id bigint,p_otp text)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); o public.orders; begin
  if actor is null or public.fr21_role() is distinct from 'rider' then
    raise exception 'Rider required' using errcode='42501'; end if;
  select * into o from public.orders where id=p_order_id for update;
  if not found or o.rider_id is distinct from actor then raise exception 'Delivery forbidden' using errcode='42501'; end if;
  if p_otp is null or p_otp !~ '^[0-9]{6}$' or o.delivery_otp is distinct from p_otp then return false; end if;
  if o.order_status='delivered' then return true; end if;
  if o.order_status is distinct from 'on_the_way' then raise exception 'Delivery is not active' using errcode='22023'; end if;
  perform 1 from public.riders where userid=actor for update;
  update public.orders set order_status='delivered' where id=o.id;
  update public.rider_assignments set status='Delivered' where orderid=o.id and riderid=actor;
  update public.riders set is_available=true,isavailable=true where userid=actor
    and not exists(select 1 from public.orders where rider_id=actor
      and (order_status is null or order_status not in ('cancelled','delivered')));
  insert into public.delivery_proof(proofid,orderid,riderid,otpconfirmed,is_verified,verified_at)
    values('fr21-otp-'||o.id,o.id::text,auth.uid()::text,true,true,clock_timestamp());
  return true;
end $$;
notify pgrst,'reload schema';
commit;
