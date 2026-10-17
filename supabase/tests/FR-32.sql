-- Actual PostgreSQL assertions, synthetic identities, deterministic private clock.
-- Entire transaction rolls back. Independent-session races have a separate runner.
begin;
create temp table fr32_results(name text,result text);
create temp table fr32_people(label text,id bigint,auth_id uuid,session_id uuid,email text);
create function pg_temp.ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'FR32 assertion: %',label;end if;
 insert into fr32_results values(label,'PASS');end$$;
do $$declare who text;a uuid;s uuid;uid bigint;mail text;begin
 foreach who in array array['customer','other','vendor','vendor2','rider','admin']loop
 a:=gen_random_uuid();s:=gen_random_uuid();mail:='fr32-sql-'||a||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud)values(a,mail,now(),'authenticated','authenticated');
 insert into public.users(email,name,role,verification_status)values(mail,'FR32 SQL SYNTHETIC',case when who='other'then'customer'when who='vendor2'then'vendor'else who end,'approved')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
 insert into fr32_people values(who,uid,a,s,mail);end loop;
end$$;
create function pg_temp.claim(who text)returns void language plpgsql security definer as $$declare p fr32_people;begin
 if who='service'then perform set_config('request.jwt.claims','{"role":"service_role"}',true);return;end if;
 select *into p from fr32_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,'email',p.email)::text,true);
end$$;
create function pg_temp.product(who text)returns bigint language plpgsql security definer as $$declare r jsonb;begin
 perform pg_temp.claim(who);r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FR32 immutable product","price":80,"is_available":true}',100,5,null);
 perform pg_temp.ok(r->>'code'='UPDATED','stocked product created');return(r->>'product_id')::bigint;
end$$;
create temp table fr32_fixture(order_id bigint,invoice_id uuid,job_id uuid,customer_id bigint);
grant select on fr32_fixture to authenticated;
do $$declare p bigint;q bigint;r jsonb;oid bigint;pid bigint;iid uuid;jid uuid;count_before bigint;uid bigint;begin
 p:=pg_temp.product('vendor');q:=pg_temp.product('vendor2');perform pg_temp.claim('customer');
 r:=public.fr10_checkout(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2),jsonb_build_object('product_id',q,'quantity',1)),
 '{"address":"FR32 synthetic TEST","lat":33.68,"lng":73.04,"speed":"standard"}');
 perform pg_temp.ok(r->>'code'='PLACED','real shared checkout placed');oid:=(r->>'order_id')::bigint;
 select id into uid from fr32_people where label='customer';
 perform pg_temp.ok((select count(*)=1 from public.email_outbox where dedupe_key='order:'||oid),'checkout atomically enqueues one confirmation');
 perform fr32_private.enqueue('order_confirmation',uid,'order',oid::text,'order:'||oid);
 perform pg_temp.ok((select count(*)=1 from public.email_outbox where dedupe_key='order:'||oid),'duplicate stable business key suppressed');
 perform pg_temp.ok(not exists(select 1 from public.invoices where order_id=oid),'uncollected COD has no paid invoice');
 select id into pid from public.payments where orderid=oid::text;
 perform pg_temp.claim('service');
 update public.payments set status='PAID',paidat=clock_timestamp(),paymentid='FR32-SYNTHETIC-CAPTURE-'||pid where id=pid;
 select id into iid from public.invoices where payment_id=pid;
 perform pg_temp.ok(iid is not null,'server recorded full COD collection enqueues invoice');
 update public.payments set status='PAID'where id=pid;
 perform pg_temp.ok((select count(*)=1 from public.invoices where payment_id=pid),'repeated captured event one invoice');
 select id into jid from public.email_outbox where dedupe_key='invoice:'||pid;
 perform pg_temp.ok(jid is not null,'invoice outbox exists');
 perform pg_temp.ok((select snapshot->>'subtotal_cents'='24000'and snapshot->>'delivery_cents'='20000'and snapshot->>'total_cents'='44000'and jsonb_array_length(snapshot->'items')=2 from fr32_private.invoice_snapshots where invoice_id=iid),'immutable integer-cent shared invoice reconciles delivery once');
 update public.products set price=999 where id=p;
 perform pg_temp.ok((select snapshot->>'total_cents'='44000'from fr32_private.invoice_snapshots where invoice_id=iid),'mutable catalog price cannot alter invoice');
 perform pg_temp.ok(fr32_private.recipient(uid)=(select email from fr32_people where id=uid),'recipient canonical verified Auth identity');
 update auth.users set email_confirmed_at=null where id=(select auth_id from fr32_people where id=uid);
 perform pg_temp.ok(fr32_private.recipient(uid)is null,'unverified recipient withheld');
 update auth.users set email_confirmed_at=now()where id=(select auth_id from fr32_people where id=uid);
 insert into fr32_fixture values(oid,iid,jid,uid);
