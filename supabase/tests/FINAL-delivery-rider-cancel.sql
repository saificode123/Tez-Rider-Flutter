-- Reuses secured real checkout/stock/checklist start prefix; all synthetic rollback.
reset role;
create temporary table pay_cancel_request(request_id uuid);
insert into pay_cancel_request values(gen_random_uuid());
grant select on pay_cancel_request to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',__CANCEL_CLAIMS__,true);
do $$declare oid bigint:=(select s.oid from final2_history_state s);req uuid:=(select request_id from pay_cancel_request);r jsonb;begin
 begin perform public.final_delivery_cancel_after_pickup(oid,req,false,'Synthetic cancellation rollback');raise exception 'Unconfirmed cancellation permitted';exception when invalid_parameter_value then null;end;
 r:=public.final_delivery_cancel_after_pickup(oid,req,true,'Synthetic cancellation rollback');
 if r->>'code'<>'CANCELLED'or not(r->>'rider_base_credit_recorded')::boolean or r->>'payment_state'<>'UNPAID'then raise exception 'Confirmed pickup cancellation failed';end if;
 r:=public.final_delivery_cancel_after_pickup(oid,req,true,'Synthetic cancellation rollback');
 if r->>'code'<>'ALREADY_CANCELLED'then raise exception 'Cancellation retry not idempotent';end if;
 begin perform public.final_delivery_cancel_after_pickup(oid,req,true,'Changed cancellation reason');raise exception 'Cancellation request mutation accepted';exception when sqlstate 'PT409'then null;end;
 insert into final2_history_results values('__CANCEL_ROLE_NAME__ explicit confirmation/reason gates whole-order cancellation; exact immutable retry succeeds and changed payload fails');
end$$;
reset role;
do $$declare oid bigint:=(select s.oid from final2_history_state s);e final_delivery_private.rider_earnings;begin
 select *into e from final_delivery_private.rider_earnings where order_id=oid;
 if e.amount<>60 or e.kind<>'CANCEL_AFTER_PICKUP'or e.calculation->>'distance_method'<>'not_applicable'
  or(e.calculation->>'distance_amount')::numeric<>0 then raise exception 'Cancellation base credit incorrect';end if;
 if(select count(*)from public.security_audit_log where target_id=oid and action='rider_cancel_base_recorded')<>1
  or(select count(*)from public.security_audit_log where target_id=oid and action='order_cancelled_after_pickup')<>1 then raise exception 'Cancellation audit duplicated';end if;
 insert into final2_history_results values('__CANCEL_ROLE_NAME__ post-pickup cancellation credits exactly base PKR60 once with separate canonical earning and cancellation audits; no delivery/minimum/distance fee');
 if exists(select 1 from public.vendor_orders where order_id=oid and status<>'cancelled')
  or exists(select 1 from public.rider_assignments where orderid=oid and status in('Pending','Accepted'))then raise exception 'Cross-role cancellation did not propagate';end if;
 if(select coalesce(sum(quantity_delta),0)from public.inventory_movements where order_id=oid and movement_type in('ORDER_DECREMENT','ORDER_RESTORE'))<>0
  or exists(select 1 from public.inventory_movements d where d.order_id=oid and d.movement_type='ORDER_DECREMENT'
   and(select count(*)from public.inventory_movements r where r.order_item_id=d.order_item_id and r.movement_type='ORDER_RESTORE')<>1)then raise exception 'Stock restoration incorrect';end if;
 insert into final2_history_results values('__CANCEL_ROLE_NAME__ cancellation atomically restores each stock decrement once and closes every Vendor portion and Rider assignment');
 if exists(select 1 from public.delivery_latest_locations where order_id=oid)
  or exists(select 1 from fr13_private.sessions where order_id=oid)
  or exists(select 1 from public.delivery_route_cache where order_id=oid)
  or exists(select 1 from public.payments where orderid=oid::text and(paidat is not null or lower(status)not in('pending','unpaid')))then
  raise exception 'Private GPS cleanup or unpaid payment state incorrect';end if;
 insert into final2_history_results values('__CANCEL_ROLE_NAME__ cancelled task retains unpaid COD truth and clears route/location/session data through accepted terminal cleanup');
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$declare h jsonb;e jsonb;begin
 h:=public.final_delivery_rider_earnings(1);e:=h#>'{entries,0}';
 if e->>'kind'<>'post_pickup_cancellation'or e->>'distance_method'<>'not_applicable'
  or jsonb_typeof(e->'distance_km')<>'number'or(e->>'distance_km')::numeric<>0
  or jsonb_typeof(e->'base_amount')<>'number'or(e->>'base_amount')::numeric<>60
  or jsonb_typeof(e->'per_km_rate')<>'number'or(e->>'per_km_rate')::numeric<>0
  or jsonb_typeof(e->'distance_amount')<>'number'or(e->>'distance_amount')::numeric<>0
  or jsonb_typeof(e->'admin_review_required')<>'boolean'or not(h->>'earnings_only')::boolean then
  raise exception 'Flutter cancellation history wire contract invalid';end if;
 insert into final2_history_results values('__CANCEL_ROLE_NAME__ actual Rider cancellation-history RPC uses complete Flutter-compatible numeric base60/distance0/rate0 parts with explicit records-only semantics');
end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results
 from final2_history_results where label like '__CANCEL_ROLE_NAME__%';
rollback;
