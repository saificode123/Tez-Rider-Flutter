-- Storage metadata below is a rolled-back SQL fixture, not byte-upload proof.
begin;
create temporary table image_results(label text);
create temporary table image_state(id uuid default gen_random_uuid(),draft uuid default gen_random_uuid(),auth_id uuid,product bigint,legacy bigint,path text,audits bigint);
insert into image_state(auth_id)select auth_user_id from public.users where id=__VENDOR_ID__;
-- A genuinely pre-migration legacy reference must survive unchanged.
-- FINAL2_LEGACY_BEGIN
insert into public.products(vendor_id,name,price,image_url)values(__VENDOR_ID__,'FINAL2 historical image SQL fixture',1,'https://example.invalid/historical.png');
update image_state set legacy=currval(pg_get_serial_sequence('public.products','id'));
-- FINAL2_LEGACY_END
-- FINAL2_CANDIDATE
grant all on image_results,image_state to authenticated,service_role;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$begin
 if public.final2_product_upload_authority()<>__VENDOR_ID__ then raise exception 'Owner upload authority failed';end if;
 begin perform public.final2_product_image_begin(auth.uid(),gen_random_uuid(),repeat('a',64),'image/png',68);raise exception 'Client forge accepted';exception when insufficient_privilege then null;end;
 insert into image_results values('approved owning Vendor authorized; client cannot call trusted upload begin');
end$$;
reset role;
do $$declare s image_state;p text;begin
 select *into s from image_state;
 begin perform public.final2_product_image_begin(s.auth_id,s.id,'bad','image/png',68);raise exception 'Bad digest accepted';exception when invalid_parameter_value then null;end;
 begin perform public.final2_product_image_begin(s.auth_id,s.id,repeat('a',64),'text/html',68);raise exception 'Bad MIME accepted';exception when invalid_parameter_value then null;end;
 begin perform public.final2_product_image_begin(s.auth_id,s.id,repeat('a',64),'image/png',5242881);raise exception 'Oversize accepted';exception when invalid_parameter_value then null;end;
 insert into image_results values('trusted metadata bounds reject invalid digest, MIME and oversize payload');
 p:=public.final2_product_image_begin(s.auth_id,s.id,repeat('a',64),'image/png',68);
 if p<>public.final2_product_image_begin(s.auth_id,s.id,repeat('a',64),'image/png',68)then raise exception 'Retry path changed';end if;
 begin perform public.final2_product_image_begin(s.auth_id,s.id,repeat('b',64),'image/png',68);raise exception 'Changed retry accepted';exception when sqlstate 'PT409'then null;end;
 update image_state set path=p;
 insert into image_results values('immutable owner/UUID upload reservation retries exact bytes and rejects changed payload');
 begin perform public.final2_product_image_finish(s.auth_id,s.id,repeat('a',64),'image/png',68);raise exception 'Missing object accepted';exception when invalid_parameter_value then null;end;
 insert into image_results values('missing Storage object cannot become a completed image');
 insert into storage.objects(bucket_id,name,metadata)values('final2-product-images',p,'{"mimetype":"image/png","size":68}');
 update image_state set audits=(select count(*)from public.security_audit_log where actor_id=__VENDOR_ID__ and action='product_image_uploaded');
 if public.final2_product_image_finish(s.auth_id,s.id,repeat('a',64),'image/png',68)<>'tezproduct:'||s.id then raise exception 'Reference invalid';end if;
 perform public.final2_product_image_finish(s.auth_id,s.id,repeat('a',64),'image/png',68);
 if(select count(*)from public.security_audit_log where actor_id=__VENDOR_ID__ and action='product_image_uploaded')<>(select audits+1 from image_state)then raise exception 'Audit not exact once';end if;
 insert into image_results values('confirmed Storage metadata completes exactly one canonical owner audit; identical finish adds none');
 perform public.final2_product_image_begin(s.auth_id,s.draft,repeat('b',64),'image/png',68);
