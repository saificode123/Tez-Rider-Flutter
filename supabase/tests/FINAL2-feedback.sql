-- Rolled-back synthetic rating fixtures; no physical-delivery assertion.
begin;
-- FINAL2_CANDIDATE
create temporary table final2_feedback_results(label text);
create temporary table final2_feedback_state(first_order bigint,second_order bigint,pending_order bigint,legacy_order bigint,
 vendor bigint,other_vendor bigint,rider bigint,customer bigint,request uuid);
grant all on final2_feedback_results,final2_feedback_state to authenticated;
create function pg_temp.feedback_fault()returns trigger language plpgsql as $$begin
 if new.action='feedback_submitted'and current_setting('final2.feedback_audit_fault',true)='on'then raise exception 'Synthetic feedback audit failure';end if;
 return new;end$$;
create trigger final2_feedback_test_fault before insert on public.security_audit_log for each row execute function pg_temp.feedback_fault();
do $$declare customer bigint:=(select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid);
 rider bigint:=(select id from public.users where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid);
 foreign_vendor bigint:=(select id from public.users where auth_user_id=(__OTHER_VENDOR_CLAIMS__::jsonb->>'sub')::uuid);
 label text;oid bigint;aid bigint;r jsonb;ids bigint[]:='{}';begin
 foreach label in array array['first','second','pending','legacy']loop
  insert into public.orders(user_id,vendor_id,rider_id,amount,fare,order_status,payment_method,delivery_address)
   values(customer,__VENDOR_ID__,rider,15,2,case when label='pending'then'pending'else'ready'end,'COD','FINAL2 synthetic feedback SQL fixture')returning id into oid;
  ids:=array_append(ids,oid);
  if label<>'legacy'then insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,__VENDOR_ID__,5,'ready');end if;
  if label='first'then insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,foreign_vendor,8,'ready');end if;
  if label<>'pending'then
   insert into public.rider_assignments(orderid,riderid,status)values(oid,rider,'Accepted')returning id into aid;
   perform set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
   r:=public.submit_pre_delivery_checklist(aid,1,'[{"id":"items_match","confirmed":true},{"id":"packaging_intact","confirmed":true},{"id":"details_confirmed","confirmed":true}]');
   if r->>'code'<>'COMPLETED'then raise exception 'Feedback fixture checklist failed';end if;
   update public.orders set order_status='delivered',delivered_at=clock_timestamp()where id=oid;
   update public.vendor_orders set status='delivered'where order_id=oid;
   update public.rider_assignments set status='Completed'where id=aid;
  end if;
 end loop;
 insert into final2_feedback_state values(ids[1],ids[2],ids[3],ids[4],__VENDOR_ID__,foreign_vendor,rider,customer,gen_random_uuid());
end$$;
-- Preserve and verify pre-existing legitimate/synthetic ratings. Re-running this
-- rolled-back suite must never depend on an empty review database.
create temporary table final2_feedback_baseline as
select coalesce(v.rating_count,0)as vendor_count,coalesce(v.rating_total,0)as vendor_total,
 coalesce(r.rating_count,0)as rider_count,coalesce(r.rating_total,0)as rider_total,
 (select count(*)from public.security_audit_log where action='feedback_submitted'
  and actor_id=f.customer and target_id in(f.vendor,f.other_vendor,f.rider))as audit_count
from final2_feedback_state f left join public.rating_summaries v on v.target_user_id=f.vendor
 left join public.rating_summaries r on r.target_user_id=f.rider;
