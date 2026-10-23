-- All records are synthetic rule fixtures and rolled back. Seeded delivered
-- states are not proof of physical delivery or real money changing hands.
begin;
-- FINAL2_CANDIDATE
create temporary table final2_cash_results(label text);
create temporary table final2_cash_cases(case_name text,order_id bigint,payment_id bigint,dispute_id bigint);
create temporary table final2_cash_request(id uuid);
insert into final2_cash_request values(gen_random_uuid());
grant all on final2_cash_results,final2_cash_cases,final2_cash_request to authenticated;
create function pg_temp.cash_fault()returns trigger language plpgsql as $$begin
 if TG_TABLE_NAME='security_audit_log'then
  if current_setting('final2.cash_audit_fault',true)='on'and new.target_type='cod_cash_event'then raise exception 'Synthetic mandatory audit failure';end if;
 end if;
 if TG_TABLE_NAME='notifications'then
  if current_setting('final2.cash_notice_fault',true)='on'and new.title='Cash collection recorded'then raise exception 'Synthetic mandatory notification failure';end if;
 end if;
 return new;end$$;
create trigger final2_cash_test_audit before insert on public.security_audit_log for each row execute function pg_temp.cash_fault();
create trigger final2_cash_test_notice before insert on public.notifications for each row execute function pg_temp.cash_fault();

