-- Transaction-only synthetic database rule fixtures. Storage content/signing
-- and real separate-session concurrency are covered by hosted HTTP tests.
begin;
set local statement_timeout='60s';
create temporary table fr26_results(test text,result text);
create temporary table fr26_cases(label text primary key,id bigint,order_id bigint);
create function pg_temp.assert(p_ok boolean,p_label text) returns void language plpgsql as $$ begin
 if p_ok is not true then raise exception 'FR26 assertion failed: %',p_label; end if;
 insert into fr26_results values(p_label,'PASS');
end $$;
create function pg_temp.denied(p_sql text,p_label text) returns void language plpgsql as $$ begin
 begin execute p_sql; exception when insufficient_privilege or check_violation or unique_violation
 or sqlstate 'PT404' or sqlstate 'PT409' or sqlstate 'PT422' then
 insert into fr26_results values(p_label,'PASS');return; end;
 raise exception 'FR26 forbidden operation succeeded: %',p_label;
end $$;
do $$ declare identity uuid; profile bigint; label text; role_name text; owner bigint; order_id bigint; dispute bigint; status text; begin
 foreach label in array array['admin','admin2','pending-admin','customer','other','vendor','rider'] loop
  identity:=gen_random_uuid();role_name:=case when label in ('admin','admin2','pending-admin') then 'admin' when label='other' then 'customer' else label end;
  insert into auth.users(id,email,email_confirmed_at,role,aud) values(identity,'fr26-sql-'||identity||'@example.test',clock_timestamp(),'authenticated','authenticated');
  insert into public.users(email,name,role,verification_status) values('fr26-sql-'||identity||'@example.test','FR26 SQL synthetic',role_name,
   case when label in ('admin','admin2') then 'approved' else 'pending' end) returning id into profile;
  perform set_config('fr26.auth_'||replace(label,'-','_'),identity::text,true);
  perform set_config('fr26.profile_'||replace(label,'-','_'),profile::text,true);
 end loop;
 owner:=current_setting('fr26.profile_customer')::bigint;
 foreach label in array array['resolve','null-state','missing-method','blank-method','success-payment','reject','missing','unpaid','wrong-owner','wrong-amount','wrong-method','ambiguous','no-receipt','future-receipt','audit-failure','notice-failure','legacy-final','under-review','escalated'] loop
  insert into public.orders(user_id,order_status,amount,payment_method,delivery_address) values(owner,'delivered',25,case when label='missing-method' then null when label='blank-method' then '' else 'COD' end,'FR26 SQL SYNTHETIC ONLY') returning id into order_id;
  status:=case label when 'null-state' then null when 'legacy-final' then 'Closed' when 'under-review' then 'UNDER_REVIEW' when 'escalated' then 'ESCALATED' else 'Open' end;
  insert into public.disputes(type,by,customer_id,order_id,status,reason,description,request_id,evidence_paths)
   values('Other','Customer',owner,order_id,status,'Other','FR26 SQL synthetic evidence fixture',gen_random_uuid(),array['fr26-sql-rule-fixture.png']) returning id into dispute;
  insert into fr26_cases values(label,dispute,order_id);
  if label not in ('missing','reject','legacy-final') then
   insert into public.payments(orderid,customerid,paymentid,method,status,amount,paidat) values(order_id::text,
    case when label='wrong-owner' then current_setting('fr26.profile_other') else owner::text end,
    'FR26-SQL-SYNTHETIC-'||order_id,case when label='wrong-method' then 'CARD' when label='missing-method' then null when label='blank-method' then '' else 'COD' end,
    case when label='unpaid' then 'pending' when label='success-payment' then 'SUCCESS' else 'PAID' end,case when label='wrong-amount' then 20 else 25 end,
    case when label='no-receipt' then null when label='future-receipt' then clock_timestamp()+interval '1 day' else clock_timestamp() end);
   if label='ambiguous' then insert into public.payments(orderid,customerid,paymentid,method,status,amount,paidat)
    values(order_id::text,owner::text,'FR26-SQL-DUPLICATE','COD','PAID',25,clock_timestamp());end if;
  end if;
 end loop;
