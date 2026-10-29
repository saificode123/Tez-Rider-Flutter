-- Read-only, owner-identified existing TEST Rider; no identity document contents.
begin read only;
set local statement_timeout='15s';
select jsonb_build_object(
 'rider_profile_id',u.id,'role',u.role,'verification_status',u.verification_status,
 'blocked',u.is_blocked,'email_confirmed',a.email_confirmed_at is not null,
 'auth_session_count',(select count(*)from auth.sessions where user_id=a.id),
 'online',(select is_online from public.riders where userid=u.id),
 'online_presence_fresh',exists(select 1 from public.riders where userid=u.id and is_online and last_seen>clock_timestamp()-interval '90 seconds'),
 'matching_location_fresh',exists(select 1 from public.riders where userid=u.id and latitude is not null and longitude is not null and location_updated_at>clock_timestamp()-interval '90 seconds'),
 'document_exists',fr04_private.document_exists(u.id),
 'cnic_bucket_private',(select not public from storage.buckets where id='rider-cnic'),
 'submission_status',u.cnic_submission_status,'submitted_at',u.cnic_submitted_at,
 'admin_approval_after_current_submission',exists(
   select 1 from public.security_audit_log l join public.users reviewer on reviewer.id=l.actor_id
   where l.target_type='users'and l.target_id=u.id and l.action='fr04_rider_approved'
   and l.created_at>=u.cnic_submitted_at and reviewer.role='admin'
   and reviewer.verification_status='approved'and not reviewer.is_blocked),
 'active_orders',(select count(*)from public.orders where rider_id=u.id and order_status not in('delivered','cancelled')),
 'recent_auth_actions',(select coalesce(jsonb_agg(events),'[]'::jsonb)from(
   select payload->>'action'as action,count(*)as entries,max(created_at)as latest
   from auth.audit_log_entries where created_at>=current_date
   and(payload->>'actor_id'=a.id::text or lower(payload->>'actor_username')=lower(a.email))
   group by payload->>'action')events)
)as acceptance from public.users u join auth.users a on a.id=u.auth_user_id
where u.id=999 and u.role='rider';
rollback;
