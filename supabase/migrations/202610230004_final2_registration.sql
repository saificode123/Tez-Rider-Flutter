-- Stage2 FR01/03/27: verified registration completion and reasoned vendor review.
-- Additive APIs; retain canonical identity, session/quota, audit and email guards.
begin;
create or replace function public.final2_complete_registration(
 p_name text default null,p_phone text default null,p_role text default null,
 p_store_name text default null,p_store_address text default null,p_update_profile boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a auth.users;u public.users;v public.vendors;chosen text;begin
 if auth.role()is distinct from'authenticated'or auth.uid()is null or not public.fr28_token_live()then
  raise exception 'A live authenticated session is required'using errcode='42501';end if;
 select *into a from auth.users where id=auth.uid()for update;
 if a.id is null or a.email_confirmed_at is null then raise exception 'Verified email required'using errcode='42501';end if;
 select *into u from public.users where auth_user_id=a.id for update;
 if u.is_blocked then raise exception 'FR28_ACCOUNT_BLOCKED'using errcode='PT403';end if;
 chosen:=coalesce(u.role,p_role,'customer');
 if u.id is null then
  if chosen not in('customer','vendor','rider')then raise exception 'Invalid registration role'using errcode='22023';end if;
 end if;
 if u.id is null or p_update_profile is true then
  if nullif(btrim(p_name),'')is null or nullif(btrim(p_phone),'')is null then
   return jsonb_build_object('code','PROFILE_REQUIRED','role',chosen);end if;
  if char_length(btrim(p_name))>120 or p_name~'[[:cntrl:]]'or char_length(p_phone)>32
   or p_phone!~'^[+0-9() .-]+$'or p_phone!~'[0-9]'then raise exception 'Invalid profile details'using errcode='22023';end if;
 end if;
 if chosen='vendor'then
  select *into v from public.vendors where user_id=u.id for update;
  if v.id is null then
   if nullif(btrim(p_store_name),'')is null or nullif(btrim(p_store_address),'')is null then
    return jsonb_build_object('code','STORE_REQUIRED','role',chosen);end if;
   if char_length(btrim(p_store_name))>200 or char_length(btrim(p_store_address))>500
    or p_store_name~'[[:cntrl:]]'or p_store_address~'[[:cntrl:]]'then
    raise exception 'Invalid store details'using errcode='22023';end if;
  end if;
 end if;
 if u.id is null then
  if exists(select 1 from public.users where lower(email)=lower(a.email))then
   raise exception 'Existing profile requires identity reconciliation'using errcode='PT409';end if;
  insert into public.users(name,email,phone,role,verification_status,auth_user_id)
  values(btrim(p_name),a.email,btrim(p_phone),chosen,case when chosen='customer'then'approved'else'pending'end,a.id)
  returning *into u;
 elsif p_update_profile is true then
  update public.users set name=btrim(p_name),phone=btrim(p_phone)where id=u.id returning *into u;
 end if;
 if chosen='vendor'and v.id is null then
  insert into public.vendors(user_id,store_name,address,is_active)
  values(u.id,btrim(p_store_name),btrim(p_store_address),u.verification_status='approved')returning *into v;
 end if;
 return jsonb_build_object('code','OK','id',u.id,'role',u.role,'verification_status',u.verification_status,
  'rejection_reason',u.rejection_reason,'store_id',v.id,'name',u.name,'phone',u.phone);
end$$;
revoke all on function public.final2_complete_registration(text,text,text,text,text,boolean)from public,anon;
grant execute on function public.final2_complete_registration(text,text,text,text,text,boolean)to authenticated;

create or replace function public.final2_review_vendor(p_user_id bigint,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor();u public.users;reason text:=nullif(btrim(p_reason),'');begin
 if actor is null or public.fr21_role()is distinct from'admin'then raise exception 'Approved administrator required'using errcode='42501';end if;
 if p_user_id is null or p_user_id<=0 or p_status is null or p_status not in('approved','rejected')
  or char_length(coalesce(p_reason,''))>500 or coalesce(p_reason,'')~'[[:cntrl:]]'then
  raise exception 'Invalid review'using errcode='22023';end if;
 perform 1 from public.users where id=actor for update;
 if public.fr21_role()is distinct from'admin'then raise exception 'Approved administrator required'using errcode='42501';end if;
 select *into u from public.users where id=p_user_id and role='vendor'for update;
 if u.id is null then raise exception 'Vendor not found'using errcode='22023';end if;
 if u.verification_status is distinct from p_status then
  if p_status='rejected'and reason is null then raise exception 'A rejection reason is required'using errcode='22023';end if;
  if p_status='approved'and not exists(select 1 from public.vendors where user_id=u.id)then
   raise exception 'Vendor must complete store registration before approval'using errcode='22023';end if;
  update public.users set verification_status=p_status,rejection_reason=case when p_status='rejected'then reason else null end where id=u.id;
  update public.vendors set is_active=(p_status='approved')where user_id=u.id;
  -- Existing triggers atomically retain canonical Admin audit and FR32 account email.
  insert into public.notifications(user_id,title,message,type)
  values(u.id,case when p_status='approved'then'Vendor registration approved'else'Vendor registration rejected'end,
   case when p_status='approved'then'Your store has been approved. You can now manage products and orders.'else reason end,'system');
 elsif p_status='rejected'and reason is not null and reason is distinct from u.rejection_reason then
  raise exception 'Decision already recorded; refresh before reviewing again'using errcode='PT409';
 end if;
 return jsonb_build_object('id',u.id,'verification_status',p_status,'rejection_reason',
  case when p_status='rejected'then coalesce(reason,u.rejection_reason)else null end);
end$$;
revoke all on function public.final2_review_vendor(bigint,text,text)from public,anon;
grant execute on function public.final2_review_vendor(bigint,text,text)to authenticated;
-- Retain the old signature without a reasonless-rejection bypass. Approval and
-- exact no-op reconciliation stay compatible; a new rejection needs the new API.
create or replace function public.final1_review_vendor(p_user_id bigint,p_status text)
returns jsonb language sql security definer set search_path='' as $$
 select public.final2_review_vendor(p_user_id,p_status,null)
$$;
commit;
