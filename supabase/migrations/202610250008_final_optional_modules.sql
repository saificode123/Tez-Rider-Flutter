-- Owner retained the existing tailoring, prescription and AI modules.
-- No tailor assignment/pricing policy is introduced here.
begin;
set local lock_timeout='5s';
alter table public.tailoring_requests add column if not exists measurements jsonb not null default '{}'::jsonb;
alter table public.tailoring_requests add column if not exists reference_image_url text;

create table final2_private.optional_media(
 id uuid primary key,owner_id bigint not null references public.users(id),auth_id uuid not null,
 kind text not null check(kind in('tailoring','prescription')),order_id bigint references public.vendor_orders(id),
 path text not null unique,digest text not null check(digest~'^[0-9a-f]{64}$'),
 mime text not null check(mime in('image/jpeg','image/png')),size integer not null check(size between 1 and 5242880),
 uploaded boolean not null default false,created_at timestamptz not null default clock_timestamp(),
 check((kind='tailoring'and order_id is null)or(kind='prescription'and order_id is not null))
);
alter table final2_private.optional_media enable row level security;
revoke all on final2_private.optional_media from public,anon,authenticated,service_role;
create table final2_private.optional_receipts(
 actor_id bigint not null references public.users(id),request_id uuid not null,action text not null,
 payload jsonb not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(actor_id,request_id)
);
alter table final2_private.optional_receipts enable row level security;
revoke all on final2_private.optional_receipts from public,anon,authenticated,service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('optional-private-media','optional-private-media',false,5242880,array['image/jpeg','image/png']);
create policy optional_media_private on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'optional-private-media')with check(bucket_id<>'optional-private-media');

create function public.optional_media_authority(p_kind text,p_order_id bigint default null)returns bigint
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();begin
 if not public.is_current_user_allowed()or public.fr21_role()is distinct from'customer'or actor is null or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then
 raise exception 'Live Customer required'using errcode='42501';end if;
 if p_kind='tailoring'and p_order_id is null then return actor;end if;
 if p_kind='prescription'and exists(select 1 from public.vendor_orders vo join public.orders o on o.id=vo.order_id
 where vo.id=p_order_id and o.user_id=actor and o.order_status not in('cancelled','delivered'))then return actor;end if;
 raise exception 'Owned active order required'using errcode='42501';end$$;
revoke all on function public.optional_media_authority(text,bigint)from public,anon;
grant execute on function public.optional_media_authority(text,bigint)to authenticated;

create function public.optional_media_begin(p_auth_id uuid,p_session_id uuid,p_request_id uuid,p_kind text,p_order_id bigint,
 p_digest text,p_mime text,p_size integer)returns text language plpgsql security definer set search_path=''as $$
declare actor bigint:=final2_private.photo_actor(p_auth_id,p_session_id);media final2_private.optional_media;begin
 if p_request_id is null or p_request_id::text!~'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
 or p_digest is null or p_digest!~'^[0-9a-f]{64}$'or p_mime is null or p_mime not in('image/jpeg','image/png')
 or p_size is null or p_size not between 1 and 5242880 then raise exception 'Invalid image'using errcode='22023';end if;
 perform 1 from public.users where id=actor and role='customer'for no key update;
 if not found then raise exception 'Customer required'using errcode='42501';end if;
 if p_kind='prescription'then
  perform 1 from public.vendor_orders vo join public.orders o on o.id=vo.order_id
  where vo.id=p_order_id and o.user_id=actor and o.order_status not in('cancelled','delivered')for update of vo,o;
  if not found then raise exception 'Owned active order required'using errcode='42501';end if;
 elsif p_kind is distinct from'tailoring'or p_order_id is not null then raise exception 'Invalid image scope'using errcode='22023';end if;
 perform final2_private.photo_actor(p_auth_id,p_session_id);
 insert into final2_private.optional_media(id,owner_id,auth_id,kind,order_id,path,digest,mime,size)
 values(p_request_id,actor,p_auth_id,p_kind,p_order_id,p_auth_id||'/'||p_request_id||case when p_mime='image/png'then'.png'else'.jpg'end,p_digest,p_mime,p_size)
 on conflict(id)do nothing;
 select *into media from final2_private.optional_media where id=p_request_id for update;
 if media.auth_id is distinct from p_auth_id then raise exception 'Image forbidden'using errcode='42501';end if;
 if media.kind is distinct from p_kind or media.order_id is distinct from p_order_id or media.digest<>p_digest
 or media.mime<>p_mime or media.size<>p_size then raise exception 'Retry original image'using errcode='PT409';end if;
 return media.path;end$$;
