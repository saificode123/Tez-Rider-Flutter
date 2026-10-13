-- FR-25 final review: exactly one confirmed admin recipient per submission.
-- Serialize unfinished-draft limits per customer without locking another user's
-- profile/order/draft. Preserve all previously generated synthetic test records.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
create or replace function public.fr25_prepare(p_request_id uuid,p_order_id bigint) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); d fr25_private.drafts; begin
 if actor is null or public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'Submission identifier required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('fr25-customer-'||actor,25));
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,25));
 select * into d from fr25_private.drafts where id=p_request_id and customer_id=actor for update;
 if d.id is null and exists(select 1 from fr25_private.drafts where id=p_request_id) then raise exception 'Submission access forbidden' using errcode='42501'; end if;
 if d.id is not null then
   if d.customer_id<>actor or d.order_id<>p_order_id or d.state='abandoned' then
     raise exception 'Submission access forbidden' using errcode='42501'; end if;
   return jsonb_build_object('request_id',d.id,'state',d.state);
 end if;
 perform 1 from public.orders where id=p_order_id and user_id=actor for update;
 perform fr25_private.check_order(p_order_id,actor);
 if exists(select 1 from public.disputes where order_id=p_order_id and upper(replace(status,' ','_')) in ('OPEN','UNDER_REVIEW','ESCALATED')) then
   raise exception 'This order already has an open dispute.' using errcode='PT409'; end if;
 if (select count(*) from fr25_private.drafts where customer_id=actor and state='draft' and created_at>now()-interval '24 hours')>=10 then
   raise exception 'Too many unfinished submissions. Complete or discard a draft.' using errcode='PT429'; end if;
 insert into fr25_private.drafts(id,auth_id,customer_id,order_id) values(p_request_id,auth.uid(),actor,p_order_id);
 return jsonb_build_object('request_id',p_request_id,'state','draft');
end $$;
create or replace function public.create_dispute(p_order_id bigint,p_reason text,p_description text,p_evidence_paths text[],p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor bigint:=public.fr21_actor(); d fr25_private.drafts; existing public.disputes; result bigint; admin_id bigint; begin
 if actor is null or public.fr21_role() is distinct from 'customer' then raise exception 'Customer required' using errcode='42501'; end if;
 -- Serialize all requests for this order, then the draft. No opposite lock ordering.
 perform 1 from public.orders where id=p_order_id and user_id=actor for update;
 if not found then raise exception 'Order access forbidden' using errcode='42501'; end if;
 select * into d from fr25_private.drafts where id=p_request_id and customer_id=actor and order_id=p_order_id for update;
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
 select u.id into admin_id from public.users u where u.role='admin' and u.verification_status='approved'
 and exists(select 1 from auth.users a where a.email=u.email and a.email_confirmed_at is not null) order by u.id limit 1;
 if admin_id is null then raise exception 'No approved administrator is available. Retry later.' using errcode='PT503'; end if;
 insert into public.disputes(type,"by",status,customer_id,order_id,request_id,reason,description,evidence_paths)
 values(p_reason,actor::text,'Open',actor,p_order_id,p_request_id,p_reason,btrim(p_description),p_evidence_paths) returning id into result;
 update fr25_private.drafts set state='submitted' where id=d.id;
 insert into public.notifications(user_id,title,message,type,dispute_id)
 values(admin_id,'New customer dispute','Order #'||p_order_id||' has a new dispute.','dispute',result);
 return jsonb_build_object('id',result,'request_id',p_request_id,'status','Open');
end $$;
create or replace function public.fr25_abandon(p_request_id uuid) returns text[]
language plpgsql security definer set search_path='' as $$ declare d fr25_private.drafts; begin
 select * into d from fr25_private.drafts where id=p_request_id and customer_id=public.fr21_actor() for update;
 if d.id is null or d.customer_id is distinct from public.fr21_actor() or public.fr21_role() is distinct from 'customer' then raise exception 'Submission access forbidden' using errcode='42501'; end if;
 if d.state='submitted' or exists(select 1 from public.disputes where request_id=d.id) then return array[]::text[]; end if;
 update fr25_private.drafts set state='abandoned' where id=d.id;
 return array(select name from storage.objects where bucket_id='dispute-evidence' and name like d.auth_id||'/'||d.id||'/%');
end $$;
notify pgrst,'reload schema';
commit;
