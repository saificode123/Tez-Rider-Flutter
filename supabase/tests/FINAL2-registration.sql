-- Live authenticated TEST claims are substituted only into an ignored private copy.
-- All inserted application records and decisions are rolled back; Auth fixtures
-- are synthetic accounts prepared separately through the real Auth API.
begin;
-- FINAL2_CANDIDATE
set local role authenticated;
create temporary table final2_results(seq bigint generated always as identity,label text);
create temporary table final2_state(value jsonb);
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true)is not null as claims_set;
do $tests$declare r jsonb;again jsonb;begin
 r:=public.final2_complete_registration(null,null,'vendor',null,null);
 if r->>'code'<>'PROFILE_REQUIRED'then raise exception 'Missing profile accepted';end if;
 insert into final2_results(label)values('missing profile fields remain recoverably incomplete; no success claim');
 begin perform public.final2_complete_registration('FINAL2 TEST ONLY','123456','admin','Store','Street');raise exception 'Admin signup accepted';exception when sqlstate '22023'then null;end;
 insert into final2_results(label)values('self-registration cannot create an Admin');
 begin perform public.final2_complete_registration('FINAL2 TEST ONLY','invalid-phone','vendor','Store','Street');raise exception 'Bad phone accepted';exception when sqlstate '22023'then null;end;
 insert into final2_results(label)values('trusted registration rejects invalid phone');
 r:=public.final2_complete_registration('FINAL2 TEST ONLY','123456','vendor','Store',null);
 if r->>'code'<>'STORE_REQUIRED'then raise exception 'Missing address accepted';end if;
 if exists(select 1 from public.users where auth_user_id=auth.uid())then raise exception 'Incomplete vendor partly persisted';end if;
 insert into final2_results(label)values('missing store address does not partially create a vendor profile');
 r:=public.final2_complete_registration('FINAL2 TEST ONLY','123456','vendor','FINAL2 Store','FINAL2 Synthetic Street');
 if r->>'code'<>'OK'or r->>'role'<>'vendor'or r->>'verification_status'<>'pending'or r->>'store_id'is null then raise exception 'Vendor completion missing';end if;
 insert into final2_state values(r);
 if not exists(select 1 from public.vendors where id=(r->>'store_id')::bigint and user_id=(r->>'id')::bigint and address='FINAL2 Synthetic Street'and is_active=false)then raise exception 'Store not confirmed inactive';end if;
 insert into final2_results(label)values('actual live vendor claim creates one pending profile and persisted inactive store');
 again:=public.final2_complete_registration('Changed metadata','999','admin','Changed store','Changed address');
 if again<>r or(select count(*)from public.vendors where user_id=(r->>'id')::bigint)<>1 then raise exception 'Retry duplicated or escalated';end if;
 insert into final2_results(label)values('registration replay preserves canonical role, original profile/store and identifiers');
 again:=public.final2_complete_registration('Confirmed owner change','999','vendor',null,null,true);
 if again->>'name'<>'Confirmed owner change'or again->>'phone'<>'999'or again->>'role'<>'vendor'then raise exception 'Explicit profile completion not persisted';end if;
 insert into final2_results(label)values('explicit profile completion updates only owned name/phone; metadata-only restoration cannot overwrite them');
 begin perform public.final2_review_vendor((r->>'id')::bigint,'approved',null);raise exception 'Vendor approved itself';exception when insufficient_privilege then null;end;
 insert into final2_results(label)values('pending vendor cannot review or approve itself');
 begin update public.users set verification_status='approved'where id=(r->>'id')::bigint;raise exception 'Direct self approval accepted';exception when insufficient_privilege then null;end;
 insert into final2_results(label)values('direct self approval remains denied');
