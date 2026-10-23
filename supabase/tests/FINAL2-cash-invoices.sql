begin;
-- FINAL2_CANDIDATE
create temporary table final2_invoice_state(label text,order_id bigint,payment_id bigint);
create temporary table final2_invoice_results(label text);
grant all on final2_invoice_state,final2_invoice_results to authenticated;
create function pg_temp.invoice_fault()returns trigger language plpgsql as $$begin
 if current_setting('final2.invoice_fault',true)='on'and new.email_type='paid_invoice'then raise exception 'Synthetic receipt outbox fault';end if;
 return new;end$$;
create trigger final2_invoice_test_fault before insert on public.email_outbox for each row execute function pg_temp.invoice_fault();
do $$declare customer bigint:=(select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid);
 rider bigint:=(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid);
 label text;oid bigint;vid bigint;pid bigint;aid bigint;product bigint;r jsonb;begin
 perform set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
 r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FINAL2 invoice SQL","price":5}',10,0,null);
 product:=(r->>'product_id')::bigint;
 foreach label in array array['valid','outbox-failure','legacy-missing-source']loop
  insert into public.orders(user_id,vendor_id,rider_id,amount,fare,order_status,payment_method,delivery_address)
   values(customer,__VENDOR_ID__,rider,12,2,'ready','COD','FINAL2 synthetic invoice fixture')returning id into oid;
  insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,__VENDOR_ID__,10,'ready')returning id into vid;
  insert into public.order_items(vendor_order_id,product_id,quantity,price_at_time)values(vid,product,2,5);
  if label<>'legacy-missing-source'then update public.orders set checkout_finalized_at=clock_timestamp()where id=oid;end if;
  insert into public.rider_assignments(orderid,riderid,status)values(oid,rider,'Accepted')returning id into aid;
  perform set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
  r:=public.submit_pre_delivery_checklist(aid,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
  if r->>'code'<>'COMPLETED'then raise exception 'Invoice fixture checklist failed';end if;
  update public.orders set order_status='delivered',delivered_at=clock_timestamp()where id=oid;
  update public.rider_assignments set status='Completed'where id=aid;
  update public.vendor_orders set status='delivered'where id=vid;
  insert into public.payments(paymentid,orderid,customerid,method,status,amount)
   values('FINAL2-INVOICE-'||oid,oid::text,customer::text,'COD','pending',12)returning id into pid;
  insert into final2_invoice_state values(label,oid,pid);
 end loop;
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$declare oid bigint:=(select order_id from final2_invoice_state where label='valid');
 req uuid:=gen_random_uuid();r jsonb;begin
 if exists(select 1 from public.invoices where order_id=oid)then raise exception 'Unpaid invoice fabricated';end if;
 r:=public.final2_record_cash(oid,'COLLECTED',12,req,true,'FINAL2-SYNTHETIC-INVOICE');
 if r->>'code'<>'RECORDED'then raise exception 'Receipt not committed';end if;
 r:=public.final2_record_cash(oid,'COLLECTED',12,req,true,'FINAL2-SYNTHETIC-INVOICE');
 if r->>'code'<>'ALREADY_APPLIED'then raise exception 'Receipt replay failed';end if;
 insert into final2_invoice_results values('unpaid delivery has no paid invoice; committed receipt is idempotent');
 perform set_config('final2.invoice_fault','on',true);
 begin
  perform public.final2_record_cash((select order_id from final2_invoice_state where label='outbox-failure'),'COLLECTED',12,gen_random_uuid(),true,'FINAL2-SYNTHETIC-OUTBOX-FAULT');
  raise exception 'Injected mandatory receipt outbox fault ignored';
 exception when raise_exception then if sqlerrm<>'Synthetic receipt outbox fault'then raise;end if;end;
 perform set_config('final2.invoice_fault','off',true);
 perform public.final2_record_cash((select order_id from final2_invoice_state where label='legacy-missing-source'),'COLLECTED',12,gen_random_uuid(),true,'FINAL2-SYNTHETIC-LEGACY');
 begin perform final2_private.cash_invoice(1);raise exception 'Private helper reachable';exception when insufficient_privilege then null;end;
 insert into final2_invoice_results values('private invoice helper cannot be invoked by an authenticated caller');
end$$;
reset role;
do $$declare oid bigint:=(select order_id from final2_invoice_state where label='valid');
 invoice public.invoices;snapshot jsonb;begin
 select *into invoice from public.invoices where order_id=oid;
 select s.snapshot into snapshot from fr32_private.invoice_snapshots s where s.invoice_id=invoice.id;
 if invoice.status is distinct from'pending'or snapshot->>'payment_status'<>'CASH_RECORDED'
  or snapshot->>'cash_actor_role'<>'rider'or snapshot->>'total_cents'<>'1200'
  or snapshot->>'payment_reference'<>'COD-CASH-'||(select id from public.cod_cash_events where order_id=oid and event_kind='COLLECTED')then
  raise exception 'Cash receipt source not canonical';end if;
 if(snapshot#>>'{items,0,quantity}')::int<>2 or snapshot#>>'{items,0,unit_cents}'<>'500'then raise exception 'Itemized receipt differs from immutable checkout';end if;
 insert into final2_invoice_results values('receipt snapshot binds canonical cash event/actor/time and exact immutable itemized cents');
 if(select count(*)from public.email_outbox where entity_type='invoice'and entity_id=invoice.id::text)<>1
  or exists(select 1 from public.email_outbox where entity_id=invoice.id::text and test_approved)then raise exception 'Outbox duplication or unapproved send';end if;
 if(select status from public.payments where id=invoice.payment_id)<>'pending'then raise exception 'Original payment overwritten';end if;
 insert into final2_invoice_results values('one private invoice and one unapproved TEST outbox intent; original payment status preserved');
 if exists(select 1 from public.cod_cash_events where order_id=(select order_id from final2_invoice_state where label='outbox-failure'))
  or exists(select 1 from public.invoices where order_id=(select order_id from final2_invoice_state where label='outbox-failure'))then raise exception 'Outbox fault left partial cash evidence';end if;
 insert into final2_invoice_results values('mandatory invoice outbox failure rolls back both cash event and invoice metadata');
 if not exists(select 1 from public.invoices where order_id=(select order_id from final2_invoice_state where label='legacy-missing-source')
  and status='failed'and failure_code='SOURCE_REVIEW_REQUIRED')then raise exception 'Incomplete legacy source fabricated PDF readiness';end if;
 insert into final2_invoice_results values('incomplete legacy source is review-required; no fabricated itemized invoice');
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$begin
 if(select count(*)from public.invoices where order_id=any(array(select order_id from final2_invoice_state)))<>2 then raise exception 'Owner receipt metadata missing';end if;
 insert into final2_invoice_results values('owned Customer can read actual receipt metadata through existing RLS');end$$;
select set_config('request.jwt.claims',__OTHER_CLAIMS__,true);
do $$begin
 if exists(select 1 from public.invoices where order_id=any(array(select order_id from final2_invoice_state)))then raise exception 'Unrelated Customer read private receipt';end if;
 insert into final2_invoice_results values('unrelated authenticated Customer cannot read receipt metadata');end$$;
reset role;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from final2_invoice_results;
rollback;
