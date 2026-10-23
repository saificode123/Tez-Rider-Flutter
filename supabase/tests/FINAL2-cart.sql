begin;
-- FINAL2_CANDIDATE
set local role authenticated;
create temporary table final2_cart_results(label text);
create temporary table final2_cart_state(product_id bigint,revision bigint,request_id uuid,items jsonb);
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $test$declare r jsonb;begin
 r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FINAL2 cart rollback product","price":25.75,"category":"Food"}',5,1,null);
 if r->>'code'<>'UPDATED'then raise exception 'Fixture write denied';end if;
 insert into final2_cart_state(product_id)values((r->>'product_id')::bigint);
 begin perform public.final2_cart_get();raise exception 'Vendor cart access allowed';exception when insufficient_privilege then null;end;
 insert into final2_cart_results values('vendor cannot use customer cart APIs');
end$test$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $test$declare r jsonb;before jsonb;payload jsonb;request uuid:=gen_random_uuid();revision bigint;begin
 before:=public.final2_cart_get();revision:=(before->>'revision')::bigint;
 payload:=jsonb_build_array(jsonb_build_object('product_id',(select product_id from final2_cart_state),'qty',2));
 r:=public.final2_cart_replace(revision,request,payload);
 if r->>'code'<>'OK'or(r->>'revision')::bigint<>revision+1 or jsonb_array_length(r->'items')<>1
  or(r->'items'->0->>'price')::numeric<>25.75 or(r->'items'->0->>'qty')::integer<>2 then raise exception 'Persistence not confirmed';end if;
 insert into final2_cart_results values('customer saves canonical fractional price and quantity; caller cannot supply identity or price');
 update final2_cart_state set revision=(r->>'revision')::bigint,request_id=request,items=payload;
 r:=public.final2_cart_get();
 if jsonb_array_length(r->'items')<>1 then raise exception 'Restoration missing';end if;
 insert into final2_cart_results values('separate cart read restores actual persisted rows');
 r:=public.final2_cart_replace(revision,request,payload);
 if r->>'code'<>'ALREADY_APPLIED'or(r->>'revision')::bigint<>revision+1 then raise exception 'Replay incremented revision';end if;
 insert into final2_cart_results values('uncertain-result retry preserves request UUID, payload and revision exactly once');
 begin perform public.final2_cart_replace(revision,request,'[]');raise exception 'Request payload changed';exception when sqlstate 'PT409'then null;end;
 insert into final2_cart_results values('same UUID cannot be rebound to a different payload');
 r:=public.final2_cart_replace(revision,gen_random_uuid(),'[]');
 if r->>'code'<>'CART_CHANGED'or jsonb_array_length(r->'items')<>1 then raise exception 'Stale device overwrote cart';end if;
 insert into final2_cart_results values('stale concurrent device receives current cart instead of overwriting it');
 begin perform public.final2_cart_replace(revision+1,gen_random_uuid(),jsonb_build_array(payload->0,payload->0));raise exception 'Duplicate product';exception when sqlstate '22023'then null;end;
 begin perform public.final2_cart_replace(revision+1,gen_random_uuid(),jsonb_build_array((payload->0)||'{"price":0}'));raise exception 'Client price accepted';exception when sqlstate '22023'then null;end;
 begin perform public.final2_cart_replace(revision+1,gen_random_uuid(),jsonb_build_array((payload->0)||'{"qty":101}'));raise exception 'Oversized quantity';exception when sqlstate '22023'then null;end;
 insert into final2_cart_results values('duplicate products, untrusted fields and invalid quantities rejected before replacement');
 r:=public.final2_cart_replace(revision+1,gen_random_uuid(),jsonb_build_array((payload->0)||'{"qty":6}'));
 if r->>'code'<>'UNAVAILABLE'or(r->>'revision')::bigint<>revision+1 then raise exception 'Insufficient stock partly persisted';end if;
 insert into final2_cart_results values('insufficient stock leaves prior saved cart and revision unchanged');
 begin delete from public.cart_items where user_id=auth.uid();raise exception 'Direct delete bypass';exception when insufficient_privilege then null;end;
 insert into final2_cart_results values('direct cart mutation denied; revision protocol cannot be bypassed');
end$test$;
select set_config('request.jwt.claims',__OTHER_CLAIMS__,true);
do $test$begin
 if exists(select 1 from jsonb_array_elements(public.final2_cart_get()->'items')i where i->>'product_id'=(select product_id::text from final2_cart_state))then raise exception 'Other customer saw cart';end if;
 insert into final2_cart_results values('distinct authenticated customer cannot observe another saved cart');
end$test$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $test$declare r jsonb;begin
 r:=public.final2_cart_replace((select revision from final2_cart_state),gen_random_uuid(),'[]');
 if r->>'code'<>'OK'or jsonb_array_length(public.final2_cart_get()->'items')<>0 then raise exception 'Clear not persisted';end if;
 insert into final2_cart_results values('explicit clear removes only the current customer cart and is restorable');
end$test$;
reset role;
set local role anon;
do $test$begin
 begin perform public.final2_cart_get();raise exception 'Anonymous cart allowed';exception when insufficient_privilege then null;end;
 begin perform public.final2_cart_replace(0,gen_random_uuid(),'[]');raise exception 'Anonymous write allowed';exception when insufficient_privilege then null;end;
end$test$;
reset role;
insert into final2_cart_results values('anonymous cart APIs denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from final2_cart_results;
rollback;
