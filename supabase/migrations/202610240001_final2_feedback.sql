-- FR23/24: canonical delivered-order feedback, private review ownership and
-- public-in-app aggregate updates. No low-rating blocking policy is inferred.
begin;
alter table public.reviews add column target_user_id bigint references public.users(id),
 add column target_role text check(target_role in('vendor','rider')),
 add column verified_at timestamptz,add column request_payload jsonb,
 add constraint final2_verified_review_shape check(verified_at is null or(
  target_user_id is not null and target_role is not null and reviewer_id is not null
  and reviewee_id is not null and order_id is not null and rating is not null and request_payload is not null));
create unique index final2_feedback_once on public.reviews(order_id,reviewer_id,target_user_id)where verified_at is not null;
revoke insert,update,delete on public.reviews from anon,authenticated;

create table public.rating_summaries(
 target_user_id bigint primary key references public.users(id),
 target_role text not null check(target_role in('vendor','rider')),
 rating_count bigint not null check(rating_count>0),
 rating_total bigint not null check(rating_total>=rating_count and rating_total<=5*rating_count),
 average_rating numeric generated always as(round(rating_total::numeric/rating_count,2))stored,
 updated_at timestamptz not null default clock_timestamp()
);
alter table public.rating_summaries enable row level security;
revoke all on public.rating_summaries from public,anon,authenticated,service_role;
grant select on public.rating_summaries to authenticated,service_role;
-- Resolve visibility under a fixed-path definer: users-table RLS intentionally
-- hides unrelated profiles and must not suppress safe public rating events.
create function public.final2_rating_visible(p_target bigint,p_role text)returns boolean
language sql stable security definer set search_path=''as $$
 select public.is_current_user_allowed()and exists(select 1 from public.users a where a.id=public.fr21_actor()and a.verification_status='approved')
 and(public.fr21_role()='admin'or exists(select 1 from public.users t where t.id=p_target
  and t.role=p_role and t.role in('vendor','rider')and t.verification_status='approved'and not t.is_blocked))
$$;
revoke all on function public.final2_rating_visible(bigint,text)from public,anon;
grant execute on function public.final2_rating_visible(bigint,text)to authenticated;
create policy final2_rating_public_read on public.rating_summaries for select to authenticated using(
 public.final2_rating_visible(target_user_id,target_role));

create function final2_private.review_guard()returns trigger language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'then
  if old.verified_at is not null then raise exception 'Verified feedback is immutable'using errcode='42501';end if;
  return old;
 end if;
 if tg_op='UPDATE'and(old.verified_at is not null or new.verified_at is not null)then
  raise exception 'Verified feedback is immutable'using errcode='42501';end if;
 if new.verified_at is not null and current_user in('authenticated','anon','service_role')then
  raise exception 'Trusted feedback API required'using errcode='42501';end if;
 return new;end$$;
revoke all on function final2_private.review_guard()from public,anon,authenticated,service_role;
create trigger final2_review_guard before insert or update or delete on public.reviews
 for each row execute function final2_private.review_guard();
create function final2_private.review_aggregate()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if new.verified_at is null then return new;end if;
 insert into public.rating_summaries(target_user_id,target_role,rating_count,rating_total)
 values(new.target_user_id,new.target_role,1,new.rating)
 on conflict(target_user_id)do update set rating_count=public.rating_summaries.rating_count+1,
  rating_total=public.rating_summaries.rating_total+excluded.rating_total,updated_at=clock_timestamp()
 where public.rating_summaries.target_role=excluded.target_role;
 if not found then raise exception 'Rating role history requires review'using errcode='PT409';end if;
 return new;end$$;
revoke all on function final2_private.review_aggregate()from public,anon,authenticated,service_role;
create trigger final2_review_aggregate after insert on public.reviews for each row execute function final2_private.review_aggregate();

