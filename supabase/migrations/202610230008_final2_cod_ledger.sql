-- Approved A: COD-only, explicit manual cash acknowledgements; no provider or
-- automatic collection/refund claim. Existing payment/refund history is immutable.
begin;
create table public.cod_cash_events(
 id bigint generated always as identity primary key,
 request_id uuid not null unique,
 order_id bigint not null references public.orders(id),
 payment_id bigint not null references public.payments(id),
 actor_id bigint not null references public.users(id),
 actor_role text not null check(actor_role in('admin','rider')),
 event_kind text not null check(event_kind in('COLLECTED','REFUND_CONFIRMED','REFUND_FAILED')),
 amount numeric not null check(amount>0 and amount<=1000000000000 and amount=round(amount,2)),
 receipt_reference text not null check(char_length(receipt_reference)between 5 and 120 and receipt_reference!~'[[:cntrl:]]'),
 refund_kind text check(refund_kind in('ORDER','DISPUTE')),
 order_refund_id bigint references public.order_refund_actions(id),
 dispute_refund_id bigint references public.dispute_refund_actions(id),
 request_payload jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 check((event_kind='COLLECTED'and refund_kind is null and order_refund_id is null and dispute_refund_id is null)
  or(event_kind<>'COLLECTED'and refund_kind is not null and((refund_kind='ORDER'and order_refund_id is not null and dispute_refund_id is null)
   or(refund_kind='DISPUTE'and dispute_refund_id is not null and order_refund_id is null))))
);
create unique index final2_cash_collection_once on public.cod_cash_events(payment_id)where event_kind='COLLECTED';
create unique index final2_order_cash_refund_once on public.cod_cash_events(order_refund_id)where event_kind='REFUND_CONFIRMED'and order_refund_id is not null;
create unique index final2_dispute_cash_refund_once on public.cod_cash_events(dispute_refund_id)where event_kind='REFUND_CONFIRMED'and dispute_refund_id is not null;
create index final2_cash_order_history on public.cod_cash_events(order_id,id);
alter table public.cod_cash_events enable row level security;
revoke all on public.cod_cash_events from public,anon,authenticated;
grant select on public.cod_cash_events to authenticated;
grant all on public.cod_cash_events to service_role;
grant usage,select on sequence public.cod_cash_events_id_seq to service_role;
create policy final2_cash_read on public.cod_cash_events for select to authenticated using(
 public.is_current_user_allowed()and(public.fr21_role()='admin'or actor_id=public.fr21_actor()
  or exists(select 1 from public.orders o where o.id=order_id and o.user_id=public.fr21_actor())));
create trigger final2_cash_append_only before update or delete on public.cod_cash_events for each row execute function public.fr26_append_only();