end $$;
grant all on fr26_results,fr26_cases to authenticated,anon;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr26.auth_admin'),'role','authenticated')::text,true);
select pg_temp.assert((public.fr26_options()->>'note_min')::integer=5,'server-defined note minimum');
select pg_temp.assert((public.fr26_options()->>'note_max')::integer=2000,'server-defined note maximum');
select pg_temp.assert((select count(*) from public.fr26_queue('OPEN',null,null,2))<=2,'bounded admin queue');
select pg_temp.denied('select public.fr26_queue(''INVALID'')','invalid queue filter denied');
select pg_temp.denied('select public.fr26_queue(null,null,null,101)','oversized queue limit denied');
select pg_temp.denied('select public.fr26_queue(null,now(),null,30)','partial cursor denied');
select pg_temp.denied('select public.admin_resolve_dispute(-1,''RESOLVED'',''Valid note'')','invalid dispute ID denied');
select pg_temp.denied('select public.admin_resolve_dispute(9223372036854775807,''RESOLVED'',''Valid note'')','nonexistent dispute denied');
do $$ declare d bigint:=(select id from fr26_cases where label='resolve');case_label text; begin
 perform pg_temp.denied(format('select public.admin_resolve_dispute(%s,''CLOSED'',''Valid note'')',d),'unsupported decision denied');
 perform pg_temp.denied(format('select public.admin_resolve_dispute(%s,''RESOLVED'',null)',d),'null note denied');
 perform pg_temp.denied(format('select public.admin_resolve_dispute(%s,''RESOLVED'',''abcd'')',d),'short note denied');
 perform pg_temp.denied(format('select public.admin_resolve_dispute(%s,''RESOLVED'',repeat(''x'',2001))',d),'overlong note denied');
 perform pg_temp.denied(format('update public.disputes set status=''Resolved'' where id=%s',d),'direct admin decision denied');
 foreach case_label in array array['null-state','missing-method','blank-method','missing','unpaid','wrong-owner','wrong-amount','wrong-method','ambiguous','no-receipt','future-receipt','legacy-final'] loop
  perform pg_temp.denied(format('select public.admin_resolve_dispute(%s,''RESOLVED'',''Synthetic safe decision'')',(select id from fr26_cases where fr26_cases.label=case_label)),case_label||' blocks unsafe resolution');
 end loop;
 perform pg_temp.assert((public.admin_resolve_dispute(d,'RESOLVED','Synthetic verified refund')->>'refund_pending')::boolean,'admin resolve records pending refund');
 perform pg_temp.assert((public.admin_resolve_dispute(d,'RESOLVED','Do not replace winning note')->>'replayed')::boolean,'same-decision retry replays');
 perform pg_temp.assert(public.fr26_detail(d)->>'admin_note'='Synthetic verified refund','same-decision retry preserves original note');
 perform pg_temp.denied(format('select public.admin_resolve_dispute(%s,''REJECTED'',''Opposite decision note'')',d),'opposite finalized decision conflicts');
 perform pg_temp.assert(public.admin_resolve_dispute((select id from fr26_cases where fr26_cases.label='success-payment'),'RESOLVED','Canonical SUCCESS payment')->>'decision'='RESOLVED','SRDS SUCCESS payment is refundable');
 perform pg_temp.assert(public.admin_resolve_dispute((select id from fr26_cases where fr26_cases.label='reject'),'REJECTED','Synthetic rejection reason')->>'decision'='REJECTED','rejection allowed without payment');
 perform pg_temp.assert(public.admin_resolve_dispute((select id from fr26_cases where fr26_cases.label='under-review'),'RESOLVED','Synthetic reviewed refund')->>'decision'='RESOLVED','under-review may finalize');
 perform pg_temp.assert(public.admin_resolve_dispute((select id from fr26_cases where fr26_cases.label='escalated'),'REJECTED','Synthetic escalated rejection')->>'decision'='REJECTED','existing escalated state may finalize');
end $$;
reset role;
select pg_temp.assert((select count(*) from public.security_audit_log where target_type='dispute' and action='dispute_decision' and target_id=(select id from fr26_cases where label='resolve'))=1,'one final audit event');
select pg_temp.assert((select actor_id from public.security_audit_log where target_type='dispute' and action='dispute_decision' and target_id=(select id from fr26_cases where label='resolve'))=current_setting('fr26.profile_admin')::bigint,'audit actor comes from trusted context');
select pg_temp.assert((select count(*) from public.notifications where dispute_id=(select id from fr26_cases where label='resolve'))=1,'one customer resolution notification');
select pg_temp.assert((select count(*) from public.dispute_refund_actions where dispute_id=(select id from fr26_cases where label='resolve'))=1,'one pending refund action');
select pg_temp.assert(not exists(select 1 from public.dispute_refund_actions where dispute_id=(select id from fr26_cases where label='reject')),'reject creates no refund action');
select pg_temp.assert((select status from public.payments where orderid=(select order_id::text from fr26_cases where label='resolve'))='PAID','settled payment status preserved');
select pg_temp.assert((select user_id from public.notifications where dispute_id=(select id from fr26_cases where label='reject'))=current_setting('fr26.profile_customer')::bigint,'notification reaches owner only');
select pg_temp.denied(format('update public.disputes set admin_note=''Forged final note'' where id=%s',(select id from fr26_cases where label='resolve')),'privileged final mutation blocked');
select pg_temp.denied(format('delete from public.disputes where id=%s',(select id from fr26_cases where label='resolve')),'final deletion blocked');
select pg_temp.denied(format('update public.security_audit_log set action=''forged'' where target_type=''dispute'' and target_id=%s',(select id from fr26_cases where label='resolve')),'audit event append-only');
select pg_temp.denied(format('update public.dispute_refund_actions set amount=1 where dispute_id=%s',(select id from fr26_cases where label='resolve')),'refund action append-only');