end$$;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare s image_state;r jsonb;begin
 select *into s from image_state;
 if public.final2_product_image_view(s.id)->>'path'<>s.path then raise exception 'Owner preview missing';end if;
 begin perform public.final2_product_image_view(s.draft);raise exception 'Unfinished image accepted';exception when insufficient_privilege then null;end;
 insert into image_results values('owner previews only completed image; unfinished reservation cannot be viewed');
 r:=public.fr17_save_product(gen_random_uuid(),null,jsonb_build_object('name','FINAL2 validated image SQL fixture','price',1,'image_url','tezproduct:'||s.id),2,0,null);
 if r->>'code'<>'UPDATED'then raise exception 'Real product save failed';end if;
 update image_state set product=(r->>'product_id')::bigint;
 begin perform public.fr17_save_product(gen_random_uuid(),(r->>'product_id')::bigint,'{"name":"FORGED","price":1,"image_url":"https://example.invalid/unvalidated.png"}',2,0,1);raise exception 'Arbitrary URL accepted';exception when invalid_parameter_value then null;end;
 insert into image_results values('own validated image attaches via real product API; arbitrary new URL rejected server-side');
 r:=public.fr17_save_product(gen_random_uuid(),s.legacy,'{"name":"FINAL2 legacy preserved","price":1,"image_url":"https://example.invalid/historical.png"}',0,0,0);
 if r->>'code'<>'UPDATED'then raise exception 'Legacy unchanged edit broken';end if;
 insert into image_results values('existing legitimate legacy image reference survives unchanged owner product edit');
 begin perform 1 from final2_private.product_images;raise exception 'Ledger leak';exception when insufficient_privilege then null;end;
 begin perform public.final2_product_image_finish(auth.uid(),s.id,repeat('a',64),'image/png',68);raise exception 'Client finish forge';exception when insufficient_privilege then null;end;
 if exists(select 1 from storage.objects where bucket_id='final2-product-images')then raise exception 'Raw Storage listing leaked';end if;
 insert into image_results values('private ledger and trusted finish deny clients; raw object listing reveals no product object');
end$$;
select set_config('request.jwt.claims',__OTHER_VENDOR_CLAIMS__,true);
do $$declare s image_state;begin
 select *into s from image_state;
 begin perform public.fr17_save_product(gen_random_uuid(),null,jsonb_build_object('name','FORGED foreign image','price',1,'image_url','tezproduct:'||s.id),1,0,null);raise exception 'Foreign image adopted';exception when invalid_parameter_value then null;end;
 insert into image_results values('another Vendor cannot adopt an owned validated image into its own listing');
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$declare s image_state;begin
 select *into s from image_state;
 begin perform public.final2_product_upload_authority();raise exception 'Customer uploader accepted';exception when insufficient_privilege then null;end;
 if public.final2_product_image_view(s.id)->>'path'<>s.path then raise exception 'Customer catalogue image denied';end if;
 begin perform public.final2_product_image_view(s.draft);raise exception 'Foreign draft leaked';exception when insufficient_privilege then null;end;
 insert into image_results values('approved Customer sees published commercial product image, never foreign draft; upload authority denied');
end$$;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$declare s image_state;r jsonb;begin
 select *into s from image_state;
 r:=public.fr17_save_product(gen_random_uuid(),s.product,'{"name":"FINAL2 image cleared","price":1,"image_url":""}',0,0,(select stock_version from public.products where id=s.product));
 if r->>'code'<>'UPDATED'then raise exception 'Clear failed';end if;
end$$;
select set_config('request.jwt.claims',__CUSTOMER_CLAIMS__,true);
do $$begin
 begin perform public.final2_product_image_view((select id from image_state));raise exception 'Unreferenced image leaked';exception when insufficient_privilege then null;end;
 insert into image_results values('clearing the product reference removes Customer image authority without deleting historical objects');
end$$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.users set is_blocked=true where id=__VENDOR_ID__;
set local role authenticated;
select set_config('request.jwt.claims',__VENDOR_CLAIMS__,true);
do $$begin
 begin perform public.final2_product_upload_authority();raise exception 'Blocked uploader accepted';exception when insufficient_privilege then null;end;
 begin perform public.final2_product_image_view((select id from image_state));raise exception 'Blocked owner view accepted';exception when insufficient_privilege then null;end;
 insert into image_results values('blocked Vendor loses upload and owned-image viewing authority');
end$$;
reset role;
do $$begin
 if(select public from storage.buckets where id='final2-product-images')then raise exception 'Public bucket';end if;
 if exists(select 1 from pg_publication_tables where schemaname='final2_private'and tablename='product_images')then raise exception 'Ledger published';end if;
 insert into image_results values('dedicated bucket remains private and image ledger is unpublished');
end$$;
set local role anon;
do $$begin
 begin perform public.final2_product_upload_authority();raise exception 'Anonymous authority accepted';exception when insufficient_privilege then null;end;
 begin perform public.final2_product_image_view(gen_random_uuid());raise exception 'Anonymous view accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into image_results values('anonymous upload and view APIs denied');
select jsonb_agg(jsonb_build_object('check',label,'result','PASS','surface','authenticated TEST SQL rollback'))as results from image_results;
rollback;
