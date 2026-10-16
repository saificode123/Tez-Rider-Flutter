-- FR17. Unknown existing inventory remains unconfirmed; no real stock invented.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create schema fr17_private;
revoke all on schema fr17_private from public,anon,authenticated;
alter table public.products
 add column stock_qty integer not null default 0 check(stock_qty>=0),
 add column low_stock_threshold integer not null default 5 check(low_stock_threshold>=0),
 add column stock_confirmed boolean not null default false,
 add column stock_version bigint not null default 0 check(stock_version>=0);
-- The existing fr21_product_vendor_idx already covers vendor equality.
create index fr17_vendor_inventory_idx on public.products(vendor_id,id desc);
create table public.inventory_movements(
 id bigint generated always as identity primary key,
 -- Product identity/name are historical snapshots. No cascading product FK:
 -- vendors may still delete an unsold listing without deleting its audit trail.
 product_id bigint not null,product_name text not null,vendor_id bigint not null references public.users(id),
 order_id bigint references public.orders(id),order_item_id bigint references public.order_items(id),
 quantity_delta integer not null,stock_before integer not null check(stock_before>=0),
 stock_after integer not null check(stock_after>=0),
 movement_type text not null check(movement_type in('ORDER_DECREMENT','ORDER_RESTORE','VENDOR_ADJUSTMENT')),
 reason text not null check(char_length(reason)between 1 and 300),actor_id bigint references public.users(id),
 request_id uuid,request_payload jsonb,created_at timestamptz not null default clock_timestamp(),
 check(stock_after::bigint=stock_before::bigint+quantity_delta),
 check((movement_type='VENDOR_ADJUSTMENT'and order_id is null and order_item_id is null and request_id is not null and request_payload is not null)
 or(movement_type='ORDER_DECREMENT'and order_id is not null and order_item_id is not null and quantity_delta<0 and request_id is null)
 or(movement_type='ORDER_RESTORE'and order_id is not null and order_item_id is not null and quantity_delta>0 and request_id is null)));
create unique index fr17_item_movement_once_idx on public.inventory_movements(order_item_id,movement_type)where order_item_id is not null;
create unique index fr17_adjust_request_once_idx on public.inventory_movements(vendor_id,request_id)where request_id is not null;
create index fr17_product_movements_idx on public.inventory_movements(product_id,id desc);
create index fr17_order_movements_idx on public.inventory_movements(order_id,product_id)where order_id is not null;
-- Includes accepted orders whose next vendor deadline is NULL but whose
-- verified payment may fail; excludes durable completed/cancelled history.
create index fr17_open_inventory_orders_idx on public.orders(coalesce(acceptance_deadline_at,created_at),id)
 where checkout_finalized_at is not null and cancelled_at is null and timeout_review_reason is null;
alter table public.inventory_movements enable row level security;
revoke all on public.inventory_movements from public,anon,authenticated;
grant select on public.inventory_movements to authenticated;
grant select,insert on public.inventory_movements to service_role;
grant usage,select on sequence public.inventory_movements_id_seq to service_role;
create policy fr17_ledger_read on public.inventory_movements for select to authenticated using(
 public.is_current_user_allowed()and(vendor_id=public.fr21_actor()or public.fr21_role()='admin'));
create trigger fr17_ledger_immutable before update or delete on public.inventory_movements for each row execute function public.fr26_append_only();

-- Tighten only product mutations. Existing catalog SELECT policies remain.
revoke insert,update on public.products from anon,authenticated;
grant update(is_available)on public.products to authenticated;
create policy fr17_product_update_owner on public.products as restrictive for update to authenticated
 using(public.fr21_role()='vendor'and vendor_id=public.fr21_actor()and public.is_current_user_allowed())
 with check(public.fr21_role()='vendor'and vendor_id=public.fr21_actor()and public.is_current_user_allowed());
create policy fr17_product_delete_owner on public.products as restrictive for delete to authenticated
 using(public.fr21_role()='vendor'and vendor_id=public.fr21_actor()and public.is_current_user_allowed());