revoke all on function public.optional_media_begin(uuid,uuid,uuid,text,bigint,text,text,integer)from public,anon,authenticated;
grant execute on function public.optional_media_begin(uuid,uuid,uuid,text,bigint,text,text,integer)to service_role;

create function public.optional_media_finish(p_auth_id uuid,p_session_id uuid,p_request_id uuid,p_kind text,p_order_id bigint,
 p_digest text,p_mime text,p_size integer)returns text language plpgsql security definer set search_path=''as $$
declare media final2_private.optional_media;object storage.objects;path text;begin
 path:=public.optional_media_begin(p_auth_id,p_session_id,p_request_id,p_kind,p_order_id,p_digest,p_mime,p_size);
 select *into media from final2_private.optional_media where id=p_request_id for update;
 select *into object from storage.objects where bucket_id='optional-private-media'and name=path;
 if object.id is null or object.metadata->>'mimetype'is distinct from p_mime
 or(object.metadata->>'size')::bigint is distinct from p_size::bigint then
 raise exception 'Validated image not confirmed'using errcode='22023';end if;
 if not media.uploaded then
  update final2_private.optional_media set uploaded=true where id=media.id;
  insert into public.security_audit_log(actor_id,action,target_type,target_id)
  values(media.owner_id,'optional_image_uploaded',media.kind,coalesce(media.order_id,media.owner_id));
 end if;
 return 'tezphoto:'||media.id;end$$;
revoke all on function public.optional_media_finish(uuid,uuid,uuid,text,bigint,text,text,integer)from public,anon,authenticated;
grant execute on function public.optional_media_finish(uuid,uuid,uuid,text,bigint,text,text,integer)to service_role;

create function public.optional_media_view(p_image_id uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();media final2_private.optional_media;begin
 if not public.is_current_user_allowed()or actor is null or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then raise exception 'Live account required'using errcode='42501';end if;
 select *into media from final2_private.optional_media where id=p_image_id and uploaded;
 if media.id is null or not(media.owner_id=actor or public.fr21_role()='admin'
 or(media.kind='prescription'and exists(select 1 from public.vendor_orders vo where vo.id=media.order_id and vo.vendor_id=actor))
 or(media.kind='tailoring'and exists(select 1 from public.tailoring_requests t where t.reference_image_url='tezphoto:'||media.id
 and(actor=t.vendor_id or actor=t.rider_id))))then raise exception 'Private image forbidden'using errcode='42501';end if;
 return jsonb_build_object('path',media.path,'digest',media.digest,'mime',media.mime,'size',media.size);end$$;
revoke all on function public.optional_media_view(uuid)from public,anon;
grant execute on function public.optional_media_view(uuid)to authenticated;

create function public.optional_submit_tailoring(p_instructions text,p_measurements jsonb,p_reference text,p_request_id uuid)returns jsonb
language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.optional_media_authority('tailoring',null);payload jsonb;receipt final2_private.optional_receipts;t public.tailoring_requests;k text;v jsonb;begin
 if p_request_id is null or p_instructions is null or length(btrim(p_instructions))not between 1 and 2000
 or regexp_replace(p_instructions,E'[\n\r\t]','','g')~'[[:cntrl:]]'or p_measurements is null or jsonb_typeof(p_measurements)<>'object'
 or octet_length(p_measurements::text)>1000 then raise exception 'Invalid tailoring details'using errcode='22023';end if;
 for k,v in select *from jsonb_each(p_measurements)loop
  if k not in('length','shoulder','chest')or jsonb_typeof(v)not in('string','number')or
   (trim(both '"'from v::text)<>''and trim(both '"'from v::text)!~'^[0-9]{1,3}([.][0-9]{1,2})?$')then
   raise exception 'Invalid measurement'using errcode='22023';end if;
 end loop;
 perform 1 from public.users where id=actor for no key update;
 payload:=jsonb_build_object('instructions',btrim(p_instructions),'measurements',p_measurements,'reference',p_reference);
 select *into receipt from final2_private.optional_receipts where actor_id=actor and request_id=p_request_id;
 if found then
  if receipt.action<>'tailoring_submit'or receipt.payload<>payload then raise exception 'Retry original request'using errcode='PT409';end if;
  return receipt.result;
 end if;
 if p_reference is not null and not exists(select 1 from final2_private.optional_media m where m.kind='tailoring'and m.owner_id=actor
 and m.uploaded and p_reference='tezphoto:'||m.id)then raise exception 'Owned validated reference required'using errcode='42501';end if;
 insert into public.tailoring_requests(customer_id,instructions,measurements,reference_image_url,status)
 values(actor,btrim(p_instructions),p_measurements,p_reference,'pickup_requested')returning *into t;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'tailoring_requested','tailoring_requests',t.id);
 insert into final2_private.optional_receipts(actor_id,request_id,action,payload,result)values(actor,p_request_id,'tailoring_submit',payload,to_jsonb(t));
 return to_jsonb(t);end$$;
