-- Appended to accepted secured checkout/checklist/OTP TEST transaction; rollback.
reset role;
set constraints final_delivery_credit_pay immediate;
do $$declare oid bigint:=(select s.oid from final2_history_state s);q jsonb;e final_delivery_private.rider_earnings;before_count bigint;
 did bigint;admin_id bigint;pid bigint;begin
 select quote into q from final_delivery_private.pay_snapshots where order_id=oid;
 select *into e from final_delivery_private.rider_earnings where order_id=oid;
 if q is null or not(q->>'frozen')::boolean or q->>'distance_method'<>'straight_line'
  or q->>'expected_amount'<>'80'or e.amount<>80 or e.kind<>'DELIVERED'then raise exception 'Frozen amount or OTP earning incorrect';end if;
 insert into final2_history_results values('secured checklist start freezes original distance/rate; actual synthetic verified OTP transaction credits exactly PKR80 after its proof/USED challenge');
 select count(*)into before_count from final_delivery_private.rider_earnings;
 update public.orders set delivered_at=delivered_at where id=oid;
 if(select count(*)from final_delivery_private.rider_earnings)<>before_count
  or(select count(*)from public.security_audit_log where target_id=oid and action='rider_earning_recorded')<>1 then raise exception 'Earning retry duplicated';end if;
 insert into final2_history_results values('repeated terminal writes cannot duplicate one-per-order earning or audit');
 update final_delivery_private.pay_settings set base_amount=999,per_km_rate=999,minimum_amount=999,revision=2 where id=1;
 if(select quote from final_delivery_private.pay_snapshots where order_id=oid)is distinct from q then raise exception 'Frozen quote drift';end if;
 insert into final2_history_results values('later server rate edits cannot rewrite frozen historical pay or distance');
 if exists(select 1 from final_delivery_private.rider_earnings where order_id=(select cancelled from final2_history_state))then raise exception 'Unpicked cancellation credited';end if;
 insert into final2_history_results values('ordinary pre-pickup cancellation earns nothing and old delivered orders are not backfilled');
 begin update final_delivery_private.rider_earnings set amount=0 where order_id=oid;raise exception 'Earning mutable';exception when insufficient_privilege then null;end;
 begin delete from final_delivery_private.pay_snapshots where order_id=oid;raise exception 'Snapshot deletable';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('earnings and frozen calculation evidence are append-only even under trusted SQL');
 if exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='final_delivery_private'and tablename in('pay_snapshots','rider_earnings','earning_reviews'))then raise exception 'Private earning publication';end if;
 insert into final2_history_results values('private pay settings/snapshots/ledgers are protected by RLS, revoked grants and unpublished tables');
 -- Controlled public-table trigger probes remain wholly inside this rollback;
 -- they do not assert actual provider settlement or an end-user dispute journey.
 select id into admin_id from public.users where auth_user_id=(__ADMIN_CLAIMS__::jsonb->>'sub')::uuid;
 select id into pid from public.payments where orderid=oid::text;
 insert into public.disputes(type,status,customer_id,order_id)
  select 'Other','Open',o.user_id,o.id from public.orders o where o.id=oid returning id into did;
 update public.disputes set status='Resolved',decision='RESOLVED',admin_note='Synthetic earnings review rollback',
  decided_by=admin_id,decided_at=clock_timestamp()where id=did;
 if not exists(select 1 from final_delivery_private.earning_reviews where earning_id=e.id and reason='DISPUTE_RESOLVED'and source_id=did)
  or(select amount from final_delivery_private.rider_earnings where id=e.id)<>80 then
  raise exception 'Resolved dispute must flag review without clawback';end if;
 insert into final2_history_results values('synthetic actual public dispute-resolution trigger flags delivered earning for Admin review without changing recorded amount; no refund-settlement claim');
 insert into public.dispute_refund_actions(dispute_id,payment_id,order_id,customer_id,actor_id,amount)
  select did,pid,o.id,o.user_id,admin_id,o.amount from public.orders o where o.id=oid;
 if not exists(select 1 from final_delivery_private.earning_reviews where earning_id=e.id and reason='REFUND_RECORDED')
  or(select amount from final_delivery_private.rider_earnings where id=e.id)<>80 then
  raise exception 'Refund action must flag review without clawback';end if;
 insert into final2_history_results values('synthetic actual refund-action trigger adds Admin review evidence and preserves full delivered earning rather than clawing it back');
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$declare q jsonb;h jsonb;m jsonb;begin
 q:=public.final_delivery_rider_quote((select oid from final2_history_state));
 h:=public.final_delivery_rider_earnings(1);
 m:=public.final2_rider_performance();
 if q->>'expected_amount'<>'80'or not(q->>'frozen')::boolean or h->>'code'<>'OK'
  or(h->>'total_amount')::numeric<80 or h#>>'{entries,0,kind}'<>'delivery'
  or h#>>'{entries,0,distance_method}'<>'straight_line'or not(h->>'earnings_only')::boolean
  or(m->>'earned_fee_cents')::numeric<>(h->>'total_amount')::numeric*100 then raise exception 'Owner earning history incorrect';end if;
 insert into final2_history_results values('own live Rider reads frozen quote, paged itemized earning, exact total and reconciled existing performance without payout simulation');
 if jsonb_typeof(q->'minimum_amount')<>'number'or jsonb_typeof(q->'frozen')<>'boolean'
  or q->>'currency'<>'PKR'or jsonb_typeof(q->'rider_id')<>'number'
  or jsonb_typeof(q->'distance_km')<>'number'or jsonb_typeof(q->'base_amount')<>'number'
  or jsonb_typeof(q->'per_km_rate')<>'number'or jsonb_typeof(q->'expected_amount')<>'number'
  or jsonb_typeof(h->'record_count')<>'number'or jsonb_typeof(h->'total_amount')<>'number'
  or jsonb_typeof(h#>'{entries,0,id}')<>'number'or jsonb_typeof(h#>'{entries,0,earned_at}')<>'string'
  or jsonb_typeof(h#>'{entries,0,admin_review_required}')<>'boolean'then
  raise exception 'Flutter quote or history wire contract invalid';end if;
 insert into final2_history_results values('actual SQL quote/history field types satisfy Flutter parser: numeric amounts and ids, ISO date, boolean frozen/review, PKR currency and minimum');
 begin perform public.final_delivery_rider_earnings(0);raise exception 'Invalid page allowed';exception when invalid_parameter_value then null;end;
 begin perform public.final_delivery_rider_earnings(25,null,__VENDOR_ID__);raise exception 'Foreign earning allowed';exception when insufficient_privilege then null;end;
 begin perform 1 from final_delivery_private.rider_earnings;raise exception 'Raw ledger allowed';exception when insufficient_privilege then null;end;
 begin perform final_delivery_private.calculate_quote(1,1);raise exception 'Private calculation allowed';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('Rider cannot forge target actor, bypass page bounds, read raw earnings or directly invoke private calculation');
end$$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$begin
 begin perform public.final_delivery_rider_earnings();raise exception 'Vendor earning allowed';exception when insufficient_privilege then null;end;
 begin perform public.final_delivery_rider_quote((select oid from final2_history_state));raise exception 'Vendor quote allowed';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('Vendor cannot access Rider private quote or earnings');end$$;
select set_config('request.jwt.claims',__OTHER_CLAIMS__,true);
do $$begin
 begin perform public.final_delivery_rider_earnings();raise exception 'Customer earning allowed';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('Customer cannot access Rider earnings');end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$begin
 begin perform public.final_delivery_rider_earnings();raise exception 'Blocked Rider earning allowed';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('blocked Rider loses private earnings access');end$$;
reset role;
set local role anon;
do $$begin
 begin perform public.final_delivery_rider_earnings();raise exception 'Anon earning allowed';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into final2_history_results values('anonymous earnings denied');