alter table public.notifications add column stock_product_id bigint,add column stock_version bigint;
create unique index fr17_low_notice_once_idx on public.notifications(stock_product_id,stock_version)where stock_product_id is not null;
create function fr17_private.low_stock()returns trigger language plpgsql security definer set search_path='' as $$begin
 -- Changing a threshold alone (or in the same adjustment) emits no alert.
 -- Subsequent quantity changes use the new threshold and naturally re-arm.
 if old.stock_confirmed and new.stock_confirmed and old.low_stock_threshold=new.low_stock_threshold
 and new.stock_qty<>old.stock_qty and old.stock_qty>new.low_stock_threshold and new.stock_qty<=new.low_stock_threshold
 and exists(select 1 from public.users where id=new.vendor_id and role='vendor'and verification_status='approved'and not is_blocked)then
  insert into public.notifications(user_id,title,message,type,stock_product_id,stock_version,order_push_event_id)
  values(new.vendor_id,'Low stock','Low stock alert: '||new.name||'.','inventory',new.id,new.stock_version,gen_random_uuid())
  on conflict(stock_product_id,stock_version)where stock_product_id is not null do nothing;
 end if;return new;
end$$;
create trigger fr17_low_stock after update of stock_qty,low_stock_threshold on public.products for each row execute function fr17_private.low_stock();

create function fr17_private.adjust(p_product bigint,p_quantity integer,p_mode text,p_reason text,p_request uuid,p_threshold integer,p_version bigint,p_payload jsonb)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();p public.products;m public.inventory_movements;qty bigint;begin
 if actor is null or public.fr21_role()is distinct from'vendor'then return jsonb_build_object('code','FORBIDDEN');end if;
 perform 1 from public.users where id=actor and not is_blocked and verification_status='approved' for no key update;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request is null or p_mode is null or p_mode not in('set','delta')or p_quantity is null or p_reason is null or char_length(btrim(p_reason))not between 1 and 300
 or p_threshold<0 then raise exception 'Invalid stock adjustment'using errcode='22023';end if;
 select * into m from public.inventory_movements where vendor_id=actor and request_id=p_request;
 if found then
  if m.request_payload is distinct from p_payload then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT');end if;
  select * into p from public.products where id=m.product_id and vendor_id=actor;
  if not found then return jsonb_build_object('code','PRODUCT_REMOVED');end if;
  return jsonb_build_object('code','ALREADY_UPDATED','product_id',m.product_id,'stock_qty',p.stock_qty,'low_stock_threshold',p.low_stock_threshold,'stock_version',p.stock_version);
 end if;
 select * into p from public.products where id=p_product and vendor_id=actor for update;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_mode='set'and(p_version is null or p_version<>p.stock_version)then return jsonb_build_object('code','STOCK_CHANGED','stock_qty',p.stock_qty,'stock_version',p.stock_version);end if;
 qty:=case when p_mode='set'then p_quantity::bigint else p.stock_qty::bigint+p_quantity end;
 if qty not between 0 and 1000000000 then raise exception 'Stock must be between 0 and 1000000000'using errcode='22023';end if;
 update public.products set stock_qty=qty::integer,stock_confirmed=true,stock_version=stock_version+1,
 low_stock_threshold=coalesce(p_threshold,low_stock_threshold)where id=p.id;
 insert into public.inventory_movements(product_id,product_name,vendor_id,quantity_delta,stock_before,stock_after,movement_type,reason,actor_id,request_id,request_payload)
 values(p.id,p.name,actor,(qty-p.stock_qty)::integer,p.stock_qty,qty::integer,'VENDOR_ADJUSTMENT',btrim(p_reason),actor,p_request,p_payload);
 return jsonb_build_object('code','UPDATED','product_id',p.id,'stock_qty',qty,'low_stock_threshold',coalesce(p_threshold,p.low_stock_threshold),'stock_version',p.stock_version+1);
end$$;
create function public.vendor_adjust_stock(p_product_id bigint,p_quantity integer,p_mode text,p_reason text,p_request_id uuid,p_threshold integer default null,p_expected_version bigint default null)returns jsonb
language plpgsql security definer set search_path='' as $$begin
 return fr17_private.adjust(p_product_id,p_quantity,p_mode,p_reason,p_request_id,p_threshold,p_expected_version,
 jsonb_build_object('product_id',p_product_id,'quantity',p_quantity,'mode',p_mode,'reason',p_reason,'threshold',p_threshold,'version',p_expected_version));
end$$;