revoke all on function public.optional_submit_tailoring(text,jsonb,text,uuid)from public,anon;
grant execute on function public.optional_submit_tailoring(text,jsonb,text,uuid)to authenticated;

create function public.optional_tailoring_status(p_id bigint,p_status text)returns jsonb
language plpgsql security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();t public.tailoring_requests;role text:=public.fr21_role();begin
 if not public.is_current_user_allowed()or actor is null or role not in('rider','vendor')then raise exception 'Approved role required'using errcode='42501';end if;
 perform 1 from public.users where id=actor and verification_status='approved'for no key update;
 if not found then raise exception 'Approved role required'using errcode='42501';end if;
 select *into t from public.tailoring_requests where id=p_id for update;
 if t.id is null then raise exception 'Request unavailable'using errcode='42501';end if;
 if role='vendor'and t.vendor_id=actor then
  if t.status=p_status then return to_jsonb(t);end if;
  if not((t.status='delivered_to_tailor'and p_status='stitching')or(t.status in('delivered_to_tailor','stitching')and p_status='ready_for_customer'))then
   raise exception 'Invalid tailoring transition'using errcode='PT409';end if;
 elsif role='rider'then
  if t.rider_id=actor and t.status=p_status then return to_jsonb(t);end if;
  if p_status in('picked_up_from_customer','picked_up_from_tailor')then
   if t.vendor_id is null or(t.rider_id is not null and t.rider_id<>actor)
   or not((t.status='pickup_requested'and p_status='picked_up_from_customer')or(t.status='ready_for_customer'and p_status='picked_up_from_tailor'))
   or not exists(select 1 from public.riders r where r.userid=actor and r.is_online and r.last_seen>=clock_timestamp()-interval '2 minutes')then raise exception 'Assigned available pickup required'using errcode='PT409';end if;
   if exists(select 1 from public.orders o where o.rider_id=actor and o.order_status not in('delivered','cancelled'))
   or exists(select 1 from public.tailoring_requests r where r.rider_id=actor and r.id<>t.id and r.status in('picked_up_from_customer','picked_up_from_tailor'))then
    raise exception 'Complete active delivery first'using errcode='PT409';end if;
  elsif t.rider_id is distinct from actor or not((t.status='picked_up_from_customer'and p_status='delivered_to_tailor')
   or(t.status='picked_up_from_tailor'and p_status='completed'))then raise exception 'Assigned delivery required'using errcode='42501';end if;
 else raise exception 'Owned request required'using errcode='42501';end if;
 update public.tailoring_requests set status=p_status,rider_id=case when role='rider'then actor else rider_id end where id=t.id returning *into t;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'tailoring_'||p_status,'tailoring_requests',t.id);
 return to_jsonb(t);end$$;
revoke all on function public.optional_tailoring_status(bigint,text)from public,anon;
grant execute on function public.optional_tailoring_status(bigint,text)to authenticated;

create function public.optional_save_prescription(p_vendor_order_id bigint,p_reference text,p_request_id uuid)returns jsonb
language plpgsql security definer set search_path=''as $$declare actor bigint:=public.optional_media_authority('prescription',p_vendor_order_id);
 payload jsonb:=jsonb_build_object('order',p_vendor_order_id,'reference',p_reference);receipt final2_private.optional_receipts;p public.prescriptions;vo public.vendor_orders;begin
 if p_request_id is null then raise exception 'Request id required'using errcode='22023';end if;
 perform 1 from public.users where id=actor for no key update;
 select *into receipt from final2_private.optional_receipts where actor_id=actor and request_id=p_request_id;
 if found then
  if receipt.action<>'prescription_save'or receipt.payload<>payload then raise exception 'Retry original request'using errcode='PT409';end if;
  return receipt.result;
 end if;
 select *into vo from public.vendor_orders where id=p_vendor_order_id for update;
 if not exists(select 1 from final2_private.optional_media m where m.kind='prescription'and m.owner_id=actor and m.order_id=vo.id
 and m.uploaded and p_reference='tezphoto:'||m.id)then raise exception 'Owned validated prescription required'using errcode='42501';end if;
 select *into p from public.prescriptions where vendor_order_id=vo.id and customer_id=actor and prescription_image_url=p_reference;
 if found then
  insert into final2_private.optional_receipts(actor_id,request_id,action,payload,result)values(actor,p_request_id,'prescription_save',payload,to_jsonb(p));
  return to_jsonb(p);
 end if;
 insert into public.prescriptions(vendor_order_id,customer_id,vendor_id,prescription_image_url,status)
 values(vo.id,actor,vo.vendor_id,p_reference,'pending')returning *into p;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'prescription_submitted','prescriptions',p.id);
 insert into final2_private.optional_receipts(actor_id,request_id,action,payload,result)values(actor,p_request_id,'prescription_save',payload,to_jsonb(p));
 return to_jsonb(p);end$$;