create function public.final2_feedback_context(p_order_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;targets jsonb;begin
 if actor is null or public.fr21_role()is distinct from'customer'or not exists(
  select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then
  raise exception 'Approved owning Customer required'using errcode='42501';end if;
 select *into o from public.orders where id=p_order_id and user_id=actor;
 if o.id is null then raise exception 'Owned order required'using errcode='42501';end if;
 if o.order_status is distinct from'delivered'or o.delivered_at is null or o.delivered_at>clock_timestamp()then
  raise exception 'Feedback requires confirmed delivery'using errcode='PT409';end if;
 with eligible as(
  select u.id,u.role,u.name from public.users u join public.vendor_orders v on v.vendor_id=u.id
   where v.order_id=o.id and v.status='delivered'and u.role='vendor'and u.auth_user_id is not null
  union
  select u.id,u.role,u.name from public.users u where u.id=o.vendor_id and u.role='vendor'and u.auth_user_id is not null
   and not exists(select 1 from public.vendor_orders where order_id=o.id)
  union
  select u.id,u.role,u.name from public.users u where u.id=o.rider_id and u.role='rider'and u.auth_user_id is not null)
 select coalesce(jsonb_agg(jsonb_build_object('target_id',e.id,'role',e.role,'name',e.name,'review',(
  select jsonb_build_object('id',r.id,'rating',r.rating,'comment',r.comment,'created_at',r.created_at)
  from public.reviews r where r.order_id=o.id and r.reviewer_id=auth.uid()and r.target_user_id=e.id and r.verified_at is not null))order by e.role,e.id),'[]')
 into targets from eligible e;
 return jsonb_build_object('code','OK','order_id',o.id,'targets',targets);
end$$;
revoke all on function public.final2_feedback_context(bigint)from public,anon;
grant execute on function public.final2_feedback_context(bigint)to authenticated;

create function public.final2_submit_feedback(p_order_id bigint,p_target_id bigint,p_rating integer,p_comment text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();o public.orders;existing public.reviews;target public.users;
 context jsonb;payload jsonb;comment_text text:=nullif(btrim(p_comment),'');result jsonb;begin
 if actor is null or public.fr21_role()is distinct from'customer'then raise exception 'Approved Customer required'using errcode='42501';end if;
 perform 1 from public.users where id=actor and verification_status='approved'and not is_blocked for share;
 if not found then raise exception 'Approved Customer required'using errcode='42501';end if;
 if p_order_id is null or p_order_id<=0 or p_target_id is null or p_target_id<=0 or p_request_id is null
  or p_rating is null or p_rating not between 1 and 5 or char_length(p_comment)>2000
  or regexp_replace(coalesce(p_comment,''),E'[\n\r\t]','','g')~'[[:cntrl:]]'then
  raise exception 'Choose 1 to 5 stars and feedback up to 2000 characters'using errcode='22023';end if;
 select *into o from public.orders where id=p_order_id and user_id=actor for update;
 if o.id is null then raise exception 'Owned order required'using errcode='42501';end if;
 payload:=jsonb_build_object('order_id',o.id,'target_id',p_target_id,'rating',p_rating,'comment',comment_text);
 select *into existing from public.reviews where id=p_request_id;
 if found then
  if existing.reviewer_id is distinct from auth.uid()or existing.request_payload is distinct from payload or existing.verified_at is null then
   raise exception 'Feedback request conflict'using errcode='PT409';end if;
  return jsonb_build_object('code','ALREADY_APPLIED','id',existing.id,'order_id',o.id,'target_id',p_target_id,'rating',existing.rating,'comment',existing.comment);
 end if;
 context:=public.final2_feedback_context(o.id);
 if not exists(select 1 from jsonb_array_elements(context->'targets')t where(t->>'target_id')::bigint=p_target_id)then
  raise exception 'Only the delivered Vendor or assigned Rider can be rated'using errcode='42501';end if;
 select *into target from public.users where id=p_target_id for share;
 select *into existing from public.reviews where order_id=o.id and reviewer_id=auth.uid()and target_user_id=target.id and verified_at is not null;
 if found then return jsonb_build_object('code','ALREADY_REVIEWED','id',existing.id,'order_id',o.id,'target_id',target.id,'rating',existing.rating,'comment',existing.comment);end if;
 insert into public.reviews(id,order_id,reviewer_id,reviewee_id,rating,comment,target_user_id,target_role,verified_at,request_payload)
 values(p_request_id,o.id,auth.uid(),target.auth_user_id,p_rating,comment_text,target.id,target.role,clock_timestamp(),payload);
 insert into public.security_audit_log(actor_id,action,target_type,target_id)values(actor,'feedback_submitted','users',target.id);
 return jsonb_build_object('code','SUBMITTED','id',p_request_id,'order_id',o.id,'target_id',target.id,'rating',p_rating,'comment',comment_text);
end$$;
revoke all on function public.final2_submit_feedback(bigint,bigint,integer,text,uuid)from public,anon;
grant execute on function public.final2_submit_feedback(bigint,bigint,integer,text,uuid)to authenticated;

create function public.final2_rating_summary(p_target_id bigint)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare actor bigint:=public.fr21_actor();target public.users;summary public.rating_summaries;recent jsonb;begin
 if actor is null or not exists(select 1 from public.users where id=actor and verification_status='approved'and not is_blocked)then
  raise exception 'Approved account required'using errcode='42501';end if;
 select *into target from public.users where id=p_target_id and role in('vendor','rider');
 if target.id is null or((target.is_blocked or target.verification_status<>'approved')and public.fr21_role()<>'admin')then
  raise exception 'Rating target unavailable'using errcode='42501';end if;
 select *into summary from public.rating_summaries where target_user_id=target.id and target_role=target.role;
 select coalesce(jsonb_agg(to_jsonb(r)order by created_at desc,id),'[]')into recent from(
  select id,rating,comment,created_at from public.reviews where target_user_id=target.id and target_role=target.role and verified_at is not null
   order by created_at desc,id limit 10)r;
 return jsonb_build_object('code','OK','target_id',target.id,'role',target.role,
  'count',coalesce(summary.rating_count,0),'average',summary.average_rating,'recent',recent);
end$$;
revoke all on function public.final2_rating_summary(bigint)from public,anon;
grant execute on function public.final2_rating_summary(bigint)to authenticated;
-- Keep existing Vendor cards/dashboard callers compatible. Rider ratings must
-- never be included in a Vendor average merely because they share an order.
create or replace function public.get_vendor_ratings(p_vendor_ids bigint[])
returns table(vendor_id bigint,avg_rating numeric,review_count bigint)
language plpgsql stable security invoker set search_path=''as $$begin
 if public.fr21_actor()is null or not exists(select 1 from public.users where id=public.fr21_actor()and verification_status='approved')then
  raise exception 'Approved account required'using errcode='42501';end if;
 if p_vendor_ids is null or cardinality(p_vendor_ids)>100 or exists(select 1 from unnest(p_vendor_ids)v where v is null or v<=0)then
  raise exception 'Invalid Vendor rating targets'using errcode='22023';end if;
 return query select s.target_user_id,s.average_rating,s.rating_count from public.rating_summaries s
  where s.target_user_id=any(p_vendor_ids)and s.target_role='vendor'and public.final2_catalog_vendor_visible(s.target_user_id);
end$$;
revoke all on function public.get_vendor_ratings(bigint[])from public,anon;
grant execute on function public.get_vendor_ratings(bigint[])to authenticated;
alter publication supabase_realtime add table public.rating_summaries;
commit;
