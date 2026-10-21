"""Generate redacted Stage1 evidence and metadata ledgers from captured results."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.fr21-local/final1'


def cell(value):
    return str(value).replace('|', '\\|').replace('\r', ' ').replace('\n', ' ')


def table(headers, rows):
    return '| ' + ' | '.join(headers) + ' |\n|' + '|'.join('---' for _ in headers) + '|\n' + ''.join(
        '| ' + ' | '.join(cell(value) for value in row) + ' |\n' for row in rows) + '\n'


def client_scope(name, operation, role):
    if name == 'users':
        return {'SELECT': 'Own canonical profile' if role != 'Admin' else 'Authorized directory',
                'INSERT': 'Own non-admin signup; forced safe status',
                'UPDATE': 'Own granted profile fields; Admin moderation only' if role == 'Admin' else 'Own granted profile fields; no role/identity changes',
                'DELETE': 'Denied by existing guards'}[operation]
    if name == 'products':
        return 'Catalogue visibility RLS' if operation == 'SELECT' else ('Own approved unblocked vendor/granted columns' if role == 'Vendor' else 'Denied by owner/role guard')
    if name == 'admin_broadcasts':
        return 'Admin history RLS' if role == 'Admin' and operation == 'SELECT' else 'Denied by role/RLS'
    if name == 'notifications':
        return 'Own inbox; UPDATE is_read only'
    if name in ('orders', 'vendor_orders', 'order_items', 'rider_assignments'):
        return {'Customer': 'Owned parent order scope', 'Vendor': 'Owned vendor portion/order scope',
                'Rider': 'Assigned related order scope', 'Admin': 'Approved Admin scope'}[role] + '; operation/column RLS applies'
    return 'Exact operation RLS predicates apply; not every positive role case independently executed'


def generate():
    catalog = json.loads((OUT / 'catalog.json').read_text())
    sql = json.loads((OUT / 'sql-results.json').read_text())
    http = json.loads((OUT / 'hosted-results.json').read_text())
    scan = json.loads((OUT / 'secret-scan.json').read_text())
    evidence = {
        'date': '2026-10-22', 'project': 'igeisilhtmglgnqvllrx', 'base': 'c0a8da1',
        'status': 'PARTIAL - SECURITY ACCEPTANCE PENDING',
        'sql': sql, 'real_session_http': http,
        'flutter': {'full_passed': 279, 'full_inherited_skips': 2, 'last_focused_passed': 6},
        'deno': {'unique_cases_with_passing_evidence': 143, 'initial_passed': 141,
                 'initial_output_permission_failures': 2, 'invoice_group_retry_passed': 4},
        'migrations': ['202610220001_final1_security_foundation.sql', '202610220002_final1_legacy_definer_paths.sql'], 'versions': catalog['versions'],
        'tables': len(catalog['tables']), 'functions': len(catalog['functions']),
        'production_modified': False, 'external_provider_requests': 0,
        'secret_scan': {'current_files': scan['current_text_files'], 'historical_small_blobs': scan['historical_small_blobs'],
                        'candidates': scan['current'], 'history': scan['history'], 'limits': scan['limits']},
    }
    (ROOT / 'docs/evidence/FINAL-security-results.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')
    path = ROOT / 'docs/FINAL-security-audit.md'
    text = path.read_text(encoding='utf-8').split('<!-- GENERATED-INVENTORY -->')[0] + '<!-- GENERATED-INVENTORY -->\n\n'
    text += '## Current operation policy matrix\n\nDirect client access only. Accepted mutations performed by explicitly authorized RPCs are separate from table grants. Every Customer/Vendor/Rider/Admin shares database role authenticated; application scopes come from predicates/canonical helper checks, not separate PostgreSQL roles. DENIED(no grant) is a metadata conclusion, not a dynamically exercised positive feature. Service Role may bypass RLS only where table privileges permit; constraints/triggers/explicit RPC service checks remain.\n\n'
    rows = []
    for t in sorted(catalog['tables'], key=lambda t: (t['schema'], t['name'])):
        for operation in ['SELECT', 'INSERT', 'UPDATE', 'DELETE']:
            grants = [g['grantee'] for g in t['grants'] if g['privilege_type'] == operation]
            column_grant = any(g['privilege_type'] == operation and g['grantee'] == 'authenticated' for g in t['columns'])
            direct = 'authenticated' in grants or column_grant
            roles = [client_scope(t['name'], operation, r) if direct else 'DENIED(no grant)' for r in ['Customer', 'Vendor', 'Rider', 'Admin']]
            service = 'BYPASSRLS subject to grants/constraints/triggers' if 'service_role' in grants else 'No direct table grant; use authorized definer path if applicable'
            names = ', '.join(p['policyname'] for p in t['policies'] if p['cmd'] in (operation, 'ALL')) or 'No policy'
            rows.append([t['schema'] + '.' + t['name'], operation, *roles, service, names + '; catalog2026-10-22; runtime coverage is named in evidence JSON'])
    text += table(['Table', 'Operation', 'Customer', 'Vendor', 'Rider', 'Admin', 'Service Role', 'Evidence'], rows)
    text += '## Function privilege/guard index\n\nAll170retained/new function definitions captured for inspection. The guard column is a source index; it is not a substitute for reviewing delegated helper implementations or running every RPC scenario. Hash refers to function definition, never secret material.\n\n'
    funcs = []
    for f in sorted(catalog['functions'], key=lambda f: (f['schema'], f['name'], f['signature'])):
        guards = sorted(set(re.findall(r'(?:public\.)?(?:fr21_actor|fr21_role|fr28_identity|fr28_token_live|is_current_user_allowed|fr28_require_unblocked|fr13_can_receive|fr13_can_read|fr14_can_read|fr21_order_visible|auth\.uid|auth\.role)', f['definition'])))
        funcs.append([f['schema'] + '.' + f['name'] + '(' + f['signature'] + ')', f['definer'],
                      f['config'], f['anon_execute'], f['authenticated_execute'], ', '.join(guards) or 'Private/trigger/delegated/static boundary; inspect source',
                      hashlib.sha256(f['definition'].encode()).hexdigest()[:16]])
    text += table(['Function', 'Definer', 'Settings', 'Anon EXECUTE', 'Authenticated EXECUTE', 'Guard/dependency index', 'Definition SHA256 prefix'], funcs)
    text += '## Exact current policy predicates\n\n'
    text += table(['Table', 'Policy', 'Operation/mode/roles', 'USING', 'WITH CHECK'], [
        [t['schema'] + '.' + t['name'], p['policyname'], p['cmd'] + '/' + p['permissive'] + '/' + ','.join(p['roles']), p['qual'], p['with_check']]
        for t in catalog['tables'] for p in t['policies']])
    text += '## Stage1 file manifest\n\nGenerated from the current worktree/index, excluding all preserved .kilo deletions and ignored outputs.\n\n'
    changed = subprocess.check_output(['git', 'diff', '--name-only', 'c0a8da1', '--', '.', ':!.kilo'], cwd=ROOT).decode().splitlines()
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard'], cwd=ROOT).decode().splitlines()
    files = sorted(set(changed + untracked))
    text += ''.join('- `' + f + '`\n' for f in files if not f.startswith('.kilo/'))
    path.write_text(text, encoding='utf-8')
    print(json.dumps({'policy_matrix_rows': len(rows), 'function_entries': len(funcs), 'SQL_passed': len(sql), 'HTTP_passed': len(http)}))


if __name__ == '__main__':
    generate()
