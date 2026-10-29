begin read only;
select jsonb_agg(jsonb_build_object(
 'signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),
 'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text
) order by p.oid::regprocedure::text) as functions
from pg_proc p where p.oid in (
 'public.final2_complete_registration(text,text,text,text,text,boolean)'::regprocedure,
 'public.final2_rating_visible(bigint,text)'::regprocedure,
 'public.final2_feedback_context(bigint)'::regprocedure,
 'public.final2_submit_feedback(bigint,bigint,integer,text,uuid)'::regprocedure,
 'public.final2_rating_summary(bigint)'::regprocedure
);
rollback;
