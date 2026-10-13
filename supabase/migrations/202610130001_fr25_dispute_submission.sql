-- FR-25: additive TEST migration. No resets, identity changes, or FR-26 writes.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
alter table public.orders add column delivered_at timestamptz;
-- Only confirmed server receipts are a trustworthy historical delivery source.
update public.orders o set delivered_at=p.verified_at from public.delivery_proof p
 where p.proofid='fr21-otp-'||o.id and p.otpconfirmed is true and p.is_verified is true
 and o.order_status='delivered' and p.verified_at is not null;
create function public.fr25_delivery_timestamp() returns trigger
language plpgsql set search_path='' as $$ begin
 if TG_OP='INSERT' then
   if new.order_status='delivered' then new.delivered_at:=clock_timestamp();
   else new.delivered_at:=null; end if;
 elsif old.order_status is distinct from 'delivered' and new.order_status='delivered' then
   new.delivered_at:=clock_timestamp();
 else new.delivered_at:=old.delivered_at;
 end if;
 return new;
end $$;
create trigger fr25_delivery_timestamp before insert or update on public.orders
 for each row execute function public.fr25_delivery_timestamp();

alter table public.disputes
 add column customer_id bigint references public.users(id),
 add column order_id bigint references public.orders(id),
 add column request_id uuid unique,
 add column reason text,
 add column description text,
 add column evidence_paths text[];
-- Preserve legacy title-case values. No resolution implementation is added.
alter table public.disputes add constraint fr25_dispute_status check
 (upper(replace(status,' ','_')) in ('OPEN','UNDER_REVIEW','RESOLVED','CLOSED','ESCALATED','REJECTED')) not valid;
alter table public.disputes add constraint fr25_dispute_shape check
 (request_id is null or (customer_id is not null and order_id is not null and reason is not null
 and char_length(btrim(description)) between 1 and 2000 and cardinality(evidence_paths) between 1 and 3));
create unique index fr25_one_open_order_idx on public.disputes(order_id)
 where upper(replace(status,' ','_')) in ('OPEN','UNDER_REVIEW','ESCALATED');
create index fr25_customer_history_idx on public.disputes(customer_id,id desc);
create index fr25_order_history_idx on public.disputes(order_id,id desc);
create index fr25_eligible_orders_idx on public.orders(user_id,delivered_at desc,id desc)
 where order_status='delivered';
create schema fr25_private;
revoke all on schema fr25_private from public,anon,authenticated;
create table fr25_private.drafts(
 id uuid primary key, auth_id uuid not null, customer_id bigint not null references public.users(id),
 order_id bigint not null references public.orders(id), state text not null default 'draft'
 check(state in ('draft','submitted','abandoned')), created_at timestamptz not null default now());
create index fr25_draft_owner_idx on fr25_private.drafts(customer_id,state,created_at);
create index fr25_draft_order_idx on fr25_private.drafts(order_id);
create table fr25_private.evidence(
 path text primary key, draft_id uuid not null references fr25_private.drafts(id),
 digest text not null check(digest~'^[0-9a-f]{64}$'), mime text not null check(mime in ('image/png','image/jpeg')),
 size integer not null check(size between 1 and 5242880), validated_at timestamptz not null default now());
create index fr25_evidence_draft_idx on fr25_private.evidence(draft_id);
alter table fr25_private.drafts enable row level security;
alter table fr25_private.evidence enable row level security;
revoke all on all tables in schema fr25_private from public,anon,authenticated;
alter table public.notifications add column dispute_id bigint references public.disputes(id);
create unique index fr25_notification_once_idx on public.notifications(dispute_id,user_id)
 where dispute_id is not null;
create policy fr25_dispute_read_guard on public.disputes as restrictive for select to authenticated
 using((customer_id=(select public.fr21_actor()) and (select public.fr21_role())='customer')
 or (select public.fr21_role())='admin');
