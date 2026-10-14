-- FR33: expire crashed reservations before idempotent replay; recheck dispatch authorization.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create or replace function public.issue_delivery_otp(p_order_id bigint,p_request_id uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders; a bigint; existing public.delivery_otps; latest timestamptz; n int;
 recipient text; review_admin bigint; random_bytes bytea; number int; code text; salt text; budget int; used_count int; moment timestamptz:=clock_timestamp(); begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server issuance required' using errcode='42501'; end if;
 select u.id into a from public.users u join auth.users au on au.email=u.email where au.id=p_actor and au.email_confirmed_at is not null and u.role='rider' and u.verification_status='approved';
 select * into o from public.orders where id=p_order_id for update;
 if a is null or o.id is null or o.rider_id is distinct from a or not public.fr21_approved_rider(a) then return jsonb_build_object('code','FORBIDDEN'); end if;
 if o.order_status='delivered' then return jsonb_build_object('code','ALREADY_DELIVERED'); end if;
 if o.order_status is distinct from 'on_the_way' or p_request_id is null then return jsonb_build_object('code','WRONG_STATE'); end if;
 update public.delivery_otps set state=case when state='RESERVED' then 'FAILED' else 'UNKNOWN' end where order_id=o.id and state in ('RESERVED','SENDING') and lease_until<=moment;
 select * into existing from public.delivery_otps where id=p_request_id;
 if found then
  if existing.order_id<>o.id or existing.auth_id<>p_actor then return jsonb_build_object('code','FORBIDDEN'); end if;
  return jsonb_build_object('code',case existing.state when 'ACCEPTED' then case when existing.expires_at>moment then 'EMAIL_ACCEPTED' else 'EXPIRED' end when 'FAILED' then 'EMAIL_FAILED' when 'UNKNOWN' then 'EMAIL_UNKNOWN' when 'RESERVED' then 'EMAIL_PENDING' when 'SENDING' then 'EMAIL_PENDING' else 'EXPIRED' end,'replayed',true);
 end if;
 -- Expired leases never resend. The old accepted issuance is retained until replacement acceptance.
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
create or replace function public.fr33_start_send(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare d public.delivery_otps; o public.orders; begin
 if auth.role() is distinct from 'service_role' then raise exception 'Server required' using errcode='42501'; end if;
 select * into d from public.delivery_otps where id=p_id;
 if not found then return false; end if;
 select * into o from public.orders where id=d.order_id for update;
 if o.rider_id is distinct from d.rider_id or o.order_status is distinct from 'on_the_way' or not public.fr21_approved_rider(d.rider_id) or not exists(select 1 from auth.users au join public.users u on u.email=au.email where au.id=d.auth_id and au.email_confirmed_at is not null and u.id=d.rider_id) then
  update public.delivery_otps set state='FAILED' where id=d.id and state='RESERVED';return false;end if;
 update public.delivery_otps set state='SENDING' where id=p_id and state='RESERVED' and lease_until>clock_timestamp();return found;
end $$;
notify pgrst,'reload schema';
commit;
