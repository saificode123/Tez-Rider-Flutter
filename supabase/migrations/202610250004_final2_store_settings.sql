begin;
set local lock_timeout='5s';
alter table public.vendors add column settings_version bigint not null default 0 check(settings_version>=0);
create table final2_private.store_settings_receipts(
 actor_id bigint not null references public.users(id),request_id uuid not null,payload jsonb not null,
 created_at timestamptz not null default clock_timestamp(),primary key(actor_id,request_id)
);
alter table final2_private.store_settings_receipts enable row level security;
revoke all on final2_private.store_settings_receipts from public,anon,authenticated,service_role;

create function public.final2_store_settings()returns jsonb
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();v public.vendors;begin
 if actor is null or not public.is_current_user_allowed()or public.fr21_role()is distinct from'vendor'
 or not exists(select 1 from public.users where id=actor and not is_blocked and verification_status='approved')then
 raise exception 'Approved live Vendor required'using errcode='42501';end if;
 select *into v from public.vendors where user_id=actor;
 if v.id is null then raise exception 'Complete store registration first'using errcode='22023';end if;
 return jsonb_build_object('store_id',v.id,'store_name',v.store_name,'address',v.address,
 'latitude',v.latitude,'longitude',v.longitude,'is_active',v.is_active,'version',v.settings_version);end$$;
revoke all on function public.final2_store_settings()from public,anon;
grant execute on function public.final2_store_settings()to authenticated;

create function public.final2_save_store_settings(p_request_id uuid,p_expected_version bigint,p_name text,p_address text,
 p_latitude double precision default null,p_longitude double precision default null)returns jsonb
language plpgsql security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();v public.vendors;payload jsonb;prior jsonb;begin
 if actor is null or not public.is_current_user_allowed()or public.fr21_role()is distinct from'vendor'then
 raise exception 'Approved live Vendor required'using errcode='42501';end if;
 perform 1 from public.users where id=actor and role='vendor'and not is_blocked and verification_status='approved'for no key update;
 if not found then raise exception 'Approved Vendor required'using errcode='42501';end if;
 if p_request_id is null or p_request_id::text!~'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
 or p_expected_version is null or p_expected_version<0 or nullif(btrim(p_name),'')is null or char_length(btrim(p_name))>200
 or nullif(btrim(p_address),'')is null or char_length(btrim(p_address))>500 or p_name~'[[:cntrl:]]'or p_address~'[[:cntrl:]]'
 or(p_latitude is null)<>(p_longitude is null)or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
 raise exception 'Invalid store details'using errcode='22023';end if;
 select *into v from public.vendors where user_id=actor for update;
 if v.id is null then raise exception 'Complete store registration first'using errcode='22023';end if;
 payload:=jsonb_build_object('version',p_expected_version,'name',btrim(p_name),'address',btrim(p_address),'lat',p_latitude,'lng',p_longitude);
 select r.payload into prior from final2_private.store_settings_receipts r where r.actor_id=actor and r.request_id=p_request_id;
 if found then
 if prior is distinct from payload then raise exception 'Retry original store details'using errcode='PT409';end if;
 return jsonb_build_object('code','ALREADY_APPLIED','store',public.final2_store_settings());end if;
 if v.settings_version<>p_expected_version then raise exception 'Store changed. Reload before editing'using errcode='PT409';end if;
 if v.store_name is distinct from btrim(p_name)or v.address is distinct from btrim(p_address)
 or v.latitude is distinct from p_latitude or v.longitude is distinct from p_longitude then
 update public.vendors set store_name=btrim(p_name),address=btrim(p_address),latitude=p_latitude,longitude=p_longitude,
 settings_version=settings_version+1 where id=v.id;
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'store_settings_updated','vendors',v.id);
 end if;
 insert into final2_private.store_settings_receipts(actor_id,request_id,payload)values(actor,p_request_id,payload);
 -- Activation/review status is never writable through this owner endpoint.
 return jsonb_build_object('code','SAVED','store',public.final2_store_settings());end$$;
revoke all on function public.final2_save_store_settings(uuid,bigint,text,text,double precision,double precision)from public,anon;
grant execute on function public.final2_save_store_settings(uuid,bigint,text,text,double precision,double precision)to authenticated;
notify pgrst,'reload schema';
commit;
