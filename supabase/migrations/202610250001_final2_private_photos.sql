-- Private avatars and delivery photos; canonical OTP proof remains authoritative.
begin;
set local lock_timeout='5s';
create table final2_private.photos(
 id uuid primary key,owner_id bigint not null references public.users(id),auth_id uuid not null,
 kind text not null check(kind in('avatar','delivery')),order_id bigint references public.orders(id),
 path text not null unique,digest text not null check(digest~'^[0-9a-f]{64}$'),
 mime text not null check(mime in('image/jpeg','image/png')),size integer not null check(size between 1 and 5242880),
 uploaded boolean not null default false,created_at timestamptz not null default clock_timestamp(),
 check((kind='avatar'and order_id is null)or(kind='delivery'and order_id is not null))
);
alter table final2_private.photos enable row level security;
revoke all on final2_private.photos from public,anon,authenticated,service_role;
create index final2_delivery_photo_order on final2_private.photos(order_id,created_at desc)where kind='delivery';
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('final2-private-photos','final2-private-photos',false,5242880,array['image/jpeg','image/png']);
create policy final2_photos_private on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'final2-private-photos')with check(bucket_id<>'final2-private-photos');

create function final2_private.photo_actor(p_auth uuid,p_session uuid)returns bigint
language plpgsql stable security definer set search_path=''as $$declare actor bigint;begin
 select u.id into actor from public.users u join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=p_auth and not u.is_blocked and u.verification_status='approved'
 and a.email_confirmed_at is not null and exists(select 1 from auth.sessions s
 where s.id=p_session and s.user_id=p_auth and(s.not_after is null or s.not_after>clock_timestamp()));
 if actor is null then raise exception 'Approved live account required'using errcode='42501';end if;
 return actor;end$$;
revoke all on function final2_private.photo_actor(uuid,uuid)from public,anon,authenticated,service_role;

create function public.final2_photo_authority(p_kind text,p_order_id bigint default null)returns bigint
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();begin
 if not public.is_current_user_allowed()or actor is null or not exists(select 1 from public.users u
 join auth.users a on a.id=u.auth_user_id where u.id=actor and not u.is_blocked and u.verification_status='approved'
 and a.email_confirmed_at is not null)then raise exception 'Approved account required'using errcode='42501';end if;
 if p_kind='avatar'and p_order_id is null then return actor;end if;
 if p_kind='delivery'and public.fr21_role()='rider'and exists(select 1 from public.orders o
 where o.id=p_order_id and o.rider_id=actor and o.order_status in('on_the_way','delivered'))then return actor;end if;
 raise exception 'Photo upload forbidden'using errcode='42501';end$$;
revoke all on function public.final2_photo_authority(text,bigint)from public,anon;
grant execute on function public.final2_photo_authority(text,bigint)to authenticated;

create function public.final2_photo_begin(p_auth_id uuid,p_session_id uuid,p_request_id uuid,p_kind text,p_order_id bigint,
 p_digest text,p_mime text,p_size integer)returns text language plpgsql security definer set search_path=''as $$
declare actor bigint:=final2_private.photo_actor(p_auth_id,p_session_id);photo final2_private.photos;o public.orders;begin
 if p_request_id is null or p_request_id::text!~'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
 or p_digest is null or p_digest!~'^[0-9a-f]{64}$'or p_mime is null or p_mime not in('image/jpeg','image/png')
 or p_size is null or p_size not between 1 and 5242880 then raise exception 'Invalid photo'using errcode='22023';end if;
 if p_kind='delivery'then
  select *into o from public.orders where id=p_order_id for update;
  if o.id is null or o.rider_id is distinct from actor or o.order_status not in('on_the_way','delivered')
   or not exists(select 1 from public.users where id=actor and role='rider')then
   raise exception 'Assigned delivery required'using errcode='42501';end if;
 elsif p_kind is distinct from'avatar'or p_order_id is not null then raise exception 'Invalid photo scope'using errcode='22023';end if;
 perform 1 from public.users where id=actor for no key update;
 perform final2_private.photo_actor(p_auth_id,p_session_id);
 insert into final2_private.photos(id,owner_id,auth_id,kind,order_id,path,digest,mime,size)
 values(p_request_id,actor,p_auth_id,p_kind,p_order_id,p_auth_id||'/'||p_request_id||case when p_mime='image/png'then'.png'else'.jpg'end,p_digest,p_mime,p_size)
 on conflict(id)do nothing;
 select *into photo from final2_private.photos where id=p_request_id for update;
 if photo.auth_id is distinct from p_auth_id then raise exception 'Photo forbidden'using errcode='42501';end if;
 if photo.kind is distinct from p_kind or photo.order_id is distinct from p_order_id or photo.digest<>p_digest
 or photo.mime<>p_mime or photo.size<>p_size then raise exception 'Retry original photo'using errcode='PT409';end if;
 return photo.path;end$$;