grant select on final2_feedback_baseline to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare s final2_feedback_state;b final2_feedback_baseline;r jsonb;v jsonb;bad integer;begin
 select *into s from final2_feedback_state;select *into b from final2_feedback_baseline;
 r:=public.final2_feedback_context(s.first_order);
 if r->>'code'<>'OK'or jsonb_array_length(r->'targets')<>3 then raise exception 'Dual/multi-Vendor context incorrect';end if;
 if not exists(select 1 from jsonb_array_elements(r->'targets')t where(t->>'target_id')::bigint=s.rider and t->>'role'='rider')then raise exception 'Assigned Rider target missing';end if;
 insert into final2_feedback_results values('own delivered multi-Vendor order exposes two actual Vendors and assigned Rider; UUID/numeric identities resolved server-side');
 begin perform public.final2_feedback_context(s.pending_order);raise exception 'Pending feedback accepted';exception when sqlstate 'PT409'then null;end;
 insert into final2_feedback_results values('pending/nonterminal delivery cannot be rated');
 foreach bad in array array[0,6]loop
  begin perform public.final2_submit_feedback(s.first_order,s.vendor,bad,'FINAL2 invalid stars',gen_random_uuid());raise exception 'Invalid rating accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.final2_submit_feedback(s.first_order,s.vendor,5,repeat('x',2001),gen_random_uuid());raise exception 'Oversize feedback accepted';exception when invalid_parameter_value then null;end;
 begin perform public.final2_submit_feedback(s.first_order,s.vendor,5,chr(1),gen_random_uuid());raise exception 'Control feedback accepted';exception when invalid_parameter_value then null;end;
 insert into final2_feedback_results values('star bounds, oversize comments and unsafe control characters enforced on server');
 begin perform public.final2_submit_feedback(s.second_order,s.other_vendor,5,'FINAL2 wrong Vendor',gen_random_uuid());raise exception 'Unrelated Vendor rated';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('current valid Vendor from another order is not an authorized feedback target');
 begin insert into public.reviews(order_id,rating)values(s.first_order,5);raise exception 'Direct feedback bypass accepted';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('direct authenticated review INSERT remains denied');
 r:=public.final2_submit_feedback(s.first_order,s.vendor,5,'FINAL2 SQL feedback',s.request);
 if r->>'code'<>'SUBMITTED'or(r->>'rating')::int<>5 then raise exception 'Canonical Vendor feedback failed';end if;
 v:=public.final2_submit_feedback(s.first_order,s.rider,1,E'FINAL2 synthetic Rider\nfeedback',gen_random_uuid());
 if v->>'code'<>'SUBMITTED'then raise exception 'Assigned Rider feedback failed';end if;
 v:=public.final2_submit_feedback(s.first_order,s.other_vendor,2,'FINAL2 second Vendor feedback',gen_random_uuid());
 if v->>'code'<>'SUBMITTED'then raise exception 'Second Vendor feedback failed';end if;
 insert into final2_feedback_results values('independent delivered Vendor/Rider ratings commit through real canonical authenticated APIs');
 r:=public.final2_submit_feedback(s.first_order,s.vendor,5,'FINAL2 SQL feedback',s.request);
 if r->>'code'<>'ALREADY_APPLIED'then raise exception 'UUID replay duplicated feedback';end if;
 begin perform public.final2_submit_feedback(s.first_order,s.vendor,1,'changed payload',s.request);raise exception 'Changed replay accepted';exception when sqlstate 'PT409'then null;end;
 r:=public.final2_submit_feedback(s.first_order,s.vendor,1,'different request',gen_random_uuid());
 if r->>'code'<>'ALREADY_REVIEWED'or(r->>'rating')::int<>5 then raise exception 'Duplicate rewrote original rating';end if;
 insert into final2_feedback_results values('same-request replay is idempotent; changed payload conflicts; fresh duplicate returns actual original feedback');
 perform public.final2_submit_feedback(s.second_order,s.vendor,3,'FINAL2 second order',gen_random_uuid());
 perform public.final2_submit_feedback(s.legacy_order,s.vendor,4,'FINAL2 legacy direct order',gen_random_uuid());
 r:=public.final2_rating_summary(s.vendor);
 if(r->>'count')::int<>b.vendor_count+3 or(r->>'average')::numeric<>round((b.vendor_total+12)::numeric/(b.vendor_count+3),2) then raise exception 'Vendor average includes other role or order targets';end if;
 if exists(select 1 from jsonb_array_elements(r->'recent')x where x?'reviewer_id'or x?'order_id'or x?'reviewee_id')then raise exception 'Public review summary leaked private identity';end if;
 r:=public.final2_rating_summary(s.rider);if(r->>'count')::int<>b.rider_count+1 or(r->>'average')::numeric<>round((b.rider_total+1)::numeric/(b.rider_count+1),2) then raise exception 'Rider average incorrect';end if;
 if not exists(select 1 from public.rating_summaries where target_user_id=s.vendor and average_rating=round((b.vendor_total+12)::numeric/(b.vendor_count+3),2)and rating_count=b.vendor_count+3)then
  raise exception 'Public rating RLS incorrectly depends on visibility of unrelated private user profiles';end if;
 if not exists(select 1 from public.get_vendor_ratings(array[s.vendor])where avg_rating=round((b.vendor_total+12)::numeric/(b.vendor_count+3),2)and review_count=b.vendor_count+3)then raise exception 'Legacy Vendor cards aggregate wrong identity/role';end if;
 insert into final2_feedback_results values('exact target averages, legacy direct-order feedback and compatible Vendor card API exclude unrelated/Rider ratings');
 begin
  if exists(select 1 from public.reviews)then raise exception 'Raw private feedback rows became readable';end if;
 exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('public-in-app summary omits reviewer/order identity; raw private review rows stay deny-default');
 perform set_config('final2.feedback_audit_fault','on',true);
 begin perform public.final2_submit_feedback(s.second_order,s.rider,5,'FINAL2 audit fault',gen_random_uuid());raise exception 'Mandatory feedback audit fault ignored';
 exception when raise_exception then if sqlerrm<>'Synthetic feedback audit failure'then raise;end if;end;
 perform set_config('final2.feedback_audit_fault','off',true);
 r:=public.final2_rating_summary(s.rider);
 if(r->>'count')::int<>b.rider_count+1 or(r->>'average')::numeric<>round((b.rider_total+1)::numeric/(b.rider_count+1),2) then raise exception 'Audit fault left partial aggregate';end if;
 insert into final2_feedback_results values('mandatory audit failure atomically rolls back review and aggregate');
 begin update public.rating_summaries set rating_total=5 where target_user_id=s.rider;raise exception 'Client reputation tampering accepted';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('clients cannot modify stored reputation totals');
