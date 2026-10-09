"""Prepare real local PostgREST/k6 fixtures. Never connects to a hosted database.

Usage: python tests/load/FR-21-local.py --psql PATH --postgrest PATH
Starts PostgREST only on 127.0.0.1:54321 and stops it when interrupted.
Fixtures/JWT/config live under ignored build/fr21-evidence, never in Git.
Requires the reconstructed bootstrap and FR-21 migration already tested locally.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "fr21-evidence"
DB = "fr21_isolated_test"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--psql", required=True)
    parser.add_argument("--postgrest", required=True)
    parser.add_argument("--k6", required=True)
    parser.add_argument("--pool-size", type=int, default=10)
    args = parser.parse_args()
    if not 1 <= args.pool_size <= 50:
        parser.error("--pool-size must be between 1 and 50")
    OUT.mkdir(parents=True, exist_ok=True)
    secret = secrets.token_urlsafe(48)

    def jwt(role, subject=None, email=None):
        claims = {"role": role, "exp": int(time.time()) + 7200}
        if subject:
            claims.update(sub=subject, email=email)
        encode = lambda x: base64.urlsafe_b64encode(x).rstrip(b"=").decode()
        parts = [encode(b'{"alg":"HS256","typ":"JWT"}'),
                 encode(json.dumps(claims).encode())]
        parts.append(encode(hmac.new(secret.encode(), ".".join(parts).encode(), hashlib.sha256).digest()))
        return ".".join(parts)

    sql = ["do $$ begin if current_database()<>'fr21_isolated_test' then raise exception 'Local only'; end if; end $$;"]
    # Leave existing race fixtures offline so the load dataset is self-contained.
    sql.append("update public.riders set is_online=false where userid=-22003;")
    # Reset only the named local load dataset, making assignment (not just its
    # idempotent return path) run again when testing a revised migration.
    sql.append("delete from public.rider_assignments where orderid between 30001 and 31000 and exists(select 1 from public.orders o where o.id=orderid and o.user_id=9000);")
    sql.append("update public.orders set rider_id=null,delivery_otp=null,order_status='accepted' where id between 30001 and 31000 and user_id=9000;")
    sql.append("update public.vendor_orders set status='accepted' where id between 30001 and 31000 and vendor_id between 20001 and 21000;")
    sql.append("update public.riders set is_online=false,is_available=true,isavailable=true where userid between 10001 and 11000;")
    sql.append("insert into public.users(id,name,email,role,verification_status) values(9000,'Load customer','load-c@example.test','customer','approved');")
    fixtures = []
    for i in range(1, 1001):
        rider, vendor, order = 10000+i, 20000+i, 30000+i
        tokens = []
        for account, role in [(rider, "rider"), (vendor, "vendor")]:
            subject = f"31000000-0000-0000-0000-{account:012d}"
            email = f"load-{account}@example.test"
            sql.append(f"insert into auth.users(id,email,email_confirmed_at,aud,role) values('{subject}','{email}',now(),'authenticated','authenticated');")
            sql.append(f"insert into public.users(id,name,email,role,verification_status) values({account},'Local load {role}','{email}','{role}','approved');")
            tokens.append(jwt("authenticated", subject, email))
        sql.extend([
            f"insert into public.riders(userid,latitude,longitude) values({rider},31.52,74.35);",
            f"insert into public.vendors(user_id,store_name,latitude,longitude) values({vendor},'Local load shop',31.52,74.35);",
            f"insert into public.orders(id,user_id,amount,order_status) values({order},9000,100,'accepted');",
            f"insert into public.vendor_orders(id,order_id,vendor_id,status) values({order},{order},{vendor},'accepted');",
        ])
        fixtures.append(dict(rider_token=tokens[0], vendor_token=tokens[1], vendor_order_id=order))
    # Reruns reuse only these disposable fixture identities.
    sql = [line[:-1] + " on conflict do nothing;" if line.startswith("insert into ") else line for line in sql]
    seed = OUT / "local-fixtures.sql"
    seed.write_text("begin;\n" + "\n".join(sql) + "\ncommit;\n", encoding="utf-8")
    with (OUT / "load-seed.txt").open("w") as log:
        subprocess.run([args.psql, "-h", "127.0.0.1", "-p", "55432", "-U", "postgres", "-d", DB,
                        "-v", "ON_ERROR_STOP=1", "-f", str(seed)], check=True, stdout=log, stderr=log)
    fixture_file = OUT / "local-fixtures.json"
    fixture_file.write_text(json.dumps(fixtures), encoding="utf-8")
    config = OUT / "local-postgrest.conf"
    config.write_text(f'db-uri = "postgresql://fr21_authenticator@127.0.0.1:55432/{DB}"\n'
                      f'db-schemas = "public"\ndb-anon-role = "anon"\ndb-pool = {args.pool_size}\n'
                      f'jwt-secret = "{secret}"\nserver-host = "127.0.0.1"\nserver-port = 54321\n', encoding="utf-8")
    env = dict(os.environ, FR21_URL="http://127.0.0.1:54321", FR21_ANON_KEY=jwt("anon"),
               FR21_FIXTURES=str(fixture_file), FR21_NATIVE_POSTGREST="true")
    env["PATH"] = str(Path(args.psql).resolve().parent) + os.pathsep + env.get("PATH", "")
    with (OUT / "postgrest.txt").open("w") as server_log:
        process = subprocess.Popen([args.postgrest, str(config)], env=env, stdout=server_log, stderr=server_log,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        try:
            import urllib.request
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            for _ in range(30):
                try:
                    opener.open("http://127.0.0.1:54321/", timeout=1).close()
                    break
                except OSError:
                    if process.poll() is not None:
                        raise RuntimeError(f"Local PostgREST exited ({process.returncode}); see its private log")
                    time.sleep(1)
            else:
                raise RuntimeError("Local PostgREST did not become ready")
            print("Local PostgreSQL/PostgREST ready; running 1,000-VU k6 test.", flush=True)
            with (OUT / "k6.txt").open("w") as log:
                result = subprocess.run([args.k6, "run", "--summary-export", str(OUT / "k6-summary.json"),
                                         str(ROOT / "tests/load/FR-21.js")], env=env, stdout=log, stderr=log)
            print(f"K6_EXIT_CODE={result.returncode}", flush=True)
            raise SystemExit(result.returncode)
        finally:
            process.terminate()
            process.wait(timeout=15)


if __name__ == "__main__":
    main()
