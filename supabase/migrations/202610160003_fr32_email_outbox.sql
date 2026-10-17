-- FR32: durable business intents, private invoice snapshots and shared mail admission.
-- TEST only. Scheduling/secrets are configured separately after worker verification.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create schema fr32_private;
revoke all on schema fr32_private from public,anon,authenticated,service_role;
create table fr32_private.configuration(
 singleton boolean primary key default true check(singleton),
 daily_budget integer not null default 300 check(daily_budget between 1 and 300),
 otp_reserve integer not null default 90 check(otp_reserve>=0 and otp_reserve<=daily_budget),
 quota_mode text not null default 'unverified' check(quota_mode in('unverified','provider_day','rolling_26h')),
 provider_timezone text,
 dispatch_enabled boolean not null default false,
 check(quota_mode<>'provider_day'or provider_timezone is not null));
-- User approved temporary rolling26h policy on2026-10-16; no UTC reset claim.
insert into fr32_private.configuration(quota_mode)values('rolling_26h');
create table fr32_private.quota_reservations(
 id bigint generated always as identity primary key, attempt_key uuid not null,
 kind text not null check(kind in('otp','transactional')), units integer not null default 1 check(units>0),
 reserved_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 check(expires_at>reserved_at));
create index fr32_quota_window_idx on fr32_private.quota_reservations(expires_at,kind);
create index fr32_quota_attempt_idx on fr32_private.quota_reservations(attempt_key,expires_at desc);
-- Cover existing OTP reservations; do not erase/reset accepted accounting.
insert into fr32_private.quota_reservations(attempt_key,kind,reserved_at,expires_at)
 select id,'otp',created_at,created_at+interval '26 hours'from public.delivery_otps
 where created_at>clock_timestamp()-interval '26 hours';
insert into fr32_private.quota_reservations(attempt_key,kind,units,reserved_at,expires_at)
 select gen_random_uuid(),'otp',b.used-coalesce(d.n,0),clock_timestamp(),clock_timestamp()+interval '26 hours'
 from public.delivery_otp_budgets b left join lateral(select count(*)::integer n from public.delivery_otps
 where(created_at at time zone 'UTC')::date=b.day)d on true
 where b.day>=(clock_timestamp()at time zone 'UTC')::date-1 and b.used>coalesce(d.n,0);

create table fr32_private.account_events(
 id uuid primary key default gen_random_uuid(),user_id bigint not null references public.users(id),
 actor_id bigint,kind text not null,source_operation uuid unique,created_at timestamptz not null default clock_timestamp());
create trigger fr32_account_event_immutable before update or delete on fr32_private.account_events
 for each row execute function public.fr26_append_only();
alter table public.security_audit_log add column email_event_id uuid;
create unique index fr32_email_audit_once_idx on public.security_audit_log(email_event_id)where email_event_id is not null;
create table fr32_private.order_snapshots(
 -- Immutable historical IDs, deliberately no parent FK/lock from a payment hook.
 order_id bigint primary key,owner_id bigint not null,snapshot jsonb not null,
 created_at timestamptz not null default clock_timestamp());
create trigger fr32_order_snapshot_immutable before update or delete on fr32_private.order_snapshots
 for each row execute function public.fr26_append_only();
create table public.invoices(
 id uuid primary key default gen_random_uuid(),payment_id bigint not null unique,
 order_id bigint not null,owner_id bigint not null references public.users(id),
 invoice_number text not null unique,status text not null default 'pending'check(status in('pending','ready','failed')),
 object_path text not null unique,sha256 text,byte_size integer,
 failure_code text,created_at timestamptz not null default clock_timestamp(),ready_at timestamptz,
 check((status='ready'and sha256~'^[a-f0-9]{64}$'and byte_size between 1 and 5242880 and ready_at is not null)or status<>'ready'));
create index fr32_owner_invoice_idx on public.invoices(owner_id,order_id,id);
create table fr32_private.invoice_snapshots(invoice_id uuid primary key,snapshot jsonb not null);
create trigger fr32_invoice_snapshot_immutable before update or delete on fr32_private.invoice_snapshots
 for each row execute function public.fr26_append_only();
