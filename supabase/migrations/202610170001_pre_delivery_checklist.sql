-- New checklist evidence; accepted migrations are never replayed.
begin;
set local lock_timeout='5s';
create schema checklist_private;
revoke all on schema checklist_private from public,anon,authenticated,service_role;
create table checklist_private.definitions(
 version integer primary key,items jsonb not null check(jsonb_typeof(items)='array'),
 approved boolean not null default false);
alter table checklist_private.definitions enable row level security;
insert into checklist_private.definitions values(1,'[
 {"id":"items_match","label":"Items match the order."},
 {"id":"packaging_intact","label":"Packaging is sealed and undamaged."},
 {"id":"details_confirmed","label":"Delivery address and customer details are confirmed."}
]',true);
alter table public.rider_assignments
 add column checklist_completed boolean not null default false,
 add column checklist_completed_at timestamptz,
 add constraint checklist_completion_pair check(checklist_completed=(checklist_completed_at is not null));
create table public.pre_delivery_checklists(
 assignment_id bigint primary key references public.rider_assignments(id),
 rider_id bigint not null references public.users(id),
 checklist_version integer not null references checklist_private.definitions(version),
 confirmations jsonb not null check(jsonb_typeof(confirmations)='array'),
 definition_snapshot jsonb not null,
 submitted_at timestamptz not null default clock_timestamp());
create index checklist_rider_idx on public.pre_delivery_checklists(rider_id,assignment_id);
-- Exact immutable migration-time identity, including old orphan in-transit
-- orders. No future assignment/order can acquire this compatibility exemption.
create table checklist_private.legacy_transit(
 order_id bigint primary key references public.orders(id),rider_id bigint not null,
 assignment_id bigint references public.rider_assignments(id),recorded_at timestamptz not null default clock_timestamp(),
 reason text not null check(reason='already_in_transit_at_migration'));
alter table checklist_private.legacy_transit enable row level security;
insert into checklist_private.legacy_transit(order_id,rider_id,assignment_id,reason)
 select o.id,o.rider_id,(select a.id from public.rider_assignments a
 where a.orderid=o.id and a.riderid=o.rider_id and a.status in('Pending','Accepted')order by a.id desc limit 1),
 'already_in_transit_at_migration' from public.orders o where o.order_status='on_the_way'and o.rider_id is not null;
create trigger checklist_legacy_immutable before update or delete on checklist_private.legacy_transit
 for each row execute function public.fr26_append_only();
revoke all on public.pre_delivery_checklists from public,anon,authenticated,service_role;
alter table public.pre_delivery_checklists enable row level security;
create policy checklist_read on public.pre_delivery_checklists for select to authenticated
 using((public.fr21_role()='rider'and rider_id=public.fr21_actor())or public.fr21_role()='admin');
grant select on public.pre_delivery_checklists to authenticated,service_role;
create trigger checklist_evidence_immutable before update or delete on public.pre_delivery_checklists
 for each row execute function public.fr26_append_only();

create function checklist_private.legacy(p_order bigint,p_rider bigint)returns boolean
 language sql stable security definer set search_path=''as $$
 select exists(select 1 from checklist_private.legacy_transit l where l.order_id=p_order and l.rider_id=p_rider
 and((l.assignment_id is null and not exists(select 1 from public.rider_assignments a where a.orderid=l.order_id))
 or exists(select 1 from public.rider_assignments a where a.id=l.assignment_id
 and a.orderid=l.order_id and a.riderid=l.rider_id and a.status in('Pending','Accepted')
 and not exists(select 1 from public.rider_assignments newer where newer.orderid=l.order_id
 and newer.status in('Pending','Accepted')and newer.id<>l.assignment_id))))
