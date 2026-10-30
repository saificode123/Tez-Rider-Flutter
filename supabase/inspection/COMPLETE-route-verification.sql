begin read only;
select jsonb_build_object(
 'request_count',(select count(*)from fr14_private.verification_requests),
 'status',(select jsonb_agg(jsonb_build_object('request_count',request_count,'status',status,'distance',distance_meters,'duration',duration_seconds)order by request_count)from fr14_private.verification_requests),
 'distance',(select data->'distanceMeters'from public.delivery_route_cache where order_id=3180),
 'duration',(select data->'durationSeconds'from public.delivery_route_cache where order_id=3180)
)as summary;
rollback;