create table public.email_outbox(
 id uuid primary key default gen_random_uuid(),email_type text not null check(email_type in(
 'order_confirmation','paid_invoice','vendor_approved','vendor_rejected','rider_approved','rider_rejected','rider_cnic_verified','account_blocked','account_unblocked')),
 recipient_user_id bigint not null references public.users(id),entity_type text not null,entity_id text not null,
 dedupe_key text not null unique,payload jsonb not null default '{}',
 status text not null default 'pending'check(status in('pending','sending','sent','deferred','failed','delivery_unknown','skipped_test')),
 priority smallint not null default 20,attempts integer not null default 0 check(attempts between 0 and 5),
 preparations integer not null default 0 check(preparations>=0),next_attempt_at timestamptz not null default clock_timestamp(),
 lease_token uuid,lease_expires_at timestamptz,send_started_at timestamptz,first_send_at timestamptz,uncertain_since timestamptz,
 wire_sha256 text,provider_key uuid not null default gen_random_uuid(),provider_message_id text,last_error text,
 test_approved boolean not null default false,created_at timestamptz not null default clock_timestamp(),sent_at timestamptz,
 check(wire_sha256 is null or wire_sha256~'^[a-f0-9]{64}$'));
create index fr32_due_email_idx on public.email_outbox(priority,next_attempt_at,created_at,id)where status in('pending','deferred');
create index fr32_email_lease_idx on public.email_outbox(lease_expires_at)where status='sending';
create index fr32_email_entity_idx on public.email_outbox(entity_type,entity_id);
alter table public.email_outbox enable row level security;
alter table public.invoices enable row level security;
revoke all on public.email_outbox,public.invoices from public,anon,authenticated;
grant select on public.invoices to authenticated;
create policy fr32_invoice_owner_read on public.invoices for select to authenticated using(
 public.is_current_user_allowed()and(owner_id=public.fr21_actor()or public.fr21_role()='admin'));
grant select on public.email_outbox,public.invoices to service_role;
-- Only reviewed RPCs mutate jobs/invoice metadata, including for the worker role.
revoke insert,update,delete,truncate on public.email_outbox,public.invoices from service_role;
do $$declare t record;begin
 for t in select tablename from pg_tables where schemaname='fr32_private'loop
 execute format('alter table fr32_private.%I enable row level security',t.tablename);
 execute format('revoke all on fr32_private.%I from public,anon,authenticated,service_role',t.tablename);
 end loop;
end$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('invoices','invoices',false,5242880,array['application/pdf']);
create policy fr32_invoice_direct_deny on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'invoices')with check(bucket_id<>'invoices');

create function fr32_private.server_only()returns void language plpgsql stable set search_path=''as $$begin
 if auth.role()is distinct from'service_role'then raise exception 'Server required'using errcode='42501';end if;
end$$;
create function fr32_private.recipient(p_user bigint)returns text language sql stable security definer set search_path=''as $$
 select au.email from public.users u join auth.users au on au.id=u.auth_user_id
 where u.id=p_user and lower(u.email)=lower(au.email)and au.email_confirmed_at is not null
 and char_length(au.email)<=254 and au.email~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
$$;
create function fr32_private.enqueue(p_type text,p_user bigint,p_entity text,p_id text,p_key text,p_payload jsonb default '{}')returns uuid
 language plpgsql security definer set search_path=''as $$declare result uuid;begin
 insert into public.email_outbox(email_type,recipient_user_id,entity_type,entity_id,dedupe_key,payload,priority)
 values(p_type,p_user,p_entity,p_id,p_key,p_payload,case when p_type like 'account_%'then 10 when p_type='paid_invoice'then 15 else 20 end)
 on conflict(dedupe_key)do nothing returning id into result;
 if result is null then select id into result from public.email_outbox where dedupe_key=p_key;end if;return result;
end$$;
create function fr32_private.account_event(p_user bigint,p_kind text,p_source uuid default null)returns void
 language plpgsql security definer set search_path=''as $$declare event_id uuid;begin
 insert into fr32_private.account_events(user_id,actor_id,kind,source_operation)
 values(p_user,public.fr21_actor(),p_kind,p_source)on conflict(source_operation)do nothing returning id into event_id;
 if event_id is null then return;end if;
 insert into public.security_audit_log(actor_id,action,target_type,target_id,email_event_id)
 values(public.fr21_actor(),'fr32_'||p_kind,'users',p_user,event_id);
 perform fr32_private.enqueue(p_kind,p_user,'account_event',event_id::text,'account:'||event_id);
