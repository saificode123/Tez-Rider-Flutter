"""Restore encrypted Storage bytes through an isolated local Storage API.

No host ports or external network; temporary JWTs are local to this rehearsal.
No credentials, object paths, contents or raw service errors enter public output.
"""
import base64
import ctypes
import datetime as dt
import hashlib
import hmac
import json
import os
import re
from pathlib import Path
import secrets
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
DB = 'tezrider-master-restore-20261028'
STORAGE = 'tezrider-release-storage-recovery'
IMAGE = 'public.ecr.aws/supabase/storage-api:v1.79.36'


def docker(*args, data=None, env=None, timeout=60):
    result = subprocess.run(['docker', *args], input=data, capture_output=True, env=env, timeout=timeout)
    if result.returncode:
        if 'psql' in args:
            private = Path(os.environ['LOCALAPPDATA']) / 'TezRider-FR21/recovery-last-sql-error.private.log'
            private.write_bytes(result.stderr)
        code = re.search(rb'(UPLOAD_HTTP_\d+|DOWNLOAD_HTTP_\d+|HASH_MISMATCH)', result.stderr)
        raise RuntimeError('Isolated Docker operation failed' + (': ' + code[0].decode() if code else '; no raw output disclosed'))
    return result.stdout


class Blob(ctypes.Structure):
    _fields_ = [('size', ctypes.c_ulong), ('data', ctypes.POINTER(ctypes.c_ubyte))]


def decrypt(data):
    buffer = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    output = Blob()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)):
        raise RuntimeError('Protected backup unavailable')
    try:
        return ctypes.string_at(output.data, output.size)
    finally:
        ctypes.windll.kernel32.LocalFree(output.data)


