"""Recover real saved TEST password logins in the owned offline Auth runtime."""
import base64
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import secrets
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('storage_recovery', HERE / 'RELEASE-storage-recovery.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
AUTH = 'tezrider-release-auth-recovery'


def main(directory, verify_existing=False):
    directory = Path(directory).resolve()
    assert directory.is_relative_to((Path(os.environ['LOCALAPPDATA']) / 'TezRider-FR21/backups').resolve())
    assert json.loads((directory / 'manifest.json').read_text(encoding='utf-8-sig'))['project'] == 'igeisilhtmglgnqvllrx'
    db = json.loads(r.docker('inspect', r.DB))[0]
    assert db['HostConfig']['NetworkMode'] == 'none' and not db['HostConfig']['PortBindings']
    assert db['Config']['Labels']['tezrider.purpose'] == 'isolated-restore'
    storage = json.loads(r.docker('inspect', r.STORAGE))[0]
    assert storage['HostConfig']['NetworkMode'] == 'container:' + db['Id']
    started = time.monotonic()
    if verify_existing:
        existing = json.loads(r.docker('inspect', AUTH))[0]
        assert existing['HostConfig']['NetworkMode'] == 'container:' + db['Id']
        assert existing['Config']['Labels']['tezrider.purpose'] == 'isolated-auth-recovery'
    else:
        assert not r.docker('ps', '-a', '--filter', 'name=^' + AUTH + '$', '--format', '{{.Names}}').strip()
        password = secrets.token_hex(32)
        r.docker('exec', '-i', r.DB, 'psql', '-q', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1',
                 data=("alter role supabase_auth_admin password '" + password + "';").encode())
        settings = {'GOTRUE_API_HOST': '127.0.0.1', 'GOTRUE_API_PORT': '9999',
                    'API_EXTERNAL_URL': 'http://127.0.0.1:9999', 'GOTRUE_SITE_URL': 'http://127.0.0.1:9999',
                    'GOTRUE_DB_DRIVER': 'postgres',
                    'GOTRUE_DB_DATABASE_URL': 'postgres://supabase_auth_admin:' + password + '@127.0.0.1:5432/postgres',
                    'GOTRUE_JWT_SECRET': secrets.token_hex(32), 'GOTRUE_JWT_EXP': '3600',
                    'GOTRUE_JWT_AUD': 'authenticated', 'GOTRUE_JWT_ADMIN_ROLES': 'service_role',
                    'GOTRUE_JWT_DEFAULT_GROUP_NAME': 'authenticated', 'GOTRUE_DISABLE_SIGNUP': 'true',
                    'GOTRUE_EXTERNAL_EMAIL_ENABLED': 'true', 'GOTRUE_MAILER_AUTOCONFIRM': 'false',
                    'GOTRUE_SMTP_HOST': '127.0.0.1', 'GOTRUE_SMTP_PORT': '1',
                    'GOTRUE_SMTP_ADMIN_EMAIL': 'offline@example.test'}
        args = ['run', '--detach', '--name', AUTH, '--network', 'container:' + r.DB,
                '--label', 'tezrider.purpose=isolated-auth-recovery']
        for name in settings:
            args += ['--env', name]
        r.docker(*args, 'public.ecr.aws/supabase/gotrue:v2.197.0', env={**os.environ, **settings})
    probe = 'fetch("http://127.0.0.1:9999/health").then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))'
    for _ in range(20):
        try:
            r.docker('exec', r.STORAGE, 'node', '-e', probe, timeout=10)
            break
        except RuntimeError:
            time.sleep(1)
    else:
        (directory / 'release-auth-service.private.log').write_bytes(r.docker('logs', AUTH))
        raise RuntimeError('Offline Auth runtime did not start; private diagnostic retained')
    # Recover the backup's nested DPAPI credential file, not current credentials.
    state = json.loads(r.decrypt(r.decrypt((directory / 'encrypted-demo-credential-file.dpapi').read_bytes())))
    assert state['namespace'] == 'tezrider-owner-demo-v1' and len(state['accounts']) == 7
    accounts = list(state['accounts'].values())
    assert all(a['email'].endswith('@example.test') for a in accounts)
    node = r'''
const fs=require('fs');
(async()=>{
 const accounts=JSON.parse(fs.readFileSync(0,'utf8')), results=[];
 for(const account of accounts){
  let response=await fetch('http://127.0.0.1:9999/token?grant_type=password',{
   method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:account.email,password:account.password})});
  if(!response.ok)throw Error('AUTH_LOGIN_HTTP_'+response.status);
  const login=await response.json();if(login.user.id!==account.auth_id)throw Error('WRONG_AUTH_ID');
  response=await fetch('http://127.0.0.1:9999/user',{headers:{Authorization:'Bearer '+login.access_token}});
  if(!response.ok||(await response.json()).id!==account.auth_id)throw Error('TOKEN_NOT_ACCEPTED');
  response=await fetch('http://127.0.0.1:9999/token?grant_type=refresh_token',{
   method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({refresh_token:login.refresh_token})});
  if(!response.ok)throw Error('REFRESH_FAILED');const fresh=await response.json();
  if(fresh.user.id!==account.auth_id)throw Error('WRONG_REFRESH_ID');
  results.push(JSON.parse(Buffer.from(fresh.access_token.split('.')[1],'base64url').toString()));
 }
 console.log(JSON.stringify(results));
})().catch(()=>{console.error('OFFLINE_AUTH_ACCEPTANCE_FAILED');process.exit(1)});
'''
    claims = json.loads(r.docker('exec', '-i', r.STORAGE, 'node', '-e', node, data=json.dumps(accounts).encode(), timeout=90))
    profiles = json.loads(r.docker('exec', r.DB, 'psql', '-At', '-U', 'supabase_admin', '-d', 'postgres', '-c',
        "select json_agg(json_build_object('auth_id',auth_user_id,'id',id,'role',role)) from public.users where auth_user_id is not null;"))
    profiles = {p['auth_id']: p for p in profiles}
    for claim in claims:
        identity = str(uuid.UUID(claim['sub']))
        profile = profiles[identity]
        assert profile['role'] in ('customer', 'vendor', 'rider', 'admin') and isinstance(profile['id'], int)
        encoded = base64.b64encode(json.dumps(claim).encode()).decode()
        sql = f"""begin;set local role authenticated;
do $check$ begin perform set_config('request.jwt.claims',convert_from(decode('{encoded}','base64'),'UTF8'),true);end $check$;
select json_build_object('actor_ok',public.fr21_actor()={profile['id']},'role_ok',public.fr21_role()='{profile['role']}');rollback;"""
        checks = json.loads(r.docker('exec', '-i', r.DB, 'psql', '-qAt', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', data=sql.encode()))
        assert checks == {'actor_ok': True, 'role_ok': True}
    result = {'project': 'igeisilhtmglgnqvllrx', 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'status': 'BOUNDED PASS', 'recovered_password_logins': len(claims),
              'get_user_and_refresh_verified': len(claims), 'canonical_actor_and_role_verified': len(claims),
              'network': 'Owned network=none database namespace; no host ports or external mail',
              'elapsed_seconds': round(time.monotonic() - started, 3), 'hosted_modified': False,
              'scope': 'Auth runtime accepted restored password hashes and backed-up credentials, new tokens and refresh; canonical SQL actor/role checks passed. Temporary local JWT signing identity differs from hosted identity. Remote Auth configuration parity, full Flutter/Edge recovery, signed media and cross-machine recovery remain separate.'}
    (r.ROOT / 'docs/evidence/RELEASE-auth-runtime.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    assert len(sys.argv) == 2 or (len(sys.argv) == 3 and sys.argv[2] == '--verify-existing')
    main(sys.argv[1], len(sys.argv) == 3)
