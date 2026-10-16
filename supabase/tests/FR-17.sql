-- Real database assertions, synthetic fixtures, full rollback. Concurrency is
-- exercised separately with independent sessions (FR-17-local.py).
begin;
create temp table fr17_results(name text,result text);
create temp table fr17_people(label text,id bigint,auth_id uuid,session_id uuid,email text);
create function pg_temp.ok(v boolean,label text)returns void language plpgsql security definer as $$begin
 if v is distinct from true then raise exception 'FR17 assertion: %',label;end if;
 insert into fr17_results values(label,'PASS');end$$;
do $$declare who text;a uuid;s uuid;uid bigint;mail text;begin
 foreach who in array array['customer','other','vendor','vendor2','rider','admin','blocked']loop
 a:=gen_random_uuid();s:=gen_random_uuid();mail:='fr17-sql-'||a||'@example.test';
 insert into auth.users(id,email,email_confirmed_at,role,aud,raw_user_meta_data)values(a,mail,now(),'authenticated','authenticated','{"fr17_fixture":true}');
 insert into public.users(email,name,role,verification_status,is_blocked)values(mail,'FR17 SQL SYNTHETIC',case when who='other'then'customer'when who in('vendor2','blocked')then'vendor'else who end,'approved',who='blocked')returning id into uid;
 insert into auth.sessions(id,user_id,created_at,updated_at)values(s,a,now(),now());
 insert into fr17_people values(who,uid,a,s,mail);end loop;
end$$;
create function pg_temp.claim(who text)returns void language plpgsql security definer as $$declare p fr17_people;begin
 select * into p from fr17_people where label=who;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p.auth_id,'role','authenticated','session_id',p.session_id,'email',p.email)::text,true);
end$$;
create function pg_temp.product(who text,qty integer,threshold integer default 5)returns bigint language plpgsql security definer as $$declare r jsonb;begin
 perform pg_temp.claim(who);
 r:=public.fr17_save_product(gen_random_uuid(),null,jsonb_build_object('name','FR17 synthetic '||who,'price',80,'is_available',true),qty,threshold,null);
 perform pg_temp.ok(r->>'code'='UPDATED','trusted product creation '||who||' qty'||qty);
 return(r->>'product_id')::bigint;
end$$;
create function pg_temp.buy(pid bigint,qty integer,req uuid default gen_random_uuid())returns jsonb language plpgsql security definer as $$begin
 perform pg_temp.claim('customer');return public.fr10_checkout(req,jsonb_build_array(jsonb_build_object('product_id',pid,'quantity',qty)),
 '{"address":"FR17 synthetic TEST address","lat":33.68,"lng":73.04,"speed":"standard"}');end$$;
create function pg_temp.adjust(pid bigint,qty integer,threshold integer default null)returns jsonb language plpgsql security definer as $$declare version bigint;begin
 perform pg_temp.claim('vendor');select stock_version into version from public.products where id=pid;
 return public.vendor_adjust_stock(pid,qty,'set','FR17 synthetic stock count',gen_random_uuid(),threshold,version);end$$;
create function pg_temp.expire(oid bigint)returns void language plpgsql security definer as $$declare stamp timestamptz;begin
 -- Controlled clock fixture: temporarily unenroll ONLY this synthetic parent;
 -- no guard or RLS is disabled, no real or historical order is modified.
 if not exists(select 1 from public.orders where id=oid and user_id=(select id from fr17_people where label='customer'))then raise exception 'Own synthetic order required';end if;
 select checkout_finalized_at into stamp from public.orders where id=oid;
 update public.orders set checkout_finalized_at=null where id=oid;
 update public.vendor_orders set acceptance_started_at=clock_timestamp()-interval '1 hour',acceptance_deadline_at=clock_timestamp()-interval '1 second'where order_id=oid;
 update public.orders set checkout_finalized_at=stamp,acceptance_deadline_at=clock_timestamp()-interval '1 second'where id=oid;
end$$;
create temp table fr17_ids(label text,id bigint);
grant select on fr17_people,fr17_ids to authenticated;
grant execute on function pg_temp.ok(boolean,text),pg_temp.claim(text)to authenticated,anon;

