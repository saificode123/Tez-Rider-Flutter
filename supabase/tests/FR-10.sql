-- Synthetic fixtures only. Every mutation is rolled back. Real races are in
-- the separate-session integration runner, not claimed by this SQL suite.
begin;
create temp table fr10_results(name text,result text);
create function pg_temp.ok(value boolean,label text)returns void language plpgsql security definer as $$begin
 if value is distinct from true then raise exception 'FR10 assertion failed: %',label;end if;
 insert into fr10_results values(label,'PASS');end$$;
create temp table fr10_people(label text,id bigint,auth_id uuid,session_id uuid,email text);
do $$declare who text;aid uuid;uid bigint;sid uuid;mail text;begin
 foreach who in array array['customer','other','vendor','other-vendor','rider','admin','blocked']loop
  aid:=gen_random_uuid();sid:=gen_random_uuid();mail:='fr10-sql-'||aid||'@example.test';
  insert into auth.users(id,email,email_confirmed_at,role,aud,raw_app_meta_data,raw_user_meta_data)
  values(aid,mail,now(),'authenticated','authenticated','{"provider":"email","providers":["email"]}','{"fr10_fixture":true}');
  insert into public.users(email,name,role,verification_status,is_blocked)
  values(mail,'FR10 SQL SYNTHETIC',case when who='other'then 'customer'when who in('other-vendor','blocked')then 'vendor'else who end,'approved',who='blocked')returning id into uid;
  insert into auth.sessions(id,user_id,created_at,updated_at)values(sid,aid,now(),now());
  insert into fr10_people values(who,uid,aid,sid,mail);
 end loop;
end$$;
create function pg_temp.claim(who text)returns void language plpgsql security definer as $$declare p fr10_people;begin
 select * into p from fr10_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,'email',p.email)::text,true);
end$$;
create function pg_temp.fixture(seconds integer default -1,method text default 'COD',payment_state text default 'pending')returns bigint
language plpgsql security definer as $$declare oid bigint;stamp timestamptz:=clock_timestamp();begin
 insert into public.orders(user_id,amount,fare,order_status,payment_method) values((select id from fr10_people where label='customer'),200,120,'pending',method)returning id into oid;
 insert into public.vendor_orders(order_id,vendor_id,sub_total,status,acceptance_started_at,acceptance_deadline_at)
 values(oid,(select id from fr10_people where label='vendor'),80,'pending',stamp-interval '1 hour',stamp+make_interval(secs=>seconds));
 insert into public.payments(paymentid,orderid,customerid,method,status,amount,paidat)
 values('fr10-synthetic-'||oid,oid::text,(select id::text from fr10_people where label='customer'),method,payment_state,200,case when upper(payment_state)in('SUCCESS','PAID','COMPLETED','SUCCEEDED')then stamp else null end);
 update public.orders set checkout_finalized_at=stamp,acceptance_deadline_at=stamp+make_interval(secs=>seconds)where id=oid;
 return oid;
