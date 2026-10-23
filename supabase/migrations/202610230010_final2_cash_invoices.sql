-- Extend accepted FR32 invoice delivery to explicit committed COD cash receipts.
-- Preserve original payments and immutable snapshots; never fabricate legacy items.
begin;
create function final2_private.cash_invoice(p_event bigint)returns void
language plpgsql security definer set search_path='' as $$
declare e public.cod_cash_events;o public.orders;p public.payments;snapshot jsonb;
 invoice public.invoices;invoice_id uuid:=gen_random_uuid();begin
 select *into e from public.cod_cash_events where id=p_event and event_kind='COLLECTED';
 if not found then return;end if;
 select *into o from public.orders where id=e.order_id;
 select *into p from public.payments where id=e.payment_id;
 if o.id is null or p.id is null or p.orderid is distinct from o.id::text or p.customerid is distinct from o.user_id::text
  or lower(btrim(p.method))is distinct from'cod'or lower(btrim(o.payment_method))is distinct from'cod'
  or e.amount is distinct from o.amount or p.amount::numeric is distinct from o.amount then
  raise exception 'Committed COD invoice relationship invalid'using errcode='22023';end if;
 if exists(select 1 from public.invoices where payment_id=p.id)then return;end if;
 snapshot:=fr32_private.snapshot_order(o.id);
 insert into public.invoices(id,payment_id,order_id,owner_id,invoice_number,object_path,status,failure_code)
 values(invoice_id,p.id,o.id,o.user_id,'TR-'||lpad(p.id::text,greatest(12,length(p.id::text)),'0'),
  o.user_id||'/'||o.id||'/'||invoice_id||'.pdf',case when snapshot is null then'failed'else'pending'end,
  case when snapshot is null then'SOURCE_REVIEW_REQUIRED'end)
 on conflict(payment_id)do nothing returning *into invoice;
 if invoice.id is null then return;end if;
 if snapshot is not null then
  insert into fr32_private.invoice_snapshots values(invoice.id,snapshot||jsonb_build_object('invoice_id',invoice.id,
   'invoice_number',invoice.invoice_number,'payment_id',p.id,'payment_reference','COD-CASH-'||e.id,
   'payment_status','CASH_RECORDED','paid_at',e.created_at,'cash_event_id',e.id,'cash_actor_role',e.actor_role));
 end if;
 perform fr32_private.enqueue('paid_invoice',o.user_id,'invoice',invoice.id::text,'invoice:'||p.id,jsonb_build_object('invoice_id',invoice.id));
end$$;
revoke all on function final2_private.cash_invoice(bigint)from public,anon,authenticated,service_role;
create function final2_private.cash_invoice_trigger()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.event_kind='COLLECTED'then perform final2_private.cash_invoice(new.id);end if;
 return new;end$$;
revoke all on function final2_private.cash_invoice_trigger()from public,anon,authenticated,service_role;
create trigger final2_cash_invoice after insert on public.cod_cash_events
 for each row execute function final2_private.cash_invoice_trigger();
-- Compatible catch-up for earlier explicit cash events only. Missing source
-- creates an honest review-required metadata row, never an invented paid PDF.
do $$declare event_id bigint;begin
 for event_id in select e.id from public.cod_cash_events e where e.event_kind='COLLECTED'
  and not exists(select 1 from public.invoices i where i.payment_id=e.payment_id)
 loop perform final2_private.cash_invoice(event_id);end loop;
end$$;
commit;
