-- FR-25 review hardening: reserve at most three immutable object paths before
-- Storage writes. Reuse the existing role model and pagination indexes.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
alter table fr25_private.evidence add column uploaded boolean not null default true;
create function public.fr25_begin_evidence(p_auth_id uuid,p_request_id uuid,p_digest text,p_mime text,p_size integer) returns text
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; p text; begin
 select * into d from fr25_private.drafts where id=p_request_id for update;
 if d.id is null or d.auth_id is distinct from p_auth_id or d.state<>'draft' then raise exception 'Evidence access forbidden' using errcode='42501'; end if;
 perform fr25_private.check_order(d.order_id,d.customer_id);
 if p_digest is null or p_digest!~'^[0-9a-f]{64}$' or p_mime is null or p_mime not in ('image/png','image/jpeg')
 or p_size is null or p_size not between 1 and 5242880 then raise exception 'Invalid image' using errcode='22023'; end if;
 p:=d.auth_id||'/'||d.id||'/'||p_digest||case when p_mime='image/png' then '.png' else '.jpg' end;
 if not exists(select 1 from fr25_private.evidence where path=p) and (select count(*) from fr25_private.evidence where draft_id=d.id)>=3 then
  raise exception 'Select 1–3 evidence images.' using errcode='22023'; end if;
 insert into fr25_private.evidence(path,draft_id,digest,mime,size,uploaded) values(p,d.id,p_digest,p_mime,p_size,false) on conflict(path) do nothing;
 return p;
end $$;
revoke all on function public.fr25_begin_evidence(uuid,uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.fr25_begin_evidence(uuid,uuid,text,text,integer) to service_role;
create or replace function public.fr25_finish_upload(p_auth_id uuid,p_request_id uuid,p_digest text,p_mime text,p_size integer) returns text
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
 insert into fr25_private.evidence(path,draft_id,digest,mime,size,uploaded) values(p,d.id,p_digest,p_mime,p_size,true) on conflict(path) do update set uploaded=true;
 return p;
end $$;
create or replace function public.create_dispute(p_order_id bigint,p_reason text,p_description text,p_evidence_paths text[],p_request_id uuid) returns jsonb
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
 if p_description is null or p_description ~ '^[[:space:]]*$' or char_length(btrim(p_description)) not between 1 and 2000 then raise exception 'Enter a description of 1–2000 characters.' using errcode='22023'; end if;
 if p_evidence_paths is null or cardinality(p_evidence_paths) not between 1 and 3
 or cardinality(p_evidence_paths)<>(select count(distinct x) from unnest(p_evidence_paths)x) then raise exception 'Select 1–3 evidence images.' using errcode='22023'; end if;
 if exists(select 1 from unnest(p_evidence_paths)p where not exists(
   select 1 from fr25_private.evidence e join storage.objects o on o.name=e.path and o.bucket_id='dispute-evidence'
   where e.path=p and e.draft_id=d.id and e.uploaded and (o.metadata->>'size')::bigint=e.size and o.metadata->>'mimetype'=e.mime)) then
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
create function public.fr25_order_history(p_before bigint default null) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$ begin
 if public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 return query select jsonb_build_object('id',o.id,'amount',o.amount,'order_status',o.order_status,'created_at',o.created_at,
 'rider_id',o.rider_id,'delivered_at',o.delivered_at,'dispute_open',exists(select 1 from public.disputes d where d.order_id=o.id
 and upper(replace(d.status,' ','_')) in ('OPEN','UNDER_REVIEW','ESCALATED')))
 from public.orders o where o.user_id=public.fr21_actor() and (p_before is null or o.id<p_before) order by o.id desc limit 30;
end $$;
revoke all on function public.fr25_order_history(bigint) from public,anon;
grant execute on function public.fr25_order_history(bigint) to authenticated;
notify pgrst,'reload schema';
commit;