end$$;
create function fr32_private.account_transition()returns trigger language plpgsql security definer set search_path=''as $$declare kind text;begin
 if old.verification_status is not distinct from new.verification_status or new.role not in('vendor','rider')or new.verification_status not in('approved','rejected')then return new;end if;
 kind:=new.role||'_'||new.verification_status;
 if new.role='rider'and new.verification_status='approved'and fr04_private.document_exists(new.id)then kind:='rider_cnic_verified';end if;
 perform fr32_private.account_event(new.id,kind);return new;
end$$;
create trigger fr32_account_transition after update of verification_status on public.users
 for each row execute function fr32_private.account_transition();
create function fr32_private.block_transition()returns trigger language plpgsql security definer set search_path=''as $$begin
 if new.state='SYNCED'and old.state is distinct from'SYNCED'then
 perform fr32_private.account_event(new.target_id,case when new.desired_blocked then'account_blocked'else'account_unblocked'end,new.id);
 end if;return new;
end$$;
create trigger fr32_block_transition after update of state on public.fr28_operations
 for each row execute function fr32_private.block_transition();

create function fr32_private.snapshot_order(p_order bigint)returns jsonb language plpgsql security definer set search_path=''as $$
declare o public.orders;items jsonb;total numeric;result jsonb;begin
 select snapshot into result from fr32_private.order_snapshots where order_id=p_order;if found then return result;end if;
 select *into o from public.orders where id=p_order;
 if o.id is null or o.checkout_finalized_at is null then return null;end if;
 if exists(select 1 from public.order_items i join public.vendor_orders v on v.id=i.vendor_order_id where v.order_id=o.id
 and(i.quantity is null or i.quantity<=0 or i.price_at_time is null or i.price_at_time<0 or i.price_at_time::text in('NaN','Infinity','-Infinity')or i.price_at_time<>round(i.price_at_time,2)))then return null;end if;
 select sum(i.price_at_time*i.quantity),jsonb_agg(jsonb_build_object(
 'item_id',i.id,'product_id',i.product_id,'product',coalesce(p.name,'Product #'||i.product_id),
 'vendor_id',v.vendor_id,'vendor',coalesce(u.name,'Vendor #'||v.vendor_id),
 'quantity',i.quantity,'unit_cents',(i.price_at_time*100)::bigint::text,'line_cents',(i.price_at_time*i.quantity*100)::bigint::text)order by v.vendor_id,i.id)
 into total,items from public.order_items i join public.vendor_orders v on v.id=i.vendor_order_id
 left join public.products p on p.id=i.product_id left join public.users u on u.id=v.vendor_id where v.order_id=o.id;
 if items is null or jsonb_array_length(items)>100 or o.amount is null or o.fare is null or o.amount::text in('NaN','Infinity','-Infinity')or o.fare::text in('NaN','Infinity','-Infinity')or total+o.fare<>o.amount or o.fare<0 or o.fare<>round(o.fare,2)
 or o.amount<>round(o.amount,2)or o.amount<=0 or o.amount>1000000000000 then return null;end if;
 if exists(select 1 from public.vendor_orders v where v.order_id=o.id and(v.sub_total is null or v.sub_total<>(select coalesce(sum(i.quantity*i.price_at_time),0)from public.order_items i where i.vendor_order_id=v.id)))then return null;end if;
 result:=jsonb_build_object('order_id',o.id,'customer_id',o.user_id,'customer',(select name from public.users where id=o.user_id),
 'items',items,'subtotal_cents',(total*100)::bigint::text,'delivery_cents',(o.fare*100)::bigint::text,
 'total_cents',(o.amount*100)::bigint::text,'currency','PKR','checkout_at',o.checkout_finalized_at);
 insert into fr32_private.order_snapshots(order_id,owner_id,snapshot)values(o.id,o.user_id,result)on conflict do nothing;
 select snapshot into result from fr32_private.order_snapshots where order_id=o.id;return result;
end$$;
create function fr32_private.order_finalized()returns trigger language plpgsql security definer set search_path=''as $$begin
 if new.checkout_finalized_at is not null and old.checkout_finalized_at is null then
 perform fr32_private.snapshot_order(new.id);
 perform fr32_private.enqueue('order_confirmation',new.user_id,'order',new.id::text,'order:'||new.id);
 end if;return new;
