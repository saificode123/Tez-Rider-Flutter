-- Synthetic reporting states only; everything rolls back. No physical delivery claim.
begin;
-- FINAL2_CANDIDATE
create temporary table final2_report_results(label text);
create temporary table final2_report_state(base jsonb,product_id bigint,orders bigint[]);
grant all on final2_report_results,final2_report_state to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare p jsonb;begin
 p:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FINAL2 report SQL","price":5}',20,0,null);
 insert into final2_report_state values(public.final2_vendor_report(),(p->>'product_id')::bigint,'{}');
end$$;
reset role;
do $$declare customer bigint:=(select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid);
 rider bigint:=(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid);
 oid bigint;vid bigint;aid bigint;r jsonb;label text;ids bigint[]:='{}';begin
 foreach label in array array['delivered','pending-parent','cancelled-parent','legacy']loop
  insert into public.orders(user_id,vendor_id,rider_id,amount,fare,order_status,payment_method,delivery_address)
   values(customer,__VENDOR_ID__,rider,case when label='legacy'then 10 else 12 end,2,
    case when label in('delivered','legacy')then'ready'when label='cancelled-parent'then'cancelled'else'pending'end,
    'COD','FINAL2 synthetic reporting fixture')returning id into oid;
  ids:=array_append(ids,oid);
  if label<>'legacy'then
   insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,__VENDOR_ID__,
    case when label='delivered'then 10 when label='pending-parent'then 30 else 40 end,case when label='delivered'then'ready'else'delivered'end)returning id into vid;
   insert into public.order_items(vendor_order_id,product_id,quantity,price_at_time)
    values(vid,(select product_id from final2_report_state),case when label='delivered'then 2 when label='pending-parent'then 6 else 8 end,5);
  end if;
  if label in('delivered','legacy')then
   insert into public.rider_assignments(orderid,riderid,status)values(oid,rider,'Accepted')returning id into aid;
   perform set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
   r:=public.submit_pre_delivery_checklist(aid,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
   if r->>'code'<>'COMPLETED'then raise exception 'Reporting fixture checklist failed';end if;
   update public.orders set order_status='delivered',delivered_at=clock_timestamp()where id=oid;
   update public.rider_assignments set status='Completed'where id=aid;
   update public.vendor_orders set status='delivered'where order_id=oid;
  end if;
 end loop;
 update final2_report_state set orders=ids;
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare r jsonb;b jsonb:=(select base from final2_report_state);cursor jsonb;p jsonb;
 ids bigint[]:='{}';bad jsonb;begin
 r:=public.final2_vendor_report(null,2);
 if (r#>>'{summary,total_orders}')::bigint<>(b#>>'{summary,total_orders}')::bigint+4
  or(r#>>'{summary,delivered_orders}')::bigint<>(b#>>'{summary,delivered_orders}')::bigint+2
  or(r#>>'{summary,delivered_sales}')::numeric<>(b#>>'{summary,delivered_sales}')::numeric+18 then raise exception 'Delivered-only aggregate incorrect';end if;
 insert into final2_report_results values('delivered gross sales require parent and portion delivery; cancelled and pending excluded; legacy fee excluded');
 if not exists(select 1 from jsonb_array_elements(r->'top_products')top_row where(top_row->>'product_id')::bigint=(select product_id from final2_report_state)and(top_row->>'quantity')::int=2)then raise exception 'Undelivered items counted as sales';end if;
 insert into final2_report_results values('top products count delivered quantities only; no invented fallback quantities');
 if jsonb_array_length(r->'items')<>2 or not(r->>'has_more')::boolean then raise exception 'Page not bounded';end if;
 for p in select *from jsonb_array_elements(r->'items')loop ids:=array_append(ids,(p->>'order_id')::bigint);end loop;
 cursor:=r->'next_cursor';r:=public.final2_vendor_report(cursor,2);
 for p in select *from jsonb_array_elements(r->'items')loop ids:=array_append(ids,(p->>'order_id')::bigint);end loop;
 if cardinality(ids)<>4 or(select count(distinct v)from unnest(ids)v)<>4
  or not ids @>(select orders from final2_report_state)then raise exception 'Keyset rows missing or repeated';end if;
 insert into final2_report_results values('bounded composite keyset pages return all four actual portions exactly once');
 r:=public.final2_vendor_report(null,50);
 if exists(select 1 from jsonb_array_elements(r->'items')x where x->'payment'->'amount'<>'null'::jsonb
  or exists(select 1 from jsonb_array_elements(x->'payment'->'events')e where e->'reference'<>'null'::jsonb))then raise exception 'Private parent finance leaked';end if;
 if not exists(select 1 from jsonb_array_elements(r->'items')x where(x->>'order_id')::bigint=(select orders[1]from final2_report_state)
  and x->'items'->0->>'quantity'='2'and x->'items'->0->>'unit_price'='5')then raise exception 'Item breakdown missing';end if;
 insert into final2_report_results values('own itemized prices retained; whole-parent amounts/private references masked');
 foreach bad in array array['{}'::jsonb,'{"order_id":1,"vendor_order_id":0,"extra":true}',
  '{"order_id":9223372036854775808,"vendor_order_id":0}','{"order_id":1,"vendor_order_id":-1}','[]']loop
  begin perform public.final2_vendor_report(bad,20);raise exception 'Bad cursor accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.final2_vendor_report(null,51);raise exception 'Large page accepted';exception when invalid_parameter_value then null;end;
 insert into final2_report_results values('unknown cursor fields, overflow, wrong shape, negative IDs and oversized pages rejected');
 begin perform *from final2_private.vendor_report_rows(__VENDOR_ID__);raise exception 'Private helper bypass accepted';exception when insufficient_privilege then null;end;
 insert into final2_report_results values('private reporting helper cannot bypass canonical Vendor authorization');
end$$;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.final2_vendor_report(null,50);
 if exists(select 1 from jsonb_array_elements(r->'items')x where(x->>'order_id')::bigint=any((select orders from final2_report_state)::bigint[]))then raise exception 'Cross Vendor rows leaked';end if;
 insert into final2_report_results values('distinct approved Vendor cannot observe another Vendor portions');
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$begin
 begin perform public.final2_vendor_report();raise exception 'Customer report accepted';exception when insufficient_privilege then null;end;
 insert into final2_report_results values('Customer cannot invoke Vendor financial report');end$$;
select set_config('request.jwt.claims',__ADMIN_CLAIMS__,true);
do $$begin
 begin perform public.final2_vendor_report();raise exception 'Admin impersonated Vendor';exception when insufficient_privilege then null;end;
 insert into final2_report_results values('Admin cannot implicitly impersonate a Vendor report');end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=__VENDOR_ID__;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$begin
 begin perform public.final2_vendor_report();raise exception 'Blocked report accepted';exception when insufficient_privilege then null;end;
 insert into final2_report_results values('blocked Vendor loses reporting access under existing live session');end$$;
reset role;
set local role anon;
do $$begin begin perform public.final2_vendor_report();raise exception 'Anonymous report accepted';exception when insufficient_privilege then null;end;end$$;
reset role;
insert into final2_report_results values('anonymous report denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from final2_report_results;
rollback;