end$tests$;
select set_config('request.jwt.claims',__ADMIN_CLAIMS__,true)is not null as claims_set;
do $tests$declare v_target bigint:=(select(value->>'id')::bigint from final2_state);r jsonb;begin
 r:=public.final1_review_vendor(v_target,'approved');
 if r->>'verification_status'<>'approved'then raise exception 'Legacy approval regressed';end if;
 perform public.final2_review_vendor(v_target,'approved',null);
 insert into final2_results(label)values('Admin approval and exact replay confirm the existing legacy signature');
 begin perform public.final2_review_vendor(v_target,'rejected',null);raise exception 'Reasonless rejection accepted';exception when sqlstate '22023'then null;end;
 begin perform public.final1_review_vendor(v_target,'rejected');raise exception 'Legacy reason bypass accepted';exception when sqlstate '22023'then null;end;
 insert into final2_results(label)values('new and legacy review APIs cannot introduce a reasonless rejection');
 r:=public.final2_review_vendor(v_target,'rejected','FINAL2 synthetic rejection');
 if r->>'rejection_reason'<>'FINAL2 synthetic rejection'then raise exception 'Reason missing';end if;
 if not exists(select 1 from public.users where users.id=v_target and rejection_reason='FINAL2 synthetic rejection'and verification_status='rejected')then raise exception 'Rejection not persisted';end if;
 if exists(select 1 from public.vendors where user_id=v_target and is_active)then raise exception 'Rejected store active';end if;
 perform public.final2_review_vendor(v_target,'rejected','FINAL2 synthetic rejection');
 insert into final2_results(label)values('reasoned rejection persists and deactivates store; replay is idempotent');
 begin perform public.final2_review_vendor(v_target,'rejected','Changed reason');raise exception 'Silent decision rewrite accepted';exception when sqlstate 'PT409'then null;end;
 insert into final2_results(label)values('changed rejection reason cannot silently rewrite an already-recorded decision');
 r:=public.final2_review_vendor(v_target,'approved',null);
 if r->>'rejection_reason'is not null then raise exception 'Old reason retained';end if;
 insert into final2_results(label)values('subsequent explicit approval clears stale rejection reason');
end$tests$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true)is not null as claims_set;
do $tests$declare r jsonb;begin
 r:=public.final2_complete_registration('FINAL2 customer','123456','customer',null,null);
 if r->>'role'<>'customer'or r->>'verification_status'<>'approved'then raise exception 'Customer registration regressed';end if;
 insert into final2_results(label)values('customer profile completion stays approved without an invented Admin review');
 begin perform public.final2_review_vendor((select(value->>'id')::bigint from final2_state),'approved',null);raise exception 'Customer review accepted';exception when insufficient_privilege then null;end;
 insert into final2_results(label)values('ordinary customer cannot review another account');
 if has_function_privilege('anon','public.final2_complete_registration(text,text,text,text,text,boolean)','execute')or has_function_privilege('anon','public.final2_review_vendor(bigint,text,text)','execute')then raise exception 'Anonymous execute granted';end if;
 insert into final2_results(label)values('anonymous/PUBLIC cannot execute registration or review APIs');
end$tests$;
reset role;
do $accounting$declare v_target bigint:=(select(value->>'id')::bigint from final2_state);begin
 if(select count(*)from public.security_audit_log where target_type='users'and target_id=v_target and action in('vendor_approved','vendor_rejected'))<>3 then raise exception 'Missing/duplicate critical audit';end if;
 if exists(select 1 from public.security_audit_log where target_type='users'and target_id=v_target and action in('vendor_approved','vendor_rejected')and actor_id<>__ADMIN_ID__)then raise exception 'Incorrect audit actor';end if;
 insert into final2_results(label)values('three actual decisions have exactly three canonical Admin actor/target audits');
 if(select count(*)from public.notifications where user_id=v_target)<>3 then raise exception 'Missing/duplicate recipient notice';end if;
 if not exists(select 1 from public.notifications where user_id=v_target and message='FINAL2 synthetic rejection')then raise exception 'Recipient rejection notice missing';end if;
 insert into final2_results(label)values('recipient-only in-app approval/rejection notices created once per actual decision');
end$accounting$;
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','real live-claim SQL; full rollback')order by seq)as results from final2_results;
rollback;