create policy fr25_dispute_insert_deny on public.disputes as restrictive for insert to authenticated with check(false);
create policy fr25_dispute_update_deny on public.disputes as restrictive for update to authenticated using(false);
create policy fr25_dispute_delete_deny on public.disputes as restrictive for delete to authenticated using(false);
revoke all on public.disputes from public,anon,authenticated;
grant select on public.disputes to authenticated;

create function public.fr25_options() returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('description_limit',2000,'reasons',jsonb_build_array('Damaged items','Missing items','Wrong items','Quality issue','Other'))
$$;
create function fr25_private.check_order(p_order_id bigint,p_actor bigint) returns void
language plpgsql set search_path='' as $$ declare o public.orders; begin
 select * into o from public.orders where id=p_order_id;
 if o.id is null or o.user_id is distinct from p_actor then raise exception 'Order access forbidden' using errcode='42501'; end if;
 if o.order_status is distinct from 'delivered' then raise exception 'Select a delivered order.' using errcode='22023'; end if;
 if o.delivered_at is null then raise exception 'Delivery time is unavailable. Contact support.' using errcode='22023'; end if;
 if clock_timestamp()>o.delivered_at+interval '24 hours' then
   raise exception 'The dispute window for this order has closed.' using errcode='PT422'; end if;
end $$;
create function public.fr25_prepare(p_request_id uuid,p_order_id bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); d fr25_private.drafts; begin
 if actor is null or public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'Submission identifier required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,25));
 select * into d from fr25_private.drafts where id=p_request_id for update;
 if d.id is not null then
   if d.customer_id<>actor or d.order_id<>p_order_id or d.state='abandoned' then
     raise exception 'Submission access forbidden' using errcode='42501'; end if;
   return jsonb_build_object('request_id',d.id,'state',d.state);
 end if;
 perform 1 from public.orders where id=p_order_id for update;
 perform fr25_private.check_order(p_order_id,actor);
 if exists(select 1 from public.disputes where order_id=p_order_id and upper(replace(status,' ','_')) in ('OPEN','UNDER_REVIEW','ESCALATED')) then
   raise exception 'This order already has an open dispute.' using errcode='PT409'; end if;
 if (select count(*) from fr25_private.drafts where customer_id=actor and state='draft' and created_at>now()-interval '24 hours')>=10 then
   raise exception 'Too many unfinished submissions. Complete or discard a draft.' using errcode='PT429'; end if;
 insert into fr25_private.drafts(id,auth_id,customer_id,order_id) values(p_request_id,auth.uid(),actor,p_order_id);
 return jsonb_build_object('request_id',p_request_id,'state','draft');