end$$;
create trigger fr32_order_finalized after update of checkout_finalized_at on public.orders
 for each row execute function fr32_private.order_finalized();
create function fr32_private.payment_captured()returns trigger language plpgsql security definer set search_path=''as $$
declare o public.orders;snapshot jsonb;invoice public.invoices;invoice_id uuid:=gen_random_uuid();begin
 if upper(coalesce(new.status,''))not in('SUCCESS','PAID','COMPLETED','SUCCEEDED')or new.paidat is null then return new;end if;
 if exists(select 1 from public.invoices where payment_id=new.id)then return new;end if;
 if new.orderid is null or new.orderid!~'^[0-9]{1,18}$'then return new;end if;
 -- Plain MVCC reads: never acquire an existing parent lock behind a payment row.
 select *into o from public.orders where id=new.orderid::bigint;
 if o.id is null or new.customerid is distinct from o.user_id::text or lower(new.method)is distinct from lower(o.payment_method)
 or new.amount is null or new.amount::text in('NaN','Infinity','-Infinity')or new.amount::numeric<>o.amount or new.amount<=0 or new.paidat>clock_timestamp()
 or nullif(btrim(new.paymentid),'')is null or(select count(*)from public.payments where orderid=new.orderid)<>1 then return new;end if;
 snapshot:=fr32_private.snapshot_order(o.id);
 insert into public.invoices(id,payment_id,order_id,owner_id,invoice_number,object_path,status,failure_code)
 values(invoice_id,new.id,o.id,o.user_id,'TR-'||lpad(new.id::text,greatest(12,length(new.id::text)),'0'),o.user_id||'/'||o.id||'/'||invoice_id||'.pdf',
 case when snapshot is null then'failed'else'pending'end,case when snapshot is null then'SOURCE_REVIEW_REQUIRED'end)
 on conflict(payment_id)do nothing returning *into invoice;
 if invoice.id is null then return new;end if;
 if snapshot is not null then
 insert into fr32_private.invoice_snapshots values(invoice.id,snapshot||jsonb_build_object('invoice_id',invoice.id,
 'invoice_number',invoice.invoice_number,'payment_id',new.id,'payment_reference',new.paymentid,'payment_status',upper(new.status),'paid_at',new.paidat));
 end if;
 perform fr32_private.enqueue('paid_invoice',o.user_id,'invoice',invoice.id::text,'invoice:'||new.id,jsonb_build_object('invoice_id',invoice.id));
 return new;
end$$;
create trigger fr32_payment_captured after insert or update of status,paidat,amount,paymentid,orderid,customerid,method on public.payments
 for each row execute function fr32_private.payment_captured();

-- Private deterministic clock exists for rollback/race tests only. RPC callers cannot inject time.
create function fr32_private.reserve_quota(p_kind text,p_key uuid,p_now timestamptz default clock_timestamp())returns jsonb
 language plpgsql security definer set search_path=''as $$declare cfg fr32_private.configuration;used bigint;non_otp bigint;ending timestamptz;again timestamptz;begin
 if p_kind not in('otp','transactional')or p_kind is null or p_key is null or p_now is null then raise exception 'Invalid quota reservation'using errcode='22023';end if;
 select *into cfg from fr32_private.configuration where singleton for update;
 if cfg.quota_mode='unverified'then return jsonb_build_object('code','CONFIGURATION_REQUIRED');end if;
 if cfg.quota_mode='provider_day'then
 if not exists(select 1 from pg_timezone_names where name=cfg.provider_timezone)then raise exception 'Verified timezone required';end if;
 ending:=(((p_now at time zone cfg.provider_timezone)::date+1)::timestamp at time zone cfg.provider_timezone);
 else ending:=p_now+interval '26 hours';end if;
 if exists(select 1 from fr32_private.quota_reservations where attempt_key=p_key and kind=p_kind and expires_at>p_now)then return jsonb_build_object('code','RESERVED','replayed',true);end if;
 select coalesce(sum(units),0),coalesce(sum(units)filter(where kind='transactional'),0),min(expires_at)
 into used,non_otp,again from fr32_private.quota_reservations where expires_at>p_now;
 if used>=cfg.daily_budget or(p_kind='transactional'and non_otp>=cfg.daily_budget-cfg.otp_reserve)then
 return jsonb_build_object('code','QUOTA_EXCEEDED','next_attempt_at',coalesce(again,ending));end if;
 insert into fr32_private.quota_reservations(attempt_key,kind,reserved_at,expires_at)values(p_key,p_kind,p_now,ending);
 return jsonb_build_object('code','RESERVED','expires_at',ending);
