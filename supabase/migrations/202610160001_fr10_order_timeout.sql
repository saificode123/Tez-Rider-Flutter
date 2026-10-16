-- Approved policy: shared checkout is atomic; any required vendor timeout
-- cancels all portions, unless fulfillment has become irreversible.
begin;
set local lock_timeout='5s';
set local statement_timeout='90s';
create schema fr10_private;
revoke all on schema fr10_private from public,anon,authenticated;
create table fr10_private.configuration(
 singleton boolean primary key default true check(singleton),
 vendor_acceptance_timeout_seconds integer not null default 180 check(vendor_acceptance_timeout_seconds between 60 and 3600));
insert into fr10_private.configuration values(true,180);
alter table fr10_private.configuration enable row level security;
revoke all on fr10_private.configuration from public,anon,authenticated;
alter table public.orders add column checkout_request_id uuid unique,
 add column checkout_finalized_at timestamptz,
 add column acceptance_deadline_at timestamptz,
 add column cancelled_at timestamptz,
 add column cancellation_reason text,
 add column timeout_review_reason text;
create table fr10_private.checkout_requests(
 id uuid primary key,user_id bigint not null references public.users(id),
 order_id bigint not null unique references public.orders(id),payload jsonb not null);
alter table fr10_private.checkout_requests enable row level security;
revoke all on fr10_private.checkout_requests from public,anon,authenticated;
alter table public.vendor_orders add column acceptance_started_at timestamptz,
 add column acceptance_deadline_at timestamptz,
 add constraint fr10_deadline_shape check((acceptance_started_at is null and acceptance_deadline_at is null)
 or (acceptance_started_at is not null and acceptance_deadline_at>acceptance_started_at));
create index fr10_expiry_idx on public.orders(acceptance_deadline_at,id)
 where checkout_finalized_at is not null and acceptance_deadline_at is not null and cancelled_at is null and timeout_review_reason is null;
create index fr10_vendor_pending_idx on public.vendor_orders(order_id,acceptance_deadline_at) where status='pending';
create table public.order_refund_actions(
 id bigint generated always as identity primary key,
 order_id bigint not null unique references public.orders(id),
 payment_id bigint not null unique references public.payments(id),
 customer_id bigint not null references public.users(id),
 amount numeric not null check(amount>0 and amount<=1000000000000),
 reason text not null check(reason in('vendor_timeout','vendor_rejected')),
 status text not null default 'PENDING' check(status='PENDING'),
 created_at timestamptz not null default clock_timestamp());
create table public.order_timeline_events(
 id bigint generated always as identity primary key,
 order_id bigint not null references public.orders(id),
 status text not null, reason text,
 created_at timestamptz not null default clock_timestamp(),
 unique(order_id,status));
alter table public.order_refund_actions enable row level security;
alter table public.order_timeline_events enable row level security;
revoke all on public.order_refund_actions,public.order_timeline_events from public,anon,authenticated;
grant select on public.order_refund_actions,public.order_timeline_events to authenticated;
grant all on public.order_refund_actions,public.order_timeline_events to service_role;
grant usage,select on sequence public.order_refund_actions_id_seq,public.order_timeline_events_id_seq to service_role;
create policy fr10_refund_read on public.order_refund_actions for select to authenticated using(
 public.is_current_user_allowed() and (customer_id=public.fr21_actor() or public.fr21_role()='admin'));
create policy fr10_timeline_read on public.order_timeline_events for select to authenticated using(
 public.is_current_user_allowed() and public.fr21_order_visible(order_id));
create trigger fr10_refund_immutable before update or delete on public.order_refund_actions for each row execute function public.fr26_append_only();
create trigger fr10_timeline_immutable before update or delete on public.order_timeline_events for each row execute function public.fr26_append_only();
alter table public.notifications add column timeout_order_id bigint references public.orders(id),
 add column order_push_event_id uuid unique;
create unique index fr10_notification_once_idx on public.notifications(timeout_order_id) where timeout_order_id is not null;

