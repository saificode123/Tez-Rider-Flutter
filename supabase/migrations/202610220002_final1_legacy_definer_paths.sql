-- Narrow follow-up found during final definition review. Bodies/grants unchanged.
-- Both legacy bodies already qualify their application/Auth table references.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
alter function public.vendor_can_insert_product(integer) set search_path='';
alter function public.is_current_vendor(bigint) set search_path='';
notify pgrst,'reload schema';
commit;