create function public.fr17_save_product(p_request_id uuid,p_product_id bigint,p_data jsonb,p_stock integer,p_threshold integer,p_expected_version bigint default null)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();p public.products;m public.inventory_movements;payload jsonb;result jsonb;v_price numeric;begin
 if actor is null or public.fr21_role()is distinct from'vendor'then return jsonb_build_object('code','FORBIDDEN');end if;
 perform 1 from public.users where id=actor and not is_blocked and verification_status='approved'for no key update;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or jsonb_typeof(p_data)is distinct from'object'or nullif(btrim(p_data->>'name'),'')is null
 or char_length(p_data->>'name')>200 or char_length(p_data->>'description')>5000 or char_length(p_data->>'image_url')>2000
 or p_stock is null or p_stock not between 0 and 1000000000 or p_threshold is null or p_threshold<0 then raise exception 'Invalid product inventory'using errcode='22023';end if;
 v_price:=(p_data->>'price')::numeric;
 if v_price is null or v_price<0 or v_price>1000000000000 then raise exception 'Invalid product price'using errcode='22023';end if;
 payload:=jsonb_build_object('product_id',p_product_id,'data',p_data,'stock',p_stock,'threshold',p_threshold,'version',p_expected_version);
 select * into m from public.inventory_movements where vendor_id=actor and request_id=p_request_id;
 if found then
  if m.request_payload is distinct from payload then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT');end if;
  select * into p from public.products where id=m.product_id and vendor_id=actor;
  if not found then return jsonb_build_object('code','PRODUCT_REMOVED');end if;
  return jsonb_build_object('code','ALREADY_UPDATED','product_id',m.product_id,'stock_qty',p.stock_qty,'stock_version',p.stock_version,'low_stock_threshold',p.low_stock_threshold);
 end if;
 if p_product_id is null then
  insert into public.products(vendor_id,name,price)values(actor,btrim(p_data->>'name'),v_price)returning * into p;
 else
  select * into p from public.products where id=p_product_id and vendor_id=actor for update;
  if not found then return jsonb_build_object('code','FORBIDDEN');end if;
  if p_expected_version is null or p_expected_version<>p.stock_version then return jsonb_build_object('code','STOCK_CHANGED','stock_qty',p.stock_qty,'stock_version',p.stock_version);end if;
 end if;
 update public.products set name=btrim(p_data->>'name'),description=p_data->>'description',price=v_price,
 image_url=p_data->>'image_url',category=coalesce(nullif(p_data->>'category',''),'General'),
 is_available=coalesce((p_data->>'is_available')::boolean,true),requires_prescription=coalesce((p_data->>'requires_prescription')::boolean,p.requires_prescription)where id=p.id;
 result:=fr17_private.adjust(p.id,p_stock,'set','Vendor product save',p_request_id,p_threshold,p.stock_version,payload);
 if result->>'code'<>'UPDATED'then raise exception 'Product stock save not confirmed'using errcode='40001';end if;
 return result;
end$$;