end$$;
grant execute on function pg_temp.ok(boolean,text),pg_temp.claim(text),pg_temp.fixture(integer,text,text)to authenticated,anon;
grant select on fr10_people to authenticated;
do $$declare a bigint;b bigint;c bigint;res jsonb;vid bigint;d timestamptz;state text;before_count bigint;begin
 a:=pg_temp.fixture();b:=pg_temp.fixture(60);
 res:=public.cancel_timed_out_orders();
 perform pg_temp.ok((select order_status='cancelled'and cancellation_reason='vendor_timeout'and cancelled_at is not null from public.orders where id=a),'expired cancelled with reason/time');
 perform pg_temp.ok((select order_status='pending'from public.orders where id=b),'future deadline untouched');
 perform pg_temp.ok((select count(*)=1 from public.notifications where timeout_order_id=a and message='Order cancelled — vendor unavailable.'),'exact owner notification once');
 perform pg_temp.ok((select count(*)=1 from public.order_timeline_events where order_id=a and status='cancelled'),'timeline once');
 perform pg_temp.ok(not exists(select 1 from public.order_refund_actions where order_id=a),'COD no monetary refund');
 perform public.cancel_timed_out_orders();
 perform pg_temp.ok((select count(*)=1 from public.notifications where timeout_order_id=a),'repeat worker notification deduplicated');
 perform pg_temp.claim('vendor');
 select id into vid from public.vendor_orders where order_id=b;
 res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='ACCEPTED','accept before deadline');
 res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='ALREADY_ACCEPTED','accept replay');
 a:=pg_temp.fixture(0);select id into vid from public.vendor_orders where order_id=a;
 res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='ORDER_EXPIRED','at/past deadline acceptance denied independently of worker');
 perform pg_temp.claim('other-vendor');res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='FORBIDDEN','other vendor denied');
 perform pg_temp.claim('blocked');res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='FORBIDDEN','blocked vendor denied');
 perform pg_temp.claim('customer');res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='FORBIDDEN','customer acceptance denied');
 perform public.cancel_timed_out_orders();perform pg_temp.claim('vendor');res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='ORDER_CANCELLED','cancelled order cannot accept');
 a:=pg_temp.fixture(-1,'CARD','SUCCESS');perform public.cancel_timed_out_orders();
 perform pg_temp.ok((select count(*)=1 and min(amount)=200 and min(status)='PENDING'from public.order_refund_actions where order_id=a),'full captured amount including fare pending');
 perform pg_temp.ok((select status='SUCCESS'and amount=200 from public.payments where orderid=a::text),'captured payment history preserved');
 perform public.cancel_timed_out_orders();perform pg_temp.ok((select count(*)=1 from public.order_refund_actions where order_id=a),'refund idempotent');
 foreach state in array array['AUTHORIZED','pending','UNPAID','FAILED']loop
  a:=pg_temp.fixture(-1,'CARD',state);perform public.cancel_timed_out_orders();
  perform pg_temp.ok(not exists(select 1 from public.order_refund_actions where order_id=a),'uncaptured no refund: '||state);
  perform pg_temp.ok((select status=state from public.payments where orderid=a::text),'uncaptured state preserved: '||state);
 end loop;
 a:=pg_temp.fixture(-1,'CARD','PAID');update public.payments set amount=199 where orderid=a::text;perform public.cancel_timed_out_orders();
 perform pg_temp.ok(not exists(select 1 from public.order_refund_actions where order_id=a)and(select timeout_review_reason='payment_verification_required'from public.orders where id=a),'mismatched captured amount flagged not fabricated');
 -- Mixed shared-order policy explicitly approved by the user.
 a:=pg_temp.fixture();insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(a,(select id from fr10_people where label='other-vendor'),0,'accepted');
 perform public.cancel_timed_out_orders();perform pg_temp.ok(not exists(select 1 from public.vendor_orders where order_id=a and status<>'cancelled'),'accepted sibling cancelled atomically');
 perform pg_temp.ok((select count(*)=1 from public.notifications where timeout_order_id=a),'one shared-order notice');
 foreach state in array array['preparing','ready','on_the_way','delivered']loop
  a:=pg_temp.fixture();insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(a,(select id from fr10_people where label='other-vendor'),0,state);
  perform public.cancel_timed_out_orders();perform pg_temp.ok((select order_status<>'cancelled'and timeout_review_reason='fulfillment_conflict'from public.orders where id=a),'irreversible sibling reviewed: '||state);
 end loop;
 foreach state in array array['accepted','on_the_way','delivered','cancelled']loop
  a:=pg_temp.fixture(60);update public.orders set checkout_finalized_at=null where id=a;
  update public.vendor_orders set status=state where order_id=a;
  update public.orders set checkout_finalized_at=clock_timestamp(),order_status=state,acceptance_deadline_at=null where id=a;
  perform public.cancel_timed_out_orders();perform pg_temp.ok((select order_status=state from public.orders where id=a),'nonwaiting state preserved: '||state);
 end loop;
 a:=pg_temp.fixture();update public.orders set checkout_finalized_at=null where id=a;
 update public.orders set rider_id=(select id from fr10_people where label='rider')where id=a;
 update public.orders set checkout_finalized_at=clock_timestamp()where id=a;
 perform public.cancel_timed_out_orders();perform pg_temp.ok((select order_status='pending'and timeout_review_reason='fulfillment_conflict'and rider_id is not null from public.orders where id=a),'assigned order flagged without forced cancellation');
 a:=pg_temp.fixture(60);update public.vendor_orders set vendor_id=(select id from fr10_people where label='blocked')where order_id=a;
 select id into vid from public.vendor_orders where order_id=a;perform pg_temp.claim('blocked');
 res:=public.fr10_vendor_transition(vid,'accepted');perform pg_temp.ok(res->>'code'='FORBIDDEN','blocked owning vendor denied');
 -- Deadline snapshots remain stable after configuration changes.
 a:=pg_temp.fixture(60);select acceptance_deadline_at into d from public.vendor_orders where order_id=a;
 update fr10_private.configuration set vendor_acceptance_timeout_seconds=240;
 perform pg_temp.ok((select acceptance_deadline_at=d from public.vendor_orders where order_id=a),'existing deadline unaffected by configuration');
 begin update fr10_private.configuration set vendor_acceptance_timeout_seconds=0;raise exception 'missing bound';exception when check_violation then null;end;
 perform pg_temp.ok(true,'configuration bounds');
 begin update public.vendor_orders set acceptance_deadline_at=clock_timestamp()+interval '1 hour'where order_id=a;raise exception 'mutable deadline';exception when sqlstate 'PT409'then null;end;
 perform pg_temp.ok(true,'deadline immutable');
 -- Deliberately fail a transactional side effect; cancellation must roll back.
 a:=pg_temp.fixture(-1,'CARD','SUCCESS');
 execute 'create function pg_temp.fr10_fail()returns trigger language plpgsql as $f$begin raise exception ''FR10 injected failure'' using errcode=''P9999'';end$f$';
 execute 'create trigger fr10_injected_failure before insert on public.notifications for each row execute function pg_temp.fr10_fail()';
 begin perform public.cancel_timed_out_orders();raise exception 'injected trigger missing';exception when sqlstate 'P9999'then null;end;
 execute 'drop trigger fr10_injected_failure on public.notifications';
 perform pg_temp.ok((select order_status='pending'from public.orders where id=a)and not exists(select 1 from public.order_refund_actions where order_id=a)and not exists(select 1 from public.order_timeline_events where order_id=a and status='cancelled'),'transaction rollback covers order refund timeline');
