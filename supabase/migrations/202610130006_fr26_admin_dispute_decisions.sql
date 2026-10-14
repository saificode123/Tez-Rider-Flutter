-- FR-26 additive migration. Payment history and accepted workflows remain intact.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
alter table public.disputes
 add column decision text check(decision in ('RESOLVED','REJECTED')),
 add column admin_note text,
 add column decided_by bigint references public.users(id),
 add column decided_at timestamptz,
 add constraint fr26_decision_shape check(
  (decision is null and admin_note is null and decided_by is null and decided_at is null)
  or (decision is not null and admin_note is not null and status is not null and char_length(admin_note) between 5 and 2000
   and decided_by is not null and decided_at is not null
   and upper(replace(status,' ','_'))=decision));
create index fr26_queue_idx on public.disputes(created_at desc,id desc);
create index fr26_queue_status_idx on public.disputes(upper(replace(status,' ','_')),created_at desc,id desc);
create index fr26_decision_actor_idx on public.disputes(decided_by);
create index fr26_payment_order_idx on public.payments(orderid,id);
create index fr26_notification_page_idx on public.notifications(user_id,id desc);
-- Text relationships are validated against the actual order/owner by the RPC.
-- No payment status, amount, receipt or settlement timestamp is overwritten.
create table public.dispute_refund_actions(
 id bigint generated always as identity primary key,
 dispute_id bigint not null unique references public.disputes(id),
 payment_id bigint not null unique references public.payments(id),
 order_id bigint not null references public.orders(id),
 customer_id bigint not null references public.users(id),
 actor_id bigint not null references public.users(id),
 amount numeric not null check(amount>0 and amount<=1000000000000),
 status text not null default 'PENDING' check(status='PENDING'),
 created_at timestamptz not null default clock_timestamp());
create index fr26_refund_order_idx on public.dispute_refund_actions(order_id);
create index fr26_refund_customer_idx on public.dispute_refund_actions(customer_id,id desc);
create index fr26_refund_actor_idx on public.dispute_refund_actions(actor_id);
alter table public.dispute_refund_actions enable row level security;
revoke all on public.dispute_refund_actions from public,anon,authenticated;
grant all on public.dispute_refund_actions to service_role;
grant usage,select on sequence public.dispute_refund_actions_id_seq to service_role;
create unique index fr26_decision_audit_once_idx on public.security_audit_log(target_id)
 where target_type='dispute' and action='dispute_decision';

create function public.fr26_final_immutable() returns trigger language plpgsql set search_path='' as $$ begin
 if upper(replace(old.status,' ','_')) in ('RESOLVED','REJECTED','CLOSED') then
  if TG_OP='DELETE' or new is distinct from old then raise exception 'Final dispute is immutable.' using errcode='PT409'; end if;
 end if;
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
create trigger fr26_final_immutable before update or delete on public.disputes
 for each row execute function public.fr26_final_immutable();
create function public.fr26_append_only() returns trigger language plpgsql set search_path='' as $$ begin
 raise exception 'Audit and refund actions are append-only.' using errcode='42501';
end $$;
create trigger fr26_audit_append_only before update or delete on public.security_audit_log
 for each row execute function public.fr26_append_only();
create trigger fr26_refund_append_only before update or delete on public.dispute_refund_actions
 for each row execute function public.fr26_append_only();

create function public.fr26_options() returns jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if public.fr21_role() is distinct from 'admin' then raise exception 'Admin authorization required.' using errcode='42501'; end if;
 return jsonb_build_object('note_min',5,'note_max',2000,'statuses',jsonb_build_array('OPEN','UNDER_REVIEW','RESOLVED','CLOSED','ESCALATED','REJECTED'),
 'open_count',(select count(*) from public.disputes where upper(replace(status,' ','_')) in ('OPEN','UNDER_REVIEW','ESCALATED')));
end $$;
create function public.fr26_queue(p_status text default null,p_before_at timestamptz default null,p_before_id bigint default null,p_limit integer default 30)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if public.fr21_role() is distinct from 'admin' then raise exception 'Admin authorization required.' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 or (p_before_at is null)<>(p_before_id is null)
 or (p_status is not null and p_status not in ('OPEN','UNDER_REVIEW','RESOLVED','CLOSED','ESCALATED','REJECTED')) then
  raise exception 'Invalid queue parameters.' using errcode='PT422'; end if;
 return query select jsonb_build_object('id',d.id,'order_id',d.order_id,'reason',coalesce(d.reason,d.type),'status',d.status,'created_at',d.created_at)
 from public.disputes d where (p_status is null or upper(replace(d.status,' ','_'))=p_status)
 and (p_before_at is null or (d.created_at,d.id)<(p_before_at,p_before_id)) order by d.created_at desc,d.id desc limit p_limit;