revoke all on function public.final2_photo_begin(uuid,uuid,uuid,text,bigint,text,text,integer)from public,anon,authenticated;
grant execute on function public.final2_photo_begin(uuid,uuid,uuid,text,bigint,text,text,integer)to service_role;

create function public.final2_photo_finish(p_auth_id uuid,p_session_id uuid,p_request_id uuid,p_kind text,p_order_id bigint,
 p_digest text,p_mime text,p_size integer)returns text language plpgsql security definer set search_path=''as $$
declare photo final2_private.photos;object storage.objects;path text;reference text;begin
 path:=public.final2_photo_begin(p_auth_id,p_session_id,p_request_id,p_kind,p_order_id,p_digest,p_mime,p_size);
 select *into photo from final2_private.photos where id=p_request_id for update;
 select *into object from storage.objects where bucket_id='final2-private-photos'and name=path;
 if object.id is null or object.metadata->>'mimetype'is distinct from p_mime
 or(object.metadata->>'size')::bigint is distinct from p_size::bigint then
 raise exception 'Validated photo not confirmed'using errcode='22023';end if;
 reference:='tezphoto:'||photo.id;
 if not photo.uploaded then
  update final2_private.photos set uploaded=true where id=photo.id;
  if photo.kind='avatar'then update public.users set profile_image=reference where id=photo.owner_id;
  else update public.delivery_proof set photourl=reference where orderid=photo.order_id::text
   and riderid=photo.auth_id::text and proofid='fr21-otp-'||photo.order_id and is_verified and otpconfirmed;end if;
  insert into public.security_audit_log(actor_id,action,target_type,target_id)
  values(photo.owner_id,case when photo.kind='avatar'then'profile_photo_uploaded'else'delivery_photo_uploaded'end,
   case when photo.kind='avatar'then'users'else'orders'end,coalesce(photo.order_id,photo.owner_id));
 end if;
 return reference;end$$;
revoke all on function public.final2_photo_finish(uuid,uuid,uuid,text,bigint,text,text,integer)from public,anon,authenticated;
grant execute on function public.final2_photo_finish(uuid,uuid,uuid,text,bigint,text,text,integer)to service_role;

create function final2_private.attach_delivery_photo()returns trigger language plpgsql security definer set search_path=''as $$begin
 if new.proofid='fr21-otp-'||new.orderid and new.is_verified and new.otpconfirmed then
 select 'tezphoto:'||p.id into new.photourl from final2_private.photos p
 where p.kind='delivery'and p.order_id::text=new.orderid and p.auth_id::text=new.riderid and p.uploaded order by p.created_at desc,p.id limit 1;
 end if;return new;end$$;
revoke all on function final2_private.attach_delivery_photo()from public,anon,authenticated,service_role;
create trigger final2_attach_delivery_photo before insert on public.delivery_proof
 for each row execute function final2_private.attach_delivery_photo();

