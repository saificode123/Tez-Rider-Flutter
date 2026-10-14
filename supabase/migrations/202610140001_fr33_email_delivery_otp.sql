-- FR-33 TEST: protected delivery OTPs. Existing migrations/keys are untouched.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create table public.delivery_otps(
 id uuid primary key, order_id bigint not null references public.orders(id),
 rider_id bigint not null references public.users(id), review_admin_id bigint not null references public.users(id), auth_id uuid not null references auth.users(id),
 nonce text not null, verifier bytea not null,
 state text not null check(state in ('RESERVED','SENDING','ACCEPTED','FAILED','UNKNOWN','INVALIDATED','EXPIRED','LOCKED','USED')),
 created_at timestamptz not null default clock_timestamp(), sent_at timestamptz,
 expires_at timestamptz, attempts int not null default 0 check(attempts between 0 and 3),
 provider_id text, lease_until timestamptz not null);
create index fr33_order_history on public.delivery_otps(order_id,created_at desc);
create index fr33_rider_history on public.delivery_otps(rider_id,created_at desc);
create index fr33_review_admin_idx on public.delivery_otps(review_admin_id);
create index fr33_auth_idx on public.delivery_otps(auth_id);
create unique index fr33_one_active on public.delivery_otps(order_id) where state='ACCEPTED';
create unique index fr33_one_send on public.delivery_otps(order_id) where state in ('RESERVED','SENDING');
create table public.delivery_otp_verifications(
 id uuid primary key, order_id bigint not null references public.orders(id),
 rider_id bigint not null references public.users(id), input_tag bytea not null,
 result jsonb not null, created_at timestamptz not null default clock_timestamp());
create index fr33_verify_order on public.delivery_otp_verifications(order_id);
create index fr33_verify_rider on public.delivery_otp_verifications(rider_id);
create table public.delivery_otp_budgets(day date primary key,used int not null check(used between 0 and 300));
create table public.delivery_otp_rates(rider_id bigint primary key references public.users(id),window_at timestamptz not null,used int not null,verify_window timestamptz not null default clock_timestamp(),verify_used int not null default 0);
alter table public.delivery_otps enable row level security;
alter table public.delivery_otp_verifications enable row level security;
alter table public.delivery_otp_budgets enable row level security;
alter table public.delivery_otp_rates enable row level security;
revoke all on public.delivery_otps,public.delivery_otp_verifications,public.delivery_otp_budgets,public.delivery_otp_rates from public,anon,authenticated;
grant all on public.delivery_otps,public.delivery_otp_verifications,public.delivery_otp_budgets,public.delivery_otp_rates to service_role;
alter table public.orders add column otp_admin_review boolean not null default false,
 add column delivery_otp_email_status text not null default 'none' check(delivery_otp_email_status in ('none','accepted'));
alter table public.security_audit_log add column otp_operation_id uuid;
create unique index fr33_audit_once on public.security_audit_log(action,otp_operation_id) where otp_operation_id is not null;
alter table public.notifications add column delivery_otp_id uuid references public.delivery_otps(id);
create unique index fr33_notice_once on public.notifications(delivery_otp_id,user_id,type) where delivery_otp_id is not null;
-- Purge legacy codes only, preserving order/receipt history. New codes require email issuance.
update public.orders set delivery_otp=null where delivery_otp is not null;
alter table public.orders add constraint fr33_no_plaintext_order_otp check(delivery_otp is null);
alter table public.delivery_proof add constraint fr33_no_plaintext_proof_otp check(otp is null);
revoke insert,update,delete on public.delivery_proof from anon,authenticated;
do $$ begin
 if not exists(select 1 from vault.secrets where name='fr33_delivery_hmac_v1') then
  perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'fr33_delivery_hmac_v1','FR33 delivery verifier only');
 end if;
