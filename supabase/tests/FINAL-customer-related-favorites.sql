begin;
set local statement_timeout='60s';
create function pg_temp.related_ok(ok boolean,label text)returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Related Favorites test failed: %',label;end if;
end$$;
do $$declare owner_claims text;foreign_claims text;v bigint;r bigint;targets jsonb;page jsonb;receipt jsonb;fid uuid;begin
 select jsonb_build_object('sub',u.auth_user_id,'role','authenticated','session_id',s.id)::text,o.vendor_id,o.rider_id into owner_claims,v,r
 from public.orders o join public.users u on u.id=o.user_id join lateral(select id from auth.sessions where user_id=u.auth_user_id order by created_at desc limit 1)s on true
 where o.id=3180 and o.order_status='delivered';
 if v is null then select vendor_id into v from public.vendor_orders where order_id=3180 order by id limit 1;end if;
 perform pg_temp.related_ok(owner_claims is not null and v is not null and r is not null,'existing real delivered-order relationships retained');
 perform set_config('request.jwt.claims',owner_claims,true);
 targets:=public.final_customer_order_favorite_targets(3180);
 perform pg_temp.related_ok(jsonb_array_length(targets->'items')=2,'only recorded Vendor and delivered Rider returned');
 perform public.final_customer_set_related_favorite(v,'vendor',true);
 perform public.final_customer_set_related_favorite(v,'vendor',true);
 perform public.final_customer_set_related_favorite(r,'rider',true);
 perform pg_temp.related_ok((select count(*)=2 from public.favorites where user_id=auth.uid()),'duplicate intent creates one favorite per target');
 page:=public.final_customer_related_favorites(null,null,1);
 perform pg_temp.related_ok(jsonb_array_length(page->'items')=1 and(page->>'has_more')::boolean,'keyset paging is bounded');
 fid:=(page->'items'->0->>'id')::uuid;
 perform pg_temp.related_ok(jsonb_array_length(public.final_customer_related_favorites((page->>'cursor_at')::timestamptz,(page->>'cursor_id')::uuid,1)->'items')=1,'next page preserves other favorite');
 select jsonb_build_object('sub',u.auth_user_id,'role','authenticated','session_id',s.id)::text into foreign_claims
 from public.users u join lateral(select id from auth.sessions where user_id=u.auth_user_id order by created_at desc limit 1)s on true where u.email='fr25-customer-a@example.test';
 perform set_config('request.jwt.claims',foreign_claims,true);
 perform pg_temp.related_ok(jsonb_array_length(public.final_customer_related_favorites()->'items')=0,'unrelated Customer cannot read owner favorites');
 begin perform public.final_customer_order_favorite_targets(3180);raise exception 'Foreign order exposed';exception when insufficient_privilege then null;end;
 begin perform public.final_customer_set_related_favorite(r,'rider',true);raise exception 'Unrelated Rider relation accepted';exception when insufficient_privilege then null;end;
 perform public.final_customer_remove_related_favorite(fid);
 perform set_config('request.jwt.claims',owner_claims,true);
 perform pg_temp.related_ok(jsonb_array_length(public.final_customer_related_favorites()->'items')=2,'foreign removal has no effect');
 perform public.final_customer_set_related_favorite(v,'vendor',false);
 perform public.final_customer_set_related_favorite(r,'rider',false);
 perform pg_temp.related_ok(jsonb_array_length(public.final_customer_related_favorites()->'items')=0,'owner removes confirmed favorites');
end$$;
set local role anon;
do $$begin
 begin perform public.final_customer_related_favorites();raise exception 'Anonymous RPC access accepted';exception when insufficient_privilege then null;end;
 begin perform count(*)from public.favorites;raise exception 'Anonymous table read accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;
select 'PASS: history scope, unique intent, paging, owner/foreign access and anonymous denials; rollback only' as result;
rollback;