create function public.final2_record_cash(p_order_id bigint,p_event_kind text,p_amount numeric,p_request_id uuid,
 p_confirmed boolean,p_reference text,p_refund_kind text default null,p_refund_id bigint default null)returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();role_name text:=public.fr21_role();o public.orders;p public.payments;
 e public.cod_cash_events;payload jsonb;reference_text text;payment_ids bigint[];eligible numeric;refund_customer bigint;
 refund_order bigint;refund_payment bigint;already_refunded numeric;begin
 if actor is null or role_name is null or role_name not in('admin','rider')then raise exception 'Authorized cash recorder required'using errcode='42501';end if;
 perform 1 from public.users where id=actor and role=role_name and verification_status='approved'and not is_blocked for share;
 if not found then raise exception 'Approved account required'using errcode='42501';end if;
 if p_event_kind is null or p_event_kind not in('COLLECTED','REFUND_CONFIRMED','REFUND_FAILED')
  or p_order_id is null or p_order_id<=0 or p_request_id is null or p_confirmed is distinct from true
  or p_amount is null or p_amount::text in('NaN','Infinity','-Infinity')or p_amount<=0 or p_amount>1000000000000 or p_amount<>round(p_amount,2)
  or p_reference is null or char_length(btrim(p_reference))not between 5 and 120 or p_reference~'[[:cntrl:]]'then
  raise exception 'Explicit confirmation, exact amount and a one-line receipt reference are required'using errcode='22023';end if;
 reference_text:=btrim(p_reference);
 if(p_event_kind='COLLECTED'and(p_refund_kind is not null or p_refund_id is not null))
  or(p_event_kind<>'COLLECTED'and(p_refund_kind is null or p_refund_kind not in('ORDER','DISPUTE')or p_refund_id is null or p_refund_id<=0))then
  raise exception 'Invalid refund relationship'using errcode='22023';end if;
 if p_event_kind<>'COLLECTED'and role_name<>'admin'then raise exception 'Only Admin can reconcile a manual refund'using errcode='42501';end if;
 select * into o from public.orders where id=p_order_id for update;
 if o.id is null or(role_name='rider'and o.rider_id is distinct from actor)then raise exception 'Order unavailable for this recorder'using errcode='42501';end if;
 payload:=jsonb_build_object('order_id',p_order_id,'event_kind',p_event_kind,'amount',p_amount,'reference',reference_text,'refund_kind',p_refund_kind,'refund_id',p_refund_id);
 select * into e from public.cod_cash_events where request_id=p_request_id;
 if found then
  if e.actor_id<>actor then raise exception 'Request unavailable'using errcode='42501';end if;
  if e.request_payload is distinct from payload then raise exception 'Request payload changed'using errcode='PT409';end if;
  return jsonb_build_object('code','ALREADY_APPLIED','event_id',e.id,'event_kind',e.event_kind,'amount',e.amount);
 end if;
 select array_agg(id)into payment_ids from(select id from public.payments where orderid=o.id::text order by id limit 2 for update)locked;
 if coalesce(cardinality(payment_ids),0)<>1 then raise exception 'One canonical payment record is required'using errcode='PT409';end if;
 select * into p from public.payments where id=payment_ids[1];
 if p.customerid is distinct from o.user_id::text or lower(btrim(p.method))is distinct from'cod'or lower(btrim(o.payment_method))is distinct from'cod'
  or p.amount is null or p.amount<=0 or p.amount>1000000000000 or p.amount::text in('NaN','Infinity','-Infinity')
  or p.amount::numeric is distinct from o.amount or nullif(btrim(p.paymentid),'')is null then
  raise exception 'Canonical COD payment relationship is invalid'using errcode='22023';end if;
 if p_event_kind='COLLECTED'then
  if o.order_status is distinct from'delivered'or o.delivered_at is null or o.delivered_at>clock_timestamp()or p_amount is distinct from o.amount then
   raise exception 'Confirm exact cash received only after recorded delivery'using errcode='PT409';end if;
  select * into e from public.cod_cash_events where payment_id=p.id and event_kind='COLLECTED';
  if found then return jsonb_build_object('code','ALREADY_COLLECTED','event_id',e.id,'event_kind',e.event_kind,'amount',e.amount);end if;
  if upper(p.status)in('SUCCESS','PAID','COMPLETED','SUCCEEDED')and p.paidat is not null and p.paidat<=clock_timestamp()then
   return jsonb_build_object('code','ALREADY_SETTLED','event_kind','COLLECTED','amount',p.amount);
  end if;
  if lower(p.status)not in('pending','unpaid')or p.status is null then raise exception 'Payment state requires Admin review'using errcode='PT409';end if;
 else
  if not exists(select 1 from public.cod_cash_events where payment_id=p.id and event_kind='COLLECTED')
   and not(upper(p.status)in('SUCCESS','PAID','COMPLETED','SUCCEEDED')and p.paidat is not null and p.paidat<=clock_timestamp())then
   raise exception 'An unpaid order cannot be refunded'using errcode='PT409';end if;
  if p_refund_kind='ORDER'then
   if o.order_status is distinct from'cancelled'then raise exception 'Order refund requires a cancelled order'using errcode='22023';end if;
   select amount,customer_id,order_id,payment_id into eligible,refund_customer,refund_order,refund_payment
    from public.order_refund_actions where id=p_refund_id for update;
  else
   select f.amount,f.customer_id,f.order_id,f.payment_id into eligible,refund_customer,refund_order,refund_payment
    from public.dispute_refund_actions f join public.disputes d on d.id=f.dispute_id
    where f.id=p_refund_id and d.decision='RESOLVED'and d.customer_id=f.customer_id and d.order_id=f.order_id for update of f;
  end if;
  if eligible is null or refund_customer is distinct from o.user_id or refund_order is distinct from o.id or refund_payment is distinct from p.id
   or p_amount is distinct from eligible then raise exception 'Refund must match its authorized pending action and amount'using errcode='22023';end if;
  select * into e from public.cod_cash_events where event_kind='REFUND_CONFIRMED'
   and((p_refund_kind='ORDER'and order_refund_id=p_refund_id)or(p_refund_kind='DISPUTE'and dispute_refund_id=p_refund_id));
  if found then
   if p_event_kind='REFUND_FAILED'then raise exception 'A confirmed refund cannot be marked failed'using errcode='PT409';end if;
   return jsonb_build_object('code','ALREADY_REFUNDED','event_id',e.id,'event_kind',e.event_kind,'amount',e.amount);
  end if;
  select coalesce(sum(amount),0)into already_refunded from public.cod_cash_events where payment_id=p.id and event_kind='REFUND_CONFIRMED';
  if already_refunded+p_amount>p.amount::numeric then raise exception 'Refund exceeds collected payment'using errcode='PT409';end if;
 end if;
 insert into public.cod_cash_events(request_id,order_id,payment_id,actor_id,actor_role,event_kind,amount,receipt_reference,refund_kind,order_refund_id,dispute_refund_id,request_payload)
 values(p_request_id,o.id,p.id,actor,role_name,p_event_kind,p_amount,reference_text,p_refund_kind,
  case when p_refund_kind='ORDER'then p_refund_id end,case when p_refund_kind='DISPUTE'then p_refund_id end,payload)returning *into e;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)
 values(actor,case p_event_kind when'COLLECTED'then'cod_collection_recorded'when'REFUND_CONFIRMED'then'cod_refund_confirmed'else'cod_refund_failed'end,'cod_cash_event',e.id);
 insert into public.notifications(user_id,title,message,type)values(o.user_id,
  case p_event_kind when'COLLECTED'then'Cash collection recorded'when'REFUND_CONFIRMED'then'Manual cash refund confirmed'else'Manual refund attempt unsuccessful'end,
  case p_event_kind when'COLLECTED'then'An authorized recorder acknowledged receipt of the order cash. This is a manual cash record.'
   when'REFUND_CONFIRMED'then'An authorized Admin confirmed the manual cash return. No payment-provider transfer was performed by the app.'
   else'An Admin recorded an unsuccessful refund attempt. This does not record returned money.'end,'system');
 return jsonb_build_object('code','RECORDED','event_id',e.id,'event_kind',e.event_kind,'amount',e.amount);
