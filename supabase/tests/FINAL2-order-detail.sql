-- Real secured role RPCs in a rolled-back TEST fixture. The accepted challenge
-- below is synthetic: no email, GPS, cash, photo or physical delivery asserted.
begin;
-- FINAL2_CANDIDATE
create temporary table final2_history_results(label text);
create temporary table final2_history_state(pa bigint,pb bigint,oid bigint,va bigint,vb bigint,assignment bigint,legacy bigint,recorded bigint,bad bigint,cancelled bigint);
insert into final2_history_state default values;
grant all on final2_history_results,final2_history_state to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FINAL2 history original A","price":11.25}',10,0,null);
 if r->>'code'<>'UPDATED'then raise exception 'Owner product A fixture failed';end if;
 update final2_history_state set pa=(r->>'product_id')::bigint;
end$$;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FINAL2 history original B","price":7.25}',10,0,null);
 if r->>'code'<>'UPDATED'then raise exception 'Owner product B fixture failed';end if;
 update final2_history_state set pb=(r->>'product_id')::bigint;
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare s final2_history_state;r jsonb;begin
 select *into s from final2_history_state;
 r:=public.fr10_checkout(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',s.pa,'quantity',2),jsonb_build_object('product_id',s.pb,'quantity',1)),
 '{"address":"FINAL2 synthetic history SQL only","lat":33.68,"lng":73.04,"speed":"standard","destination_confirmed":true,"destination_source":"map_pin"}');
 if r->>'code'<>'PLACED'then raise exception 'Real stock-aware checkout failed: %',r->>'code';end if;
 update final2_history_state set oid=(r->>'order_id')::bigint;
 r:=public.final2_order_detail((r->>'order_id')::bigint);
 if r->>'item_source'<>'CHECKOUT_SNAPSHOT'or jsonb_array_length(r->'items')<>2
  or r#>>'{totals,total_cents}'<>'22975'or r#>>'{totals,subtotal_cents}'<>'2975'or r#>>'{totals,delivery_cents}'<>'20000'
  or r#>>'{totals,state}'<>'CONFIRMED'or r->>'status'<>'pending'or(r->>'history_limited')::boolean then raise exception 'Canonical history snapshot/totals/milestone incorrect';end if;
 if jsonb_array_length(r->'vendor_orders')<>2 or jsonb_array_length(r->'events')<>1
  or exists(select 1 from jsonb_array_elements(r->'vendor_orders')v where jsonb_array_length(v->'events')<>1)then raise exception 'New shared initial history missing';end if;
 if r#>>'{payment,state}'<>'UNPAID'then raise exception 'Unpaid COD falsely settled';end if;
 insert into final2_history_results values('real owned multi-Vendor stock-aware checkout returns immutable fractional items, exact delivery/total cents, initial milestones and unpaid COD context');
 begin perform public.final2_order_detail(0);raise exception 'Invalid order accepted';exception when invalid_parameter_value then null;end;
 begin perform public.final2_order_detail(9223372036854775807);raise exception 'Missing order accepted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('missing and invalid order identities fail without exposing another order');
end$$;
reset role;
update final2_history_state s set va=(select id from public.vendor_orders where order_id=s.oid and vendor_id=__VENDOR_ID__),
 vb=(select v.id from public.vendor_orders v where v.order_id=s.oid and v.vendor_id<>__VENDOR_ID__);
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare s final2_history_state;r jsonb;begin
 select *into s from final2_history_state;
 r:=public.fr17_save_product(gen_random_uuid(),s.pa,'{"name":"FINAL2 changed catalogue name","price":99}',8,0,(select stock_version from public.products where id=s.pa));
 if r->>'code'<>'UPDATED'then raise exception 'Real catalogue edit failed';end if;
 r:=public.fr10_vendor_transition(s.va,'accepted');if r->>'code'<>'ACCEPTED'then raise exception 'Vendor A acceptance failed';end if;
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare s final2_history_state;r jsonb;begin
 select *into s from final2_history_state;r:=public.final2_order_detail(s.oid);
 if r->>'status'<>'pending'or not exists(select 1 from jsonb_array_elements(r->'items')i where(i->>'product_id')::bigint=s.pa
  and i->>'product'='FINAL2 history original A'and i->>'unit_cents'='1125'and i->>'line_cents'='2250')then raise exception 'Partial shared acceptance or original snapshot lost';end if;
 insert into final2_history_results values('one Vendor acceptance leaves required shared parent pending; later catalogue name/price edits cannot rewrite checkout history');
 begin insert into final2_private.vendor_status_events(vendor_order_id,status,source)values(s.va,'delivered','transition');raise exception 'Client history forge accepted';exception when insufficient_privilege then null;end;
 begin perform 1 from final2_private.vendor_status_events;raise exception 'Private ledger direct read accepted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('Customer cannot directly read/write private Vendor event ledger or forge timeline completion');
end$$;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
do $$declare s final2_history_state;r jsonb;begin
 select *into s from final2_history_state;r:=public.fr10_vendor_transition(s.vb,'accepted');if r->>'code'<>'ACCEPTED'then raise exception 'Vendor B acceptance failed';end if;