-- No fabricated historical events/deadlines: pre-migration incomplete client
-- checkouts are not automatically enrolled. All new checkouts use this RPC.
create function public.fr10_checkout(p_request_id uuid,p_items jsonb,p_delivery jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();o public.orders;v record;total numeric;fee numeric;vendors integer;stamp timestamptz;seconds integer;payload jsonb;
begin
 if actor is null or public.fr21_role() is distinct from 'customer' then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100
 or jsonb_typeof(p_delivery) is distinct from 'object' then raise exception 'Invalid checkout' using errcode='22023';end if;
 payload:=jsonb_build_object('items',p_items,'delivery',p_delivery);
 -- Serialize idempotency per authenticated owner, including simultaneous retries.
 perform 1 from public.users where id=actor and not is_blocked for update;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 select * into o from public.orders where checkout_request_id=p_request_id;
 if found then
  if o.user_id<>actor or (select c.payload from fr10_private.checkout_requests c where c.id=p_request_id and c.user_id=actor)is distinct from payload then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT');end if;
  return jsonb_build_object('code','ALREADY_PLACED','order_id',o.id,'amount',o.amount);
 end if;
 if nullif(btrim(p_delivery->>'address'),'') is null or char_length(p_delivery->>'address')>1000
 or coalesce(p_delivery->>'speed','') not in('standard','express')
 or (p_delivery->>'lat')::numeric not between -90 and 90 or (p_delivery->>'lng')::numeric not between -180 and 180
 or p_delivery->>'lat' is null or p_delivery->>'lng' is null then raise exception 'Invalid delivery details' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(p_items)e where jsonb_typeof(e->'product_id')<>'number' or jsonb_typeof(e->'quantity')<>'number'
 or (e->>'quantity')::integer not between 1 and 100 or (e->>'quantity')::numeric<>(e->>'quantity')::integer)
 or (select count(distinct e->>'product_id') from jsonb_array_elements(p_items)e)<>jsonb_array_length(p_items)
 then raise exception 'Invalid cart items' using errcode='22023';end if;
 -- Lock the canonical product snapshots in deterministic order; no stock writes.
 perform 1 from public.products p join jsonb_to_recordset(p_items)x(product_id bigint,quantity integer) on p.id=x.product_id order by p.id for share of p;
 if (select count(*) from public.products p join jsonb_to_recordset(p_items)x(product_id bigint,quantity integer) on p.id=x.product_id
 join public.users u on u.id=p.vendor_id and u.role='vendor' and u.verification_status='approved' and not u.is_blocked
 where p.is_available and p.price>=0 and p.price<=1000000000000)<>jsonb_array_length(p_items)
 then raise exception 'A product or vendor is unavailable' using errcode='22023';end if;
 select sum(p.price*x.quantity),count(distinct p.vendor_id) into total,vendors from public.products p join jsonb_to_recordset(p_items)x(product_id bigint,quantity integer) on p.id=x.product_id;
 -- Existing checkout fee formula, now validated on the server.
 fee:=120+(vendors-1)*80+case when p_delivery->>'speed'='express' then 90 else 0 end;
 if total+fee>1000000000000 then raise exception 'Order amount too large' using errcode='22023';end if;
 insert into public.orders(user_id,amount,fare,order_status,payment_method,delivery_address,delivery_lat,delivery_lng,delivery_speed,checkout_request_id)
 values(actor,total+fee,fee,'pending','COD',btrim(p_delivery->>'address'),(p_delivery->>'lat')::numeric,(p_delivery->>'lng')::numeric,p_delivery->>'speed',p_request_id) returning * into o;
 insert into fr10_private.checkout_requests(id,user_id,order_id,payload)values(p_request_id,actor,o.id,payload);
 with groups as(select p.vendor_id,sum(p.price*x.quantity) subtotal,bool_or(coalesce(p.requires_prescription,false)) prescription
 from public.products p join jsonb_to_recordset(p_items)x(product_id bigint,quantity integer) on p.id=x.product_id group by p.vendor_id)
 insert into public.vendor_orders(order_id,vendor_id,sub_total,status,requires_prescription)
 select o.id,vendor_id,subtotal,case when prescription then 'pending_prescription' else 'pending' end,prescription from groups order by vendor_id;
 insert into public.order_items(vendor_order_id,product_id,quantity,price_at_time)
 select vo.id,p.id,x.quantity,p.price from public.products p join jsonb_to_recordset(p_items)x(product_id bigint,quantity integer) on p.id=x.product_id
 join public.vendor_orders vo on vo.order_id=o.id and vo.vendor_id=p.vendor_id;
 -- COD is unpaid: preserve this record forever, never label it captured.
 insert into public.payments(paymentid,orderid,customerid,method,status,amount)
 values('fr10-cod-'||p_request_id,o.id::text,actor::text,'COD','pending',(total+fee)::double precision);
 select vendor_acceptance_timeout_seconds into seconds from fr10_private.configuration where singleton;
 stamp:=clock_timestamp();
 update public.orders set checkout_finalized_at=stamp,
 has_prescription_items=exists(select 1 from public.vendor_orders where order_id=o.id and requires_prescription),
 prescription_status=case when exists(select 1 from public.vendor_orders where order_id=o.id and requires_prescription)then 'pending_verification'else 'none'end where id=o.id;
 update public.vendor_orders set acceptance_started_at=stamp,acceptance_deadline_at=stamp+make_interval(secs=>seconds) where order_id=o.id and status='pending';
 update public.orders set acceptance_deadline_at=(select min(acceptance_deadline_at) from public.vendor_orders where order_id=o.id and status='pending') where id=o.id;
 insert into public.order_timeline_events(order_id,status,created_at) values(o.id,'pending',stamp);
 return jsonb_build_object('code','PLACED','order_id',o.id,'amount',total+fee);