$$;
create function checklist_private.allowed(p_order bigint,p_rider bigint)returns boolean
 language sql stable security definer set search_path=''as $$
 select checklist_private.legacy(p_order,p_rider)or exists(
 select 1 from public.rider_assignments a join public.pre_delivery_checklists c on c.assignment_id=a.id
 where a.orderid=p_order and a.riderid=p_rider and a.status='Accepted'
 and a.checklist_completed and a.checklist_completed_at=c.submitted_at and c.rider_id=p_rider)
$$;
create function checklist_private.guard_assignment()returns trigger language plpgsql security definer set search_path=''as $$begin
 if tg_op='INSERT'and(new.checklist_completed or new.checklist_completed_at is not null)then
  raise exception 'Checklist requires server submission'using errcode='42501';end if;
 if tg_op='UPDATE'then
  if old.checklist_completed and(new.checklist_completed is distinct from old.checklist_completed
   or new.checklist_completed_at is distinct from old.checklist_completed_at
   or new.orderid is distinct from old.orderid or new.riderid is distinct from old.riderid)then
   raise exception 'Completed checklist evidence is immutable'using errcode='42501';end if;
  if new.checklist_completed and not old.checklist_completed and not exists(
   select 1 from public.pre_delivery_checklists c where c.assignment_id=new.id
   and c.rider_id=new.riderid and c.submitted_at=new.checklist_completed_at)then
   raise exception 'Checklist evidence required'using errcode='42501';end if;
 end if;return new;end$$;
create trigger checklist_guard_assignment before insert or update on public.rider_assignments
 for each row execute function checklist_private.guard_assignment();

create function public.pre_delivery_checklist(p_order_id bigint)returns jsonb
 language plpgsql security definer set search_path=''as $$
