"""Read-only inspection of the authorized isolated TEST contract; no secret output."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REF = 'igeisilhtmglgnqvllrx'
CLI = 'C:/Users/urreh/AppData/Local/Temp/tezrider-fr21-tools/supabase-cli/supabase.exe'
if (ROOT / 'supabase/.temp/project-ref').read_text().strip() != REF:
    raise SystemExit('Dedicated TEST link required')
result = subprocess.run(
    [CLI, 'db', 'query', '--linked', '--project-ref', REF, '--file',
     str(ROOT / 'supabase/inspection/FR-10-preflight.sql'), '--output', 'json'],
    capture_output=True, text=True, timeout=90,
)
if result.returncode:
    raise SystemExit('TEST read-only inspection failed; no credentials emitted')
data = json.loads(result.stdout[result.stdout.index('{'):])['rows'][0]['inspection']
versions = sorted(p.name.split('_')[0] for p in (ROOT / 'supabase/migrations').glob('*.sql'))
assert data['migration_versions'] == versions, 'Review TEST migration history mismatch'
out = ROOT / '.fr21-local/fr10'
out.mkdir(parents=True, exist_ok=True)
(out / 'preflight.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
print(json.dumps({
    'target': REF, 'read_only': True, 'migration_history_matches': True,
    'migration_count': len(versions), 'extensions': data['extensions'],
    'jobs': data['jobs'],
    'timeout_function_present': any(f['name'] == 'cancel_timed_out_orders' for f in data['functions']),
    'tables': data['tables'],
}))