end$$;

create function fr10_private.timeline()returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.checkout_finalized_at is not null and new.order_status is distinct from old.order_status then
  insert into public.order_timeline_events(order_id,status,reason,created_at)
  values(new.id,new.order_status,new.cancellation_reason,coalesce(new.cancelled_at,clock_timestamp())) on conflict(order_id,status)do nothing;
 end if;return new;
end$$;
create trigger fr10_timeline after update of order_status on public.orders for each row execute function fr10_private.timeline();

-- Parent IDs are already selected with SKIP LOCKED by the worker. The same
-- helper also serves one-order vendor rejection; no external calls or per-order
-- payment/notification/refund queries are issued inside a worker loop.
create function fr10_private.cancel_batch(p_ids bigint[],p_reason text)returns jsonb
language plpgsql security definer set search_path='' as $$
declare ids bigint[];eligible bigint[];stamp timestamptz:=clock_timestamp();reviewed integer;cancelled integer;
begin
 perform 1 from public.orders where id=any(p_ids) order by id for update;
 perform 1 from public.vendor_orders where order_id=any(p_ids) order by order_id,id for update;
 select array_agg(o.id)into ids from public.orders o where o.id=any(p_ids) and o.order_status<>'cancelled'
 and(p_reason<>'vendor_timeout' or exists(select 1 from public.vendor_orders v where v.order_id=o.id and v.status='pending'and v.acceptance_deadline_at<=stamp));
 update public.orders o set timeout_review_reason='fulfillment_conflict'where o.id=any(ids)and(
 o.rider_id is not null or coalesce(o.order_status,'')not in('placed','pending','accepted')
 or exists(select 1 from public.vendor_orders v where v.order_id=o.id and coalesce(v.status,'')not in('pending','pending_prescription','accepted','cancelled'))
 or exists(select 1 from public.rider_assignments r where r.orderid=o.id and r.status in('Pending','Accepted')));
 get diagnostics reviewed=row_count;
 select array_agg(id)into eligible from public.orders where id=any(ids)and timeout_review_reason is distinct from 'fulfillment_conflict';
 perform 1 from public.payments p join public.orders o on p.orderid=o.id::text where o.id=any(eligible)order by p.id for update of p;
 insert into public.order_refund_actions(order_id,payment_id,customer_id,amount,reason)
 select o.id,p.id,o.user_id,p.amount::numeric,p_reason from public.orders o join public.payments p on p.orderid=o.id::text
 where o.id=any(eligible)and upper(o.payment_method)not in('COD','CASH','CASH ON DELIVERY')
 and(select count(*)from public.payments q where q.orderid=o.id::text)=1
 and p.customerid=o.user_id::text and p.amount::numeric=o.amount and p.amount>0 and p.amount<=1000000000000
 and upper(p.status)in('SUCCESS','PAID','COMPLETED','SUCCEEDED')and p.paidat is not null and p.paidat<=stamp
 and lower(p.method)=lower(o.payment_method)and nullif(btrim(p.paymentid),'')is not null
 and not exists(select 1 from public.dispute_refund_actions f where f.payment_id=p.id)
 on conflict(order_id)do nothing;
 update public.orders o set order_status='cancelled',cancelled_at=stamp,cancellation_reason=p_reason,
 acceptance_deadline_at=null,requires_manual_assignment=false,
 timeout_review_reason=case when upper(o.payment_method)not in('COD','CASH','CASH ON DELIVERY')
 and not exists(select 1 from public.order_refund_actions f where f.order_id=o.id)
 and not exists(select 1 from public.payments p where p.orderid=o.id::text and upper(p.status)in('PENDING','UNPAID','AUTHORIZED','FAILED','CANCELLED','VOIDED')
 and(select count(*)from public.payments q where q.orderid=o.id::text)=1)then 'payment_verification_required'else null end
 where o.id=any(eligible);
 get diagnostics cancelled=row_count;
 update public.vendor_orders set status='cancelled'where order_id=any(eligible)and status is distinct from 'cancelled';
 if p_reason='vendor_timeout'then
  insert into public.notifications(user_id,title,message,type,timeout_order_id,order_push_event_id)
  select user_id,'Order cancelled','Order cancelled — vendor unavailable.','order',id,gen_random_uuid()from public.orders where id=any(eligible)
  on conflict(timeout_order_id)where timeout_order_id is not null do nothing;
 end if;
 return jsonb_build_object('cancelled',cancelled,'review_required',reviewed);