end $$;
create function public.fr26_vendors(p_id bigint,p_before bigint default null) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$ begin
 if public.fr21_role() is distinct from 'admin' then raise exception 'Admin authorization required.' using errcode='42501'; end if;
 if not exists(select 1 from public.disputes where id=p_id) then raise exception 'Dispute unavailable.' using errcode='PT404'; end if;
 return query select jsonb_build_object('id',u.id,'name',u.name) from public.users u join
 (select o.vendor_id as id from public.disputes d join public.orders o on o.id=d.order_id where d.id=p_id
 union select vo.vendor_id from public.disputes d join public.vendor_orders vo on vo.order_id=d.order_id where d.id=p_id) v on v.id=u.id
 where p_before is null or u.id<p_before order by u.id desc limit 20;
end $$;
create function public.fr26_detail(p_id bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$ declare result jsonb; begin
 if public.fr21_role() is distinct from 'admin' then raise exception 'Admin authorization required.' using errcode='42501'; end if;
 select jsonb_build_object('id',d.id,'order_id',d.order_id,'reason',coalesce(d.reason,d.type),'description',d.description,
 'status',d.status,'created_at',d.created_at,'evidence_count',coalesce(cardinality(d.evidence_paths),0),
 'customer_id',d.customer_id,'customer_name',c.name,'customer_email',c.email,'rider_id',o.rider_id,'rider_name',r.name,
 'amount',o.amount,'payment_method',o.payment_method,'order_status',o.order_status,'delivered_at',o.delivered_at,
 'decision',d.decision,'admin_note',d.admin_note,'decided_by',d.decided_by,'admin_name',a.name,'decided_at',d.decided_at,
 'refund_pending',f.id is not null,'refund_amount',f.amount,'refund_status',f.status,
 'vendors',coalesce((select jsonb_agg(value) from public.fr26_vendors(d.id) value),'[]'::jsonb))
 into result from public.disputes d left join public.orders o on o.id=d.order_id left join public.users c on c.id=d.customer_id
 left join public.users r on r.id=o.rider_id left join public.users a on a.id=d.decided_by left join public.dispute_refund_actions f on f.dispute_id=d.id where d.id=p_id;
 if result is null then raise exception 'Dispute unavailable.' using errcode='PT404'; end if; return result;
end $$;

create function public.admin_resolve_dispute(p_dispute_id bigint,p_decision text,p_note text) returns jsonb
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
 if upper(replace(d.status,' ','_')) not in ('OPEN','UNDER_REVIEW','ESCALATED') or d.customer_id is null or d.order_id is null then
  raise exception 'Dispute is not eligible for a final decision.' using errcode='PT409'; end if;
 select * into o from public.orders where id=d.order_id for update;
 if o.id is null or o.user_id is distinct from d.customer_id or o.order_status is distinct from 'delivered' then
  raise exception 'Dispute order relationship is invalid.' using errcode='PT422'; end if;
 if p_decision='RESOLVED' then
  select array_agg(id) into payment_ids from (select id from public.payments where orderid=o.id::text order by id limit 2 for update) locked;
  if coalesce(cardinality(payment_ids),0)<>1 then raise exception 'Resolution requires one verified settled payment for this order.' using errcode='PT422'; end if;
  select * into p from public.payments where id=payment_ids[1];
  if p.customerid is distinct from o.user_id::text or upper(p.status) not in ('PAID','COMPLETED','SUCCEEDED') or p.status is null
  or p.paidat is null or p.paidat>clock_timestamp() or p.amount is null or p.amount<=0 or p.amount>1000000000000
  or p.amount::numeric is distinct from o.amount or lower(p.method) is distinct from lower(o.payment_method)
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

-- Extend the owned customer detail, retaining its original authorization and fields.
create or replace function public.fr25_detail(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$ declare result jsonb; begin
 if public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 select jsonb_build_object('id',d.id,'order_id',d.order_id,'reason',d.reason,'description',d.description,'status',d.status,
 'created_at',d.created_at,'evidence_count',cardinality(d.evidence_paths),'amount',o.amount,'delivered_at',o.delivered_at,
 'decision',d.decision,'admin_note',d.admin_note,'decided_at',d.decided_at,'refund_pending',f.id is not null,'refund_status',f.status,'refund_amount',f.amount)
 into result from public.disputes d join public.orders o on o.id=d.order_id left join public.dispute_refund_actions f on f.dispute_id=d.id
 where d.id=p_id and d.customer_id=public.fr21_actor();
 if result is null then raise exception 'Dispute access forbidden' using errcode='42501'; end if; return result;
end $$;
revoke all on function public.fr26_final_immutable(),public.fr26_append_only() from public,anon,authenticated;
revoke all on function public.fr26_options(),public.fr26_queue(text,timestamptz,bigint,integer),public.fr26_vendors(bigint,bigint),
 public.fr26_detail(bigint),public.admin_resolve_dispute(bigint,text,text) from public,anon;
grant execute on function public.fr26_options(),public.fr26_queue(text,timestamptz,bigint,integer),public.fr26_vendors(bigint,bigint),
 public.fr26_detail(bigint),public.admin_resolve_dispute(bigint,text,text) to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
 select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='disputes') then
 alter publication supabase_realtime add table public.disputes; end if;
end $$;
notify pgrst,'reload schema';
commit;
