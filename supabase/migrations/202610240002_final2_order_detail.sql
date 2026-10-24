-- FR11/12: owned itemized history and append-only Vendor portion transitions.
-- Existing milestone/snapshot/payment history is preserved. Missing historical
-- transitions are explicitly labelled; migration time is never a delivery time.
begin;
set local lock_timeout='5s';
create table final2_private.vendor_status_events(
 id bigint generated always as identity primary key,
 vendor_order_id bigint not null references public.vendor_orders(id),
 status text not null,source text not null check(source in('created','transition')),
 created_at timestamptz not null default clock_timestamp()
);
create index final2_vendor_status_order_idx on final2_private.vendor_status_events(vendor_order_id,id);
alter table final2_private.vendor_status_events enable row level security;
revoke all on final2_private.vendor_status_events from public,anon,authenticated,service_role;
create trigger final2_vendor_status_immutable before update or delete on final2_private.vendor_status_events
 for each row execute function public.fr26_append_only();
create function final2_private.vendor_status_event()returns trigger language plpgsql security definer set search_path=''as $$begin
 if tg_op='INSERT'or new.status is distinct from old.status then
  insert into final2_private.vendor_status_events(vendor_order_id,status,source)
   values(new.id,coalesce(new.status,'unknown'),case when tg_op='INSERT'then'created'else'transition'end);
 end if;return new;
end$$;
revoke all on function final2_private.vendor_status_event()from public,anon,authenticated,service_role;
create trigger final2_vendor_status_event after insert or update of status on public.vendor_orders
 for each row execute function final2_private.vendor_status_event();
create function final2_private.history_cents(p_value numeric)returns text language sql immutable set search_path=''as $$
 select case when p_value is null or p_value::text in('NaN','Infinity','-Infinity')or p_value<0
  or p_value>1000000000000 or p_value<>round(p_value,2)then null else(p_value*100)::bigint::text end
$$;
revoke all on function final2_private.history_cents(numeric)from public,anon,authenticated,service_role;
create function public.final2_order_detail(p_order_id bigint)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;snapshot jsonb;items jsonb;portions jsonb;events jsonb;
 item_source text:='UNAVAILABLE';subtotal numeric;subtotal_cents text;delivery_cents text;total_cents text;consistent boolean:=false;begin
 if actor is null or public.fr21_role()is distinct from'customer'or not exists(
  select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then
  raise exception 'Approved owning Customer required'using errcode='42501';end if;
 if p_order_id is null or p_order_id<=0 then raise exception 'Valid order required'using errcode='22023';end if;
 select *into o from public.orders where id=p_order_id and user_id=actor;
 if o.id is null then raise exception 'Owned order required'using errcode='42501';end if;
 select s.snapshot into snapshot from fr32_private.order_snapshots s where s.order_id=o.id and s.owner_id=actor;
 if snapshot is not null and jsonb_typeof(snapshot->'items')='array'then
  items:=snapshot->'items';item_source:='CHECKOUT_SNAPSHOT';
  subtotal_cents:=snapshot->>'subtotal_cents';delivery_cents:=snapshot->>'delivery_cents';total_cents:=snapshot->>'total_cents';
  consistent:=subtotal_cents~'^[0-9]{1,15}$'and delivery_cents~'^[0-9]{1,15}$'and total_cents~'^[0-9]{1,15}$'
   and subtotal_cents::numeric+delivery_cents::numeric=total_cents::numeric
   and total_cents=final2_private.history_cents(o.amount::numeric);
 else
  if not exists(select 1 from public.order_items i join public.vendor_orders v on v.id=i.vendor_order_id where v.order_id=o.id
   and(i.quantity is null or i.quantity<=0 or final2_private.history_cents(i.price_at_time::numeric)is null))then
   select sum(i.quantity*i.price_at_time::numeric),jsonb_agg(jsonb_build_object(
    'item_id',i.id,'product_id',i.product_id,'product',coalesce(p.name,'Product #'||i.product_id),
    'vendor_id',v.vendor_id,'vendor',coalesce(u.name,'Vendor #'||v.vendor_id),'quantity',i.quantity,
    'unit_cents',final2_private.history_cents(i.price_at_time::numeric),
    'line_cents',final2_private.history_cents(i.quantity*i.price_at_time::numeric))order by v.vendor_id,i.id)
   into subtotal,items from public.order_items i join public.vendor_orders v on v.id=i.vendor_order_id
    left join public.products p on p.id=i.product_id left join public.users u on u.id=v.vendor_id where v.order_id=o.id;
   if items is not null and jsonb_array_length(items)<=100 and final2_private.history_cents(subtotal)is not null
    and not exists(select 1 from jsonb_array_elements(items)x where x->>'line_cents'is null)then
    item_source:='RECORDED_ITEMS';subtotal_cents:=final2_private.history_cents(subtotal);
   else items:=null;end if;
  end if;
  delivery_cents:=final2_private.history_cents(o.fare::numeric);total_cents:=final2_private.history_cents(o.amount::numeric);
  consistent:=items is not null and subtotal_cents is not null and delivery_cents is not null and total_cents is not null
   and subtotal_cents::numeric+delivery_cents::numeric=total_cents::numeric;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'vendor_id',v.vendor_id,
  'vendor',coalesce(u.name,'Vendor #'||v.vendor_id),'status',coalesce(v.status,'unknown'),
  'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'status',e.status,'source',e.source,'created_at',e.created_at)order by e.id)
   from final2_private.vendor_status_events e where e.vendor_order_id=v.id),'[]'::jsonb))order by v.id),'[]'::jsonb)
 into portions from public.vendor_orders v left join public.users u on u.id=v.vendor_id where v.order_id=o.id;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'status',e.status,'reason',e.reason,'created_at',e.created_at)order by e.created_at,e.id),'[]'::jsonb)
 into events from public.order_timeline_events e where e.order_id=o.id;
 return jsonb_build_object('code','OK','order_id',o.id,'status',coalesce(o.order_status,'unknown'),
  'created_at',o.created_at,'delivered_at',o.delivered_at,'cancelled_at',o.cancelled_at,
  'history_limited',o.checkout_finalized_at is null or jsonb_array_length(events)=0,
  'item_source',item_source,'items',coalesce(items,'[]'::jsonb),'vendor_orders',portions,'events',events,
  'totals',jsonb_build_object('subtotal_cents',subtotal_cents,'delivery_cents',delivery_cents,'total_cents',total_cents,
   'state',case when consistent then'CONFIRMED'else'REVIEW_REQUIRED'end,'currency','PKR'),
  'payment',public.final2_order_payment(o.id));
end$$;
revoke all on function public.final2_order_detail(bigint)from public,anon;
grant execute on function public.final2_order_detail(bigint)to authenticated;
notify pgrst,'reload schema';
commit;