-- Inject failure only into these uncommitted synthetic fixtures. Restore the
-- trigger by dropping it within this transaction; no other session sees it.
create function pg_temp.fail_notice() returns trigger language plpgsql as $$ begin
 if new.dispute_id=(select id from fr26_cases where label='notice-failure') then raise exception 'Synthetic notification failure'; end if;return new;end $$;
create trigger fr26_sql_notice_failure before insert on public.notifications for each row execute function pg_temp.fail_notice();
create function pg_temp.fail_audit() returns trigger language plpgsql as $$ begin
 if new.target_type='dispute' and new.target_id=(select id from fr26_cases where label='audit-failure') then raise exception 'Synthetic audit failure'; end if;return new;end $$;
create trigger fr26_sql_audit_failure before insert on public.security_audit_log for each row execute function pg_temp.fail_audit();
set local role authenticated;
do $$ declare case_label text; d bigint; begin
 foreach case_label in array array['notice-failure','audit-failure'] loop
  select id into d from fr26_cases where fr26_cases.label=case_label;
  begin perform public.admin_resolve_dispute(d,'RESOLVED','Synthetic atomic rollback');raise exception 'Missing expected injected failure' using errcode='PT999';
   exception when sqlstate 'P0001' then null;end;
  perform pg_temp.assert(public.fr26_detail(d)->>'status'='Open',case_label||' rolls back decision');
 end loop;
end $$;
reset role;
drop trigger fr26_sql_notice_failure on public.notifications;
drop trigger fr26_sql_audit_failure on public.security_audit_log;
select pg_temp.assert(not exists(select 1 from public.dispute_refund_actions where dispute_id in(select id from fr26_cases where label in('notice-failure','audit-failure'))),'failed transaction leaves no pending refund');
select pg_temp.assert(not exists(select 1 from public.security_audit_log where target_type='dispute' and target_id in(select id from fr26_cases where label in('notice-failure','audit-failure'))),'failed transaction leaves no decision audit');
select pg_temp.assert(not exists(select 1 from public.notifications where dispute_id in(select id from fr26_cases where label in('notice-failure','audit-failure'))),'failed transaction leaves no notification');
set local role authenticated;
do $$ declare case_label text; d bigint:=(select id from fr26_cases where fr26_cases.label='resolve'); begin
 foreach case_label in array array['customer','other','vendor','rider','pending_admin'] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr26.auth_'||case_label),'role','authenticated')::text,true);
  perform pg_temp.denied(format('select public.admin_resolve_dispute(%s,''RESOLVED'',''Forbidden role note'')',d),case_label||' cannot decide');
  perform pg_temp.denied('select public.fr26_queue()',case_label||' cannot read admin queue');
  perform pg_temp.denied(format('select public.fr26_detail(%s)',d),case_label||' cannot read admin identities');
  perform pg_temp.denied('insert into public.security_audit_log(actor_id,action,target_type,target_id)values(null,''forged'',''dispute'',1)',case_label||' cannot forge audit');
  perform pg_temp.denied('insert into public.notifications(user_id,title,message,type)values(1,''forged'',''forged'',''dispute'')',case_label||' cannot forge notification');
  perform pg_temp.denied('update public.payments set status=''REFUNDED''',case_label||' cannot mutate settlements');
  perform pg_temp.denied('insert into public.dispute_refund_actions(dispute_id,payment_id,order_id,customer_id,actor_id,amount)values(1,1,1,1,1,25)',case_label||' cannot forge pending refund');
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr26.auth_customer'),'role','authenticated')::text,true);
 perform pg_temp.assert(public.fr25_detail(d)->>'admin_note'='Synthetic verified refund','owner sees final note');
 perform pg_temp.assert((public.fr25_detail(d)->>'refund_pending')::boolean,'owner sees pending not paid');
 perform pg_temp.denied(format('update public.disputes set decision=''REJECTED'' where id=%s',d),'customer cannot mutate decision');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('fr26.auth_other'),'role','authenticated')::text,true);
 perform pg_temp.denied(format('select public.fr25_detail(%s)',d),'other customer cannot read final detail');
 perform pg_temp.assert(not exists(select 1 from public.disputes where id=d),'RLS excludes other customer final dispute');
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.denied('select public.fr26_queue()','anonymous queue execution denied');
select pg_temp.denied('select public.admin_resolve_dispute(1,''RESOLVED'',''Anonymous note'')','anonymous decision execution denied');
reset role;
select jsonb_agg(jsonb_build_object('test',test,'result',result)) as results from fr26_results;
rollback;