end $$;
create function public.fr25_upload_authority(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; begin
 select * into d from fr25_private.drafts where id=p_request_id;
 if d.id is null or d.customer_id is distinct from public.fr21_actor() or public.fr21_role() is distinct from 'customer' then
   raise exception 'Evidence access forbidden' using errcode='42501'; end if;
 if d.state<>'draft' then raise exception 'Submission is immutable.' using errcode='PT409'; end if;
 perform fr25_private.check_order(d.order_id,d.customer_id);
 return jsonb_build_object('auth_id',d.auth_id,'request_id',d.id);
end $$;
-- Only the trusted validating Edge Function can attest to decoded image bytes.
create function public.fr25_finish_upload(p_auth_id uuid,p_request_id uuid,p_digest text,p_mime text,p_size integer) returns text
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; p text; o storage.objects; begin
 select * into d from fr25_private.drafts where id=p_request_id for update;
 if d.id is null or d.auth_id is distinct from p_auth_id or d.state<>'draft' then
   raise exception 'Evidence access forbidden' using errcode='42501'; end if;
 perform fr25_private.check_order(d.order_id,d.customer_id);
 if p_digest is null or p_digest!~'^[0-9a-f]{64}$' or p_mime is null or p_mime not in ('image/png','image/jpeg')
 or p_size is null or p_size not between 1 and 5242880 then raise exception 'Invalid image' using errcode='22023'; end if;
 p:=d.auth_id||'/'||d.id||'/'||p_digest||case when p_mime='image/png' then '.png' else '.jpg' end;
 select * into o from storage.objects where bucket_id='dispute-evidence' and name=p;
 if o.id is null or o.metadata->>'mimetype' is distinct from p_mime or (o.metadata->>'size')::bigint is distinct from p_size::bigint then
   raise exception 'Uploaded evidence is missing or invalid' using errcode='22023'; end if;
 if not exists(select 1 from fr25_private.evidence where path=p) and
   (select count(*) from fr25_private.evidence where draft_id=d.id)>=3 then
   raise exception 'Select 1–3 evidence images.' using errcode='22023'; end if;
 insert into fr25_private.evidence(path,draft_id,digest,mime,size) values(p,d.id,p_digest,p_mime,p_size) on conflict(path) do nothing;
 return p;
end $$;
create function public.create_dispute(p_order_id bigint,p_reason text,p_description text,p_evidence_paths text[],p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); d fr25_private.drafts; existing public.disputes; result bigint; begin
 if actor is null or public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 -- Serialize all requests for this order, then the draft. No opposite lock ordering.
 perform 1 from public.orders where id=p_order_id for update;
 select * into d from fr25_private.drafts where id=p_request_id for update;
 if d.id is null or d.customer_id is distinct from actor or d.order_id is distinct from p_order_id or d.state='abandoned' then
   raise exception 'Submission access forbidden' using errcode='42501'; end if;
 select * into existing from public.disputes where request_id=p_request_id;
 if existing.id is not null then
   if existing.reason is distinct from p_reason or existing.description is distinct from btrim(p_description)
   or existing.evidence_paths is distinct from p_evidence_paths then raise exception 'Retry must use the original submission.' using errcode='PT409'; end if;
   return jsonb_build_object('id',existing.id,'request_id',existing.request_id,'status',existing.status);
 end if;
 perform fr25_private.check_order(p_order_id,actor);
 if p_reason is null or not (public.fr25_options()->'reasons') ? p_reason then raise exception 'Select a valid dispute reason.' using errcode='22023'; end if;
 if p_description is null or char_length(btrim(p_description)) not between 1 and 2000 then raise exception 'Enter a description of 1–2000 characters.' using errcode='22023'; end if;
 if p_evidence_paths is null or cardinality(p_evidence_paths) not between 1 and 3
 or cardinality(p_evidence_paths)<>(select count(distinct x) from unnest(p_evidence_paths)x) then raise exception 'Select 1–3 evidence images.' using errcode='22023'; end if;
 if exists(select 1 from unnest(p_evidence_paths)p where not exists(
   select 1 from fr25_private.evidence e join storage.objects o on o.name=e.path and o.bucket_id='dispute-evidence'
   where e.path=p and e.draft_id=d.id and (o.metadata->>'size')::bigint=e.size and o.metadata->>'mimetype'=e.mime)) then
   raise exception 'Uploaded evidence is missing or unauthorized.' using errcode='42501'; end if;
 if exists(select 1 from public.disputes where order_id=p_order_id and upper(replace(status,' ','_')) in ('OPEN','UNDER_REVIEW','ESCALATED')) then
   raise exception 'This order already has an open dispute.' using errcode='PT409'; end if;
 insert into public.disputes(type,"by",status,customer_id,order_id,request_id,reason,description,evidence_paths)
 values(p_reason,actor::text,'Open',actor,p_order_id,p_request_id,p_reason,btrim(p_description),p_evidence_paths) returning id into result;
 update fr25_private.drafts set state='submitted' where id=d.id;
 insert into public.notifications(user_id,title,message,type,dispute_id)
 select id,'New customer dispute','Order #'||p_order_id||' has a new dispute.','dispute',result
 from public.users where role='admin' and verification_status='approved' on conflict do nothing;
 return jsonb_build_object('id',result,'request_id',p_request_id,'status','Open');
end $$;
create function public.fr25_request_status(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; result jsonb; begin
 select * into d from fr25_private.drafts where id=p_request_id;
 if d.id is null then return null; end if;
 if d.customer_id is distinct from public.fr21_actor() or public.fr21_role() is distinct from 'customer' then raise exception 'Submission access forbidden' using errcode='42501'; end if;
 select jsonb_build_object('id',id,'request_id',request_id,'status',status) into result from public.disputes where request_id=d.id;
 return result;
end $$;
create function public.fr25_abandon(p_request_id uuid) returns text[]
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; begin
 select * into d from fr25_private.drafts where id=p_request_id for update;
 if d.id is null or d.customer_id is distinct from public.fr21_actor() or public.fr21_role() is distinct from 'customer' then raise exception 'Submission access forbidden' using errcode='42501'; end if;
 if d.state='submitted' or exists(select 1 from public.disputes where request_id=d.id) then return array[]::text[]; end if;
 update fr25_private.drafts set state='abandoned' where id=d.id;
 return array(select name from storage.objects where bucket_id='dispute-evidence' and name like d.auth_id||'/'||d.id||'/%');
end $$;
create function public.fr25_evidence_authority(p_dispute_id bigint,p_index integer) returns text
language plpgsql security definer set search_path='' as $$ declare d public.disputes; begin
 select * into d from public.disputes where id=p_dispute_id;
 if d.id is null or ((d.customer_id=public.fr21_actor() and public.fr21_role()='customer') or public.fr21_role()='admin') is not true then raise exception 'Evidence access forbidden' using errcode='42501'; end if;
 if p_index is null or p_index<1 or p_index>coalesce(cardinality(d.evidence_paths),0) then raise exception 'Evidence not found' using errcode='22023'; end if;
 return d.evidence_paths[p_index];
end $$;
-- Storage API owns object creation/deletion. SQL never fabricates object records.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('dispute-evidence','dispute-evidence',false,5242880,array['image/jpeg','image/png']);
create policy fr25_evidence_direct_deny on storage.objects as restrictive for all to anon,authenticated
 using(bucket_id<>'dispute-evidence') with check(bucket_id<>'dispute-evidence');
revoke all on all functions in schema fr25_private from public,anon,authenticated;
revoke all on function public.fr25_delivery_timestamp(),public.fr25_options(),public.fr25_prepare(uuid,bigint),
 public.fr25_upload_authority(uuid),public.fr25_finish_upload(uuid,uuid,text,text,integer),
 public.create_dispute(bigint,text,text,text[],uuid),public.fr25_request_status(uuid),public.fr25_abandon(uuid),
 public.fr25_evidence_authority(bigint,integer) from public,anon,authenticated;
grant execute on function public.fr25_options(),public.fr25_prepare(uuid,bigint),public.fr25_upload_authority(uuid),
 public.create_dispute(bigint,text,text,text[],uuid),public.fr25_request_status(uuid),public.fr25_abandon(uuid),
 public.fr25_evidence_authority(bigint,integer) to authenticated;
grant execute on function public.fr25_finish_upload(uuid,uuid,text,text,integer) to service_role;
create function public.fr25_eligible_orders(p_before bigint default null) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$ begin
 if public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 return query select jsonb_build_object('id',o.id,'amount',o.amount,'order_status',o.order_status,'delivered_at',o.delivered_at)
 from public.orders o where o.user_id=public.fr21_actor() and o.order_status='delivered'
 and o.delivered_at between statement_timestamp()-interval '24 hours' and statement_timestamp()
 and (p_before is null or o.id<p_before) and not exists(select 1 from public.disputes d where d.order_id=o.id
 and upper(replace(d.status,' ','_')) in ('OPEN','UNDER_REVIEW','ESCALATED')) order by o.id desc limit 30;
end $$;
create function public.fr25_history(p_before bigint default null) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$ begin
 if public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 return query select jsonb_build_object('id',d.id,'order_id',d.order_id,'reason',d.reason,'status',d.status,'created_at',d.created_at)
 from public.disputes d where d.customer_id=public.fr21_actor() and (p_before is null or d.id<p_before) order by d.id desc limit 30;
end $$;
create function public.fr25_detail(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$ declare result jsonb; begin
 if public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 select jsonb_build_object('id',d.id,'order_id',d.order_id,'reason',d.reason,'description',d.description,'status',d.status,
 'created_at',d.created_at,'evidence_count',cardinality(d.evidence_paths),'amount',o.amount,'delivered_at',o.delivered_at)
 into result from public.disputes d join public.orders o on o.id=d.order_id where d.id=p_id and d.customer_id=public.fr21_actor();
 if result is null then raise exception 'Dispute access forbidden' using errcode='42501'; end if;
 return result;
end $$;
revoke all on function public.fr25_eligible_orders(bigint),public.fr25_history(bigint),public.fr25_detail(bigint) from public,anon;
grant execute on function public.fr25_eligible_orders(bigint),public.fr25_history(bigint),public.fr25_detail(bigint) to authenticated;

-- Essential preservation of customer/admin chat: existing TEST baseline has no
-- client grants. Re-enable only owned reads and genuine participant messages.
create index fr25_chat_owner1_idx on public.chat_rooms(user1_id,id desc);
create index fr25_chat_owner2_idx on public.chat_rooms(user2_id,id desc);
create index fr25_chat_messages_idx on public.chat_messages(room_id,id desc);
create function public.fr25_chat_owned(p_room bigint) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.chat_rooms where id=p_room and public.fr21_actor() in (user1_id,user2_id))
$$;
create policy fr25_chat_read on public.chat_rooms as restrictive for select to authenticated
 using((select public.fr21_actor()) in (user1_id,user2_id));
create policy fr25_message_read on public.chat_messages as restrictive for select to authenticated using(public.fr25_chat_owned(room_id));
create policy fr25_message_insert on public.chat_messages as restrictive for insert to authenticated
 with check(sender_id=(select public.fr21_actor()) and public.fr25_chat_owned(room_id)
 and char_length(btrim(message)) between 1 and 2000 and image_url is null);
grant select on public.chat_rooms,public.chat_messages to authenticated;
grant insert(room_id,sender_id,message) on public.chat_messages to authenticated;
grant usage,select on sequence public.chat_messages_id_seq to authenticated;
create function public.fr25_support_chat() returns bigint language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); admin_id bigint; room bigint; begin
 if actor is null or public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 perform 1 from public.users where id=actor for update;
 select id into admin_id from public.users where role='admin' and verification_status='approved' order by id limit 1;
 if admin_id is null then raise exception 'No admin found.' using errcode='22023'; end if;
 select id into room from public.chat_rooms where (user1_id=actor and user2_id=admin_id) or (user2_id=actor and user1_id=admin_id) order by id limit 1;
 if room is null then
  insert into public.chat_rooms(user1_id,user2_id) values(actor,admin_id) returning id into room;
  insert into public.chat_participants(room_id,user_id) values(room,actor),(room,admin_id);
 end if;
 return room;
end $$;
create function public.fr25_chat_list(p_before bigint default null) returns setof jsonb language plpgsql stable security definer set search_path='' as $$ begin
 if public.fr21_actor() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return query select jsonb_build_object('room_id',r.id,'other_name',u.name,'last_message',m.message,'last_time',m.created_at)
 from public.chat_rooms r join public.users u on u.id=case when r.user1_id=public.fr21_actor() then r.user2_id else r.user1_id end
 left join lateral(select message,created_at from public.chat_messages where room_id=r.id order by id desc limit 1)m on true
 where public.fr21_actor() in (r.user1_id,r.user2_id) and (p_before is null or r.id<p_before) order by r.id desc limit 30;
end $$;
revoke all on function public.fr25_chat_owned(bigint),public.fr25_support_chat(),public.fr25_chat_list(bigint) from public,anon;
grant execute on function public.fr25_chat_owned(bigint),public.fr25_support_chat(),public.fr25_chat_list(bigint) to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
 select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='chat_messages') then
 alter publication supabase_realtime add table public.chat_messages; end if;
end $$;
notify pgrst,'reload schema';
commit;