end$$;
revoke all on function public.final2_record_cash(bigint,text,numeric,uuid,boolean,text,text,bigint)from public,anon;
grant execute on function public.final2_record_cash(bigint,text,numeric,uuid,boolean,text,text,bigint)to authenticated;

create function public.final2_order_payment(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();role_name text:=public.fr21_role();o public.orders;p public.payments;
 payment_ids bigint[];legacy_settled boolean;cash_collected boolean;refunds jsonb;events jsonb;begin
 if actor is null or role_name is null or role_name not in('admin','customer','vendor','rider')
  or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then
  raise exception 'Order payment unavailable'using errcode='42501';end if;
 select *into o from public.orders where id=p_order_id;
 if o.id is null then raise exception 'Order payment unavailable'using errcode='42501';end if;
 -- Discovery of an unassigned job does not authorize its private finances.
 if(role_name='admin'or(role_name='customer'and o.user_id=actor)or(role_name='rider'and o.rider_id=actor)
  or(role_name='vendor'and(exists(select 1 from public.vendor_orders where order_id=o.id and vendor_id=actor)
   or(o.vendor_id=actor and not exists(select 1 from public.vendor_orders where order_id=o.id)))))is distinct from true then
  raise exception 'Order payment unavailable'using errcode='42501';end if;
 select array_agg(id)into payment_ids from(select id from public.payments where orderid=o.id::text order by id limit 2)records;
 if coalesce(cardinality(payment_ids),0)<>1 then return jsonb_build_object('code','REVIEW_REQUIRED','message','One canonical payment record is required.');end if;
 select *into p from public.payments where id=payment_ids[1];
 if p.customerid is distinct from o.user_id::text or p.amount is null or p.amount<=0 or p.amount>1000000000000
  or p.amount::text in('NaN','Infinity','-Infinity')or p.amount::numeric is distinct from o.amount
  or p.method is null or o.payment_method is null or lower(btrim(p.method))is distinct from lower(btrim(o.payment_method))
  or nullif(btrim(p.paymentid),'')is null then return jsonb_build_object('code','REVIEW_REQUIRED','message','Payment relationship requires Admin review.');end if;
 legacy_settled:=coalesce(upper(p.status)in('SUCCESS','PAID','COMPLETED','SUCCEEDED')and p.paidat is not null and p.paidat<=clock_timestamp(),false);
 cash_collected:=exists(select 1 from public.cod_cash_events where payment_id=p.id and event_kind='COLLECTED');
 select coalesce(jsonb_agg(jsonb_build_object('kind',r.kind,'id',r.id,'amount',case when role_name='vendor'then null else r.amount end,
  'state',case when exists(select 1 from public.cod_cash_events e where e.event_kind='REFUND_CONFIRMED'
   and((r.kind='ORDER'and e.order_refund_id=r.id)or(r.kind='DISPUTE'and e.dispute_refund_id=r.id)))then'CONFIRMED'
   when exists(select 1 from public.cod_cash_events e where e.event_kind='REFUND_FAILED'
    and((r.kind='ORDER'and e.order_refund_id=r.id)or(r.kind='DISPUTE'and e.dispute_refund_id=r.id)))then'RETRY_REQUIRED'else'PENDING'end)
  order by r.created_at,r.kind,r.id),'[]'::jsonb)into refunds
 from(select 'ORDER'::text kind,id,amount,created_at from public.order_refund_actions where order_id=o.id
  union all select 'DISPUTE',id,amount,created_at from public.dispute_refund_actions where order_id=o.id)r;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'event_kind',e.event_kind,'amount',case when role_name='vendor'then null else e.amount end,
  'actor_role',e.actor_role,'recorded_at',e.created_at,'reference',case when role_name='admin'or e.actor_id=actor then e.receipt_reference else null end)
  order by e.id),'[]'::jsonb)into events from public.cod_cash_events e where e.order_id=o.id;
 return jsonb_build_object('code','OK','order_id',o.id,'order_status',o.order_status,'payment_id',p.id,'method',p.method,
  'amount',case when role_name='vendor'then null else p.amount end,'original_status',p.status,
  'state',case when cash_collected then'CASH_RECORDED'when legacy_settled then'LEGACY_SETTLED'
   when lower(p.status)in('pending','unpaid')then'UNPAID'else'UNCONFIRMED'end,
  'refunds',refunds,'events',events,
  'refunded_amount',case when role_name='vendor'then null else(select coalesce(sum(amount),0)from public.cod_cash_events where payment_id=p.id and event_kind='REFUND_CONFIRMED')end);