end$$;
-- Checkout snapshots and strict mathematical boundary share production helpers.
do $$declare pid bigint;oid bigint;res jsonb;request uuid:=gen_random_uuid();delivery jsonb;items jsonb;vid bigint;deadline timestamptz;begin
 perform pg_temp.ok(not fr10_private.before_deadline(now(),now()),'exact deadline boundary is expired');
 perform pg_temp.ok(fr10_private.before_deadline(now(),now()-interval '1 microsecond'),'strictly before boundary allowed');
 insert into public.products(vendor_id,name,price,is_available)values((select id from fr10_people where label='vendor'),'FR10 synthetic checkout',80,true)returning id into pid;
 items:=jsonb_build_array(jsonb_build_object('product_id',pid,'quantity',2));delivery:='{"address":"FR10 synthetic address","lat":33.68,"lng":73.04,"speed":"standard"}';
 perform pg_temp.claim('customer');
 res:=public.fr10_checkout(request,items,delivery);oid:=(res->>'order_id')::bigint;
 perform pg_temp.ok(res->>'code'='PLACED'and(res->>'amount')::numeric=280,'atomic checkout trusted price and existing fare formula');
 perform pg_temp.ok((select count(*)=1 from public.payments where orderid=oid::text and method='COD'and status='pending'),'checkout creates unpaid payment record');
 perform pg_temp.ok((select count(*)=1 from public.order_items i join public.vendor_orders v on v.id=i.vendor_order_id where v.order_id=oid and i.quantity=2),'checkout creates actual items');
 perform pg_temp.ok((select extract(epoch from(acceptance_deadline_at-acceptance_started_at))=240 from public.vendor_orders where order_id=oid),'new checkout uses configured timeout');
 res:=public.fr10_checkout(request,items,delivery);perform pg_temp.ok(res->>'code'='ALREADY_PLACED'and(res->>'order_id')::bigint=oid,'checkout retry creates no duplicates');
 res:=public.fr10_checkout(request,items,delivery||'{"speed":"express"}');perform pg_temp.ok(res->>'code'='IDEMPOTENCY_CONFLICT','changed checkout retry rejected');
 perform pg_temp.claim('other');res:=public.fr10_checkout(request,items,delivery);perform pg_temp.ok(res->>'code'='IDEMPOTENCY_CONFLICT','checkout request cannot cross owners');
 perform pg_temp.claim('customer');
 begin perform public.fr10_checkout(gen_random_uuid(),'[{"product_id":-1,"quantity":1}]',delivery);raise exception 'invalid cart accepted';exception when invalid_parameter_value then null;end;
 perform pg_temp.ok(true,'invalid checkout rolls back');
 -- A preparing portion cannot be moved into assignment while a required vendor waits.
 insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,(select id from fr10_people where label='other-vendor'),0,'pending');
 begin update public.orders set rider_id=(select id from fr10_people where label='rider')where id=oid;raise exception 'assignment bypassed pending';exception when sqlstate 'PT409'then null;end;
 perform pg_temp.ok(true,'pending required vendor blocks assignment');