end$$;
create function fr10_private.cancel_locked(p_order bigint,p_reason text)returns text
language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 result:=fr10_private.cancel_batch(array[p_order],p_reason);
 if(result->>'review_required')::integer>0 then return 'REVIEW_REQUIRED';end if;
 if(result->>'cancelled')::integer>0 or exists(select 1 from public.orders where id=p_order and order_status='cancelled')then return 'ORDER_CANCELLED';end if;
 return 'NOT_EXPIRED';
end$$;
-- FR17 extension point: fr10_private.timeline() persists the trusted
-- vendor_timeout transition in order_timeline_events. No inventory work exists.
create function public.cancel_timed_out_orders(p_limit integer default 500)returns jsonb
language plpgsql security definer set search_path='' as $$declare ids bigint[];result jsonb;begin
 if p_limit is null or p_limit not between 1 and 500 then raise exception 'Batch must be 1–500'using errcode='22023';end if;
 select array_agg(id)into ids from(select id from public.orders where checkout_finalized_at is not null
 and acceptance_deadline_at<=clock_timestamp()and cancelled_at is null and timeout_review_reason is null
 order by acceptance_deadline_at,id limit p_limit for update skip locked)selected;
 result:=fr10_private.cancel_batch(ids,'vendor_timeout');
 return result||jsonb_build_object('processed',coalesce(cardinality(ids),0));
end$$;

create function fr10_private.before_deadline(p_deadline timestamptz,p_now timestamptz)returns boolean
language sql immutable set search_path='' as $$select p_now<p_deadline$$;

create function public.fr10_vendor_transition(p_vendor_order_id bigint,p_status text)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();vo public.vendor_orders;o public.orders;result text;
begin
 if actor is null or public.fr21_role() is distinct from 'vendor' then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_status is null or p_status not in('accepted','preparing','cancelled')then return jsonb_build_object('code','INVALID_STATE');end if;
 select * into vo from public.vendor_orders where id=p_vendor_order_id and vendor_id=actor;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 select * into o from public.orders where id=vo.order_id for update;
 perform 1 from public.vendor_orders where order_id=o.id order by id for update;
 select * into vo from public.vendor_orders where id=p_vendor_order_id and order_id=o.id and vendor_id=actor;
 perform 1 from public.users where id=actor and role='vendor' and verification_status='approved' and not is_blocked for share;
 if not found or vo.id is null then return jsonb_build_object('code','FORBIDDEN');end if;
 if o.order_status='cancelled' or vo.status='cancelled'then return jsonb_build_object('code','ORDER_CANCELLED');end if;
 if o.checkout_finalized_at is not null and exists(select 1 from public.vendor_orders where order_id=o.id and status='pending' and not fr10_private.before_deadline(acceptance_deadline_at,clock_timestamp()))then
  return jsonb_build_object('code','ORDER_EXPIRED');end if;
 if vo.status=p_status then return jsonb_build_object('code',case when p_status='accepted'then 'ALREADY_ACCEPTED'else 'ALREADY_UPDATED'end);end if;
 if p_status='cancelled' and o.checkout_finalized_at is not null then
  result:=fr10_private.cancel_locked(o.id,'vendor_rejected');return jsonb_build_object('code',result);
 end if;
 if not((vo.status='pending'and p_status='accepted')or(vo.status='accepted'and p_status='preparing')or(p_status='cancelled'and vo.status in('pending','accepted','preparing')))then return jsonb_build_object('code','INVALID_STATE');end if;
 update public.vendor_orders set status=p_status where id=vo.id;
 return jsonb_build_object('code',case when p_status='accepted'then 'ACCEPTED'else 'UPDATED'end);