do $$declare p bigint;q bigint;unknown bigint;r jsonb;again jsonb;req uuid:=gen_random_uuid();oid bigint;oid2 bigint;vid bigint;n bigint;v bigint;before_orders bigint;before_moves bigint;before_stock integer;begin
 insert into public.products(vendor_id,name,price,is_available)values((select id from fr17_people where label='vendor'),'FR17 unknown stock',80,true)returning id into unknown;
 perform pg_temp.ok((select stock_qty=0 and low_stock_threshold=5 and not stock_confirmed and is_available from public.products where id=unknown),'unknown backfill/default preserves flag and needs confirmation');
 begin update public.products set stock_qty=-1 where id=unknown;raise exception 'negative accepted';exception when check_violation then null;end;
 perform pg_temp.ok(true,'negative stock constraint');
 r:=pg_temp.buy(unknown,1);perform pg_temp.ok(r->>'code'='INSUFFICIENT_STOCK','unconfirmed inventory not sold');
 p:=pg_temp.product('vendor',10,5);q:=pg_temp.product('vendor2',4,1);
 insert into fr17_ids values('product',p),('other-product',q),('unknown',unknown);
 r:=pg_temp.buy(p,3,req);oid:=(r->>'order_id')::bigint;
 perform pg_temp.ok(r->>'code'='PLACED'and(select stock_qty=7 from public.products where id=p),'checkout exact decrement');
 perform pg_temp.ok((select count(*)=1 and sum(quantity_delta)=-3 from public.inventory_movements where order_id=oid),'one decrement ledger per item');
 again:=pg_temp.buy(p,3,req);
 perform pg_temp.ok(again->>'code'='ALREADY_PLACED'and again->>'order_id'=r->>'order_id'and(select stock_qty=7 from public.products where id=p),'checkout retry does not decrement twice');
 r:=pg_temp.buy(p,7);oid2:=(r->>'order_id')::bigint;
 perform pg_temp.ok(r->>'code'='PLACED'and(select stock_qty=0 from public.products where id=p),'exact remaining stock succeeds');
 r:=pg_temp.buy(p,1);perform pg_temp.ok(r->>'code'='INSUFFICIENT_STOCK'and(r->'shortages'->0->>'available')::integer=0,'zero stock structured shortage');
 perform pg_temp.ok((select count(*)=1 from public.notifications where stock_product_id=p and message='Low stock alert: FR17 synthetic vendor.'),'one crossing notification');
 perform pg_temp.adjust(p,2);perform pg_temp.buy(p,1);perform pg_temp.ok((select count(*)=1 from public.notifications where stock_product_id=p),'no alert while stock remains low');
 perform pg_temp.adjust(p,8);perform pg_temp.buy(p,3);
 perform pg_temp.ok((select count(*)=2 from public.notifications where stock_product_id=p),'restock above threshold re-arms');
 perform pg_temp.adjust(p,5,9);perform pg_temp.ok((select count(*)=2 from public.notifications where stock_product_id=p),'threshold change emits no alert');
 perform pg_temp.adjust(p,10,5);
 perform pg_temp.claim('customer');select count(*)into before_orders from public.orders;select count(*)into before_moves from public.inventory_movements;
 r:=public.fr10_checkout(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2),jsonb_build_object('product_id',q,'quantity',5)),
 '{"address":"FR17 synthetic","lat":33.68,"lng":73.04,"speed":"standard"}');
 perform pg_temp.ok(r->>'code'='INSUFFICIENT_STOCK'and(r->'shortages'->0->>'requested')::integer=5,'multi-item shortage identifies requested quantity');
 perform pg_temp.ok((select count(*)=before_orders from public.orders)and(select count(*)=before_moves from public.inventory_movements)and(select stock_qty=10 from public.products where id=p),'shortage leaves no partial order/ledger/stock');
 r:=public.fr10_checkout(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1),jsonb_build_object('product_id',p,'quantity',2)),
 '{"address":"FR17 synthetic","lat":33.68,"lng":73.04,"speed":"standard"}');oid:=(r->>'order_id')::bigint;
 perform pg_temp.ok(r->>'code'='PLACED'and(select stock_qty=7 from public.products where id=p)and(select count(*)=1 and sum(quantity_delta)=-3 from public.inventory_movements where order_id=oid),'duplicate product IDs aggregate');
 foreach n in array array[0,-1]loop
 begin perform pg_temp.buy(p,n::integer);raise exception 'invalid quantity accepted';exception when invalid_parameter_value then null;end;
 perform pg_temp.ok(true,'invalid quantity rejected '||n);end loop;
 update public.products set is_available=false where id=p;
 r:=pg_temp.buy(p,1);perform pg_temp.ok(r->>'code'='INSUFFICIENT_STOCK','availability false prevents purchase');
 update public.products set is_available=true where id=p;
 -- Actual vendor rejection restores the whole recorded decrement.
 perform pg_temp.claim('vendor');select id into vid from public.vendor_orders where order_id=oid;
 r:=public.fr10_vendor_transition(vid,'cancelled');
 perform pg_temp.ok(r->>'code'='ORDER_CANCELLED'and(select stock_qty=10 from public.products where id=p),'vendor rejection restores exact stock');
 perform public.fr10_vendor_transition(vid,'cancelled');
 perform pg_temp.ok((select count(*)=1 and sum(quantity_delta)=3 from public.inventory_movements where order_id=oid and movement_type='ORDER_RESTORE'),'repeat cancellation restores once');
 -- Full shared checkout: one accepted vendor plus an expired sibling.
 perform pg_temp.claim('customer');r:=public.fr10_checkout(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2),jsonb_build_object('product_id',q,'quantity',1)),
 '{"address":"FR17 synthetic shared","lat":33.68,"lng":73.04,"speed":"standard"}');oid:=(r->>'order_id')::bigint;
 perform pg_temp.claim('vendor');select id into vid from public.vendor_orders where order_id=oid and vendor_id=(select id from fr17_people where label='vendor');
 perform public.fr10_vendor_transition(vid,'accepted');perform pg_temp.expire(oid);
 update public.orders set payment_method='CARD'where id=oid;
 update public.payments set method='CARD',status='SUCCESS',paidat=clock_timestamp()where orderid=oid::text;
 perform public.cancel_timed_out_orders();
 perform pg_temp.ok((select order_status='cancelled'from public.orders where id=oid)and(select stock_qty=10 from public.products where id=p)and(select stock_qty=4 from public.products where id=q),'FR10 timeout restores entire shared order including accepted sibling');
 perform pg_temp.ok((select count(*)=2 from public.inventory_movements where order_id=oid and movement_type='ORDER_RESTORE'),'one restore per shared item');
 perform pg_temp.ok((select count(*)=1 and min(status)='PENDING'and min(amount)=440 from public.order_refund_actions where order_id=oid),'accepted FR10 full captured refund including delivery preserved');
 perform public.cancel_timed_out_orders();
 perform pg_temp.ok((select count(*)=2 from public.inventory_movements where order_id=oid and movement_type='ORDER_RESTORE')and(select count(*)=1 from public.notifications where timeout_order_id=oid),'repeated worker does not duplicate restoration/notice');
 -- A precommit exception rolls back order, stock, ledger and low-stock notice.
 select stock_qty into before_stock from public.products where id=p;select count(*)into before_orders from public.orders;select count(*)into before_moves from public.inventory_movements;
 begin perform pg_temp.buy(p,6);raise exception 'synthetic payment failure before commit'using errcode='P0002';exception when no_data_found then null;end;
 perform pg_temp.ok((select stock_qty=before_stock from public.products where id=p)and(select count(*)=before_orders from public.orders)and(select count(*)=before_moves from public.inventory_movements),'precommit payment failure rolls back without compensating addition');
 r:=pg_temp.buy(p,2);oid:=(r->>'order_id')::bigint;
 update public.orders set payment_method='CARD'where id=oid;update public.payments set method='CARD',status='FAILED',paidat=null where orderid=oid::text;
 perform public.cancel_timed_out_orders();
 perform pg_temp.ok((select order_status='cancelled'and cancellation_reason='payment_failed'from public.orders where id=oid)and(select stock_qty=10 from public.products where id=p),'durable postcommit failed payment compensation restores');
 perform pg_temp.ok(not exists(select 1 from public.order_refund_actions where order_id=oid),'failed unpaid payment never creates completed or pending monetary refund');
 -- Idempotent manual changes and optimistic absolute count protection.
 perform pg_temp.claim('vendor');select stock_version into v from public.products where id=p;req:=gen_random_uuid();
 r:=public.vendor_adjust_stock(p,12,'set','Synthetic count',req,5,v);again:=public.vendor_adjust_stock(p,12,'set','Synthetic count',req,5,v);
 perform pg_temp.ok(r->>'code'='UPDATED'and again->>'code'='ALREADY_UPDATED'and(select stock_qty=12 from public.products where id=p),'manual adjustment retry records once');
 r:=public.vendor_adjust_stock(p,13,'set','Synthetic count',req,5,v);perform pg_temp.ok(r->>'code'='IDEMPOTENCY_CONFLICT','manual idempotency payload conflict');
 r:=public.vendor_adjust_stock(p,13,'set','Synthetic count',gen_random_uuid(),5,v);perform pg_temp.ok(r->>'code'='STOCK_CHANGED','stale absolute count does not overwrite concurrent inventory');
 r:=public.vendor_adjust_stock(p,1,'delta','Synthetic addition',gen_random_uuid(),null,null);perform pg_temp.ok(r->>'code'='UPDATED'and(select stock_qty=13 from public.products where id=p),'legitimate repeated adjustment allowed');
 begin perform public.vendor_adjust_stock(p,-99,'delta','Synthetic invalid',gen_random_uuid(),null,null);raise exception 'negative adjustment';exception when invalid_parameter_value then null;end;
 perform pg_temp.ok(true,'negative adjustment denied');
 perform pg_temp.claim('vendor2');r:=public.vendor_adjust_stock(p,99,'set','Synthetic intruder',gen_random_uuid(),null,0);perform pg_temp.ok(r->>'code'='FORBIDDEN','wrong vendor denied');
 perform pg_temp.claim('blocked');r:=public.vendor_adjust_stock(p,99,'set','Synthetic blocked',gen_random_uuid(),null,0);perform pg_temp.ok(r->>'code'='FORBIDDEN','blocked vendor denied');
 perform pg_temp.claim('vendor');
 perform pg_temp.ok((select sum(quantity_delta)=(select stock_qty from public.products where id=p)from public.inventory_movements where product_id=p),'ledger reconciles product stock from zero opening');
 perform pg_temp.ok(not exists(select 1 from public.inventory_movements where stock_after<0 or stock_after::bigint<>stock_before::bigint+quantity_delta),'ledger arithmetic valid and nonnegative');
 begin update public.inventory_movements set reason='forged'where product_id=p;raise exception 'ledger mutable';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'ledger append-only');
 begin perform public.vendor_adjust_stock(p,1,null,'Synthetic invalid mode',gen_random_uuid(),null,null);raise exception 'null mode accepted';exception when invalid_parameter_value then null;end;
 perform pg_temp.ok(true,'null adjustment mode rejected');
 -- Compatibility: pre-FR17 noncanonical payloads replay without new decrement
 -- or fictional restoration. This deliberately calls the preserved base only
 -- as database owner to represent an already-existing historical checkout.
 perform pg_temp.claim('customer');req:=gen_random_uuid();select stock_qty into before_stock from public.products where id=p;
 r:=fr17_private.checkout_base(req,jsonb_build_array(jsonb_build_object('product_id',q,'quantity',1),jsonb_build_object('product_id',p,'quantity',1)),
 '{"address":"FR17 legacy synthetic","lat":33.68,"lng":73.04,"speed":"standard"}');oid:=(r->>'order_id')::bigint;
 again:=public.fr10_checkout(req,jsonb_build_array(jsonb_build_object('product_id',q,'quantity',1),jsonb_build_object('product_id',p,'quantity',1)),
 '{"address":"FR17 legacy synthetic","lat":33.68,"lng":73.04,"speed":"standard"}');
 perform pg_temp.ok(again->>'code'='ALREADY_PLACED'and(select stock_qty=before_stock from public.products where id=p),'pre-FR17 checkout original payload replay preserved');
 perform fr10_private.cancel_batch(array[oid],'vendor_rejected');
 perform pg_temp.ok((select stock_qty=before_stock from public.products where id=p)and not exists(select 1 from public.inventory_movements where order_id=oid),'legacy cancellation never invents inventory restoration');
 perform pg_temp.claim('vendor');req:=gen_random_uuid();
 r:=public.fr17_save_product(req,null,'{"name":"FR17 deleted unsold synthetic","price":1}',1,5,null);unknown:=(r->>'product_id')::bigint;
 delete from public.products where id=unknown;
 again:=public.fr17_save_product(req,null,'{"name":"FR17 deleted unsold synthetic","price":1}',1,5,null);
 perform pg_temp.ok(again->>'code'='PRODUCT_REMOVED'and(select count(*)=1 from public.inventory_movements where product_id=unknown),'unsold listing deletion preserves ledger and retry reports removed');
 insert into fr17_ids values('order',oid);
