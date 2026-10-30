-- Owner-approved physical verification: one TEST order, at most three calls.
begin;
set local lock_timeout='5s';
create table fr14_private.verification_requests(
 request_count integer primary key check(request_count between 1 and 3),
 status text not null default 'STARTED',
 distance_meters double precision,
 duration_seconds double precision
);
alter table fr14_private.verification_requests enable row level security;
revoke all on fr14_private.verification_requests from public,anon,authenticated,service_role;

create function public.fr14_verification_claim(p_order_id bigint,p_actor bigint,p_pickup boolean)
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if p_order_id is distinct from 3180 or p_actor is null or p_actor not in(159,999)
 or p_pickup is distinct from false or not fr14_private.allowed(p_order_id,p_actor)
 or not exists(select 1 from public.orders where id=3180 and user_id=159 and rider_id=999 and order_status='on_the_way')
 then return 0;end if;
 perform pg_advisory_xact_lock(318014);
 select coalesce(max(request_count),0)into n from fr14_private.verification_requests;
 if n>=3 then return 0;end if;
 insert into fr14_private.verification_requests(request_count)values(n+1);
 return n+1;
end$$;

create function public.fr14_verification_record(p_request_count integer,p_status text,p_distance double precision,p_duration double precision)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_status not in('HTTP_200','FAILED')then raise insufficient_privilege;end if;
 if p_distance is not null and not(p_distance>=0 and p_distance<=1000000)
 or p_duration is not null and not(p_duration>=0 and p_duration<=86400)
 then raise insufficient_privilege;end if;
 update fr14_private.verification_requests set status=p_status,distance_meters=p_distance,duration_seconds=p_duration
 where request_count=p_request_count and status='STARTED';
end$$;
revoke all on function public.fr14_verification_claim(bigint,bigint,boolean)from public,anon,authenticated;
revoke all on function public.fr14_verification_record(integer,text,double precision,double precision)from public,anon,authenticated;
grant execute on function public.fr14_verification_claim(bigint,bigint,boolean)to service_role;
grant execute on function public.fr14_verification_record(integer,text,double precision,double precision)to service_role;
notify pgrst,'reload schema';
commit;