do $fixture$declare label text;oid bigint;pid bigint;did bigint;aid bigint;result jsonb;
 customer bigint:=(select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid);
 rider bigint:=(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid);begin
 foreach label in array array['cash','not-delivered','unassigned','audit-failure','notice-failure','unpaid','legacy-paid','legacy-success',
  'null-status','no-receipt','future-receipt','wrong-amount','wrong-owner','wrong-method','missing-method','ambiguous','refund-cap']loop
  insert into public.orders(user_id,vendor_id,rider_id,amount,fare,order_status,payment_method,delivery_address,delivered_at)
  values(customer,__VENDOR_ID__,case when label='unassigned'then null else rider end,25.75,0,
   case when label in('not-delivered','unassigned')then'pending'when label='refund-cap'then'cancelled'else'ready'end,'COD','FINAL2 COD SQL synthetic only',null)returning id into oid;
  if label not in('not-delivered','unassigned','refund-cap')then
   insert into public.rider_assignments(orderid,riderid,status)values(oid,rider,'Accepted')returning id into aid;
   perform set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
   result:=public.submit_pre_delivery_checklist(aid,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
   if result->>'code'<>'COMPLETED'then raise exception 'Financial fixture checklist not valid';end if;
   -- Trusted synthetic financial state, not an OTP/delivery/GPS acceptance claim.
   update public.orders set order_status='delivered',delivered_at=clock_timestamp()where id=oid;
   update public.rider_assignments set status='Completed'where id=aid;
  end if;
  insert into public.payments(paymentid,orderid,customerid,method,status,amount,paidat)
  values('FINAL2-COD-SQL-'||oid,oid::text,case when label='wrong-owner'then'0'else customer::text end,
   case when label='missing-method'then null when label='wrong-method'then'CARD'else'COD'end,
   case when label in('cash','not-delivered','unassigned','audit-failure','notice-failure','unpaid')then'pending'
    when label='null-status'then null when label='legacy-success'then'SUCCESS'else'PAID'end,
   case when label='wrong-amount'then 20 else 25.75 end,
   case when label in('cash','not-delivered','unassigned','audit-failure','notice-failure','unpaid','no-receipt')then null
    when label='future-receipt'then clock_timestamp()+interval '1 day'else clock_timestamp()end)returning id into pid;
  if label='ambiguous'then insert into public.payments(paymentid,orderid,customerid,method,status,amount,paidat)
   values('FINAL2-COD-SQL-DUP-'||oid,oid::text,customer::text,'COD','PAID',25.75,clock_timestamp());end if;
  insert into public.disputes(type,by,customer_id,order_id,status,reason,description,request_id,evidence_paths)
  values('Other','Customer',customer,oid,'Open','Other','FINAL2 synthetic SQL evidence fixture; not physical evidence',gen_random_uuid(),array['final2-synthetic-sql.png'])returning id into did;
  insert into final2_cash_cases values(label,oid,pid,did);
 end loop;
 insert into public.order_refund_actions(order_id,payment_id,customer_id,amount,reason)
 select order_id,payment_id,customer,30,'vendor_rejected'from final2_cash_cases where case_name='refund-cap';
end$fixture$;

set local role authenticated;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $test$declare r jsonb;begin
 r:=public.final2_order_payment((select order_id from final2_cash_cases where case_name='cash'));
 if r->>'state'<>'UNPAID'or jsonb_array_length(r->'events')<>0 then raise exception 'Pending COD fabricated collection';end if;
 insert into final2_cash_results values('delivered/OTP-like fixture alone never marks pending COD collected');
 begin perform public.final2_record_cash((select order_id from final2_cash_cases where case_name='cash'),'COLLECTED',25.75,gen_random_uuid(),true,'FINAL2-CUSTOMER-FORGERY');raise exception 'Customer marked paid';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('customer cannot self-claim collection or manual refund');
end$test$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $test$begin
 begin perform public.final2_record_cash((select order_id from final2_cash_cases where case_name='cash'),'COLLECTED',25.75,gen_random_uuid(),true,'FINAL2-VENDOR-FORGERY');raise exception 'Vendor marked paid';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('Vendor cannot forge whole-order cash collection');
end$test$;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $test$declare oid bigint:=(select order_id from final2_cash_cases where case_name='cash');r jsonb;failed boolean;label text;begin
 begin perform public.final2_record_cash((select order_id from final2_cash_cases where case_name='unassigned'),'COLLECTED',25.75,gen_random_uuid(),true,'FINAL2-UNASSIGNED');raise exception 'Unassigned Rider collected';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('Rider must be assigned to this exact order');
 begin perform public.final2_order_payment((select order_id from final2_cash_cases where case_name='unassigned'));raise exception 'Discovery Rider read private payment';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('job discovery never grants an unassigned Rider private financial state');
 begin perform public.final2_record_cash((select order_id from final2_cash_cases where case_name='not-delivered'),'COLLECTED',25.75,gen_random_uuid(),true,'FINAL2-NOT-DELIVERED');raise exception 'Undelivered cash collected';exception when sqlstate 'PT409'then null;end;
 insert into final2_cash_results values('collection requires actual recorded terminal delivery state/time');
 begin perform public.final2_record_cash(oid,'COLLECTED',25.75,gen_random_uuid(),false,'FINAL2-NO-ACK');raise exception 'Missing acknowledgement';exception when sqlstate '22023'then null;end;
 begin perform public.final2_record_cash(oid,'COLLECTED',25.751,gen_random_uuid(),true,'FINAL2-BAD-PRECISION');raise exception 'Bad precision';exception when sqlstate '22023'then null;end;
 begin perform public.final2_record_cash(oid,'COLLECTED',25.75,gen_random_uuid(),true,E'bad\nreceipt');raise exception 'Multiline reference';exception when sqlstate '22023'then null;end;
 begin perform public.final2_record_cash(oid,'COLLECTED',20,gen_random_uuid(),true,'FINAL2-WRONG-AMOUNT');raise exception 'Wrong amount';exception when sqlstate 'PT409'then null;end;
 insert into final2_cash_results values('explicit acknowledgement, bounded receipt reference, precision and exact canonical amount enforced');
 foreach label in array array['audit-failure','notice-failure']loop
  perform set_config(case when label='audit-failure'then'final2.cash_audit_fault'else'final2.cash_notice_fault'end,'on',true);
  failed:=false;
  begin perform public.final2_record_cash((select order_id from final2_cash_cases c where c.case_name=label),'COLLECTED',25.75,gen_random_uuid(),true,'FINAL2-ATOMIC-FAULT');exception when raise_exception then failed:=true;end;
  perform set_config(case when label='audit-failure'then'final2.cash_audit_fault'else'final2.cash_notice_fault'end,'off',true);
  if not failed or exists(select 1 from public.cod_cash_events where order_id=(select order_id from final2_cash_cases c where c.case_name=label))then raise exception 'Partial cash state after mandatory failure';end if;
  insert into final2_cash_results values('mandatory '||label||' rolls back cash event, audit and notification atomically');
 end loop;
 r:=public.final2_record_cash(oid,'COLLECTED',25.75,(select id from final2_cash_request),true,'FINAL2-RECORDED-CASH');
 if r->>'code'<>'RECORDED'then raise exception 'Assigned Rider collection missing';end if;
 r:=public.final2_record_cash(oid,'COLLECTED',25.75,(select id from final2_cash_request),true,'FINAL2-RECORDED-CASH');
 if r->>'code'<>'ALREADY_APPLIED'then raise exception 'Replay not stable';end if;
 r:=public.final2_record_cash(oid,'COLLECTED',25.75,gen_random_uuid(),true,'FINAL2-SECOND-RECEIPT');
 if r->>'code'<>'ALREADY_COLLECTED'then raise exception 'Second collection not deduplicated';end if;
 insert into final2_cash_results values('assigned Rider explicit acknowledgement records once; UUID and new-request retries cannot duplicate collection');
 begin perform public.final2_record_cash(oid,'COLLECTED',25.75,(select id from final2_cash_request),true,'FINAL2-CHANGED-RECEIPT');raise exception 'Rebound request';exception when sqlstate 'PT409'then null;end;
 insert into final2_cash_results values('same financial request UUID cannot be rebound to changed evidence');
 begin perform public.final2_record_cash(oid,'REFUND_CONFIRMED',25.75,gen_random_uuid(),true,'FINAL2-RIDER-REFUND','DISPUTE',1);raise exception 'Rider refunded';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('assigned Rider collection privilege never grants Admin refund privilege');
end$test$;
select set_config('request.jwt.claims',__ADMIN_CLAIMS__,true);
do $test$declare label text;r jsonb;did bigint:=(select dispute_id from final2_cash_cases where case_name='cash');oid bigint:=(select order_id from final2_cash_cases where case_name='cash');fid bigint;req uuid:=gen_random_uuid();begin
 foreach label in array array['null-status','no-receipt','future-receipt','wrong-amount','wrong-owner','wrong-method','missing-method','ambiguous','unpaid']loop
  begin perform public.admin_resolve_dispute((select dispute_id from final2_cash_cases c where c.case_name=label),'RESOLVED','FINAL2 trusted negative case');raise exception 'Invalid legacy payment resolved: %',label;exception when sqlstate 'PT422'theN null;end;
 end loop;
 insert into final2_cash_results values('retained FR26 rejects null/unpaid/unreceipted/future/mismatched/ambiguous legacy payments');
 foreach label in array array['legacy-paid','legacy-success']loop
  r:=public.admin_resolve_dispute((select dispute_id from final2_cash_cases c where c.case_name=label),'RESOLVED','FINAL2 valid legacy settlement fixture');
  if r->>'code'<>'RESOLVED'then raise exception 'Legacy settled payment regressed';end if;
 end loop;
 insert into final2_cash_results values('retained canonical PAID and SUCCESS receipts still authorize pending dispute refund action');
 r:=public.admin_resolve_dispute(did,'RESOLVED','FINAL2 recorded COD collection review');
 if r->>'code'<>'RESOLVED'then raise exception 'Recorded COD not eligible for actual FR26 workflow';end if;
 r:=public.final2_order_payment(oid);
 fid:=(r->'refunds'->0->>'id')::bigint;
 if r->>'state'<>'CASH_RECORDED'or r->'refunds'->0->>'state'<>'PENDING'or(r->>'refunded_amount')::numeric<>0 then raise exception 'Pending refund falsely settled';end if;
 insert into final2_cash_results values('real FR26 resolution recognizes committed COD evidence but pending action never means returned money');
 r:=public.final2_record_cash(oid,'REFUND_FAILED',25.75,gen_random_uuid(),true,'FINAL2-MANUAL-ATTEMPT-FAILED','DISPUTE',fid);
 if r->>'code'<>'RECORDED'then raise exception 'Failed refund attempt not recorded';end if;
 r:=public.final2_order_payment(oid);
 if(r->>'refunded_amount')::numeric<>0 or r->'refunds'->0->>'state'<>'RETRY_REQUIRED'then raise exception 'Failed attempt fabricated return';end if;
 insert into final2_cash_results values('manual failed refund attempt stays unreturned and explicitly retryable');
 r:=public.final2_record_cash(oid,'REFUND_CONFIRMED',25.75,req,true,'FINAL2-MANUAL-RETURN-RECEIPT','DISPUTE',fid);
 if r->>'code'<>'RECORDED'then raise exception 'Confirmed cash return not recorded';end if;
 r:=public.final2_record_cash(oid,'REFUND_CONFIRMED',25.75,req,true,'FINAL2-MANUAL-RETURN-RECEIPT','DISPUTE',fid);
 if r->>'code'<>'ALREADY_APPLIED'then raise exception 'Refund retry not idempotent';end if;
 r:=public.final2_record_cash(oid,'REFUND_CONFIRMED',25.75,gen_random_uuid(),true,'FINAL2-OTHER-RETURN-RECEIPT','DISPUTE',fid);
 if r->>'code'<>'ALREADY_REFUNDED'then raise exception 'Second refund not deduplicated';end if;
 r:=public.final2_order_payment(oid);
 if(r->>'refunded_amount')::numeric<>25.75 or r->'refunds'->0->>'state'<>'CONFIRMED'then raise exception 'Confirmed refund projection wrong';end if;
 insert into final2_cash_results values('authorized manual cash return with receipt records exactly once and changes read model only after commit');
 begin perform public.final2_record_cash(oid,'REFUND_FAILED',25.75,gen_random_uuid(),true,'FINAL2-OUT-OF-ORDER-FAILURE','DISPUTE',fid);raise exception 'Completed refund reversed';exception when sqlstate 'PT409'then null;end;
 insert into final2_cash_results values('late failed/out-of-order attempt cannot reverse a confirmed refund');
 begin perform public.final2_record_cash((select order_id from final2_cash_cases where case_name='refund-cap'),'REFUND_CONFIRMED',30,gen_random_uuid(),true,'FINAL2-OVER-REFUND','ORDER',(select id from public.order_refund_actions where order_id=(select order_id from final2_cash_cases where case_name='refund-cap')));raise exception 'Over-refund allowed';exception when sqlstate 'PT409'then null;end;
 insert into final2_cash_results values('refund cannot exceed canonical collected/legacy settled payment');
end$test$;
select set_config('request.jwt.claims',__OTHER_CLAIMS__,true);
do $test$begin
 begin perform public.final2_order_payment((select order_id from final2_cash_cases where case_name='cash'));raise exception 'Unrelated customer read payment';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.cod_cash_events where order_id=(select order_id from final2_cash_cases where case_name='cash'))then raise exception 'Raw cash ledger leaked';end if;
 insert into final2_cash_results values('distinct authenticated customer cannot read private payment snapshot or cash ledger');
