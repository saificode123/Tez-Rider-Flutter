-- Fail closed: retain the consumed request audit and prevent provider calls
-- from the current gated Edge function. Do not reset consumed requests or
-- deploy an older ungated provider under the owner's three-request consent.
begin;
drop function if exists public.fr14_verification_claim(bigint,bigint,boolean);
drop function if exists public.fr14_verification_record(integer,text,double precision,double precision);
notify pgrst,'reload schema';
commit;