end$$;
-- Add only shared admission to the accepted OTP issuance body; HMAC, expiry,
-- nonce generation, ownership, rates and its legacy conservative counter remain.
do $$declare source text;needle text:='loop'||chr(10)||'  random_bytes:=';begin
 source:=pg_get_functiondef('public.issue_delivery_otp(bigint,uuid,uuid)'::regprocedure);
 -- Hosted accepted source preserves CRLF; normalize only line endings before
 -- matching, retaining FR28's unblocked/canonical-identity guards verbatim.
 source:=replace(source,chr(13)||chr(10),chr(10));
 if position(needle in source)=0 then raise exception 'Review changed FR33 issuance before integrating quota';end if;
 source:=replace(source,needle,
 'if (fr32_private.reserve_quota(''otp'',p_request_id,moment)->>''code'')<>''RESERVED'' then return jsonb_build_object(''code'',''QUOTA_EXCEEDED'');end if;'||chr(10)||' '||needle);
 execute source;
end$$;

create function fr32_private.claim(p_limit integer,p_now timestamptz default clock_timestamp())returns setof jsonb
 language plpgsql security definer set search_path=''as $$declare job public.email_outbox;begin
 if p_limit is null or p_limit not between 1 and 20 then raise exception 'Batch must be1-20'using errcode='22023';end if;
 with expired as(select id from public.email_outbox where status='sending'and lease_expires_at<=p_now order by lease_expires_at,id limit p_limit for update skip locked)
 update public.email_outbox set status=case when send_started_at is null then'pending'else'delivery_unknown'end,
 last_error=case when send_started_at is null then'PREPARATION_LEASE_EXPIRED'else'SEND_LEASE_EXPIRED'end,
 lease_token=null,lease_expires_at=null where id in(select id from expired);
 for job in select *from public.email_outbox where status in('pending','deferred')and next_attempt_at<=p_now
 order by priority,next_attempt_at,created_at,id limit p_limit for update skip locked loop
 if not job.test_approved and job.email_type<>'paid_invoice'then update public.email_outbox set status='skipped_test',last_error='TEST_DELIVERY_NOT_APPROVED'where id=job.id;continue;end if;
 if job.preparations>=10 or job.attempts>=5 then
 update public.email_outbox set status=case when uncertain_since is null then'failed'else'delivery_unknown'end,last_error='ATTEMPT_LIMIT'where id=job.id;continue;end if;
 if job.uncertain_since is not null and job.uncertain_since<=p_now-interval '10 minutes'then
 update public.email_outbox set status='delivery_unknown',last_error='IDEMPOTENCY_RECOVERY_WINDOW_ENDED'where id=job.id;continue;end if;
 update public.email_outbox set status='sending',lease_token=gen_random_uuid(),lease_expires_at=p_now+interval '2 minutes',
 send_started_at=null,preparations=preparations+1 where id=job.id returning *into job;
 return next jsonb_build_object('id',job.id,'lease',job.lease_token,'type',job.email_type,'entity_id',job.entity_id,
 'recipient',fr32_private.recipient(job.recipient_user_id),'recipient_user_id',job.recipient_user_id,'payload',job.payload,
 'provider_key',job.provider_key,'attempts',job.attempts,'first_send_at',job.first_send_at,'test_approved',job.test_approved,
 'invoice',(select i.snapshot from fr32_private.invoice_snapshots i where i.invoice_id=(job.payload->>'invoice_id')::uuid),
 'invoice_metadata',(select jsonb_build_object('id',id,'path',object_path,'status',status,'sha256',sha256,'bytes',byte_size)from public.invoices where id=(job.payload->>'invoice_id')::uuid));
 end loop;
end$$;
create function public.fr32_claim_email(p_limit integer default 5)returns setof jsonb language plpgsql security definer set search_path=''as $$begin
 perform fr32_private.server_only();return query select *from fr32_private.claim(p_limit);