end$$;
do $$declare who text;uid bigint;n bigint;path text;upload uuid:=gen_random_uuid();op uuid;blocked boolean;aid uuid;begin
 perform pg_temp.claim('service');
 select id into uid from fr32_people where label='rider';
 path:=(select auth_id::text from fr32_people where id=uid)||'/'||upload||'/cnic.png';
 insert into storage.buckets(id,name,public)values('rider-cnic','rider-cnic',false)on conflict do nothing;
 insert into storage.objects(bucket_id,name,metadata)values('rider-cnic',path,'{"mimetype":"image/png","size":100}');
 update public.users set cnic=fr04_private.encrypt_cnic('3200012345671'),cnic_image_url=path,cnic_upload_id=upload,cnic_submission_status='submitted',cnic_image_digest=repeat('a',64),cnic_submitted_at=now()where id=uid;
 perform pg_temp.claim('admin');
 foreach who in array array['vendor','rider']loop
 select id into uid from fr32_people where label=who;
 update public.users set verification_status='rejected'where id=uid;
 update public.users set verification_status='rejected'where id=uid;
 update public.users set verification_status='approved'where id=uid;
 select count(*)into n from public.email_outbox where recipient_user_id=uid and email_type in(who||'_approved',who||'_rejected','rider_cnic_verified');
 perform pg_temp.ok(n=2,who||' real repeated transitions enqueue once each');
 end loop;
 select id into uid from fr32_people where label='other';
 select auth_id into aid from fr32_people where label='admin';perform pg_temp.claim('service');
 foreach blocked in array array[true,false,true,false]loop
 op:=gen_random_uuid();
 perform public.admin_set_user_blocked(aid,uid,blocked,op);
 select count(*)into n from public.email_outbox where recipient_user_id=uid and email_type like'account_%';
 perform public.fr28_finish(op,'AUTH_UNCONFIRMED');
 perform pg_temp.ok((select count(*)=n from public.email_outbox where recipient_user_id=uid and email_type like'account_%'),'unconfirmed Auth sync cannot send account action');
 update auth.users set banned_until=case when blocked then clock_timestamp()+interval'1 day'else null end where id=(select auth_id from fr32_people where id=uid);
 perform public.fr28_revoke_sessions(op);perform public.fr28_finish(op);perform public.fr28_finish(op);
 end loop;
 perform pg_temp.ok((select count(*)=4 from public.email_outbox where recipient_user_id=uid and email_type like'account_%'),'repeat block/unblock event identities distinct');
 insert into auth.sessions(id,user_id,created_at,updated_at)select session_id,auth_id,now(),now()from fr32_people where id=uid;