end$test$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $test$declare r jsonb;begin
 r:=public.final2_order_payment((select order_id from final2_cash_cases where case_name='cash'));
 if r->'amount'<>'null'::jsonb or exists(select 1 from jsonb_array_elements(r->'events')e where e->'amount'<>'null'::jsonb or e->'reference'<>'null'::jsonb)then raise exception 'Vendor learned whole-order cash/evidence';end if;
 insert into final2_cash_results values('assigned Vendor sees payment/refund state without another Vendor whole-order amounts or private receipt references');
 begin insert into public.cod_cash_events(request_id,order_id,payment_id,actor_id,actor_role,event_kind,amount,receipt_reference,request_payload)
  values(gen_random_uuid(),(select order_id from final2_cash_cases where case_name='cash'),(select payment_id from final2_cash_cases where case_name='cash'),__VENDOR_ID__,'admin','COLLECTED',1,'FINAL2-FORGERY','{}');raise exception 'Direct financial write allowed';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('direct client insertion cannot forge privileged cash evidence');
end$test$;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
do $test$begin
 begin perform public.final2_order_payment((select order_id from final2_cash_cases where case_name='cash'));raise exception 'Unrelated Vendor read finances';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('distinct Vendor cannot read another Vendor legacy order finances');
end$test$;
reset role;
do $test$declare oid bigint:=(select order_id from final2_cash_cases where case_name='cash');begin
 if(select count(*)from public.cod_cash_events where order_id=oid)<>3 or(select count(*)from public.security_audit_log a join public.cod_cash_events e on a.target_id=e.id and a.target_type='cod_cash_event'where e.order_id=oid and a.actor_id=e.actor_id)<>3 then raise exception 'Cash audit count or actor mismatch';end if;
 if not exists(select 1 from public.cod_cash_events where order_id=oid and actor_role='rider'and event_kind='COLLECTED')or(select count(*)from public.cod_cash_events where order_id=oid and actor_role='admin'and event_kind<>'COLLECTED')<>2 then raise exception 'Actor role not bound';end if;
 insert into final2_cash_results values('three exact critical results retain canonical actor IDs and role-at-event evidence; replays add no audit');
 begin update public.cod_cash_events set receipt_reference='TAMPERED'where order_id=oid;raise exception 'Privileged evidence rewrite allowed';exception when insufficient_privilege then null;end;
 insert into final2_cash_results values('append-only cash evidence resists UPDATE even under trusted SQL role');
 if exists(select 1 from public.payments where id=(select payment_id from final2_cash_cases where case_name='cash')and(status<>'pending'or paidat is not null))then raise exception 'Original payment history overwritten';end if;
 insert into final2_cash_results values('original pending payment and immutable pending refund action history remain unmodified');
end$test$;
set local role anon;
do $test$begin
 begin perform public.final2_order_payment(1);raise exception 'Anonymous financial access';exception when insufficient_privilege then null;end;
 begin perform public.final2_record_cash(1,'COLLECTED',1,gen_random_uuid(),true,'FINAL2-ANON');raise exception 'Anonymous cash write';exception when insufficient_privilege then null;end;
end$test$;
reset role;
insert into final2_cash_results values('anonymous cash write and payment snapshot APIs denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from final2_cash_results;
rollback;
