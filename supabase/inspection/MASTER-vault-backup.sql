-- Sensitive result: operator must write only to private encrypted backup storage.
begin read only;
select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'name',name,'description',description,'secret',decrypted_secret,
  'created_at',created_at,'updated_at',updated_at
) order by id),'[]'::jsonb) as secrets from vault.decrypted_secrets;
rollback;