exception when lock_not_available or deadlock_detected or serialization_failure then return jsonb_build_object('code','RETRYABLE_ERROR');
end$$;

-- Preserve legacy orders; aggregate managed shared orders rather than allowing
-- one child to move the parent backwards or hide a pending required vendor.
create or replace function public.sync_order_status_from_vendor_order()returns trigger
language plpgsql security definer set search_path='' as $$declare o public.orders;next_status text;begin
 if new.status is not distinct from old.status then return new;end if;
 select * into o from public.orders where id=new.order_id for update;
 if o.checkout_finalized_at is null then update public.orders set order_status=new.status where id=new.order_id;return new;end if;
 if o.order_status='cancelled'then return new;end if;
 if exists(select 1 from public.vendor_orders where order_id=o.id and status in('pending','pending_prescription'))then next_status:='pending';
 elsif exists(select 1 from public.vendor_orders where order_id=o.id and status='on_the_way')then next_status:='on_the_way';
 elsif exists(select 1 from public.vendor_orders where order_id=o.id and status='ready')then next_status:='ready';
 elsif exists(select 1 from public.vendor_orders where order_id=o.id and status='preparing')then next_status:='preparing';
 elsif not exists(select 1 from public.vendor_orders where order_id=o.id and status<>'delivered')then next_status:='delivered';
 else next_status:='accepted';end if;
 update public.orders set order_status=next_status,acceptance_deadline_at=(select min(acceptance_deadline_at)from public.vendor_orders where order_id=o.id and status='pending')where id=o.id;
 return new;
end$$;
create function fr10_private.guard_order()returns trigger language plpgsql set search_path='' as $$begin
 if old.checkout_finalized_at is not null then
  if current_user in('authenticated','anon')and new.order_status is distinct from old.order_status then raise exception 'Managed order transitions require a trusted RPC'using errcode='42501';end if;
  if old.order_status='cancelled' and (new.order_status is distinct from old.order_status or new.rider_id is distinct from old.rider_id)then raise exception 'Cancelled order is final'using errcode='PT409';end if;
  if (new.rider_id is distinct from old.rider_id and new.rider_id is not null)or(new.order_status in('ready','on_the_way','delivered')and new.order_status is distinct from old.order_status)then
   if exists(select 1 from public.vendor_orders where order_id=old.id and status in('pending','pending_prescription','cancelled'))then raise exception 'All vendors must accept before fulfillment'using errcode='PT409';end if;
  end if;
 end if;return new;
end$$;
create trigger fr10_guard_order before update on public.orders for each row execute function fr10_private.guard_order();
create function fr10_private.guard_vendor()returns trigger language plpgsql set search_path='' as $$declare finalized timestamptz;seconds integer;begin
 select checkout_finalized_at into finalized from public.orders where id=new.order_id;
 if finalized is not null then
  if current_user in('authenticated','anon')then raise exception 'Use trusted vendor transition'using errcode='42501';end if;
  if old.status='cancelled'and new.status is distinct from old.status then raise exception 'Cancelled portion is final'using errcode='PT409';end if;
  if old.acceptance_started_at is not null and(new.acceptance_started_at is distinct from old.acceptance_started_at or new.acceptance_deadline_at is distinct from old.acceptance_deadline_at)then raise exception 'Acceptance deadline is immutable'using errcode='PT409';end if;
  if new.status='pending'and new.acceptance_started_at is null then
   select vendor_acceptance_timeout_seconds into seconds from fr10_private.configuration where singleton;
   new.acceptance_started_at:=clock_timestamp();new.acceptance_deadline_at:=new.acceptance_started_at+make_interval(secs=>seconds);
  end if;
 end if;return new;