end$$;
select set_config('request.jwt.claims',__OTHER_CLAIMS__,true);
do $$begin
 begin perform public.final2_feedback_context((select first_order from final2_feedback_state));raise exception 'Other Customer context accepted';exception when insufficient_privilege then null;end;
 begin perform public.final2_submit_feedback((select first_order from final2_feedback_state),__VENDOR_ID__,5,'foreign',gen_random_uuid());raise exception 'Other Customer rating accepted';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('unrelated Customer cannot read owned feedback context or submit against another order');end$$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$begin
 begin perform public.final2_submit_feedback((select first_order from final2_feedback_state),__VENDOR_ID__,5,'self',gen_random_uuid());raise exception 'Vendor self-rating accepted';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('Vendor cannot forge Customer feedback or self-rating');end$$;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$begin
 begin perform public.final2_submit_feedback((select first_order from final2_feedback_state),__VENDOR_ID__,5,'forged',gen_random_uuid());raise exception 'Rider forged feedback accepted';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('Rider cannot forge Customer feedback');end$$;
reset role;
do $$declare s final2_feedback_state;begin
 select *into s from final2_feedback_state;
 if(select count(*)from public.reviews where verified_at is not null and order_id in(s.first_order,s.second_order,s.legacy_order))<>5
  or(select count(*)from public.security_audit_log where action='feedback_submitted'and actor_id=s.customer and target_id in(s.vendor,s.other_vendor,s.rider))<>(select audit_count+5 from final2_feedback_baseline) then raise exception 'Canonical audit or review deduplication incorrect';end if;
 insert into final2_feedback_results values('five committed reviews produce five canonical actor/target audits; retries add none');
 begin update public.reviews set rating=1 where id=s.request;raise exception 'Verified review mutation accepted';exception when insufficient_privilege then null;end;
 begin delete from public.reviews where id=s.request;raise exception 'Verified review deletion accepted';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('verified review history remains immutable even under trusted SQL role');
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='public'and tablename='rating_summaries')
  or exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='public'and tablename='reviews')then raise exception 'Private reviews incorrectly published';end if;
 insert into final2_feedback_results values('only safe aggregate rows join Realtime publication; private review rows stay unpublished');
end$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=(select customer from final2_feedback_state);
set local role authenticated;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$begin
 begin perform public.final2_submit_feedback((select second_order from final2_feedback_state),(select rider from final2_feedback_state),5,'blocked',gen_random_uuid());raise exception 'Blocked feedback accepted';exception when insufficient_privilege then null;end;
 begin perform public.final2_rating_summary(__VENDOR_ID__);raise exception 'Blocked summary accepted';exception when insufficient_privilege then null;end;
 insert into final2_feedback_results values('blocked live Customer cannot submit or read rating summaries');end$$;
reset role;
set local role anon;
do $$begin
 begin perform public.final2_rating_summary(__VENDOR_ID__);raise exception 'Anonymous summary accepted';exception when insufficient_privilege then null;end;
 begin perform public.final2_feedback_context(1);raise exception 'Anonymous context accepted';exception when insufficient_privilege then null;end;
 begin perform public.final2_submit_feedback(1,1,5,'anonymous',gen_random_uuid());raise exception 'Anonymous feedback accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into final2_feedback_results values('anonymous feedback/context/summary APIs denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from final2_feedback_results;
rollback;
