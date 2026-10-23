begin;
-- FINAL2_CANDIDATE
create temporary table final2_delete_results(label text);
create temporary table final2_delete_state(product_id bigint,version bigint,request uuid);
create temporary table final2_in_use(product_id bigint,version bigint);
grant all on final2_delete_results,final2_delete_state to authenticated;
grant all on final2_in_use to authenticated;
create function pg_temp.fail_delete_audit()returns trigger language plpgsql as $$begin
 if new.action='product_deleted'and current_setting('final2.delete_audit_failure',true)='on'then raise exception 'Synthetic audit failure';end if;
 return new;end$$;
create trigger final2_delete_test_audit before insert on public.security_audit_log for each row execute function pg_temp.fail_delete_audit();
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $test$declare r jsonb;req uuid:=gen_random_uuid();begin
 r:=public.fr17_save_product(req,null,'{"name":"FINAL2 rolled-back delete","price":1}',1,0,null);
 if r->>'code'<>'UPDATED'then raise exception 'Product creation denied';end if;
 insert into final2_delete_state values((r->>'product_id')::bigint,(r->>'stock_version')::bigint,req);
 r:=public.final2_delete_product((r->>'product_id')::bigint,(r->>'stock_version')::bigint+1);
 if r->>'code'<>'VERSION_CHANGED'then raise exception 'Stale count version not protected';end if;
 insert into final2_delete_results values('stale product snapshot cannot delete a newer stock version');
end$test$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $test$begin
 begin perform public.final2_delete_product((select product_id from final2_delete_state),1);raise exception 'Customer deleted Vendor product';exception when insufficient_privilege then null;end;
 insert into final2_delete_results values('authenticated customer cannot invoke owning Vendor deletion');
end$test$;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
do $test$begin
 begin perform public.final2_delete_product((select product_id from final2_delete_state),1);raise exception 'Unrelated Vendor deleted product';exception when insufficient_privilege then null;end;
 insert into final2_delete_results values('distinct authenticated Vendor cannot delete another Vendor product');
end$test$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $test$declare r jsonb;pid bigint:=(select product_id from final2_delete_state);v bigint:=(select version from final2_delete_state);failed boolean:=false;begin
 begin delete from public.products where id=pid;raise exception 'Direct DELETE grant relaxed';exception when insufficient_privilege then null;end;
 insert into final2_delete_results values('direct product DELETE remains denied; no broad grants restored');
 perform set_config('final2.delete_audit_failure','on',true);
 begin perform public.final2_delete_product(pid,v);exception when raise_exception then failed:=true;end;
 perform set_config('final2.delete_audit_failure','off',true);
 if not failed or not exists(select 1 from public.products where id=pid)then raise exception 'Audit failure partly deleted product';end if;
 insert into final2_delete_results values('mandatory audit failure rolls back deletion and preserves product/ledger');
 r:=public.final2_delete_product(pid,v);
 if r->>'code'<>'DELETED'or(r->>'product_id')::bigint<>pid or exists(select 1 from public.products where id=pid)then raise exception 'Deletion not confirmed';end if;
 insert into final2_delete_results values('approved owning Vendor RPC returns actual deleted ID and record is absent');
 if not exists(select 1 from public.inventory_movements where product_id=pid and request_id=(select request from final2_delete_state))then raise exception 'Inventory history removed';end if;
 insert into final2_delete_results values('unsold listing removal preserves immutable inventory movement history');
 r:=public.final2_delete_product(pid,v);
 if r->>'code'<>'NOT_FOUND'then raise exception 'Replay falsely claims deletion';end if;
 insert into final2_delete_results values('repeated deletion reports NOT_FOUND rather than fabricated success');
 r:=public.fr17_save_product(gen_random_uuid(),null,'{"name":"FINAL2 referenced product","price":1}',1,0,null);
 if r->>'code'<>'UPDATED'then raise exception 'Referenced product fixture failed';end if;
 insert into final2_in_use values((r->>'product_id')::bigint,(r->>'stock_version')::bigint);
end$test$;
reset role;
do $test$declare oid bigint;vid bigint;begin
 insert into public.orders(user_id,vendor_id,amount,fare,order_status,payment_method,delivery_address)
 values((select id from public.users where auth_user_id=(__CUSTOMER_CLAIMS__::jsonb->>'sub')::uuid),__VENDOR_ID__,1,0,'pending','COD','FINAL2 SQL fixture only')returning id into oid;
 insert into public.vendor_orders(order_id,vendor_id,sub_total,status)values(oid,__VENDOR_ID__,1,'pending')returning id into vid;
 insert into public.order_items(vendor_order_id,product_id,quantity,price_at_time)values(vid,(select product_id from final2_in_use),1,1);
end$test$;
set local role authenticated;
do $test$declare r jsonb;begin
 r:=public.final2_delete_product((select product_id from final2_in_use),(select version from final2_in_use));
 if r->>'code'<>'PRODUCT_IN_USE'or not exists(select 1 from public.products where id=(select product_id from final2_in_use))then raise exception 'Order-linked product not protected';end if;
 insert into final2_delete_results values('referenced product and order history remain intact; API reports PRODUCT_IN_USE');
end$test$;
reset role;
do $test$begin
 if(select count(*)from public.security_audit_log where action='product_deleted'and target_type='product'and target_id=(select product_id from final2_delete_state)
  and actor_id=__VENDOR_ID__)<>1 then raise exception 'Audit actor or count invalid';end if;
 insert into final2_delete_results values('exactly one product deletion audit records the canonical owning actor');
end$test$;
set local role anon;
do $test$begin
 begin perform public.final2_delete_product(1,0);raise exception 'Anonymous delete allowed';exception when insufficient_privilege then null;end;
end$test$;
reset role;
insert into final2_delete_results values('anonymous product deletion API denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from final2_delete_results;
rollback;