end$$;
revoke all on function public.final2_order_payment(bigint)from public,anon;
grant execute on function public.final2_order_payment(bigint)to authenticated;
-- Preserve the accepted FR26 decision protocol; recognize only a committed trusted
-- manual COD collection as an additional settled-payment source.
create or replace function public.admin_resolve_dispute(p_dispute_id bigint,p_decision text,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); d public.disputes; o public.orders; p public.payments; payment_ids bigint[]; note text; result jsonb;
begin
 if actor is null or public.fr21_role() is distinct from 'admin' then raise exception 'Admin authorization required.' using errcode='42501'; end if;
 note:=regexp_replace(p_note,'^\s+|\s+$','','g');
 if p_dispute_id is null or p_dispute_id<=0 or p_decision is null or p_decision not in ('RESOLVED','REJECTED')
 or note is null or char_length(note) not between 5 and 2000 then raise exception 'Choose Resolve or Reject and enter a note of 5-2000 characters.' using errcode='PT422'; end if;
 select * into d from public.disputes where id=p_dispute_id for update;
 if d.id is null then raise exception 'Dispute unavailable.' using errcode='PT404'; end if;
 if d.decision is not null then
  if d.decision<>p_decision then raise exception 'Another decision has already finalized this dispute.' using errcode='PT409'; end if;
  return public.fr26_detail(d.id)||jsonb_build_object('code',d.decision,'replayed',true);
 end if;
 if d.status is null or upper(replace(d.status,' ','_')) not in ('OPEN','UNDER_REVIEW','ESCALATED') or d.customer_id is null or d.order_id is null then
  raise exception 'Dispute is not eligible for a final decision.' using errcode='PT409'; end if;
 select * into o from public.orders where id=d.order_id for update;
 if o.id is null or o.user_id is distinct from d.customer_id or o.order_status is distinct from 'delivered' then
  raise exception 'Dispute order relationship is invalid.' using errcode='PT422'; end if;
 if p_decision='RESOLVED' then
  select array_agg(id) into payment_ids from (select id from public.payments where orderid=o.id::text order by id limit 2 for update) locked;
  if coalesce(cardinality(payment_ids),0)<>1 then raise exception 'Resolution requires one verified settled payment for this order.' using errcode='PT422'; end if;
  select * into p from public.payments where id=payment_ids[1];
  if p.customerid is distinct from o.user_id::text
  or not (coalesce(upper(p.status) in ('SUCCESS','PAID','COMPLETED','SUCCEEDED') and p.paidat is not null and p.paidat<=clock_timestamp(),false)
    or exists(select 1 from public.cod_cash_events e where e.payment_id=p.id and e.order_id=o.id and e.event_kind='COLLECTED'))
  or p.amount is null or p.amount<=0 or p.amount>1000000000000
  or p.amount::numeric is distinct from o.amount or p.method is null or o.payment_method is null
  or btrim(p.method)='' or btrim(o.payment_method)='' or lower(p.method) is distinct from lower(o.payment_method)
  or p.paymentid is null or btrim(p.paymentid)='' then raise exception 'Payment is unpaid or incompatible. Verify payment before resolving.' using errcode='PT422'; end if;
  if exists(select 1 from public.dispute_refund_actions where payment_id=p.id) then raise exception 'This payment already has a pending refund action.' using errcode='PT409'; end if;
  insert into public.dispute_refund_actions(dispute_id,payment_id,order_id,customer_id,actor_id,amount)
   values(d.id,p.id,o.id,d.customer_id,actor,p.amount::numeric);
 end if;
 update public.disputes set status=case when p_decision='RESOLVED' then 'Resolved' else 'Rejected' end,
 decision=p_decision,admin_note=note,decided_by=actor,decided_at=clock_timestamp() where id=d.id;
 insert into public.security_audit_log(actor_id,action,target_type,target_id) values(actor,'dispute_decision','dispute',d.id);
 insert into public.notifications(user_id,title,message,type,dispute_id)
 values(d.customer_id,case when p_decision='RESOLVED' then 'Refund initiated' else 'Dispute rejected' end,
 case when p_decision='RESOLVED' then 'Refund has been initiated. Pending manual processing; money has not been returned.'
 else 'Dispute rejected. See reason in app.' end,'dispute',d.id);
 return public.fr26_detail(d.id)||jsonb_build_object('code',p_decision,'replayed',false);
end $$;


commit;
