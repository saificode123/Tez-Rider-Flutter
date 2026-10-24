-- Validated product images. References are not credentials or expiring URLs.
begin;
set local lock_timeout='5s';
create table final2_private.product_images(
 id uuid primary key, owner_id bigint not null references public.users(id),
 auth_id uuid not null, path text not null unique,
 digest text not null check(digest~'^[0-9a-f]{64}$'),
 mime text not null check(mime in('image/jpeg','image/png')),
 size integer not null check(size between 1 and 5242880),
 uploaded boolean not null default false, created_at timestamptz not null default clock_timestamp()
);
alter table final2_private.product_images enable row level security;
revoke all on final2_private.product_images from public,anon,authenticated,service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('final2-product-images','final2-product-images',false,5242880,array['image/jpeg','image/png']);
-- Restrictive boundaries also protect this bucket from older permissive policies.
create policy final2_product_objects_private on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'final2-product-images')with check(bucket_id<>'final2-product-images');

create function public.final2_product_upload_authority()returns bigint
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();begin
 if public.fr21_role()is distinct from'vendor'or not exists(select 1 from public.users u
 join auth.users a on a.id=u.auth_user_id where u.id=actor and not u.is_blocked
 and u.verification_status='approved'and a.email_confirmed_at is not null)then
 raise exception 'Approved Vendor required'using errcode='42501';end if;
 return actor;end$$;
revoke all on function public.final2_product_upload_authority()from public,anon;
grant execute on function public.final2_product_upload_authority()to authenticated;

create function public.final2_product_image_begin(p_auth_id uuid,p_request_id uuid,p_digest text,p_mime text,p_size integer)
returns text language plpgsql security definer set search_path=''as $$
declare actor bigint;image final2_private.product_images;begin
 select u.id into actor from public.users u join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=p_auth_id and u.role='vendor'and not u.is_blocked
 and u.verification_status='approved'and a.email_confirmed_at is not null for no key update of u;
 if actor is null then raise exception 'Approved Vendor required'using errcode='42501';end if;
 if p_request_id is null or p_request_id::text!~'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
 or p_digest is null or p_digest!~'^[0-9a-f]{64}$'or p_mime is null or p_mime not in('image/jpeg','image/png')
 or p_size is null or p_size not between 1 and 5242880 then raise exception 'Invalid image'using errcode='22023';end if;
 insert into final2_private.product_images(id,owner_id,auth_id,path,digest,mime,size)
 values(p_request_id,actor,p_auth_id,p_auth_id||'/'||p_request_id||case when p_mime='image/png'then'.png'else'.jpg'end,p_digest,p_mime,p_size)
 on conflict(id)do nothing;
 select *into image from final2_private.product_images where id=p_request_id for update;
 if image.auth_id is distinct from p_auth_id then raise exception 'Image access forbidden'using errcode='42501';end if;
 if image.digest<>p_digest or image.mime<>p_mime or image.size<>p_size then
 raise exception 'Retry the original image submission'using errcode='PT409';end if;
 return image.path;end$$;
revoke all on function public.final2_product_image_begin(uuid,uuid,text,text,integer)from public,anon,authenticated;
grant execute on function public.final2_product_image_begin(uuid,uuid,text,text,integer)to service_role;

create function public.final2_product_image_finish(p_auth_id uuid,p_request_id uuid,p_digest text,p_mime text,p_size integer)
returns text language plpgsql security definer set search_path=''as $$
declare image final2_private.product_images;object storage.objects;path text;begin
 path:=public.final2_product_image_begin(p_auth_id,p_request_id,p_digest,p_mime,p_size);
 select *into image from final2_private.product_images where id=p_request_id for update;
 select *into object from storage.objects where bucket_id='final2-product-images'and name=path;
 if object.id is null or object.metadata->>'mimetype'is distinct from p_mime
 or(object.metadata->>'size')::bigint is distinct from p_size::bigint then
 raise exception 'Validated upload was not confirmed'using errcode='22023';end if;
 if not image.uploaded then
 update final2_private.product_images set uploaded=true where id=p_request_id;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)
 values(image.owner_id,'product_image_uploaded','users',image.owner_id);
 end if;
 return 'tezproduct:'||image.id;end$$;
revoke all on function public.final2_product_image_finish(uuid,uuid,text,text,integer)from public,anon,authenticated;
grant execute on function public.final2_product_image_finish(uuid,uuid,text,text,integer)to service_role;