end$$;
-- Isolate these rollback tests from unrelated preserved LOCAL queues.
update public.email_outbox set status='skipped_test'where id not in(select job_id from fr32_fixture);
update public.email_outbox set test_approved=true where id in(select job_id from fr32_fixture);
do $$declare j jsonb;r jsonb;uid bigint;moment timestamptz:='2090-01-01Z';k uuid:=gen_random_uuid();n bigint;begin
 perform pg_temp.claim('service');
 update public.email_outbox set test_approved=false where id=(select job_id from fr32_fixture);
 select *into j from fr32_private.claim(1);
 perform pg_temp.ok(j->>'test_approved'='false','invoice preparation claim independent of email approval');
 r:=public.fr32_begin_email((j->>'id')::uuid,(j->>'lease')::uuid,repeat('a',64));
 perform pg_temp.ok(r->>'code'='TEST_DELIVERY_NOT_APPROVED','unapproved invoice cannot send or consume quota');
 update public.email_outbox set test_approved=true,status='pending'where id=(select job_id from fr32_fixture);
 select *into j from fr32_private.claim(1);
 perform pg_temp.ok(j->>'id'=(select job_id::text from fr32_fixture),'bounded eligible claim');
 perform pg_temp.ok(not exists(select 1 from fr32_private.claim(1)),'active lease cannot be claimed again');
 update public.email_outbox set lease_expires_at=clock_timestamp()-interval'1 second'where id=(j->>'id')::uuid;
 select *into j from fr32_private.claim(1);
 perform pg_temp.ok(j is not null,'pre-send crashed lease recovered');
 update fr32_private.configuration set quota_mode='rolling_26h';
 r:=public.fr32_begin_email((j->>'id')::uuid,(j->>'lease')::uuid,repeat('a',64));
 perform pg_temp.ok(r->>'code'='SEND','shared quota admits ready provider attempt');
 r:=public.fr32_begin_email((j->>'id')::uuid,(j->>'lease')::uuid,repeat('a',64));
 perform pg_temp.ok(r->>'code'='ALREADY_STARTED','same active provider attempt not started twice');
 r:=public.fr32_finish_email((j->>'id')::uuid,(j->>'lease')::uuid,'retry',null,60,'PROVIDER_RATE_LIMIT');
 perform pg_temp.ok((select status='deferred'and next_attempt_at>clock_timestamp()+interval'50 seconds'from public.email_outbox where id=(j->>'id')::uuid),'429 backoff deferred');
 update public.email_outbox set next_attempt_at=clock_timestamp()-interval'1 second'where id=(j->>'id')::uuid;
 select *into j from fr32_private.claim(1);
 perform public.fr32_begin_email((j->>'id')::uuid,(j->>'lease')::uuid,repeat('a',64));
 perform public.fr32_finish_email((j->>'id')::uuid,(j->>'lease')::uuid,'uncertain_retry',null,30,'NETWORK_UNCERTAIN');
 perform pg_temp.ok((select uncertain_since is not null and status='deferred'from public.email_outbox where id=(j->>'id')::uuid),'lost provider response uncertainty persisted');
 update public.email_outbox set next_attempt_at=clock_timestamp()-interval'1 second',uncertain_since=clock_timestamp()-interval'11 minutes'where id=(j->>'id')::uuid;
 perform *from fr32_private.claim(1);
 perform pg_temp.ok((select status='delivery_unknown'from public.email_outbox where id=(j->>'id')::uuid),'uncertain recovery window ends without blind resend');
 perform pg_temp.ok(exists(select 1 from public.orders where id=(select order_id from fr32_fixture)),'later delivery failure preserves committed business state');
 -- Future injected clock excludes prior reservations, with no reset/deletion.
 update fr32_private.configuration set daily_budget=10,otp_reserve=3;
 for n in 1..7 loop r:=fr32_private.reserve_quota('transactional',gen_random_uuid(),moment);perform pg_temp.ok(r->>'code'='RESERVED','transactional capacity '||n);end loop;
 r:=fr32_private.reserve_quota('transactional',k,moment);perform pg_temp.ok(r->>'code'='QUOTA_EXCEEDED','OTP reserve protected');
 for n in 1..3 loop r:=fr32_private.reserve_quota('otp',gen_random_uuid(),moment);end loop;
 perform pg_temp.ok(r->>'code'='RESERVED','OTP can consume remaining reserved capacity');
 r:=fr32_private.reserve_quota('otp',k,moment);perform pg_temp.ok(r->>'code'='QUOTA_EXCEEDED','combined budget bounded');
 r:=fr32_private.reserve_quota('otp',k,moment+interval'26 hours');perform pg_temp.ok(r->>'code'='RESERVED','rolling window expiry reopens capacity');
 r:=fr32_private.reserve_quota('otp',k,moment+interval'26 hours');perform pg_temp.ok(r->>'replayed'='true','same provider attempt not counted twice');
 update fr32_private.configuration set quota_mode='provider_day',provider_timezone='Asia/Karachi';
 r:=fr32_private.reserve_quota('otp',gen_random_uuid(),'2091-01-01 18:59:00Z');
 perform pg_temp.ok((r->>'expires_at')::timestamptz='2091-01-01 19:00:00Z','explicit configured timezone boundary (synthetic, not provider claim)');
 perform pg_temp.ok(position('fr32_private.reserve_quota'in pg_get_functiondef('public.issue_delivery_otp(bigint,uuid,uuid)'::regprocedure))>0,'FR33 shared admission integrated');
 perform pg_temp.ok(position('fr33_tag'in pg_get_functiondef('public.issue_delivery_otp(bigint,uuid,uuid)'::regprocedure))>0,'FR33 HMAC retained');