-- Keep accepted FR10 order/payment logic intact, behind the stock validator.
alter function public.fr10_checkout(uuid,jsonb,jsonb)rename to checkout_base;
alter function public.checkout_base(uuid,jsonb,jsonb)set schema fr17_private;
create function public.fr10_checkout(p_request_id uuid,p_items jsonb,p_delivery jsonb)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();items jsonb;shortages jsonb;result jsonb;oid bigint;begin
 if actor is null or public.fr21_role()is distinct from'customer'then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or jsonb_typeof(p_items)is distinct from'array'or jsonb_array_length(p_items)not between 1 and 100 then raise exception 'Invalid cart'using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(p_items)e where jsonb_typeof(e->'product_id')is distinct from'number'or jsonb_typeof(e->'quantity')is distinct from'number'
 or(e->>'product_id')::numeric<>(e->>'product_id')::bigint or(e->>'product_id')::bigint<=0
 or(e->>'quantity')::numeric<>(e->>'quantity')::integer or(e->>'quantity')::integer not between 1 and 100)then raise exception 'Invalid cart quantities'using errcode='22023';end if;
 select jsonb_agg(jsonb_build_object('product_id',id,'quantity',qty)order by id)into items from(
 select(e->>'product_id')::bigint id,sum((e->>'quantity')::integer)::integer qty from jsonb_array_elements(p_items)e group by 1)x;
 if exists(select 1 from jsonb_to_recordset(items)x(product_id bigint,quantity integer)where quantity>100)then raise exception 'Cart quantity exceeds limit'using errcode='22023';end if;
 -- Customer idempotency lock precedes products. New parent/order rows created
 -- below are not yet visible: no existing order is locked after a product.
 perform 1 from public.users where id=actor and not is_blocked for update;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if exists(select 1 from public.orders where checkout_request_id=p_request_id)then
  -- Pre-FR17 requests retain their original payload/order and no stock change.
  if exists(select 1 from public.orders o join public.inventory_movements m on m.order_id=o.id where o.checkout_request_id=p_request_id and m.movement_type='ORDER_DECREMENT')then
   return fr17_private.checkout_base(p_request_id,items,p_delivery);
  end if;
  return fr17_private.checkout_base(p_request_id,p_items,p_delivery);
 end if;
 perform 1 from public.products p join jsonb_to_recordset(items)x(product_id bigint,quantity integer)on x.product_id=p.id order by p.id for update of p;
 if(select count(*)from public.products p join jsonb_to_recordset(items)x(product_id bigint,quantity integer)on x.product_id=p.id
 join public.users u on u.id=p.vendor_id and u.role='vendor'and u.verification_status='approved'and not u.is_blocked
 where p.price>=0 and p.price<=1000000000000)<>jsonb_array_length(items)then return jsonb_build_object('code','UNAVAILABLE','message','A product or vendor is unavailable.');end if;
 select jsonb_agg(jsonb_build_object('product_id',p.id,'name',p.name,'requested',x.quantity,'available',case when p.is_available and p.stock_confirmed then p.stock_qty else 0 end)order by p.id)into shortages
 from public.products p join jsonb_to_recordset(items)x(product_id bigint,quantity integer)on x.product_id=p.id
 where not p.stock_confirmed or not p.is_available or p.stock_qty<x.quantity;
 if shortages is not null then return jsonb_build_object('code','INSUFFICIENT_STOCK','message','This product is currently out of stock.','shortages',shortages);end if;
 result:=fr17_private.checkout_base(p_request_id,items,p_delivery);
 if result->>'code'='PLACED'then
  oid:=(result->>'order_id')::bigint;
  update public.products p set stock_qty=p.stock_qty-x.quantity,stock_version=stock_version+1
  from jsonb_to_recordset(items)x(product_id bigint,quantity integer)where p.id=x.product_id and p.stock_qty>=x.quantity;
  insert into public.inventory_movements(product_id,product_name,vendor_id,order_id,order_item_id,quantity_delta,stock_before,stock_after,movement_type,reason,actor_id)
  select p.id,p.name,p.vendor_id,oid,i.id,-i.quantity,p.stock_qty+i.quantity,p.stock_qty,'ORDER_DECREMENT','Order placed',actor
  from public.order_items i join public.vendor_orders v on v.id=i.vendor_order_id join public.products p on p.id=i.product_id where v.order_id=oid;
 end if;return result;
end$$;

create function fr17_private.lock_inventory(p_orders bigint[])returns void language plpgsql security definer set search_path='' as $$begin
 perform 1 from public.products p where exists(select 1 from public.inventory_movements m where m.order_id=any(p_orders)and m.product_id=p.id and m.movement_type='ORDER_DECREMENT'
 and not exists(select 1 from public.inventory_movements r where r.order_item_id=m.order_item_id and r.movement_type='ORDER_RESTORE'))order by p.id for update;
end$$;
create function fr17_private.restore_cancelled()returns trigger language plpgsql security definer set search_path='' as $$
declare m public.inventory_movements;qty integer;before_qty integer;begin
 if new.order_status is distinct from'cancelled'or old.order_status='cancelled'then return new;end if;
 -- Parent is already locked; deterministic children then products. FR10 batch
 -- prelocks the union of every affected product before its first parent update.
 perform 1 from public.vendor_orders where order_id=new.id order by id for update;
 perform fr17_private.lock_inventory(array[new.id]);
 for m in select d.*from public.inventory_movements d where d.order_id=new.id and d.movement_type='ORDER_DECREMENT'
 and not exists(select 1 from public.inventory_movements r where r.order_item_id=d.order_item_id and r.movement_type='ORDER_RESTORE')order by d.product_id,d.id loop
  qty:=-m.quantity_delta;
  select stock_qty into strict before_qty from public.products where id=m.product_id;
  update public.products set stock_qty=stock_qty+qty,stock_version=stock_version+1 where id=m.product_id;
  insert into public.inventory_movements(product_id,product_name,vendor_id,order_id,order_item_id,quantity_delta,stock_before,stock_after,movement_type,reason,actor_id)
  values(m.product_id,m.product_name,m.vendor_id,new.id,m.order_item_id,qty,before_qty,before_qty+qty,'ORDER_RESTORE',coalesce(new.cancellation_reason,'Order cancelled'),null);
 end loop;return new;