end$$;
create function public.fr32_begin_email(p_id uuid,p_lease uuid,p_fingerprint text)returns jsonb
 language plpgsql security definer set search_path=''as $$declare job public.email_outbox;quota jsonb;begin
 perform fr32_private.server_only();
 if p_fingerprint is null or p_fingerprint!~'^[a-f0-9]{64}$'then raise exception 'Invalid message fingerprint'using errcode='22023';end if;
 select *into job from public.email_outbox where id=p_id for update;
 if job.id is null or job.lease_token is distinct from p_lease or job.status<>'sending'or job.lease_expires_at<=clock_timestamp()then return jsonb_build_object('code','STALE_LEASE');end if;
 if job.send_started_at is not null then return jsonb_build_object('code','ALREADY_STARTED');end if;
 if not job.test_approved then
 update public.email_outbox set status='skipped_test',last_error='TEST_DELIVERY_NOT_APPROVED',lease_token=null,lease_expires_at=null where id=job.id;
 return jsonb_build_object('code','TEST_DELIVERY_NOT_APPROVED');end if;
 if job.wire_sha256 is not null and job.wire_sha256<>p_fingerprint then
 update public.email_outbox set status='delivery_unknown',last_error='MESSAGE_CHANGED',lease_token=null,lease_expires_at=null where id=job.id;
 return jsonb_build_object('code','DELIVERY_UNKNOWN');end if;
 quota:=fr32_private.reserve_quota('transactional',job.provider_key);
 if quota->>'code'<>'RESERVED'then
 update public.email_outbox set status='deferred',next_attempt_at=coalesce((quota->>'next_attempt_at')::timestamptz,clock_timestamp()+interval '5 minutes'),
 last_error=quota->>'code',lease_token=null,lease_expires_at=null where id=job.id;return quota;end if;
 update public.email_outbox set attempts=attempts+1,send_started_at=clock_timestamp(),first_send_at=coalesce(first_send_at,clock_timestamp()),wire_sha256=p_fingerprint where id=job.id;
 return jsonb_build_object('code','SEND');
end$$;
create function public.fr32_finish_email(p_id uuid,p_lease uuid,p_outcome text,p_provider text default null,p_retry_seconds integer default null,p_error text default null)returns jsonb
 language plpgsql security definer set search_path=''as $$declare job public.email_outbox;delay integer;begin
 perform fr32_private.server_only();
 if p_outcome is null or p_outcome not in('sent','retry','uncertain_retry','failed','delivery_unknown','prepare_retry','skipped_test')
 or char_length(coalesce(p_provider,''))>200 or(p_error is not null and p_error!~'^[A-Z0-9_]{1,80}$')then raise exception 'Invalid safe outcome'using errcode='22023';end if;
 select *into job from public.email_outbox where id=p_id for update;
 if job.id is null or job.lease_token is distinct from p_lease or job.status<>'sending'then return jsonb_build_object('code','STALE_LEASE');end if;
 if p_outcome='sent'and(job.send_started_at is null or nullif(p_provider,'')is null)then raise exception 'Confirmed provider ID required';end if;
 delay:=greatest(30,least(coalesce(p_retry_seconds,(30*power(2,greatest(job.attempts,job.preparations)-1))::integer),86400));
 update public.email_outbox set
 status=case when p_outcome in('retry','uncertain_retry','prepare_retry')then
 case when attempts>=5 then case when p_outcome='retry'and uncertain_since is null then'failed'else'delivery_unknown'end
 when p_outcome='uncertain_retry'and first_send_at+interval '10 minutes'<=clock_timestamp()+make_interval(secs=>delay)then'delivery_unknown'else'deferred'end else p_outcome end,
 uncertain_since=case when p_outcome='uncertain_retry'then coalesce(uncertain_since,first_send_at)else uncertain_since end,
 next_attempt_at=clock_timestamp()+make_interval(secs=>delay),provider_message_id=coalesce(p_provider,provider_message_id),
 sent_at=case when p_outcome='sent'then clock_timestamp()else sent_at end,last_error=p_error,
 lease_token=null,lease_expires_at=null,send_started_at=null where id=job.id;
 return jsonb_build_object('code','RECORDED');
