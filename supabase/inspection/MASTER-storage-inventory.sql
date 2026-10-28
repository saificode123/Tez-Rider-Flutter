begin read only;
select coalesce(jsonb_agg(jsonb_build_object(
  'id', id, 'bucket', bucket_id, 'name', name, 'updated', updated_at,
  'size', metadata->>'size', 'etag', metadata->>'eTag'
) order by id), '[]'::jsonb) as objects from storage.objects;
rollback;
