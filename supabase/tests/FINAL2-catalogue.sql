-- Candidate review and deployed regression run inside one rolled-back transaction.
begin;
-- FINAL2_CANDIDATE
set local role authenticated;
create temporary table final2_catalog_results(label text);
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $test$declare r jsonb;begin
 for n in 1..3 loop
  r:=public.fr17_save_product(gen_random_uuid(),null,jsonb_build_object('name','FINAL2 Catalogue '||n,
   'description','literal,*() keyword','price',25,'category',case when n=3 then 'FINAL2 Books'else 'FINAL2 Food'end),5,1,null);
  if r->>'code'<>'UPDATED'then raise exception 'Fixture write failed';end if;
 end loop;
 insert into final2_catalog_results values('approved vendor creates actual inventory through retained FR17 API');
end$test$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $test$declare a jsonb;b jsonb;begin
 a:=public.final2_catalog('FINAL2 Catalogue',null,null,2);
 if jsonb_array_length(a->'items')<>2 or not(a->>'has_more')::boolean then raise exception 'First page wrong';end if;
 b:=public.final2_catalog('FINAL2 Catalogue',null,a->'next_cursor',2);
 if jsonb_array_length(b->'items')<>1 or(b->>'has_more')::boolean or b->'items'->0->>'id'=a->'items'->1->>'id'then raise exception 'Next page wrong';end if;
 insert into final2_catalog_results values('customer keyset pages return all matching rows without overlap');
 a:=public.final2_catalog('literal,*()',null,null,40);
 if jsonb_array_length(a->'items')<>3 then raise exception 'Literal query interpreted as filter';end if;
 insert into final2_catalog_results values('punctuation is literal keyword data');
 a:=public.final2_catalog('', ' final2 books ',null,40);
 if jsonb_array_length(a->'items')<>1 then raise exception 'Category wrong';end if;
 a:=public.final2_catalog('', 'FINAL2 Book',null,40);
 if jsonb_array_length(a->'items')<>0 then raise exception 'Category substring accepted';end if;
 insert into final2_catalog_results values('exact normalized server category filtering independent of first page');
 if not exists(select 1 from public.final2_catalog_categories()where name='FINAL2 Books')then raise exception 'Category missing';end if;
 insert into final2_catalog_results values('categories include real visible inventory labels');
 begin perform public.final2_catalog(repeat('a',121));raise exception 'Unbounded query';exception when sqlstate '22023'then null;end;
 begin perform public.final2_catalog('',null,null,101);raise exception 'Unbounded page';exception when sqlstate '22023'then null;end;
 begin perform public.final2_catalog('',null,'{"id":1,"name":"x","extra":true}',1);raise exception 'Unknown cursor key';exception when sqlstate '22023'then null;end;
 begin perform public.final2_catalog('',null,'{"id":9999999999999999999,"name":"x"}',1);raise exception 'Overflow cursor';exception when sqlstate '22023'then null;end;
 insert into final2_catalog_results values('server rejects oversized query/page and malformed/overflow cursor');
end$test$;
select set_config('request.jwt.claims',__ADMIN_CLAIMS__,true);
select public.final2_review_vendor(__VENDOR_ID__,'rejected','FINAL2 rolled-back catalogue security test');
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $test$begin
 if jsonb_array_length(public.final2_catalog('FINAL2 Catalogue')->'items')<>0 then raise exception 'Rejected merchant visible';end if;
 if exists(select 1 from public.products where name like 'FINAL2 Catalogue %')then raise exception 'Direct REST product policy bypass';end if;
 if exists(select 1 from public.final2_catalog_categories()where name like 'FINAL2 %')then raise exception 'Rejected inventory category leaked';end if;
 insert into final2_catalog_results values('rejected merchant disappears from catalogue, category projection and direct product SELECT');
end$test$;
reset role;
set local role anon;
do $test$begin
 begin perform public.final2_catalog();raise exception 'Anonymous catalogue accepted';exception when insufficient_privilege then null;end;
 begin perform public.final2_catalog_categories();raise exception 'Anonymous categories accepted';exception when insufficient_privilege then null;end;
end$test$;
reset role;
insert into final2_catalog_results values('anonymous catalogue APIs denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback')) as results from final2_catalog_results;
rollback;