end$$;
create function public.fr32_register_invoice_pdf(p_job uuid,p_lease uuid,p_sha256 text,p_bytes integer)returns jsonb
 language plpgsql security definer set search_path=''as $$declare job public.email_outbox;invoice public.invoices;begin
 perform fr32_private.server_only();select *into job from public.email_outbox where id=p_job for update;
 if job.status is distinct from'sending'or job.lease_token is distinct from p_lease or job.lease_expires_at<=clock_timestamp()or job.email_type<>'paid_invoice'then return jsonb_build_object('code','STALE_LEASE');end if;
 select *into invoice from public.invoices where id=(job.payload->>'invoice_id')::uuid for update;
 if invoice.status='ready'then
 if invoice.sha256<>p_sha256 or invoice.byte_size<>p_bytes then raise exception 'Immutable PDF mismatch';end if;return jsonb_build_object('code','READY');end if;
 if invoice.status<>'pending'or p_sha256!~'^[a-f0-9]{64}$'or p_sha256 is null or p_bytes is null or p_bytes not between 1 and 5242880
 or not exists(select 1 from storage.objects where bucket_id='invoices'and name=invoice.object_path and metadata->>'mimetype'='application/pdf'and(metadata->>'size')::bigint=p_bytes)then raise exception 'Verified private PDF object required';end if;
 update public.invoices set status='ready',sha256=p_sha256,byte_size=p_bytes,ready_at=clock_timestamp()where id=invoice.id;
 update public.payments set invoiceurl=invoice.object_path where id=invoice.payment_id;
 return jsonb_build_object('code','READY');
end$$;
create function public.fr32_invoice_authority(p_order_id bigint)returns jsonb language plpgsql stable security definer set search_path=''as $$declare invoice public.invoices;actor bigint:=public.fr21_actor();begin
 if actor is null or not public.is_current_user_allowed()then raise exception 'Authentication required'using errcode='42501';end if;
 if not exists(select 1 from public.orders where id=p_order_id and(user_id=actor or public.fr21_role()='admin'))then raise exception 'Owned invoice required'using errcode='42501';end if;
 select *into invoice from public.invoices where order_id=p_order_id order by created_at desc limit 1;
 if invoice.id is null then return jsonb_build_object('code','NOT_READY');end if;
 if invoice.status<>'ready'then return jsonb_build_object('code','NOT_READY','status',invoice.status);end if;
 return jsonb_build_object('code','READY','path',invoice.object_path,'invoice_number',invoice.invoice_number,'sha256',invoice.sha256);
end$$;
-- Explicit TEST-only delivery approval, inaccessible to clients. Regressions
-- enqueue normally but cannot spam the approved inbox or consume provider quota.
create function public.fr32_test_allow_email(p_ids uuid[])returns integer language plpgsql security definer set search_path=''as $$declare changed integer;begin
 perform fr32_private.server_only();if cardinality(p_ids)not between 1 and 30 then raise exception 'Bounded TEST jobs required';end if;
 update public.email_outbox set test_approved=true,status=case when status='skipped_test'then'pending'else status end,next_attempt_at=clock_timestamp(),last_error=null
 where id=any(p_ids)and status in('pending','skipped_test')and attempts=0;get diagnostics changed=row_count;return changed;
end$$;
create function fr32_private.dispatch()returns bigint language plpgsql security definer set search_path=''as $$declare key text;begin
 if not(select dispatch_enabled from fr32_private.configuration where singleton)then return null;end if;
 select decrypted_secret into strict key from vault.decrypted_secrets where name='fr32_email_worker_key';
 return net.http_post(url:='https://igeisilhtmglgnqvllrx.supabase.co/functions/v1/fr32-email-worker',
 headers:=jsonb_build_object('Content-Type','application/json','x-fr32-worker-key',key),body:='{}'::jsonb,timeout_milliseconds:=10000);
end$$;
revoke all on all functions in schema fr32_private from public,anon,authenticated,service_role;
revoke all on function public.fr32_claim_email(integer),public.fr32_begin_email(uuid,uuid,text),public.fr32_finish_email(uuid,uuid,text,text,integer,text),
 public.fr32_register_invoice_pdf(uuid,uuid,text,integer),public.fr32_invoice_authority(bigint),public.fr32_test_allow_email(uuid[])from public,anon,authenticated;
grant execute on function public.fr32_claim_email(integer),public.fr32_begin_email(uuid,uuid,text),public.fr32_finish_email(uuid,uuid,text,text,integer,text),
 public.fr32_register_invoice_pdf(uuid,uuid,text,integer),public.fr32_test_allow_email(uuid[])to service_role;
grant execute on function public.fr32_invoice_authority(bigint)to authenticated;
notify pgrst,'reload schema';
commit;