end$$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare r jsonb;begin r:=public.fr10_vendor_transition((select va from final2_history_state),'preparing');if r->>'code'<>'UPDATED'then raise exception 'Vendor A preparing failed';end if;end$$;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.fr10_vendor_transition((select vb from final2_history_state),'accepted');if r->>'code'<>'ALREADY_ACCEPTED'then raise exception 'Duplicate acceptance changed state';end if;
 r:=public.fr10_vendor_transition((select vb from final2_history_state),'preparing');if r->>'code'<>'UPDATED'then raise exception 'Vendor B preparing failed';end if;
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare s final2_history_state;r jsonb;begin
 select *into s from final2_history_state;r:=public.final2_order_detail(s.oid);
 if r->>'status'<>'preparing'or jsonb_array_length(r->'events')<>3 or exists(select 1 from jsonb_array_elements(r->'vendor_orders')v where jsonb_array_length(v->'events')<>3)then raise exception 'Accepted/preparing milestone or event dedup incorrect';end if;
 insert into final2_history_results values('both real Vendor transition RPCs record pending/accepted/preparing once; duplicate acknowledgement adds no fake milestone');
end$$;
reset role;
do $$declare s final2_history_state;rider bigint:=(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid);aid bigint;begin
 select *into s from final2_history_state;
 update public.orders set rider_id=rider where id=s.oid;
 insert into public.rider_assignments(orderid,riderid,status)values(s.oid,rider,'Accepted')returning id into aid;
 update final2_history_state set assignment=aid;
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
select public.fr21_ready_and_assign(va)from final2_history_state;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
select public.fr21_ready_and_assign(vb)from final2_history_state;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$declare s final2_history_state;r jsonb;begin
 select *into s from final2_history_state;
 r:=public.start_checklisted_delivery(s.assignment);if r->>'code'<>'CHECKLIST_REQUIRED'then raise exception 'Checklist gate lost: %',r->>'code';end if;
 r:=public.submit_pre_delivery_checklist(s.assignment,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
 if r->>'code'<>'COMPLETED'then raise exception 'Synthetic checklist failed: %',r->>'code';end if;
 r:=public.start_checklisted_delivery(s.assignment);if r->>'code'<>'STARTED'then raise exception 'Secured start failed: %',r->>'code';end if;
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.final2_order_detail((select oid from final2_history_state));
 if r->>'status'<>'on_the_way'or jsonb_array_length(r->'events')<>5 then raise exception 'Ready/start milestones missing';end if;
 insert into final2_history_results values('shared pickup reservation does not fabricate departure; checklist gate and actual secured start produce ready/on-the-way milestones');
end$$;
reset role;
-- A controlled accepted challenge tests only the existing trusted verification
-- transaction. This is not a provider/email or physical delivery test.
insert into public.delivery_otps(id,order_id,rider_id,review_admin_id,auth_id,nonce,verifier,state,sent_at,expires_at,lease_until,provider_id)
select gen_random_uuid(),s.oid,(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid),
 (select id from public.users where auth_user_id=(__ADMIN_CLAIMS__::jsonb->>'sub')::uuid),(__RIDER_CLAIMS__::jsonb->>'sub')::uuid,
 'FINAL2-ROLLBACK-ONLY',public.fr33_tag(s.oid,'FINAL2-ROLLBACK-ONLY','123456'),'ACCEPTED',clock_timestamp(),clock_timestamp()+interval '5 minutes',clock_timestamp(),'FINAL2-SYNTHETIC-NO-SEND'
from final2_history_state s;
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.verify_delivery_otp((select oid from final2_history_state),'123456',gen_random_uuid());
 if r->>'code'<>'OK'then raise exception 'Trusted synthetic challenge transaction failed: %',r->>'code';end if;
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.final2_order_detail((select oid from final2_history_state));
 if r->>'status'<>'delivered'or r->>'delivered_at'is null or jsonb_array_length(r->'events')<>6
  or exists(select 1 from jsonb_array_elements(r->'vendor_orders')v where v->>'status'<>'delivered'or jsonb_array_length(v->'events')<>5)
  or r#>>'{payment,state}'<>'UNPAID'then raise exception 'Delivered timeline, shared status or unpaid finance inaccurate';end if;
 insert into final2_history_results values('secured synthetic OTP verification records delivered terminal/portion histories and timestamp without falsely claiming COD collection');
end$$;
reset role;
do $$declare s final2_history_state;customer bigint:=(select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid);
 v bigint;legacy_oid bigint;label text;begin
 select *into s from final2_history_state;
 foreach label in array array['legacy','recorded','bad']loop
  insert into public.orders(user_id,vendor_id,amount,fare,order_status,payment_method,delivery_address)
   values(customer,__VENDOR_ID__,case when label='legacy'then 50 when label='bad'then 8 else 7 end,case when label='legacy'then 0 else 2 end,'pending','COD','FINAL2 synthetic legacy history fixture')returning id into legacy_oid;
  if label<>'legacy'then
   insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(legacy_oid,__VENDOR_ID__,5,'pending')returning id into v;
   insert into public.order_items(vendor_order_id,product_id,quantity,price_at_time)values(v,s.pa,1,5);
  end if;
  if label='legacy'then update final2_history_state set legacy=legacy_oid;
  elsif label='recorded'then update final2_history_state set recorded=legacy_oid;
  else update final2_history_state set bad=legacy_oid;end if;
 end loop;
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare s final2_history_state;r jsonb;begin
 select *into s from final2_history_state;r:=public.final2_order_detail(s.legacy);
 if r->>'item_source'<>'UNAVAILABLE'or jsonb_array_length(r->'items')<>0 or not(r->>'history_limited')::boolean
  or r#>>'{totals,state}'<>'REVIEW_REQUIRED'then raise exception 'Invented legacy item/history completeness';end if;
 insert into final2_history_results values('legacy order lacking item/milestone records explicitly reports unavailable detail; no fabricated backfill');
 r:=public.final2_order_detail(s.recorded);
 if r->>'item_source'<>'RECORDED_ITEMS'or r#>>'{items,0,unit_cents}'<>'500'or r#>>'{totals,total_cents}'<>'700'
  or r#>>'{totals,state}'<>'CONFIRMED'then raise exception 'Legacy recorded item amounts lost';end if;
 insert into final2_history_results values('legacy recorded item price is preserved separately from current catalogue name and price');
 r:=public.final2_order_detail(s.bad);if r#>>'{totals,state}'<>'REVIEW_REQUIRED'then raise exception 'Inconsistent legacy total fabricated';end if;
 insert into final2_history_results values('legacy subtotal/delivery/total mismatch remains review-required instead of inventing financial reconciliation');
end$$;
select set_config('request.jwt.claims',__OTHER_CLAIMS__,true);
do $$begin
 begin perform public.final2_order_detail((select oid from final2_history_state));raise exception 'Other Customer detail accepted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('unrelated real Customer cannot read another complete order or payment context');end$$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$begin begin perform public.final2_order_detail((select oid from final2_history_state));raise exception 'Vendor customer detail accepted';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$begin begin perform public.final2_order_detail((select oid from final2_history_state));raise exception 'Rider customer detail accepted';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claims',__ADMIN_CLAIMS__,true);