end$$;
-- The accepted native pipeline also queues/resolves the timeout UUID.
do $$declare oid bigint;device uuid:=gen_random_uuid();event uuid;result jsonb;begin
 update fr30_private.limits set android_push_enabled=true;
 insert into fr30_private.push_devices(id,user_id,session_id,token,token_hash,secret_hash)
 select device,id,session_id,'fr10_synthetic_fid_1234567890',encode(extensions.digest('fr10_synthetic_fid_1234567890','sha256'),'hex'),encode(extensions.digest(repeat('a',64),'sha256'),'hex')from fr10_people where label='customer';
 oid:=pg_temp.fixture();perform public.cancel_timed_out_orders();
 select order_push_event_id into event from public.notifications where timeout_order_id=oid;
 perform pg_temp.ok((select count(*)=1 from fr30_private.push_deliveries j join public.notifications n on n.id=j.notification_id where n.timeout_order_id=oid),'timeout uses existing durable push queue');
 perform pg_temp.claim('customer');result:=public.fr30_resolve_push(device,repeat('a',64),event);
 perform pg_temp.ok(result->>'code'='OK'and result->>'message'='Order cancelled — vendor unavailable.'and(result->>'broadcast_id')::uuid=event,'timeout UUID resolves through existing session-bound native contract');
 result:=public.fr30_resolve_push(device,repeat('b',64),event);perform pg_temp.ok(result->>'code'='FORBIDDEN','timeout push capability cannot be forged');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 perform pg_temp.ok(exists(select 1 from public.fr30_claim_push(50)j where(j->>'broadcast_id')::uuid=event),'worker claims timeout transport UUID');
end$$;
-- Check actual roles, not only auth claims on a postgres connection.
set local role authenticated;
do $$declare who text;begin
 foreach who in array array['customer','vendor','rider','admin']loop
  perform pg_temp.claim(who);
  begin perform public.cancel_timed_out_orders();raise exception 'worker privilege leaked';exception when insufficient_privilege then null;end;
  perform pg_temp.ok(true,who||' worker execute denied');
 end loop;
 perform pg_temp.claim('other');
 perform pg_temp.ok(not exists(select 1 from public.order_refund_actions),'other customer cannot read refunds');
 perform pg_temp.ok(not exists(select 1 from public.order_timeline_events),'other customer cannot read timeline');
 begin insert into public.notifications(user_id,title,message)values((select id from fr10_people where label='customer'),'forged','forged');raise exception 'notification forged';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'notification writes denied');
 perform pg_temp.claim('vendor');
 declare oid bigint;vid bigint;begin
  oid:=pg_temp.fixture(60);select id into vid from public.vendor_orders where order_id=oid;
  begin update public.vendor_orders set status='accepted'where id=vid;raise exception 'direct status bypass';exception when insufficient_privilege then null;end;
  perform pg_temp.ok(true,'managed direct acceptance requires trusted RPC');
 end;
 begin insert into public.order_timeline_events(order_id,status)values(1,'cancelled');raise exception 'timeline forged';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'timeline writes denied');
 begin insert into public.order_refund_actions(order_id,payment_id,customer_id,amount,reason)values(1,1,1,1,'vendor_timeout');raise exception 'refund forged';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'refund writes denied');
end$$;
reset role;
set local role anon;
do $$begin
 begin perform public.cancel_timed_out_orders();raise exception 'anonymous worker';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'anonymous worker denied');
end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',name,'result',result))as results from fr10_results;
rollback;
