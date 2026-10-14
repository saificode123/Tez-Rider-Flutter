-- Explicit nullable legacy-state/method guards: SQL NULL is never eligibility.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
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
  if p.customerid is distinct from o.user_id::text or upper(p.status) not in ('SUCCESS','PAID','COMPLETED','SUCCEEDED') or p.status is null
  or p.paidat is null or p.paidat>clock_timestamp() or p.amount is null or p.amount<=0 or p.amount>1000000000000
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

notify pgrst,'reload schema';
commit;