do $$begin begin perform public.final2_order_detail((select oid from final2_history_state));raise exception 'Admin Customer endpoint accepted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('Vendor/Rider/Admin cannot impersonate the owning Customer detail endpoint; existing role-specific workflows remain separate');end$$;
reset role;
do $$begin
 begin update final2_private.vendor_status_events set status='cancelled'where vendor_order_id=(select va from final2_history_state);raise exception 'Trusted event overwrite accepted';exception when insufficient_privilege then null;end;
 begin delete from final2_private.vendor_status_events where vendor_order_id=(select va from final2_history_state);raise exception 'Trusted event deletion accepted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('captured Vendor transitions remain append-only even under trusted SQL');
 if exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='final2_private'and tablename='vendor_status_events')then raise exception 'Private detailed timeline published';end if;
 insert into final2_history_results values('private Vendor event ledger remains unpublished; detail changes do not broaden existing Realtime boundaries');
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.fr10_checkout(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',(select pa from final2_history_state),'quantity',1)),
 '{"address":"FINAL2 synthetic cancellation history","lat":33.68,"lng":73.04,"speed":"standard","destination_confirmed":true,"destination_source":"map_pin"}');
 if r->>'code'<>'PLACED'then raise exception 'Cancellation checkout failed';end if;
 update final2_history_state set cancelled=(r->>'order_id')::bigint;
end$$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.fr10_vendor_transition((select id from public.vendor_orders where order_id=(select cancelled from final2_history_state)),'cancelled');
 if r->>'code'<>'ORDER_CANCELLED'then raise exception 'Secured cancellation failed: %',r->>'code';end if;
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.final2_order_detail((select cancelled from final2_history_state));
 if r->>'status'<>'cancelled'or r->>'cancelled_at'is null or r->>'delivered_at'is not null
  or jsonb_array_length(r->'events')<>2 or r#>>'{payment,state}'<>'UNPAID'
  or exists(select 1 from jsonb_array_elements(r->'vendor_orders')v where v->>'status'<>'cancelled'or jsonb_array_length(v->'events')<>2)then
  raise exception 'Cancelled history/finance fabricated';end if;
 insert into final2_history_results values('real Vendor rejection produces exact terminal parent/portion events and preserves unpaid COD rather than inventing a refund');
end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$begin begin perform public.final2_order_detail((select oid from final2_history_state));raise exception 'Blocked Customer accepted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('blocked owning Customer loses full detail access');end$$;
reset role;
set local role anon;
do $$begin begin perform public.final2_order_detail(1);raise exception 'Anonymous detail accepted';exception when insufficient_privilege then null;end;end$$;
reset role;
insert into final2_history_results values('anonymous full detail access denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from final2_history_results;
rollback;