def main(directory):
    boundary = Path(os.environ['LOCALAPPDATA']) / 'TezRider-FR21/backups'
    directory = Path(directory).resolve()
    assert directory.is_relative_to(boundary.resolve())
    assert json.loads((directory / 'manifest.json').read_text(encoding='utf-8-sig'))['project'] == 'igeisilhtmglgnqvllrx'
    inspected = json.loads(docker('inspect', DB))[0]
    assert inspected['HostConfig']['NetworkMode'] == 'none' and not inspected['HostConfig']['PortBindings']
    assert inspected['Config']['Labels']['tezrider.purpose'] == 'isolated-restore'
    restored = json.loads((ROOT / 'docs/evidence/RELEASE-runtime-restore.json').read_text(encoding='utf-8-sig'))
    assert restored['isolated_restore_verified']
    assert not docker('ps', '-a', '--filter', 'name=^' + STORAGE + '$', '--format', '{{.Names}}').strip(), 'Inspect existing recovery container instead of overwriting it'
    docker('image', 'inspect', IMAGE)
    started = time.monotonic()
    password, jwt_secret = secrets.token_hex(32), secrets.token_hex(32)
    def jwt(role, subject=None):
        claims = {'role': role, 'iss': 'offline-recovery', 'iat': int(time.time()), 'exp': int(time.time()) + 3600}
        if subject:
            claims['sub'] = subject
        encoded = lambda value: base64.urlsafe_b64encode(value).rstrip(b'=')
        message = encoded(b'{"alg":"HS256","typ":"JWT"}') + b'.' + encoded(json.dumps(claims).encode())
        return (message + b'.' + encoded(hmac.new(jwt_secret.encode(), message, hashlib.sha256).digest())).decode()
    sql = "alter role supabase_storage_admin password '" + password + "';"
    docker('exec', '-i', DB, 'psql', '-q', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', data=sql.encode())
    settings = {'ANON_KEY': jwt('anon'), 'SERVICE_KEY': jwt('service_role'), 'AUTH_JWT_SECRET': jwt_secret,
                'DATABASE_URL': 'postgres://supabase_storage_admin:' + password + '@127.0.0.1:5432/postgres',
                'POSTGREST_URL': 'http://127.0.0.1:3000', 'STORAGE_BACKEND': 'file',
                'FILE_STORAGE_BACKEND_PATH': '/var/lib/storage', 'GLOBAL_S3_BUCKET': 'offline-recovery',
                'TENANT_ID': 'offline-recovery', 'REGION': 'local', 'FILE_SIZE_LIMIT': '16777216',
                'DB_MIGRATIONS_FREEZE_AT': 'add-bucket-name-length-trigger',
                'DB_ALLOW_MIGRATION_REFRESH': 'false',
                'ENABLE_IMAGE_TRANSFORMATION': 'false', 'STORAGE_PUBLIC_URL': 'http://127.0.0.1:5000'}
    arguments = ['run', '--detach', '--name', STORAGE, '--network', 'container:' + DB,
                 '--label', 'tezrider.purpose=isolated-storage-recovery']
    for name in settings:
        arguments += ['--env', name]
    docker(*arguments, IMAGE, env={**os.environ, **settings})
    status = 'fetch("http://127.0.0.1:5000/status").then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))'
    for _ in range(20):
        try:
            docker('exec', STORAGE, 'node', '-e', status, timeout=10)
            break
        except RuntimeError:
            time.sleep(1)
    else:
        (directory / 'release-storage-service.private.log').write_bytes(docker('logs', STORAGE))
        raise RuntimeError('Isolated Storage API did not become healthy; private diagnostic retained')
    inventory_file = boundary / '20261028T080137Z-f69b9206504842ab8fe7d7aff06c7cbc/storage-manifest.private.json'
    inventory = json.loads(inventory_file.read_text(encoding='utf-8-sig'))
    assert inventory['inventory_stable'] and not inventory['failures'] and len(inventory['objects']) == 259
    originals = docker('exec', DB, 'psql', '-At', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c',
                       "select json_agg(json_build_object('id',id,'owner',owner_id,'mime',metadata->>'mimetype')) from storage.objects;")
    metadata = {o['id']: o for o in json.loads(originals)}
    uploads = []
    for obj in inventory['objects']:
        assert obj['id'] in metadata
        encrypted = inventory_file.parent / 'storage' / (obj['id'] + '.dpapi')
        sealed = encrypted.read_bytes()
        assert hashlib.sha256(sealed).hexdigest().upper() == obj['encrypted_sha256']
        content = decrypt(sealed)
        assert len(content) == obj['bytes'] and hashlib.sha256(content).hexdigest().upper() == obj['sha256']
        uploads.append({'bucket': obj['bucket'], 'name': obj['name'], 'bytes': base64.b64encode(content).decode(),
                        'mime': metadata[obj['id']]['mime'] or 'application/octet-stream',
                        'token': jwt('service_role', metadata[obj['id']]['owner']), 'sha256': obj['sha256']})
    script = r'''
const fs=require('fs'), crypto=require('crypto');
(async()=>{
 const objects=JSON.parse(fs.readFileSync(0,'utf8'));let count=0,bytes=0;
 for(const object of objects){
  const path=encodeURIComponent(object.bucket)+'/'+object.name.split('/').map(encodeURIComponent).join('/');
  const headers={Authorization:'Bearer '+object.token,'Content-Type':object.mime,'x-upsert':'true'};
  const body=Buffer.from(object.bytes,'base64');
  let response=await fetch('http://127.0.0.1:5000/object/'+path,{method:'POST',headers,body});
  if(!response.ok)throw Error('UPLOAD_HTTP_'+response.status);await response.arrayBuffer();
  response=await fetch('http://127.0.0.1:5000/object/authenticated/'+path,{headers:{Authorization:headers.Authorization}});
  if(!response.ok)throw Error('DOWNLOAD_HTTP_'+response.status);
  const recovered=Buffer.from(await response.arrayBuffer());
  if(crypto.createHash('sha256').update(recovered).digest('hex').toUpperCase()!==object.sha256)throw Error('HASH_MISMATCH');
  count++;bytes+=recovered.length;
 }
 console.log(JSON.stringify({verified_objects:count,verified_bytes:bytes}));
})().catch(error=>{console.error(error.message);process.exit(1)});
'''
    counts = json.loads(docker('exec', '-i', STORAGE, 'node', '-e', script, data=json.dumps(uploads).encode(), timeout=240))
    after = json.loads(docker('exec', DB, 'psql', '-At', '-U', 'supabase_admin', '-d', 'postgres', '-c',
                             "select json_agg(json_build_object('id',id,'owner',owner_id,'mime',metadata->>'mimetype')) from storage.objects;"))
    assert {o['id']: o for o in after} == metadata, 'Restored object ownership/MIME/IDs changed'
    assert counts['verified_objects'] == 259
    result = {'project': 'igeisilhtmglgnqvllrx', 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'status': 'BOUNDED PASS', **counts, 'owner_mime_and_object_ids_retained': True,
              'network': 'Shared loopback namespace of owned network=none database; no host ports',
              'elapsed_seconds': round(time.monotonic() - started, 3), 'hosted_modified': False,
              'scope': 'Recovered encrypted bytes uploaded/downloaded through isolated Storage API with SHA-256 comparisons. Service-role recovery only; per-user RLS, signed URLs, Auth/Edge configuration and cross-machine recovery remain separate.'}
    (ROOT / 'docs/evidence/RELEASE-storage-runtime.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    main(sys.argv[1])
