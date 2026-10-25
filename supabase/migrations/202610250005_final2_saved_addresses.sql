begin;
set local lock_timeout='5s';
alter table public.addresses add column revision bigint not null default 0 check(revision>=0);
create table final2_private.address_receipts(
 actor_id bigint not null references public.users(id),request_id uuid not null,payload jsonb not null,result jsonb not null,
 created_at timestamptz not null default clock_timestamp(),primary key(actor_id,request_id)
);
alter table final2_private.address_receipts enable row level security;
revoke all on final2_private.address_receipts from public,anon,authenticated,service_role;

create function public.final2_saved_addresses(p_before bigint default null,p_limit integer default 50)returns jsonb
language plpgsql stable security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();items jsonb;more boolean;cursor bigint;begin
 if actor is null or not public.is_current_user_allowed()or public.fr21_role()is distinct from'customer'
 or not exists(select 1 from public.users where id=actor and not is_blocked and verification_status='approved')then
 raise exception 'Approved Customer required'using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or p_before<=0 then raise exception 'Invalid address page'using errcode='22023';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by id desc),'[]'),min(id)into items,cursor from(
 select id,label,address,created_at,revision from public.addresses where user_id=actor and(p_before is null or id<p_before)
 order by id desc limit p_limit)x;
 select exists(select 1 from public.addresses where user_id=actor and id<cursor)into more;
 return jsonb_build_object('items',items,'has_more',more,'cursor',cursor);end$$;
revoke all on function public.final2_saved_addresses(bigint,integer)from public,anon;
grant execute on function public.final2_saved_addresses(bigint,integer)to authenticated;

create function public.final2_change_address(p_request_id uuid,p_operation text,p_id bigint default null,
 p_expected_revision bigint default null,p_label text default null,p_address text default null)returns jsonb
language plpgsql security definer set search_path=''as $$declare actor bigint:=public.fr21_actor();address_row public.addresses;payload jsonb;receipt final2_private.address_receipts;result jsonb;changed boolean:=true;begin
 if actor is null or not public.is_current_user_allowed()or public.fr21_role()is distinct from'customer'then
 raise exception 'Approved Customer required'using errcode='42501';end if;
 perform 1 from public.users where id=actor and not is_blocked and verification_status='approved'for no key update;
 if not found then raise exception 'Approved Customer required'using errcode='42501';end if;
 if p_request_id is null or p_request_id::text!~'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
 or p_operation is null or p_operation not in('create','edit','delete')
 or(p_operation='delete'and(p_label is not null or p_address is not null))
or(p_operation='create'and(p_id is not null or p_expected_revision is not null))
 or(p_operation in('edit','delete')and(p_id is null or p_id<=0 or p_expected_revision is null or p_expected_revision<0))then
 raise exception 'Invalid address request'using errcode='22023';end if;
 if p_operation<>'delete'and(nullif(btrim(p_label),'')is null or char_length(btrim(p_label))>100
 or nullif(btrim(p_address),'')is null or char_length(btrim(p_address))>2000
 or p_label~'[[:cntrl:]]'or p_address~'[[:cntrl:]]')then raise exception 'Invalid address details'using errcode='22023';end if;
 payload:=jsonb_build_object('operation',p_operation,'id',p_id,'revision',p_expected_revision,'label',p_label,'address',p_address);
 select *into receipt from final2_private.address_receipts r where r.actor_id=actor and r.request_id=p_request_id;
 if found then
 if receipt.payload is distinct from payload then raise exception 'Retry original address change'using errcode='PT409';end if;
 return receipt.result||jsonb_build_object('code','ALREADY_APPLIED');end if;
 if p_operation='create'then
 insert into public.addresses(user_id,label,address)values(actor,btrim(p_label),btrim(p_address))returning *into address_row;
 else
 select *into address_row from public.addresses where id=p_id and user_id=actor for update;
 if address_row.id is null then raise exception 'Owned address required'using errcode='42501';end if;
 if address_row.revision<>p_expected_revision then raise exception 'Address changed. Reload'using errcode='PT409';end if;
 if p_operation='delete'then delete from public.addresses where id=address_row.id;
 elsif address_row.label is distinct from btrim(p_label)or address_row.address is distinct from btrim(p_address)then
 update public.addresses set label=btrim(p_label),address=btrim(p_address),revision=revision+1 where id=address_row.id;
 else changed:=false;
 end if;end if;
 result:=jsonb_build_object('code','APPLIED','address_id',address_row.id,'operation',p_operation,'changed',changed);
 insert into final2_private.address_receipts(actor_id,request_id,payload,result)values(actor,p_request_id,payload,result);
 if changed then insert into public.security_audit_log(actor_id,action,target_type,target_id)
 values(actor,'address_'||case p_operation when'create'then'created'when'edit'then'updated'else'deleted'end,'addresses',address_row.id);end if;
 return result;end$$;
revoke all on function public.final2_change_address(uuid,text,bigint,bigint,text,text)from public,anon;
grant execute on function public.final2_change_address(uuid,text,bigint,bigint,text,text)to authenticated;
notify pgrst,'reload schema';
commit;