create function public.final2_photo_view(p_image_id uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();photo final2_private.photos;begin
 if not public.is_current_user_allowed()or actor is null or not exists(select 1 from public.users where id=actor
 and not is_blocked and verification_status='approved')then raise exception 'Approved live account required'using errcode='42501';end if;
 select *into photo from final2_private.photos where id=p_image_id and uploaded;
 if photo.id is null or not(photo.owner_id=actor or public.fr21_role()='admin'
 or(photo.kind='delivery'and exists(select 1 from public.orders o where o.id=photo.order_id and o.user_id=actor))
 or(photo.kind='avatar'and exists(select 1 from public.users u join public.orders o on o.rider_id=u.id
 where u.id=photo.owner_id and u.role='rider'and not u.is_blocked and u.verification_status='approved'
 and u.profile_image='tezphoto:'||photo.id and o.user_id=actor)))then
 raise exception 'Private photo forbidden'using errcode='42501';end if;
 return jsonb_build_object('path',photo.path,'digest',photo.digest,'mime',photo.mime,'size',photo.size);end$$;
revoke all on function public.final2_photo_view(uuid)from public,anon;
grant execute on function public.final2_photo_view(uuid)to authenticated;

create function final2_private.profile_photo_guard()returns trigger language plpgsql security definer set search_path=''as $$begin
 if tg_op='UPDATE'and new.profile_image is not distinct from old.profile_image then return new;end if;
 if nullif(btrim(new.profile_image),'')is null then return new;end if;
 if not exists(select 1 from final2_private.photos p where p.kind='avatar'and p.owner_id=new.id
 and p.uploaded and new.profile_image='tezphoto:'||p.id)then raise exception 'Use validated private photo'using errcode='22023';end if;
 return new;end$$;
revoke all on function final2_private.profile_photo_guard()from public,anon,authenticated,service_role;
create trigger final2_profile_photo_guard before insert or update of profile_image on public.users
 for each row execute function final2_private.profile_photo_guard();

create or replace function public.fr04_order_rider_identity(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare o public.orders;u public.users;s public.rating_summaries;begin
 select *into o from public.orders where id=p_order_id and user_id=public.fr21_actor();
 if not public.is_current_user_allowed()or o.id is null or public.fr21_role()is distinct from'customer'then
 raise exception 'Owned live customer order required'using errcode='42501';end if;
 select *into u from public.users where id=o.rider_id and role='rider'and not is_blocked and verification_status='approved';
 if u.id is null then return null;end if;
 select *into s from public.rating_summaries where target_user_id=u.id and target_role='rider';
 return jsonb_build_object('rider_id',u.id,'name',u.name,
 'photo',case when exists(select 1 from final2_private.photos p where p.owner_id=u.id and p.kind='avatar'and p.uploaded
 and u.profile_image='tezphoto:'||p.id)then u.profile_image else null end,
 'cnic_masked',fr04_private.mask_cnic(u.cnic),'rating',s.average_rating,'rating_count',coalesce(s.rating_count,0),
 'verification_status',u.verification_status,'order_status',o.order_status);end$$;
create function public.final2_delivery_photo(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();o public.orders;ref text;begin
 if not public.is_current_user_allowed()or actor is null or not exists(select 1 from public.users where id=actor
 and not is_blocked and verification_status='approved')then raise exception 'Approved live account required'using errcode='42501';end if;
 select *into o from public.orders where id=p_order_id;
 if o.id is null or not(o.user_id=actor or o.rider_id=actor or public.fr21_role()='admin')then
 raise exception 'Owned order required'using errcode='42501';end if;
 select 'tezphoto:'||p.id into ref from final2_private.photos p where p.order_id=o.id and p.kind='delivery'and p.uploaded
 order by p.created_at desc,p.id limit 1;
 return jsonb_build_object('reference',ref,'order_status',o.order_status,'can_upload',o.rider_id=actor and o.order_status in('on_the_way','delivered'));
 end$$;
revoke all on function public.final2_delivery_photo(bigint)from public,anon;
grant execute on function public.final2_delivery_photo(bigint)to authenticated;
create function public.final2_customer_delivery_identity(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare o public.orders;begin
 select *into o from public.orders where id=p_order_id and user_id=public.fr21_actor();
 if not public.is_current_user_allowed()or o.id is null or public.fr21_role()is distinct from'customer'then
 raise exception 'Owned live customer order required'using errcode='42501';end if;
 return jsonb_build_object('order_id',o.id,'order_status',o.order_status,'rider',public.fr04_order_rider_identity(o.id));end$$;
revoke all on function public.final2_customer_delivery_identity(bigint)from public,anon;
grant execute on function public.final2_customer_delivery_identity(bigint)to authenticated;
notify pgrst,'reload schema';
commit;