revoke all on function public.optional_save_prescription(bigint,text,uuid)from public,anon;
grant execute on function public.optional_save_prescription(bigint,text,uuid)to authenticated;

create function public.optional_review_prescription(p_id bigint,p_status text,p_notes text default null)returns jsonb
language plpgsql security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();p public.prescriptions;vo public.vendor_orders;o public.orders;begin
 if not public.is_current_user_allowed()or public.fr21_role()is distinct from'vendor'or actor is null or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then raise exception 'Vendor required'using errcode='42501';end if;
 if p_status is null or p_status not in('approved','rejected')or length(coalesce(p_notes,''))>2000
 or regexp_replace(coalesce(p_notes,''),E'[\n\r\t]','','g')~'[[:cntrl:]]'or(p_status='rejected'and length(btrim(coalesce(p_notes,'')))<1)then
 raise exception 'Valid review required'using errcode='22023';end if;
 select *into p from public.prescriptions where id=p_id and vendor_id=actor;
 select *into o from public.orders where id=(select order_id from public.vendor_orders where id=p.vendor_order_id)for update;
 select *into vo from public.vendor_orders where id=p.vendor_order_id for update;
 select *into p from public.prescriptions where id=p_id and vendor_id=actor for update;
 if o.id is null or o.order_status in('cancelled','delivered')or vo.status='cancelled'then raise exception 'Active owned order required'using errcode='PT409';end if;
 if p.id is null or vo.id is null or vo.vendor_id is distinct from actor then
 raise exception 'Owned prescription required'using errcode='42501';end if;
 if p.status=p_status and p.vendor_notes is not distinct from nullif(btrim(p_notes),'')then return to_jsonb(p);end if;
 if p.status is distinct from'pending'then raise exception 'Prescription already reviewed'using errcode='PT409';end if;
 update public.prescriptions set status=p_status,vendor_notes=nullif(btrim(p_notes),''),reviewed_at=clock_timestamp(),reviewed_by=actor
 where id=p.id returning *into p;
 if p_status='approved'then
  update public.vendor_orders set prescription_id=p.id,status=case when status='pending_prescription'then'pending'else status end where id=vo.id;
  update public.orders set prescription_status=case when exists(select 1 from public.vendor_orders v where v.order_id=o.id and v.requires_prescription and v.status='pending_prescription')then'pending_verification'else'approved'end where id=o.id;
 end if;
 insert into public.notifications(user_id,title,message,type)
 values(p.customer_id,'Prescription reviewed',case when p_status='approved'then'Your prescription was approved.'else'Your prescription was rejected. Open order details to review the note.'end,'order');
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'prescription_'||p_status,'prescriptions',p.id);
 return to_jsonb(p);end$$;
revoke all on function public.optional_review_prescription(bigint,text,text)from public,anon;
grant execute on function public.optional_review_prescription(bigint,text,text)to authenticated;

create function public.optional_list_prescriptions(p_order_id bigint default null)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();role text:=public.fr21_role();begin
 if not public.is_current_user_allowed()or actor is null or role not in('customer','vendor')or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then raise exception 'Live owner required'using errcode='42501';end if;
 if p_order_id is not null and(role<>'customer'or not exists(select 1 from public.orders o where o.id=p_order_id and o.user_id=actor))then
 raise exception 'Owned order required'using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(p)order by p.uploaded_at,p.id)from(
 select p.*from public.prescriptions p join public.vendor_orders vo on vo.id=p.vendor_order_id
 join public.orders o on o.id=vo.order_id where((role='customer'and o.user_id=actor and p.customer_id=actor)
 or(role='vendor'and vo.vendor_id=actor and p.vendor_id=actor and p.status='pending'))
 and(p_order_id is null or o.id=p_order_id)order by p.uploaded_at,p.id limit 100)p),'[]'::jsonb);end$$;
revoke all on function public.optional_list_prescriptions(bigint)from public,anon;
grant execute on function public.optional_list_prescriptions(bigint)to authenticated;

revoke insert,update,delete on public.prescriptions,public.tailoring_requests from anon,authenticated;
notify pgrst,'reload schema';
commit;