end$$;

set local role authenticated;
do $$declare p bigint:=(select id from fr17_ids where label='product');who text;r jsonb;begin
 foreach who in array array['customer','rider']loop
 perform pg_temp.claim(who);r:=public.vendor_adjust_stock(p,1,'delta','Forged',gen_random_uuid(),null,null);
 perform pg_temp.ok(r->>'code'='FORBIDDEN',who||' adjustment denied');
 begin update public.products set stock_qty=99 where id=p;raise exception 'direct stock update';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,who||' direct stock update denied');end loop;
 perform pg_temp.claim('vendor');
 begin update public.products set low_stock_threshold=99 where id=p;raise exception 'direct threshold update';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'direct threshold update denied');
 begin insert into public.inventory_movements(product_id,quantity_delta)values(p,9);raise exception 'ledger forged';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'direct ledger write denied');
 begin perform fr17_private.lock_inventory(array[(select id from fr17_ids where label='order')]);raise exception 'restoration exposed';exception when insufficient_privilege then null;end;
 perform pg_temp.ok(true,'internal inventory functions inaccessible');
 perform pg_temp.claim('customer');
 perform pg_temp.ok((select stock_qty=13 and stock_confirmed from public.products where id=p),'authorized customer catalog reads current stock');
 perform pg_temp.ok(not exists(select 1 from public.inventory_movements),'customer cannot read vendor ledger');
 perform pg_temp.claim('vendor2');
 perform pg_temp.ok(not exists(select 1 from public.inventory_movements where product_id=p),'other vendor ledger isolated');
end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',name,'result',result))as results from fr17_results;
rollback;