end $$;
create function public.fr33_tag(p_order bigint,p_nonce text,p_code text) returns bytea
language sql security definer set search_path='' as $$
 select extensions.hmac(convert_to(p_order::text||':'||p_nonce||':'||p_code,'UTF8'),
 decode((select decrypted_secret from vault.decrypted_secrets where name='fr33_delivery_hmac_v1'),'hex'),'sha256')
$$;
create function public.fr33_equal(a bytea,b bytea) returns boolean language plpgsql immutable set search_path='' as $$
declare difference int:=0; i int; begin
 if a is null or b is null or octet_length(a)<>32 or octet_length(b)<>32 then return false; end if;
 for i in 0..31 loop difference:=difference | (get_byte(a,i) # get_byte(b,i)); end loop;
 return difference=0;
end $$;
create function public.issue_delivery_otp(p_order_id bigint,p_request_id uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders; a bigint; existing public.delivery_otps; latest timestamptz; n int;
 recipient text; review_admin bigint; random_bytes bytea; number int; code text; salt text; budget int; used_count int; moment timestamptz:=clock_timestamp(); begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server issuance required' using errcode='42501'; end if;
 select u.id into a from public.users u join auth.users au on au.email=u.email where au.id=p_actor and au.email_confirmed_at is not null and u.role='rider' and u.verification_status='approved';
 select * into o from public.orders where id=p_order_id for update;
 if a is null or o.id is null or o.rider_id is distinct from a or not public.fr21_approved_rider(a) then return jsonb_build_object('code','FORBIDDEN'); end if;
 if o.order_status='delivered' then return jsonb_build_object('code','ALREADY_DELIVERED'); end if;
 if o.order_status is distinct from 'on_the_way' or p_request_id is null then return jsonb_build_object('code','WRONG_STATE'); end if;
 select * into existing from public.delivery_otps where id=p_request_id;
 if found then
  if existing.order_id<>o.id or existing.auth_id<>p_actor then return jsonb_build_object('code','FORBIDDEN'); end if;
  return jsonb_build_object('code',case existing.state when 'ACCEPTED' then case when existing.expires_at>moment then 'EMAIL_ACCEPTED' else 'EXPIRED' end when 'FAILED' then 'EMAIL_FAILED' when 'UNKNOWN' then 'EMAIL_UNKNOWN' when 'RESERVED' then 'EMAIL_PENDING' when 'SENDING' then 'EMAIL_PENDING' else 'EXPIRED' end,'replayed',true);
 end if;
 -- Expired leases never resend. The old accepted issuance is retained until replacement acceptance.
 update public.delivery_otps set state=case when state='RESERVED' then 'FAILED' else 'UNKNOWN' end where order_id=o.id and state in ('RESERVED','SENDING') and lease_until<=moment;
 if exists(select 1 from public.delivery_otps where order_id=o.id and state in ('RESERVED','SENDING')) then return jsonb_build_object('code','EMAIL_PENDING'); end if;
 select count(*),max(created_at) into n,latest from public.delivery_otps where order_id=o.id;
 if n>=5 then return jsonb_build_object('code','ISSUANCE_LIMIT'); end if;
 if latest>moment-interval '60 seconds' then return jsonb_build_object('code','COOLDOWN','retry_after',ceil(extract(epoch from latest+interval '60 seconds'-moment))); end if;
 select au.email into recipient from public.users u join auth.users au on au.email=u.email where u.id=o.user_id and u.role='customer' and au.email_confirmed_at is not null;
 if recipient is null then return jsonb_build_object('code','EMAIL_UNAVAILABLE'); end if;
 select id into review_admin from public.users where role='admin' and verification_status='approved' order by id limit 1;
 if review_admin is null then return jsonb_build_object('code','ADMIN_UNAVAILABLE'); end if;
 insert into public.delivery_otp_budgets(day,used) values((moment at time zone 'UTC')::date,0) on conflict do nothing;
 select used into budget from public.delivery_otp_budgets where day=(moment at time zone 'UTC')::date for update;
 if budget>=300 then return jsonb_build_object('code','QUOTA_EXCEEDED'); end if;
 insert into public.delivery_otp_rates(rider_id,window_at,used) values(a,moment,0) on conflict do nothing;
 perform 1 from public.delivery_otp_rates where rider_id=a for update;
 update public.delivery_otp_rates set used=0,window_at=moment where rider_id=a and window_at<=moment-interval '1 minute';
 select used into used_count from public.delivery_otp_rates where rider_id=a;
 if used_count>=10 then return jsonb_build_object('code','RATE_LIMIT','retry_after',60); end if;
 loop
  random_bytes:=extensions.gen_random_bytes(3);number:=get_byte(random_bytes,0)*65536+get_byte(random_bytes,1)*256+get_byte(random_bytes,2);
  if number<16000000 then
   code:=lpad((number%1000000)::text,6,'0');
   exit when not exists(select 1 from public.delivery_otps history where history.order_id=o.id and public.fr33_equal(history.verifier,public.fr33_tag(o.id,history.nonce,code)));
  end if;
 end loop;
 salt:=encode(extensions.gen_random_bytes(24),'hex');
 insert into public.delivery_otps(id,order_id,rider_id,review_admin_id,auth_id,nonce,verifier,state,lease_until)
 values(p_request_id,o.id,a,review_admin,p_actor,salt,public.fr33_tag(o.id,salt,code),'RESERVED',moment+interval '90 seconds');
 update public.delivery_otp_budgets set used=used+1 where day=(moment at time zone 'UTC')::date;
 update public.delivery_otp_rates set used=used+1 where rider_id=a;
 insert into public.security_audit_log(actor_id,action,target_type,target_id,otp_operation_id) values(a,'delivery_otp_reserved','order',o.id,p_request_id);
 -- Privileged response only. No caller/client gets this data; no plaintext is persisted.
 return jsonb_build_object('code','SEND','otp',code,'recipient',recipient,'issuance_id',p_request_id);
end $$;
create function public.fr33_start_send(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare d public.delivery_otps; o public.orders; begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server required' using errcode='42501'; end if;
 select * into d from public.delivery_otps where id=p_id;
 if not found then return false; end if;
 select * into o from public.orders where id=d.order_id for update;
 if o.rider_id is distinct from d.rider_id or o.order_status is distinct from 'on_the_way' then return false; end if;
 update public.delivery_otps set state='SENDING' where id=p_id and state='RESERVED' and lease_until>clock_timestamp();return found;
end $$;
create function public.fr33_finish_send(p_id uuid,p_result text,p_provider_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.delivery_otps; o public.orders; begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server required' using errcode='42501'; end if;
 if p_result not in ('ACCEPTED','FAILED','UNKNOWN') or p_result is null or coalesce(length(p_provider_id),0)>200 or (p_result='ACCEPTED' and coalesce(length(trim(p_provider_id)),0)=0) then raise exception 'Invalid provider result' using errcode='22023'; end if;
 select * into d from public.delivery_otps where id=p_id;
 if not found then return jsonb_build_object('code','NO_OTP'); end if;
 select * into o from public.orders where id=d.order_id for update;
 select * into d from public.delivery_otps where id=p_id for update;
 if d.state<>'SENDING' then return jsonb_build_object('code',case when d.state='ACCEPTED' then 'EMAIL_ACCEPTED' else 'EMAIL_UNKNOWN' end); end if;
 if p_result='ACCEPTED' and (o.rider_id is distinct from d.rider_id or o.order_status is distinct from 'on_the_way' or d.lease_until<=clock_timestamp()) then
  update public.delivery_otps set state='INVALIDATED' where id=d.id;return jsonb_build_object('code','EXPIRED'); end if;
 if p_result='ACCEPTED' then
  update public.delivery_otps set state='INVALIDATED' where order_id=o.id and state='ACCEPTED';
  update public.delivery_otps set state='ACCEPTED',sent_at=clock_timestamp(),expires_at=clock_timestamp()+interval '10 minutes',provider_id=p_provider_id where id=d.id;
  update public.orders set delivery_otp_email_status='accepted' where id=o.id;
  insert into public.notifications(user_id,title,message,type,delivery_otp_id) values(o.user_id,'Delivery verification','A delivery verification code has been sent to your registered email.','otp_email',d.id);
 else update public.delivery_otps set state=p_result where id=d.id; end if;
 insert into public.security_audit_log(actor_id,action,target_type,target_id,otp_operation_id) values(d.rider_id,'delivery_email_'||lower(p_result),'order',o.id,d.id);
 return jsonb_build_object('code',case p_result when 'ACCEPTED' then 'EMAIL_ACCEPTED' when 'FAILED' then 'EMAIL_FAILED' else 'EMAIL_UNKNOWN' end);
end $$;
create function public.delivery_otp_status(p_order_id bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders; d public.delivery_otps; a bigint:=public.fr21_actor(); latest timestamptz; email text; n int; begin
 select * into o from public.orders where id=p_order_id;
 if a is null or o.id is null or not ((public.fr21_role()='rider' and o.rider_id=a and public.fr21_approved_rider(a)) or (public.fr21_role()='customer' and o.user_id=a)) then return jsonb_build_object('code','FORBIDDEN'); end if;
 if o.order_status='delivered' then return jsonb_build_object('code','ALREADY_DELIVERED'); end if;
 select * into d from public.delivery_otps where order_id=o.id and state='ACCEPTED';
 select count(*),max(created_at) into n,latest from public.delivery_otps where order_id=o.id;
 select left(u.email,1)||'***@'||split_part(u.email,'@',2) into email from public.users u where u.id=o.user_id;
 return jsonb_build_object('code',case when d.id is not null and d.expires_at>clock_timestamp() and d.rider_id=o.rider_id then 'EMAIL_ACCEPTED' when exists(select 1 from public.delivery_otps where order_id=o.id and state in ('RESERVED','SENDING') and lease_until>clock_timestamp()) then 'EMAIL_PENDING' when n>0 then 'EXPIRED' else 'NO_OTP' end,
 'expires_at',d.expires_at,'remaining',greatest(0,3-coalesce(d.attempts,0)),'retry_after',greatest(0,ceil(extract(epoch from latest+interval '60 seconds'-clock_timestamp()))),'issuances',n,'masked_email',email);
end $$;
create function public.verify_delivery_otp(p_order_id bigint,p_otp text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders; d public.delivery_otps; a bigint:=public.fr21_actor(); tag bytea; prior public.delivery_otp_verifications; result jsonb; admin_id bigint; begin
 select * into o from public.orders where id=p_order_id for update;
 if a is null or o.id is null or public.fr21_role() is distinct from 'rider' or o.rider_id is distinct from a or not public.fr21_approved_rider(a) then return jsonb_build_object('code','FORBIDDEN'); end if;
 if o.order_status='delivered' then return jsonb_build_object('code','ALREADY_DELIVERED'); end if;
 if o.order_status is distinct from 'on_the_way' then return jsonb_build_object('code','WRONG_STATE'); end if;
 if p_request_id is null or p_otp is null or p_otp !~ '^[0-9]{6}$' then return jsonb_build_object('code','FORMAT'); end if;
 tag:=public.fr33_tag(o.id,p_request_id::text,p_otp);
 select * into prior from public.delivery_otp_verifications where id=p_request_id;
 if found then
  if prior.order_id<>o.id or prior.rider_id<>a or not public.fr33_equal(prior.input_tag,tag) then return jsonb_build_object('code','REQUEST_CONFLICT'); end if;
  return prior.result||jsonb_build_object('replayed',true);
 end if;
 insert into public.delivery_otp_rates(rider_id,window_at,used) values(a,clock_timestamp(),0) on conflict do nothing;
 perform 1 from public.delivery_otp_rates where rider_id=a for update;
 update public.delivery_otp_rates set verify_used=0,verify_window=clock_timestamp() where rider_id=a and verify_window<=clock_timestamp()-interval '1 minute';
 if (select verify_used>=100 from public.delivery_otp_rates where rider_id=a) then return jsonb_build_object('code','RATE_LIMIT','retry_after',60); end if;
 update public.delivery_otp_rates set verify_used=verify_used+1 where rider_id=a;
 select * into d from public.delivery_otps where order_id=o.id and state='ACCEPTED' for update;
 if not found then result:=jsonb_build_object('code',case when exists(select 1 from public.delivery_otps where order_id=o.id) then 'EXPIRED' else 'NO_OTP' end);
 elsif d.rider_id<>a or d.expires_at<=clock_timestamp() then
  update public.delivery_otps set state='EXPIRED' where id=d.id;result:=jsonb_build_object('code','EXPIRED');
 elsif d.attempts>=3 then result:=jsonb_build_object('code','LOCKED');
 elsif not public.fr33_equal(d.verifier,public.fr33_tag(o.id,d.nonce,p_otp)) then
  update public.delivery_otps set attempts=attempts+1,state=case when attempts+1=3 then 'LOCKED' else state end where id=d.id returning * into d;
  result:=jsonb_build_object('code',case when d.attempts=3 then 'LOCKED' else 'INVALID' end,'remaining',3-d.attempts);
  insert into public.security_audit_log(actor_id,action,target_type,target_id,otp_operation_id) values(a,'delivery_otp_invalid','order',o.id,p_request_id);
  if d.attempts=3 then
   update public.orders set otp_admin_review=true where id=o.id;
   admin_id:=d.review_admin_id;
   insert into public.notifications(user_id,title,message,type,delivery_otp_id) values(admin_id,'Delivery requires review','Three incorrect delivery codes. Review order #'||o.id||'.','otp_review',d.id);
   insert into public.security_audit_log(actor_id,action,target_type,target_id,otp_operation_id) values(a,'delivery_otp_locked','order',o.id,p_request_id);
  end if;
 else
  perform 1 from public.riders where userid=a for update;
  update public.orders set order_status='delivered' where id=o.id;
  update public.vendor_orders set status='delivered' where order_id=o.id and status is distinct from 'delivered';
  update public.rider_assignments set status='Delivered' where orderid=o.id and riderid=a;
  update public.riders set is_available=true,isavailable=true where userid=a and not exists(select 1 from public.orders where rider_id=a and (order_status is null or order_status not in ('cancelled','delivered')));
  insert into public.delivery_proof(proofid,orderid,riderid,otpconfirmed,is_verified,verified_at) values('fr21-otp-'||o.id,o.id::text,auth.uid()::text,true,true,clock_timestamp());
  update public.delivery_otps set state=case when id=d.id then 'USED' else 'INVALIDATED' end where order_id=o.id and state in ('ACCEPTED','RESERVED','SENDING');
  insert into public.security_audit_log(actor_id,action,target_type,target_id,otp_operation_id) values(a,'delivery_completed','order',o.id,p_request_id);
  insert into public.notifications(user_id,title,message,type,delivery_otp_id) values(o.user_id,'Order delivered','Your order has been delivered.','delivery',d.id);
  result:=jsonb_build_object('code','OK','order_status','delivered');
 end if;
 insert into public.delivery_otp_verifications(id,order_id,rider_id,input_tag,result) values(p_request_id,o.id,a,tag,result);
 return result;
end $$;
-- Compatibility delegates to the secured verifier; old plaintext comparison is gone.
create or replace function public.fr21_complete_delivery(p_order_id bigint,p_otp text) returns boolean language sql security definer set search_path='' as $$
 select (public.verify_delivery_otp(p_order_id,p_otp,gen_random_uuid())->>'code') in ('OK','ALREADY_DELIVERED')
$$;
create function public.fr33_guard_client_order() returns trigger language plpgsql set search_path='' as $$ begin
 if current_user in ('authenticated','anon') then
  if (tg_op='INSERT' and (new.order_status='delivered' or new.otp_admin_review or new.delivery_otp_email_status<>'none'))
   or (tg_op='UPDATE' and ((new.order_status='delivered' and old.order_status is distinct from 'delivered') or new.otp_admin_review is distinct from old.otp_admin_review or new.delivery_otp_email_status is distinct from old.delivery_otp_email_status)) then
   raise exception 'Use secured delivery workflow' using errcode='42501';end if;
 end if;return new;
end $$;
create trigger fr33_guard_client_order before insert or update on public.orders for each row execute function public.fr33_guard_client_order();
revoke all on function public.fr33_tag(bigint,text,text),public.fr33_equal(bytea,bytea),public.issue_delivery_otp(bigint,uuid,uuid),public.fr33_start_send(uuid),public.fr33_finish_send(uuid,text,text),public.delivery_otp_status(bigint),public.verify_delivery_otp(bigint,text,uuid),public.fr33_guard_client_order() from public,anon,authenticated;
grant execute on function public.issue_delivery_otp(bigint,uuid,uuid),public.fr33_start_send(uuid),public.fr33_finish_send(uuid,text,text) to service_role;
grant execute on function public.delivery_otp_status(bigint),public.verify_delivery_otp(bigint,text,uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.fr21_ready_and_assign(p_vendor_order_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor bigint:=public.fr21_actor(); vo public.vendor_orders; o public.orders;
  rider public.riders; lat numeric; lng numeric; distance double precision; begin
  if actor is null or public.fr21_role() is distinct from 'vendor' or not exists(select 1
    from public.users where id=actor and verification_status='approved') then
    raise exception 'Approved vendor required' using errcode='42501'; end if;
  if p_vendor_order_id is null then raise exception 'Missing order' using errcode='22023'; end if;
  select * into vo from public.vendor_orders where id=p_vendor_order_id;
  if not found or vo.vendor_id is distinct from actor then
    raise exception 'Vendor order forbidden' using errcode='42501'; end if;
  if vo.order_id is null then raise exception 'Missing parent order' using errcode='22023'; end if;
  -- Parent -> vendor order -> rider. Duplicate/multi-vendor calls serialize.
  select * into o from public.orders where id=vo.order_id for update;
  if not found then raise exception 'Parent order missing' using errcode='P0002'; end if;
  select * into vo from public.vendor_orders where id=p_vendor_order_id for update;
  if vo.vendor_id is distinct from actor or vo.order_id is distinct from o.id then
    raise exception 'Vendor order changed' using errcode='PT409'; end if;
  if coalesce(o.order_status,'') not in ('placed','pending','accepted','preparing','ready','on_the_way')
    or coalesce(vo.status,'') not in ('pending','accepted','preparing','ready','on_the_way') then
    raise exception 'Order is closed or invalid' using errcode='22023'; end if;
  -- Keep the existing trigger's parent-status propagation and notifications.
  if o.rider_id is not null then
    update public.vendor_orders set status='on_the_way' where id=vo.id and status is distinct from 'on_the_way';
    return jsonb_build_object('message','Order ready; rider already assigned.','rider_id',o.rider_id); end if;
  update public.vendor_orders set status='ready' where id=vo.id and status is distinct from 'ready';
  select latitude,longitude into lat,lng from public.vendors where user_id=actor;
  if lat is null or lng is null then
    return jsonb_build_object('message','Order ready. Set your store location to match a rider.'); end if;
  if lat not between -90 and 90 or lng not between -180 and 180 then
    raise exception 'Invalid store coordinates' using errcode='22023'; end if;
  select r.* into rider from public.riders r join public.users u on u.id=r.userid
    where r.is_online is true and r.is_available is true and r.isavailable is true
      and r.last_seen>=statement_timestamp()-interval '2 minutes'
      and u.role='rider' and u.verification_status='approved'
      and r.latitude between -90 and 90 and r.longitude between -180 and 180
      and not exists(select 1 from public.orders busy where busy.rider_id=r.userid
        and (busy.order_status is null or busy.order_status not in ('cancelled','delivered')))
    order by (sin(radians((r.latitude-lat)::double precision)/2)^2
      + cos(radians(lat::double precision))*cos(radians(r.latitude::double precision))
      * sin(radians((r.longitude-lng)::double precision)/2)^2),r.id
    limit 1 for update of r,u skip locked;
  if not found then return jsonb_build_object('message','Order ready. No online approved fresh rider is available.'); end if;
  if rider.last_seen<clock_timestamp()-interval '2 minutes' then
    return jsonb_build_object('message','Order ready. Rider heartbeat expired; retry matching.'); end if;
  distance:=6371*2*asin(sqrt(least(1::double precision,
    sin(radians((rider.latitude-lat)::double precision)/2)^2
    + cos(radians(lat::double precision))*cos(radians(rider.latitude::double precision))
    * sin(radians((rider.longitude-lng)::double precision)/2)^2)));
  -- Existing ready-status trigger exposes this as the rider's active delivery;
  -- issue its OTP in the same transaction rather than require a second accept.
  update public.orders set rider_id=rider.userid,
    delivery_otp=null where id=o.id;
  insert into public.rider_assignments(riderid,orderid,status) values(rider.userid,o.id,'Pending');
  update public.riders set is_available=false,isavailable=false where id=rider.id;
  update public.vendor_orders set status='on_the_way' where id=vo.id and status is distinct from 'on_the_way';
  insert into public.notifications(user_id,title,message,type)
    values(rider.userid,'New Delivery Assigned','You have a new pickup ready for delivery.','order');
  return jsonb_build_object('message',format('Order ready; rider assigned, %s km from your shop.',round(distance::numeric,1)),
    'rider_id',rider.userid);
end $function$
;
CREATE OR REPLACE FUNCTION public.fr21_accept_order(p_order_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor bigint:=public.fr21_actor(); o public.orders; r public.riders; otp text; begin
  if not public.fr21_approved_rider(actor) then raise exception 'Approved rider required' using errcode='42501'; end if;
  select * into o from public.orders where id=p_order_id for update;
  if not found then raise exception 'Order missing' using errcode='P0002'; end if;
  if o.rider_id is not null and o.rider_id<>actor then raise exception 'Order assigned to another rider' using errcode='42501'; end if;
  if coalesce(o.order_status,'') not in ('placed','accepted','ready','on_the_way') then
    raise exception 'Order cannot be accepted' using errcode='22023'; end if;
  perform 1 from public.users where id=actor and role='rider' and verification_status='approved' for update;
  if not found then raise exception 'Rider approval changed' using errcode='42501'; end if;
  select * into r from public.riders where userid=actor for update;
  if not found or r.is_online is distinct from true or r.last_seen is null
    or r.last_seen<clock_timestamp()-interval '2 minutes' then
    raise exception 'Fresh online presence required' using errcode='42501'; end if;
  if exists(select 1 from public.orders where rider_id=actor and id<>o.id
    and (order_status is null or order_status not in ('cancelled','delivered'))) then
    raise exception 'Another delivery is active' using errcode='22023'; end if;
  if o.rider_id is null then
    if r.is_available is distinct from true or r.isavailable is distinct from true then
      raise exception 'Rider unavailable' using errcode='22023'; end if;
    insert into public.rider_assignments(riderid,orderid,status) values(actor,o.id,'Accepted');
  else
    update public.rider_assignments set status='Accepted' where orderid=o.id and riderid=actor and status='Pending';
  end if;
  otp:=null;
  update public.orders set rider_id=actor,order_status='on_the_way',delivery_otp=otp where id=o.id;
  update public.vendor_orders set status='on_the_way' where order_id=o.id and status is distinct from 'on_the_way';
  update public.riders set is_available=false,isavailable=false where id=r.id;
  return jsonb_build_object('order_status','on_the_way','rider_id',actor);
end $function$
;
notify pgrst,'reload schema';
commit;