declare o public.orders;a public.rider_assignments;d checklist_private.definitions;actor bigint:=public.fr21_actor();begin
 select *into o from public.orders where id=p_order_id;
 if actor is null or public.fr21_role()is distinct from'rider'or o.rider_id is distinct from actor
 or not public.fr21_approved_rider(actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 select *into a from public.rider_assignments where orderid=o.id and riderid=actor and status in('Pending','Accepted')order by id desc limit 1;
 select *into d from checklist_private.definitions where approved order by version desc limit 1;
 return jsonb_build_object('code',case when a.id is null and not checklist_private.legacy(o.id,actor)then'ASSIGNMENT_REQUIRED'else'OK'end,
 'assignment_id',a.id,'assignment_status',a.status,'version',d.version,'items',d.items,'completed',coalesce(a.checklist_completed,false),
 'completed_at',a.checklist_completed_at,'legacy_exempt',checklist_private.legacy(o.id,actor),'order_status',o.order_status);
end$$;

create function public.submit_pre_delivery_checklist(p_assignment_id bigint,p_version integer,p_confirmations jsonb)returns jsonb
 language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;d checklist_private.definitions;c public.pre_delivery_checklists;oid bigint;begin
 if actor is null or public.fr21_role()is distinct from'rider'or not public.fr21_approved_rider(actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 select orderid into oid from public.rider_assignments where id=p_assignment_id and riderid=actor;
 if oid is null then return jsonb_build_object('code','FORBIDDEN');end if;
 -- Parent before assignment; all validation and writes share the same lock.
 select *into o from public.orders where id=oid for update;
 select *into a from public.rider_assignments where id=p_assignment_id for update;
 if a.riderid is distinct from actor or a.orderid is distinct from o.id or o.rider_id is distinct from actor then return jsonb_build_object('code','FORBIDDEN');end if;
 perform 1 from public.users where id=actor and role='rider'and verification_status='approved'and not is_blocked for share;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if coalesce(a.status,'')not in('Pending','Accepted')or o.order_status in('cancelled','delivered')then return jsonb_build_object('code','INACTIVE_ASSIGNMENT');end if;
 select *into c from public.pre_delivery_checklists where assignment_id=a.id;
 if found then return jsonb_build_object('code','COMPLETED','assignment_id',a.id,'version',c.checklist_version,'completed',true,'completed_at',c.submitted_at,'replayed',true);end if;
 if a.status is distinct from'Accepted'or o.order_status is distinct from'ready'then return jsonb_build_object('code','PICKUP_REQUIRED');end if;
 if exists(select 1 from public.vendor_orders where order_id=o.id and status not in('ready','on_the_way'))then return jsonb_build_object('code','PICKUP_REQUIRED');end if;
 select *into d from checklist_private.definitions where version=p_version and approved;
 if not found then return jsonb_build_object('code','INVALID_VERSION');end if;
 if jsonb_typeof(p_confirmations)is distinct from'array'then return jsonb_build_object('code','INVALID_CONFIRMATIONS');end if;
 if jsonb_array_length(p_confirmations)<>jsonb_array_length(d.items)then return jsonb_build_object('code','INVALID_CONFIRMATIONS');end if;
 if exists(select 1 from jsonb_array_elements(p_confirmations)x where jsonb_typeof(x)<>'object'
 or not(x ?& array['id','confirmed'])or(x-'id'-'confirmed')<>'{}'::jsonb
 or x->'confirmed'is distinct from'true'::jsonb or not exists(select 1 from jsonb_array_elements(d.items)i where i->'id'=x->'id'))
 or(select count(distinct x->>'id')from jsonb_array_elements(p_confirmations)x)<>jsonb_array_length(d.items)then return jsonb_build_object('code','INVALID_CONFIRMATIONS');end if;
 insert into public.pre_delivery_checklists(assignment_id,rider_id,checklist_version,confirmations,definition_snapshot)
 values(a.id,actor,d.version,p_confirmations,d.items)returning *into c;
 update public.rider_assignments set checklist_completed=true,checklist_completed_at=c.submitted_at where id=a.id;
 return jsonb_build_object('code','COMPLETED','assignment_id',a.id,'version',c.checklist_version,'completed',true,'completed_at',c.submitted_at,'replayed',false);
end$$;

create function public.start_checklisted_delivery(p_assignment_id bigint)returns jsonb
 language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;a public.rider_assignments;oid bigint;begin
 if actor is null or public.fr21_role()is distinct from'rider'or not public.fr21_approved_rider(actor)then return jsonb_build_object('code','FORBIDDEN');end if;
 select orderid into oid from public.rider_assignments where id=p_assignment_id and riderid=actor;
 if oid is null then return jsonb_build_object('code','FORBIDDEN');end if;
 select *into o from public.orders where id=oid for update;
 select *into a from public.rider_assignments where id=p_assignment_id for update;
 if a.riderid is distinct from actor or a.orderid is distinct from o.id or o.rider_id is distinct from actor then return jsonb_build_object('code','FORBIDDEN');end if;
 perform 1 from public.users where id=actor and role='rider'and verification_status='approved'and not is_blocked for share;
 if not found then return jsonb_build_object('code','FORBIDDEN');end if;
 if a.status is distinct from'Accepted'or coalesce(o.order_status,'')not in('ready','on_the_way')then return jsonb_build_object('code','PICKUP_REQUIRED');end if;
 if exists(select 1 from public.vendor_orders where order_id=o.id and status not in('ready','on_the_way'))then return jsonb_build_object('code','PICKUP_REQUIRED');end if;
 if not checklist_private.allowed(o.id,actor)then return jsonb_build_object('code','CHECKLIST_REQUIRED');end if;
 if o.order_status='on_the_way'then return jsonb_build_object('code','STARTED','order_status','on_the_way','replayed',true);end if;
 update public.orders set order_status='on_the_way'where id=o.id;
 return jsonb_build_object('code','STARTED','order_status','on_the_way','replayed',false);
end$$;

-- Existing accept RPC still validates online presence, ownership, busy state
-- and canonical Auth. Acceptance now means pickup; starting is a separate RPC.
do $$declare s text;begin
 s:=pg_get_functiondef('public.fr21_accept_order(bigint)'::regprocedure);
 if position('order_status=''on_the_way'',delivery_otp=otp'in s)=0 then raise exception 'Review changed acceptance source';end if;
 s:=replace(s,'order_status=''on_the_way'',delivery_otp=otp','order_status=''ready'',delivery_otp=otp');
 s:=replace(s,'''order_status'',''on_the_way'',''rider_id'',actor','''order_status'',''ready'',''rider_id'',actor');
 s:=replace(s,'if o.rider_id is null then',
 'if o.order_status=''on_the_way''and checklist_private.allowed(o.id,actor)then return jsonb_build_object(''order_status'',''on_the_way'',''rider_id'',actor);end if;'||chr(10)||' if o.rider_id is null then');
 execute s;
end$$;
-- Vendor on_the_way remains its accepted reservation convention, not proof
-- that the rider has started. Preserve all other FR10 aggregation rules.
do $$declare s text;begin
 s:=pg_get_functiondef('public.sync_order_status_from_vendor_order()'::regprocedure);
 s:=replace(s,'update public.orders set order_status=new.status where id=new.order_id;',
 'update public.orders set order_status=case when new.status=''on_the_way''then case when o.order_status=''on_the_way''and checklist_private.allowed(o.id,o.rider_id)then ''on_the_way''else ''ready''end else new.status end where id=new.order_id;');
 if position('then next_status:=''on_the_way'';'in s)=0 then raise exception 'Review changed FR10 aggregation';end if;
 s:=replace(s,'then next_status:=''on_the_way'';','then next_status:=case when o.order_status=''on_the_way''and checklist_private.allowed(o.id,o.rider_id)then ''on_the_way''else ''ready''end;');
 execute s;
end$$;
create function checklist_private.guard_delivery()returns trigger language plpgsql set search_path=''as $$begin
 if new.order_status in('on_the_way','delivered')and(tg_op='INSERT'or new.order_status is distinct from old.order_status or new.rider_id is distinct from old.rider_id)then
  if current_user in('authenticated','anon','service_role')then raise exception 'Use secured rider delivery RPC'using errcode='42501';end if;
  if not checklist_private.allowed(new.id,new.rider_id)then raise exception 'CHECKLIST_REQUIRED'using errcode='23514';end if;
 end if;return new;end$$;
create trigger checklist_guard_delivery before insert or update on public.orders
 for each row execute function checklist_private.guard_delivery();
-- Check before request tags, attempts/rates, OTP state or completion mutation.
do $$declare s text;needle text:='if p_request_id is null or p_otp is null';begin
 s:=pg_get_functiondef('public.verify_delivery_otp(bigint,text,uuid)'::regprocedure);
 if position(needle in s)=0 then raise exception 'Review changed FR33 verifier';end if;
 s:=replace(s,needle,'if not checklist_private.allowed(o.id,a)then return jsonb_build_object(''code'',''CHECKLIST_REQUIRED'');end if;'||chr(10)||' '||needle);
 -- For pickup-stage requests return the actionable gate before WRONG_STATE.
 s:=replace(s,'if o.order_status is distinct from ''on_the_way'' then',
 'if o.order_status=''ready''and not checklist_private.allowed(o.id,a)then return jsonb_build_object(''code'',''CHECKLIST_REQUIRED'');end if;'||chr(10)||' if o.order_status is distinct from ''on_the_way'' then');
 execute s;
end$$;
revoke all on all tables in schema checklist_private from public,anon,authenticated,service_role;
revoke all on all functions in schema checklist_private from public,anon,authenticated,service_role;
revoke all on function public.pre_delivery_checklist(bigint),public.submit_pre_delivery_checklist(bigint,integer,jsonb),public.start_checklisted_delivery(bigint)from public,anon,service_role;
grant execute on function public.pre_delivery_checklist(bigint),public.submit_pre_delivery_checklist(bigint,integer,jsonb),public.start_checklisted_delivery(bigint)to authenticated;
notify pgrst,'reload schema';
commit;