end$$;
create trigger fr10_guard_vendor before update on public.vendor_orders for each row execute function fr10_private.guard_vendor();
-- Direct status changes cannot bypass the deadline/RPC or invert lock order.
revoke insert on public.orders,public.vendor_orders,public.order_items from authenticated;
-- Existing legacy status grant remains; managed-order trigger requires RPC.

-- Suppress legacy notices for atomic timeout (one dedicated owner notice),
-- and child vendor notices for managed whole-order cancellation.
do $$declare s text;begin
 s:=pg_get_functiondef('public.notify_customer_on_order_status()'::regprocedure);
 s:=replace(s,'IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN','IF NEW.cancellation_reason IS NOT DISTINCT FROM ''vendor_timeout'' THEN RETURN NEW; END IF; IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN');execute s;
 s:=pg_get_functiondef('public.notify_vendor_on_status_change()'::regprocedure);
 s:=replace(s,'IF NEW.status IS DISTINCT FROM OLD.status THEN','IF NEW.status=''cancelled'' AND EXISTS(SELECT 1 FROM public.orders WHERE id=NEW.order_id AND checkout_finalized_at IS NOT NULL AND order_status=''cancelled'') THEN RETURN NEW; END IF; IF NEW.status IS DISTINCT FROM OLD.status THEN');execute s;
end$$;

-- Reuse the accepted durable FCM queue and device capability contract. The
-- transport UUID is either a broadcast UUID or this one timeout notice UUID.
do $$declare s text;begin
 s:=pg_get_functiondef('fr30_private.queue_push()'::regprocedure);
 s:=replace(s,'new.broadcast_id is not null','(new.broadcast_id is not null or new.order_push_event_id is not null)');execute s;
 s:=pg_get_functiondef('public.fr30_claim_push(integer)'::regprocedure);
 s:=replace(s,'''broadcast_id'',n.broadcast_id','''broadcast_id'',coalesce(n.broadcast_id,n.order_push_event_id)');execute s;
 s:=pg_get_functiondef('public.fr30_resolve_push(uuid,text,uuid)'::regprocedure);
 s:=replace(s,'''broadcast_id'',n.broadcast_id','''broadcast_id'',coalesce(n.broadcast_id,n.order_push_event_id)');
 s:=replace(s,'n.broadcast_id=p_broadcast','coalesce(n.broadcast_id,n.order_push_event_id)=p_broadcast');execute s;
end$$;
-- Extend the existing bounded owned history projection; retain its role gate.
do $$declare s text;begin
 s:=pg_get_functiondef('public.fr25_order_history(bigint)'::regprocedure);
 if position('''rider_id'',o.rider_id' in s)=0 then raise exception 'Review changed order history';end if;
 s:=replace(s,'''rider_id'',o.rider_id','''cancellation_reason'',o.cancellation_reason,''cancelled_at'',o.cancelled_at,''timeout_review_reason'',o.timeout_review_reason,
 ''order_refund_actions'',coalesce((select jsonb_agg(jsonb_build_object(''status'',f.status,''amount'',f.amount))from public.order_refund_actions f where f.order_id=o.id),''[]''::jsonb),
 ''order_timeline_events'',coalesce((select jsonb_agg(jsonb_build_object(''status'',e.status,''reason'',e.reason,''created_at'',e.created_at)order by e.created_at,e.id)from public.order_timeline_events e where e.order_id=o.id),''[]''::jsonb),
 ''rider_id'',o.rider_id');execute s;
end$$;
revoke all on all functions in schema fr10_private from public,anon,authenticated;
revoke all on function public.cancel_timed_out_orders(integer) from public,anon,authenticated,service_role;
revoke all on function public.fr10_checkout(uuid,jsonb,jsonb),public.fr10_vendor_transition(bigint,text) from public,anon;
grant execute on function public.fr10_checkout(uuid,jsonb,jsonb),public.fr10_vendor_transition(bigint,text) to authenticated;
-- One stable cron name; migration history prevents replay; schedule is upserted.
select cron.schedule('fr10-order-timeout','* * * * *','select public.cancel_timed_out_orders(500);');
notify pgrst,'reload schema';
commit;