end$$;
create trigger fr17_restore_cancelled after update of order_status on public.orders for each row execute function fr17_private.restore_cancelled();
create function fr17_private.protect_item()returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.inventory_movements where order_item_id=old.id)then raise exception 'Recorded inventory item is immutable'using errcode='42501';end if;
 if tg_op='DELETE'then return old;end if;return new;
end$$;
create trigger fr17_protect_item before update or delete on public.order_items for each row execute function fr17_private.protect_item();
-- All cancellers prelock the whole batch product union, preventing overlapping
-- multi-order batches from acquiring products in conflicting per-order orders.
do $$declare s text;begin
 s:=pg_get_functiondef('fr10_private.cancel_batch(bigint[],text)'::regprocedure);
 if position('select array_agg(o.id)into ids'in s)=0 then raise exception 'Review changed FR10 cancellation';end if;
 s:=replace(s,'select array_agg(o.id)into ids','perform fr17_private.lock_inventory(p_ids); select array_agg(o.id)into ids');execute s;
end$$;

-- No gateway is added. A durable, verified server-recorded FAILED non-COD
-- payment can be compensated by the existing minute worker after commit.
-- No payment-row trigger acquires a parent lock in the reverse order.
create function fr17_private.payment_failed(p_order bigint)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.orders o where o.id=p_order and o.order_status in('placed','pending','accepted')and o.timeout_review_reason is null
 and upper(o.payment_method)not in('COD','CASH','CASH ON DELIVERY')
 and exists(select 1 from public.inventory_movements m where m.order_id=o.id and m.movement_type='ORDER_DECREMENT')
 and exists(select 1 from public.payments p where p.orderid=o.id::text and p.customerid=o.user_id::text and p.amount::numeric=o.amount and lower(p.method)=lower(o.payment_method)
 and upper(p.status)='FAILED'and p.paidat is null and(select count(*)from public.payments q where q.orderid=o.id::text)=1))
$$;
create or replace function public.cancel_timed_out_orders(p_limit integer default 500)returns jsonb language plpgsql security definer set search_path='' as $$
declare ids bigint[];failed bigint[];expired bigint[];result jsonb;compensation jsonb;begin
 if p_limit is null or p_limit not between 1 and 500 then raise exception 'Batch must be 1–500'using errcode='22023';end if;
 select array_agg(id)into ids from(select o.id from public.orders o where o.checkout_finalized_at is not null
 and o.cancelled_at is null and o.timeout_review_reason is null
 and(o.acceptance_deadline_at<=clock_timestamp()or fr17_private.payment_failed(o.id))
 order by coalesce(o.acceptance_deadline_at,o.created_at),o.id limit p_limit for update of o skip locked)x;
 -- Select/lock every parent before acquiring any product. Both reasons share
 -- this single bounded batch; no later parent lock after products are held.
 perform 1 from public.vendor_orders where order_id=any(ids)order by order_id,id for update;
 perform fr17_private.lock_inventory(ids);
 select array_agg(id)filter(where fr17_private.payment_failed(id)),array_agg(id)filter(where not fr17_private.payment_failed(id))into failed,expired from unnest(ids)id;
 compensation:=fr10_private.cancel_batch(failed,'payment_failed');
 result:=fr10_private.cancel_batch(expired,'vendor_timeout');
 return result||jsonb_build_object('processed',coalesce(cardinality(ids),0),'payment_cancelled',coalesce((compensation->>'cancelled')::integer,0));
end$$;

revoke all on all functions in schema fr17_private from public,anon,authenticated,service_role;
revoke all on function public.fr10_checkout(uuid,jsonb,jsonb),public.vendor_adjust_stock(bigint,integer,text,text,uuid,integer,bigint),public.fr17_save_product(uuid,bigint,jsonb,integer,integer,bigint)from public,anon;
grant execute on function public.fr10_checkout(uuid,jsonb,jsonb),public.vendor_adjust_stock(bigint,integer,text,text,uuid,integer,bigint),public.fr17_save_product(uuid,bigint,jsonb,integer,integer,bigint)to authenticated;
notify pgrst,'reload schema';
commit;