create function public.final2_product_image_view(p_image_id uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();image final2_private.product_images;begin
 if actor is null or not exists(select 1 from public.users where id=actor and not is_blocked and verification_status='approved')then
 raise exception 'Approved account required'using errcode='42501';end if;
 select *into image from final2_private.product_images where id=p_image_id and uploaded;
 if image.id is null or not(image.owner_id=actor or exists(select 1 from public.products p
 where p.image_url='tezproduct:'||image.id and p.vendor_id=image.owner_id
 and public.final2_catalog_vendor_visible(p.vendor_id)))then
 raise exception 'Image access forbidden'using errcode='42501';end if;
 return jsonb_build_object('path',image.path,'mime',image.mime,'size',image.size,'digest',image.digest);end$$;
revoke all on function public.final2_product_image_view(uuid)from public,anon;
grant execute on function public.final2_product_image_view(uuid)to authenticated;

create function final2_private.product_image_guard()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if tg_op='UPDATE'and new.image_url is not distinct from old.image_url and new.vendor_id=old.vendor_id then return new;end if;
 if nullif(btrim(new.image_url),'')is null then return new;end if;
 if not exists(select 1 from final2_private.product_images i where 'tezproduct:'||i.id=new.image_url
 and i.owner_id=new.vendor_id and i.uploaded)then
 raise exception 'Use a validated product image upload'using errcode='22023';end if;
 return new;end$$;
revoke all on function final2_private.product_image_guard()from public,anon,authenticated,service_role;
create trigger final2_product_image_guard before insert or update of image_url,vendor_id on public.products
 for each row execute function final2_private.product_image_guard();
-- Retain the accepted inventory, version, ownership and retry implementation.
-- The table trigger now validates completed upload references instead of the
-- previous blanket refusal of every new image.
CREATE OR REPLACE FUNCTION public.fr17_save_product(p_request_id uuid, p_product_id bigint, p_data jsonb, p_stock integer, p_threshold integer, p_expected_version bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor bigint:=public.fr21_actor();p public.products;m public.inventory_movements;payload jsonb;result jsonb;v_price numeric;begin
 if actor is null or public.fr21_role()is distinct from'vendor'then return jsonb_build_object('code','FORBIDDEN');end if;
 perform 1 from public.users where id=actor and not is_blocked and verification_status='approved'for no key update;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if p_request_id is null or jsonb_typeof(p_data)is distinct from'object'or nullif(btrim(p_data->>'name'),'')is null
 or char_length(p_data->>'name')>200 or char_length(p_data->>'description')>5000 or char_length(p_data->>'image_url')>2000
 or p_stock is null or p_stock not between 0 and 1000000000 or p_threshold is null or p_threshold<0 then raise exception 'Invalid product inventory'using errcode='22023';end if;
 v_price:=(p_data->>'price')::numeric;
 if v_price is null or v_price<0 or v_price>1000000000000 then raise exception 'Invalid product price'using errcode='22023';end if;
 payload:=jsonb_build_object('product_id',p_product_id,'data',p_data,'stock',p_stock,'threshold',p_threshold,'version',p_expected_version);
 select * into m from public.inventory_movements where vendor_id=actor and request_id=p_request_id;
 if found then
  if m.request_payload is distinct from payload then return jsonb_build_object('code','IDEMPOTENCY_CONFLICT');end if;
  select * into p from public.products where id=m.product_id and vendor_id=actor;
  if not found then return jsonb_build_object('code','PRODUCT_REMOVED');end if;
  return jsonb_build_object('code','ALREADY_UPDATED','product_id',m.product_id,'stock_qty',p.stock_qty,'stock_version',p.stock_version,'low_stock_threshold',p.low_stock_threshold);
 end if;
 if p_product_id is null then
  insert into public.products(vendor_id,name,price)values(actor,btrim(p_data->>'name'),v_price)returning * into p;
 else
  select * into p from public.products where id=p_product_id and vendor_id=actor for update;
  if not found then return jsonb_build_object('code','FORBIDDEN');end if;
  if p_expected_version is null or p_expected_version<>p.stock_version then return jsonb_build_object('code','STOCK_CHANGED','stock_qty',p.stock_qty,'stock_version',p.stock_version);end if;
 end if;
 update public.products set name=btrim(p_data->>'name'),description=p_data->>'description',price=v_price,
 image_url=p_data->>'image_url',category=coalesce(nullif(p_data->>'category',''),'General'),
 is_available=coalesce((p_data->>'is_available')::boolean,true),requires_prescription=coalesce((p_data->>'requires_prescription')::boolean,p.requires_prescription)where id=p.id;
 result:=fr17_private.adjust(p.id,p_stock,'set','Vendor product save',p_request_id,p_threshold,p.stock_version,payload);
 if result->>'code'<>'UPDATED'then raise exception 'Product stock save not confirmed'using errcode='40001';end if;
 return result;
end$function$
;
commit;
