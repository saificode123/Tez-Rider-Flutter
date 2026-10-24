-- Appended to the actual secured checkout/checklist/OTP rollback regression.
reset role;
create temporary table metrics_other_identity as select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid;
grant select on metrics_other_identity to authenticated;
do $$declare rid bigint;oid bigint:=(select s.oid from final2_history_state s);m final2_private.rider_performance;d final2_private.rider_delivery_metrics;begin
 select rider_id into rid from public.orders where id=oid;
 select *into d from final2_private.rider_delivery_metrics where order_id=oid;
 if d.order_id is null or d.rider_id<>rid or d.duration_seconds is null or d.duration_seconds<0
  or d.earned_fee_cents is not null or d.fee_status<>'POLICY_REQUIRED'then raise exception 'Completion metrics or unknown fee incorrect';end if;
 insert into final2_history_results values('secured synthetic OTP completion records one real assigned Rider delivery with measured nonnegative duration and unknown fee; no financial transfer');
 update public.orders set delivered_at=delivered_at where id=oid;
 if(select count(*)from final2_private.rider_delivery_metrics where order_id=oid)<>1
  or(select count(*)from public.security_audit_log where target_id=oid and target_type='orders'and action='rider_metrics_recorded')<>1 then raise exception 'Duplicate delivery metrics/audit';end if;
 insert into final2_history_results values('repeated terminal updates cannot duplicate completed metrics or the canonical Rider audit');
 select *into m from final2_private.rider_performance where rider_id=rid;
 if m.accepted_assignments<>(select count(*)from final2_private.rider_assignment_starts where rider_id=rid)
  or m.completed_deliveries<>(select count(*)from final2_private.rider_delivery_metrics where rider_id=rid)
  or m.timed_deliveries<>(select count(duration_seconds)from final2_private.rider_delivery_metrics where rider_id=rid)
  or m.completion_rate<>round(100.0*m.completed_deliveries/m.accepted_assignments,2)then raise exception 'Stored performance drift';end if;
 insert into final2_history_results values('stored counts/rate and timed sample exactly reconcile to accepted assignment and confirmed delivery ledgers');
 if exists(select 1 from final2_private.rider_delivery_metrics where order_id=(select cancelled from final2_history_state))then raise exception 'Cancelled delivery earned credit';end if;
 insert into final2_history_results values('real cancellation cannot produce delivered performance or invented earned compensation');
 if exists(select 1 from final2_private.rider_assignment_starts where history_limited and accepted_at is not null)
  or exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='final2_private'and tablename like 'rider_%')then raise exception 'Historical time fabricated or private metrics published';end if;
 insert into final2_history_results values('legacy accepted timestamps remain unknown and private performance ledgers are not publicly published');
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.final2_rider_performance();
 if r->>'code'<>'OK'or(r->>'completed_deliveries')::bigint<1 or r->>'earned_fee_cents'is not null
  or r->>'average_duration_seconds'is null then raise exception 'Owned Rider metrics unavailable';end if;
 begin perform public.final2_rider_performance((select id from metrics_other_identity));raise exception 'Foreign metrics permitted';exception when insufficient_privilege then null;end;
 begin perform 1 from final2_private.rider_performance;raise exception 'Raw private metrics permitted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('live approved Rider can read own stored performance but cannot use another identity or raw private ledger');
end$$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$begin begin perform public.final2_rider_performance();raise exception 'Vendor performance impersonation';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('Vendor cannot access the private Rider performance endpoint');end$$;
select set_config('request.jwt.claims',__OTHER_CLAIMS__,true);
do $$begin begin perform public.final2_rider_performance();raise exception 'Customer performance impersonation';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('Customer cannot access the private Rider performance endpoint');end$$;
select set_config('request.jwt.claims',__ADMIN_CLAIMS__,true);
do $$declare r jsonb;begin
 r:=public.final2_rider_performance((select rider_id from public.orders where id=(select oid from final2_history_state)));
 if r->>'code'<>'OK'then raise exception 'Admin authorized monitoring failed';end if;
 insert into final2_history_results values('approved Admin can inspect the selected Rider without exposing private ledgers');end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where auth_user_id=(__RIDER_CLAIMS__::jsonb->>'sub')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',__RIDER_CLAIMS__,true);
do $$begin begin perform public.final2_rider_performance();raise exception 'Blocked Rider read permitted';exception when insufficient_privilege then null;end;
 insert into final2_history_results values('blocked Rider loses private performance access');end$$;
reset role;
set local role anon;
do $$begin begin perform public.final2_rider_performance();raise exception 'Anonymous performance read permitted';exception when insufficient_privilege then null;end;end$$;
reset role;
insert into final2_history_results values('anonymous performance endpoint denied');