end$$;
do $$declare j jsonb;r jsonb;uid bigint;job_uuid uuid;begin
 perform pg_temp.claim('service');select customer_id into uid from fr32_fixture;
 job_uuid:=fr32_private.enqueue('order_confirmation',uid,'test','limits','fr32:limit');
 update public.email_outbox set test_approved=true,attempts=5 where email_outbox.id=job_uuid;
 perform *from fr32_private.claim(20);
 perform pg_temp.ok((select status='failed'from public.email_outbox where email_outbox.id=job_uuid),'maximum attempts terminal without send');
 job_uuid:=fr32_private.enqueue('order_confirmation',uid,'test','quota','fr32:quota');
 update public.email_outbox set test_approved=true where email_outbox.id=job_uuid;
 update fr32_private.configuration set quota_mode='rolling_26h',daily_budget=1,otp_reserve=1;
 select *into j from fr32_private.claim(1);
 r:=public.fr32_begin_email((j->>'id')::uuid,(j->>'lease')::uuid,repeat('b',64));
 perform pg_temp.ok(r->>'code'='QUOTA_EXCEEDED','quota exhaustion returned explicitly');
 perform pg_temp.ok((select status='deferred'and attempts=0 from public.email_outbox where email_outbox.id=job_uuid),'quota deferral consumes no provider attempt');
 update fr32_private.configuration set daily_budget=300,otp_reserve=90;
 update public.email_outbox set next_attempt_at=clock_timestamp()-interval'1 second'where email_outbox.id=job_uuid;
 select *into j from fr32_private.claim(1);
 r:=public.fr32_begin_email((j->>'id')::uuid,(j->>'lease')::uuid,repeat('b',64));
 perform pg_temp.ok(r->>'code'='SEND','deferred job resumes when quota available');
 update public.email_outbox set lease_expires_at=clock_timestamp()-interval'1 second'where email_outbox.id=job_uuid;
 perform *from fr32_private.claim(1);
 perform pg_temp.ok((select status='delivery_unknown'from public.email_outbox where email_outbox.id=job_uuid),'crash after send begins quarantined');
end$$;
-- Deliberate mandatory-enqueue failure must abort the surrounding state change.
create function pg_temp.reject_email()returns trigger language plpgsql as $$begin raise exception 'Synthetic enqueue failure';end$$;
create trigger fr32_test_failure before insert on public.email_outbox for each row execute function pg_temp.reject_email();
do $$declare uid bigint;before_status text;begin
 select id into uid from fr32_people where label='vendor';select verification_status into before_status from public.users where id=uid;
 begin update public.users set verification_status='rejected'where id=uid;raise exception 'Unexpected enqueue success';
 exception when raise_exception then perform pg_temp.ok(sqlerrm='Synthetic enqueue failure','mandatory enqueue failure propagated');end;
 perform pg_temp.ok((select verification_status=before_status from public.users where id=uid),'business transaction rolled back on enqueue failure');
end$$;
drop trigger fr32_test_failure on public.email_outbox;
do $$declare r text;begin
 foreach r in array array['anon','authenticated']loop
 perform pg_temp.ok(not has_table_privilege(r,'public.email_outbox','SELECT'),'outbox unreadable '||r);
 perform pg_temp.ok(not has_table_privilege(r,'public.email_outbox','INSERT'),'outbox unforgeable '||r);
 perform pg_temp.ok(not has_function_privilege(r,'public.fr32_claim_email(integer)','EXECUTE'),'worker RPC forbidden '||r);
 end loop;
 perform pg_temp.ok((select not public from storage.buckets where id='invoices'),'invoice bucket private');
end$$;
set local role authenticated;
do $$begin
 perform pg_temp.claim('customer');perform pg_temp.ok((select count(*)=1 from public.invoices where id=(select invoice_id from fr32_fixture)),'owner invoice metadata visible');
 perform pg_temp.claim('other');perform pg_temp.ok(not exists(select 1 from public.invoices),'cross-owner invoice metadata hidden');
 begin perform public.fr32_invoice_authority((select order_id from fr32_fixture));raise exception 'Unexpected cross-owner access';exception when insufficient_privilege then perform pg_temp.ok(true,'cross-owner signing authority denied');end;
end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',name,'result',result))as results from fr32_results;
rollback;
