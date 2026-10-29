"""Checkpoint and rehearse the one-function TEST registration repair offline."""
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


b = load('checkpoint_crypto', 'FR-04-hosted.py')
r = load('checkpoint_recovery', 'RELEASE-storage-recovery.py')
ROOT = HERE.parents[1]
SIGNATURE = 'final2_complete_registration(text,text,text,text,text,boolean)'


def functions(path):
    raw = Path(path).read_text(encoding='utf-8-sig')
    value = json.JSONDecoder().raw_decode(raw[raw.index('{'):])[0]
    rows = value['rows']
    assert len(rows) == 1 and len(rows[0]['functions']) == 5
    return {f['signature']: f for f in rows[0]['functions']}


def main(mode, path):
    assert (ROOT / 'supabase/.temp/project-ref').read_text().strip() == b.REF
    private = b.PRIVATE / 'release-registration-20261029'
    private.mkdir(exist_ok=True)
    checkpoint = private / 'original-functions.dpapi'
    current = functions(path)
    if mode == 'rehearse':
        assert not checkpoint.exists(), 'Never replace an existing rollback checkpoint'
        db = json.loads(r.docker('inspect', r.DB))[0]
        assert db['HostConfig']['NetworkMode'] == 'none'
        assert db['Config']['Labels']['tezrider.purpose'] == 'isolated-restore'
        assert not db['HostConfig']['PortBindings']
        protected = b.crypt(json.dumps(current).encode())
        checkpoint.write_bytes(protected)
        original = json.loads(b.crypt(checkpoint.read_bytes(), True))
        assert original == current
        sql = original[SIGNATURE]['definition']
        r.docker('exec', '-i', r.DB, 'psql', '-q', '-U', 'supabase_admin', '-d', 'postgres',
                 '-v', 'ON_ERROR_STOP=1', data=sql.encode())
        for stage in ('before', 'after'):
            if stage == 'after':
                migration = ROOT / 'supabase/migrations/202610290001_release_customer_registration_repair.sql'
                r.docker('exec', '-i', r.DB, 'psql', '-q', '-U', 'supabase_admin', '-d', 'postgres',
                         '-v', 'ON_ERROR_STOP=1', data=migration.read_bytes())
            result = subprocess.run([sys.executable, str(HERE / 'RELEASE-customer-registration.py'), stage],
                                    capture_output=True, timeout=180)
            assert result.returncode == 0, 'Offline registration rehearsal failed; raw output withheld'
        record = {'checkpoint_roundtrip': True, 'original_behavior_reproduced_after_rollback': True,
                  'repair_reapplied_nine_checks_passed': True,
                  'checkpoint_sha256': hashlib.sha256(protected).hexdigest(),
                  'scope': 'Owned network-none clone only; no hosted mutation or external messages.'}
        name = 'RELEASE-registration-rollback.json'
    elif mode == 'verify-host':
        original = json.loads(b.crypt(checkpoint.read_bytes(), True))
        assert set(original) == set(current)
        assert original[SIGNATURE]['definition'] != current[SIGNATURE]['definition']
        assert original[SIGNATURE]['owner'] == current[SIGNATURE]['owner']
        assert original[SIGNATURE]['acl'] == current[SIGNATURE]['acl']
        for signature in original:
            if signature != SIGNATURE:
                assert original[signature] == current[signature], 'Unrelated feedback function changed'
        assert 'customer_registration_reconciled' in current[SIGNATURE]['definition']
        record = {'registration_definition_changed': True, 'registration_owner_and_grants_unchanged': True,
                  'four_feedback_definitions_owners_grants_unchanged': True,
                  'scope': 'Read-only TEST function-definition comparison; profile completion is tested separately.'}
        name = 'RELEASE-registration-deployed.json'
    else:
        raise ValueError('Unsupported checkpoint operation')
    record.update(project=b.REF, utc=dt.datetime.now(dt.timezone.utc).isoformat())
    (ROOT / 'docs/evidence' / name).write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(record))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
