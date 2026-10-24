-- Concurrent uploads select the latest confirmed completion, not reservation time.
begin;
set local lock_timeout='5s';
alter table final2_private.photos add column uploaded_at timestamptz;
-- Legacy completion timestamps stay unknown; existing created_at is only fallback ordering.
create or replace function public.final2_photo_finish(p_auth_id uuid,p_session_id uuid,p_request_id uuid,p_kind text,p_order_id bigint,
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
  update final2_private.photos set uploaded=true,uploaded_at=clock_timestamp()where id=photo.id;
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


create or replace function final2_private.attach_delivery_photo()returns trigger language plpgsql security definer set search_path=''as $$begin
 if new.proofid='fr21-otp-'||new.orderid and new.is_verified and new.otpconfirmed then
 select 'tezphoto:'||p.id into new.photourl from final2_private.photos p
 where p.kind='delivery'and p.order_id::text=new.orderid and p.auth_id::text=new.riderid and p.uploaded order by p.uploaded_at desc nulls last,p.created_at desc,p.id limit 1;
 end if;return new;end$$;
revoke all on function final2_private.attach_delivery_photo()from public,anon,authenticated,service_role;

create or replace function public.final2_delivery_photo(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();o public.orders;ref text;begin
 if not public.is_current_user_allowed()or actor is null or not exists(select 1 from public.users where id=actor
 and not is_blocked and verification_status='approved')then raise exception 'Approved live account required'using errcode='42501';end if;
 select *into o from public.orders where id=p_order_id;
 if o.id is null or not(o.user_id=actor or o.rider_id=actor or public.fr21_role()='admin')then
 raise exception 'Owned order required'using errcode='42501';end if;
 select 'tezphoto:'||p.id into ref from final2_private.photos p where p.order_id=o.id and p.kind='delivery'and p.uploaded
 order by p.uploaded_at desc nulls last,p.created_at desc,p.id limit 1;
 return jsonb_build_object('reference',ref,'order_status',o.order_status,'can_upload',o.rider_id=actor and o.order_status in('on_the_way','delivered'));
 end$$;
revoke all on function public.final2_delivery_photo(bigint)from public,anon;
grant execute on function public.final2_delivery_photo(bigint)to authenticated;

notify pgrst,'reload schema';
commit;
