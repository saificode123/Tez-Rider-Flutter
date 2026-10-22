"""Offline reconciliation of real captured evidence; no deployment or test runs.

Historical reports remain intact. Current observations are linked explicitly,
and unknown rendered states/lifecycles remain unverified.
"""
import hashlib
import ast
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / '.fr21-local/final01'
DOCS = ROOT / 'docs'
DATE = '2026-10-23'


def read(name):
    return json.loads((PRIVATE / name).read_text(encoding='utf-8-sig'))


def passed(name, count):
    rows = read(name)
    assert len(rows) == count and all(row['result'] == 'PASS' for row in rows)
    return rows


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table(headers, rows):
    def cell(value):
        return str(value).replace('|', '\\|').replace('\n', ' ').replace('\r', ' ')
    return '| ' + ' | '.join(headers) + ' |\n|' + '|'.join('---' for _ in headers) + '|\n' + ''.join(
        '| ' + ' | '.join(cell(value) for value in row) + ' |\n' for row in rows) + '\n'


catalog = read('final02-catalog.private.json')
deployment = read('deployment-202610220004.json')
assert deployment['project'] == 'igeisilhtmglgnqvllrx' and deployment['versions'] == 42
assert len(catalog['versions']) == 42 and all(t['rls'] for t in catalog['tables'])
hosted = passed('hosted-enforced.json', 108)
boundary = passed('boundary-enforced-results.json', 13)
targeted = passed('enforcement-targeted.json', 20)
media = passed('media-deadline-results.json', 5)
realtime = passed('realtime-lifecycle-results.json', 12)
capability = passed('installation-capability-results.json', 8)
capability_http = passed('installation-capability-http-results.json', 10)
lifecycle = passed('lifecycle-enforced-results.json', 11)
post = passed('post-202610220004.json', 25)
ready = read('activation-readiness.json')
assert ready['retained_body_grant_matches'] == 170
build = read('build-evidence.json')
assert build['project'] == deployment['project']
assert all(sha(ROOT / item['path']).upper() == item['sha256'] for item in build['sources'])
inventory = json.loads((DOCS / 'evidence/FINAL02-ui-inventory.json').read_text())
assert inventory['counts']['historical_crosswalk'] == 707
assert inventory['counts']['unique_source_templates'] == 410 and inventory['counts']['noncontrol_references'] == 295
native = [json.loads(line) for line in (PRIVATE / 'native-results.jsonl').read_text().splitlines() if line]
current_native = [row for row in native if row.get('activation_deployed') is True]
analysis = (PRIVATE / 'final02-analysis-final.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in analysis
tests = (PRIVATE / 'final02-affected-final.log').read_text(encoding='utf-8-sig')
assert '+18: All tests passed!' in tests
helpers = list((ROOT / 'tests/integration').glob('FINAL02*.py')) + [ROOT / 'tests/integration/FINAL01-native.py', ROOT / 'tests/integration/FINAL01-boundaries.py', ROOT / 'tests/integration/FINAL01-lifecycle.py']
for helper in helpers:
    ast.parse(helper.read_text(encoding='utf-8-sig'))
secret_scan = json.loads((ROOT / '.fr21-local/final1/secret-scan.json').read_text())
protected_scan = read('final02-protected-scan.json')
assert protected_scan['protected_credential_matches'] == 0
assert not any(row['type'] in ('privileged_or_unknown_jwt', 'provider_or_private_key', 'static_private_pem') for row in secret_scan['current'])
local_verification = {'date': DATE, 'affected_serial_passed': 18, 'overlapping_additional_run_passed': 16,
                      'scoped_analyzer_errors': 0, 'scoped_analyzer_issues': 0, 'new_full_suite': False,
                      'python_helpers_parsed': len(helpers), 'protected_scan': protected_scan,
                      'bounded_pattern_scan': {'current_text_files': secret_scan['current_text_files'],
                          'historical_small_blobs': secret_scan['historical_small_blobs'],
                          'current_candidate_types': [row['type'] for row in secret_scan['current']],
                          'historical_candidate_count': len(secret_scan['history']), 'scope': secret_scan['limits']}}
(DOCS / 'evidence/FINAL02-local-verification.json').write_text(json.dumps(local_verification, indent=2) + '\n', encoding='utf-8')

# All discoverable files receive an explicit conditional-state audit entry.
# Native label observations never imply every control in a screen was tested.
rendered = {
    'lib/screens/customer/about_tezrider_screen.dart': ('widget', 'unsupported fixed claims visibly present', 'stage0_rendered_audit_test.dart'),
    'lib/screens/customer/payment_methods_screen.dart': ('widget', 'empty methods; unavailable add; no instrument saved', 'stage0_rendered_audit_test.dart'),
    'lib/screens/login_screen.dart': ('widget/native', 'required-field validation; selected four-role password routes bounded below', 'stage0_rendered_audit_test.dart; native observations'),
    'lib/screens/signup_screen.dart': ('widget', 'required-field validation only; no account created', 'stage0_rendered_audit_test.dart'),
    'lib/widgets/role_access_gate.dart': ('widget', 'unauthenticated denial and Retry remain denied', 'stage0_rendered_audit_test.dart'),
    'lib/screens/customer_dashboard.dart': ('native', 'catalogue visible and restored after activation', 'post-activation Search food, stores, cuisines... observation'),
    'lib/screens/rider_dashboard.dart': ('native', 'fresh password login; dashboard and offline state; restart restoration', 'post-activation Rider Dashboard observations'),
    'lib/screens/vendor_dashboard.dart': ('native', 'fresh password login; dashboard; restart only when separately recorded', 'post-activation Store Dashboard observations'),
    'lib/screens/admin_dashboard.dart': ('native', 'fresh password login and restoration after activation; logout observed separately', 'dated Admin Panel and sign-in observations; missed initial transition capture retained'),
    'lib/screens/admin_users_screen.dart': ('native', 'post-activation directory shows marked customer Active; earlier block/unblock remains historical', 'dated native marked-customer observation; earlier backend unblock confirmation'),
    'lib/screens/customer/order_history_screen.dart': ('checkpoint observation', 'populated history reported in prior physical checkpoint', 'checkpoint request; not a new post-activation pass'),
    'lib/screens/vendor/product_form_screen.dart': ('checkpoint observation', 'empty form validation reported in prior physical checkpoint', 'checkpoint request; not a new post-activation pass'),
}
state_rows = []
for file in inventory['files']:
    path = file['source']
    observed = rendered.get(path, ('source only', 'no independent rendered-state evidence mapped', 'canonical source inventory'))
    state_rows.append([file['role'], path, *observed,
                       'Other loading/empty/error/permission/blocked/offline/list-instance conditions NOT TESTED unless specifically named above',
                       'Stage1 security acceptance where active; Stage2 functionality/Stage3 auth/Stage4 UI/Stage5 platform as traced'])
state_text = '# Rendered-state evidence matrix\n\n' + DATE + '. Each of the 56 discovered files is reconciled. This is an evidence matrix, not full conditional-state acceptance. A visible label is an observation, not proof of its callback or backend transaction. Shared and unreachable templates remain in the canonical inventory. No runtime count is inferred.\n\n'
state_text += table(['Role', 'Source', 'Evidence class', 'Observed scope', 'Evidence', 'Unverified conditions', 'Next stage'], state_rows)
state_text += '\nFailures retained: original two rendering failures and OneDrive compiler collision preceded the historical serial18 pass. This continuation first hit an SDK-cache sandbox denial; its authorized16-case rerun passed. The final original affected18-case serial set passed. These sets overlap. Physical transient captures and missed transition assertions are attempts, not passes.\n'
(DOCS / 'FINAL02-rendered-states.md').write_text(state_text, encoding='utf-8')

# Reuse only pure formatting/scope helpers; never invoke the stale generator.
spec = importlib.util.spec_from_file_location('historical_report', ROOT / 'tests/integration/FINAL-security-report.py')
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
operations = []
policies = []
for item in sorted(catalog['tables'], key=lambda value: (value['schema'], value['name'])):
    for operation in ('SELECT', 'INSERT', 'UPDATE', 'DELETE'):
        grants = [g['grantee'] for g in item['grants'] if g['privilege_type'] == operation]
        column = any(g['grantee'] == 'authenticated' and g['privilege_type'] == operation for g in item['columns'])
        direct = 'authenticated' in grants or column
        scopes = [old.client_scope(item['name'], operation, role) if direct else 'DENIED (no grant)'
                  for role in ('Customer', 'Vendor', 'Rider', 'Admin')]
        names = ', '.join(p['policyname'] for p in item['policies'] if p['cmd'] in (operation, 'ALL')) or 'No policy'
        operations.append([item['schema'] + '.' + item['name'], operation, *scopes,
                           'BYPASSRLS subject to grants/constraints' if 'service_role' in grants else 'No direct grant', names])
    for policy in item['policies']:
        policies.append([item['schema'] + '.' + item['name'], policy['policyname'], policy['permissive'],
                         policy['roles'], policy['cmd'], policy['qual'], policy['with_check']])
matrix = '# Activated TEST policy and operation matrix\n\n' + DATE + '. Read-only post-activation catalog:42 versions,83 RLS-enabled tables,174 functions. The332 table/operation rows describe metadata and predicates. Four application roles use authenticated database identity; canonical helpers enforce application roles. They are not332 passing runtime tests. Separate executed scopes:108 enforced gateway/role,13 boundary,20 targeted,5 real media deadline,12 own-profile Realtime,8 rollback-only installation SQL,10 actual anonymous capability HTTP and11 physical/hosted lifecycle checks. Service reads establish accounting only.\n\n'
matrix += table(['Table', 'Operation', 'Customer', 'Vendor', 'Rider', 'Admin', 'Service', 'Policies'], operations)
matrix += '## Exact policy predicates\n\n' + table(['Table', 'Policy', 'Kind', 'Roles', 'Operation', 'USING', 'WITH CHECK'], policies)
matrix += '## FR43 validation and FR44 critical operations\n\n'
matrix += table(['Requirement / active path', 'Trusted enforcement', 'Actual retained/current evidence', 'Limit'], [
    ['FR43 profile/search', 'field/identity triggers; bounded invoker search RPC', '108 enforced checks include four-role empty-search rejection; historical own-profile write/escalation denial', 'not every legacy field/encoding branch exercised'],
    ['FR43 Edge/gateway', 'exact envelope/body fields, allowed paths/headers, payload bounds, canonical JWT', '108 enforced checks; forged-proof targeted test; Deno175 historical', 'no provider request or provider success claim'],
    ['FR43 stock/checkout/state', 'transactional FR17/10/20/checklist RPCs', 'historical synthetic18 workflow; accepted retained FR evidence', 'no new full lifecycle replay after activation'],
    ['FR44 vendor/rider review', 'canonical Admin; transactional review audit/trigger', 'retained SQL review/audit and current malformed/ordinary-user denial', 'new valid review transaction not repeated'],
    ['FR44 block/unblock', 'admin-user-status idempotent synchronized operation', '11post-activation lifecycle checks including physical marked-customer denial, re-login/logout and exactly-one committed block audit', 'only marked fixture; confirmed active afterward; no universal Admin workflow acceptance'],
    ['FR44 dispute decision', 'FR26 locked decision and committed audit', 'retained FR26 acceptance/current queue read', 'money settlement never inferred'],
    ['FR44 broadcast', 'FR30 canonical Admin transaction and audit', 'retained FR30 Android acceptance/current estimate and worker denial', 'no new notification send'],
    ['FR44 failure audit', 'trusted classified/deduplicated server recorder; new namespace-only30day retention', 'targeted real denial persisted; gateway audit INSERT/UPDATE/DELETE403', 'accounting read is service evidence; server-error outage injection not performed'],
    ['Later manual assignment/settings/media/rating', 'missing workflows remain deferred; existing denied paths retained', 'canonical controls and roadmap B dispositions', 'not functional acceptance; no Stage2 implementation'],
])
matrix += 'FR42/43/44 remain PARTIAL. Preservation evidence compared170 retained definitions and ACLs before activation; it is not independent functional proof. Activation intentionally changes fr28_token_live, fr28_pre_request and fr30_resolve_push and adds one restrictive users policy. No RLS or privilege was relaxed.\n'
(DOCS / 'FINAL02-security-matrix.md').write_text(matrix, encoding='utf-8')

features = [('FR-21', '1173736'), ('FR-04', 'fd478a4'), ('FR-25', '281c8a8'), ('FR-26', 'aabd6ca'),
            ('FR-33', 'ec1c63b'), ('FR-28', '7e809fd'), ('FR-20', 'fa29b4c'), ('FR-30', 'fed835f'),
            ('FR-10', '76960fa'), ('FR-17', '57914e2'), ('FR-32', '569e8c6'), ('CHECKLIST', '7cf80fe'),
            ('FR-13', '3408790'), ('FR-14', 'f8bce53')]
retained = []
for name, commit in features:
    path = DOCS / (name + '-acceptance.md')
    assert path.exists()
    ancestor = subprocess.run(['git', 'merge-base', '--is-ancestor', commit, 'HEAD'], cwd=ROOT).returncode == 0
    assert ancestor
    text = path.read_text(encoding='utf-8-sig')
    summary = next((line.strip() for line in text.splitlines() if re.search(r'FUNCTIONALLY ACCEPTED|NOT FUNCTIONALLY ACCEPTED|Acceptance.*PASS', line, re.I)), 'See exact bounded acceptance criteria in retained report')
    retained.append({'feature': name, 'report': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                     'checkpoint': commit, 'ancestor': ancestor, 'retained_disposition': summary,
                     'new_full_regression': False})
(DOCS / 'evidence/FINAL02-retained-features.json').write_text(json.dumps(retained, indent=2) + '\n', encoding='utf-8')
limits = [
    'Complete rendered conditional states and handler acceptance remain unverified; source inventory is complete only within56screen/widget files.',
    'Own-profile Realtime live/expired/revoked lifecycle passed12checks with bounded10second nondelivery; other private topics remain unverified. Installation capability passed8rollback-only SQL and10actual anonymous HTTP live/deadline/revoked checks; no new native push receipt claimed.',
    'Five real short-deadline CNIC checks passed; other media and authorized-owner direct Storage lifecycles remain unverified.',
    'Four-role password routing/restoration, logout, marked-customer blocked/re-login flow and eventual Vendor-revocation routing observed; complete physical error/retry and secure-storage fault coverage remains incomplete. Optional biometric enrollment/fault work remains Stage3 per existing policy.',
    'Independent functional proof for every retained definer/legacy operation and universal FR42/43/44 coverage remains incomplete.',
    'FR14 remains NOT FUNCTIONALLY ACCEPTED; iOS runtime and production are outside executed verification; Stage2–5 stopped.',
]
evidence = {'date': DATE, 'project': deployment['project'], 'production_modified': False,
            'stage0': 'PARTIAL — source audit reconciled; rendered evidence incomplete',
            'stage1': 'PARTIAL — activated; SECURITY ACCEPTANCE PENDING',
            'deployment': deployment, 'readiness': ready, 'catalog': {'versions': 42, 'tables': 83, 'functions': 174, 'all_inspected_rls': True},
            'build': {'package': build['package'], 'apk_sha256': build['sha256'], 'current_source_hashes_match': True, 'source_files': len(build['sources'])},
            'post_activation': {'metadata': post, 'four_role_http': hosted, 'controlled_boundaries': boundary, 'targeted': targeted, 'media_deadline': media, 'own_profile_realtime': realtime, 'installation_capability_sql': capability, 'installation_capability_http': capability_http, 'physical_hosted_lifecycle': lifecycle},
            'android': {'serial': 'AESWNRBAEUPNTGJZ', 'package': 'com.example.flutter_application_1.fr21test',
                        'source_installed_hash_check': True, 'observations': current_native,
                        'historical_observations': [row for row in native if not row.get('activation_deployed')]},
            'local': {'affected_final_serial': 18, 'additional_overlapping_run': 16, 'scoped_analyzer': '0issues/exit0',
                      'historical_full_flutter': '290PASS/2inherited skips', 'historical_full_deno': '175PASS',
                      'new_full_suite': False},
            'attempt_history': ['historical two rendered failures and OneDrive collision retained', 'initial SDK-cache sandbox access failure; authorized rerun passed',
                                'targeted helper first hit prior quota then omitted forwarded JSON type; both logs retained privately; corrected20checks passed',
                                'native transient dump failures/missed transition assertions are not passes',
                                'media clock metadata-role guard matched no row; corrected canonical-role guard and five real deadline checks passed',
                                'installation probe found no eligible existing notice and rolled back; explicit uncommitted synthetic notice then eight function-boundary checks passed and rolled back'],
            'limits': limits}
(DOCS / 'evidence/FINAL02-acceptance.json').write_text(json.dumps(evidence, indent=2) + '\n', encoding='utf-8')

# Preserve the prior manifest and original checkpoint while updating current state.
path = DOCS / 'evidence/FINAL01-security-results.json'
prior = json.loads(path.read_text())
committed = json.loads(subprocess.check_output(['git', 'show', 'afcc765:docs/evidence/FINAL01-security-results.json'], cwd=ROOT))
prior.setdefault('files_changed', committed['files_changed'])
prior.setdefault('historical_afcc765_checkpoint', {key: committed[key] for key in ('activation', 'android', 'catalog', 'limitations')})
prior['current_checkpoint'] = {'date': DATE, 'evidence': 'docs/evidence/FINAL02-acceptance.json', 'activation_applied_once': True,
                             'versions': 42, 'security_accepted': False, 'limits': limits}
prior['activation'] = {'prerequisites': '202610220003 APPLIED ONCE', 'enforcement': '202610220004 APPLIED ONCE',
                       'direct_rest_proof_required': True, 'readiness': 'actual successful preflight;170retained body/grant matches',
                       'post_deploy_metadata_passed': 25, 'four_role_enforced_checks': 108}
prior['android'] = evidence['android']
prior['catalog'] = evidence['catalog']
prior['limitations'] = limits
path.write_text(json.dumps(prior, indent=2) + '\n', encoding='utf-8')

checkpoint = '''## FINAL02 current checkpoint — 2026-10-23 (Asia/Karachi)

This checkpoint supersedes earlier pending-approval, absent-device and unapplied-activation statements; those paragraphs remain historical. A/B/C approvals retain exactly their granted scope. Stage0 remains PARTIAL: the source audit is reconciled, but full conditional rendered-state evidence remains incomplete. Stage1 remains PARTIAL — SECURITY ACCEPTANCE PENDING. Stage2 readiness NO.

Canonical inventory:40screen/16widget files;410distinct source templates (338source-connected/rendering-unverified,32unreachable,40shared),295noncontrol references and all707historical rows retained. The earlier406/297checkpoint omitted three interactive map templates and the featured PageView; the IgnorePointer map preview is passive composition. These are not passing-control counts. See FINAL02-ui-canonical.md, FINAL02-rendered-states.md and evidence/FINAL02-ui-inventory.json. The two narrow UI fixes and five rendered audit cases are retained; no Stage2–5 feature or redesign was introduced.

TEST-only read-only preflight succeeded:170retained definitions/grants unchanged, current source/installed APK hashes match, compatible regressions verified. The CLI login-role timeout did not recur in this continuation.25rollback review checks passed,0004applied exactly once,25post-deploy metadata checks passed. TEST:42versions,83inspected RLS-enabled tables,174functions. No reset, replay, production access, push or merge. Recovery source captured privately before activation; no recovery or RLS relaxation executed.

Post-activation evidence:108real four-role JWT/gateway/RLS checks,13controlled boundary checks (two-request quota race/Retry-After/authorized CNIC/read/deadline),20targeted checks (forged direct proof, gateway audit immutability, quota reset, expired/revoked sessions and private-list nondisclosure),5real short-deadline CNIC checks (only a fresh synthetic Admin session aged; URL bounded by remaining45seconds, bytes available before expiry, same URL denied after expiry and renewal denied). These are separately scoped runs, not a new whole-application acceptance total. Storage nondisclosure without an owner-positive fixture is explicitly limited. Service-role accounting never counts as user isolation. Current detailed operation/policy/validation/Admin-audit matrix: FINAL02-security-matrix.md.

The authorized phone was connected; existing installed TEST APK matched current source and build hashes. Actual dated native observations are in evidence/FINAL02-acceptance.json. Four-role password routing and restoration were observed after activation; synthetic Vendor global revocation eventually returned the phone to sign-in (no immediate transition or timing guarantee).11post-activation lifecycle checks included one necessary marked-customer block/unblock cycle: phone routed to sign-in, provider refused login while blocked, replay preserved one committed audit, finally confirmed unblock, phone password re-login restored catalogue and normal logout returned to sign-in. Earlier customer history/vendor form/directory observations remain historical. The synthetic customer is confirmed active; phone left logged out. Captures/transient failures/missed transition assertions are not passes.

Final original affected regression set:18PASS serial. Separate16PASS run overlaps and must not be added. Scoped analyzer:0issues/exit0. Historical full Flutter290PASS/2inherited skips, Deno175PASS, hosted173PASS remain historical. Original rendering failures/OneDrive collision and this continuation's helper-order/content-type failures are preserved; corrected runs passed. No report generator with stale pending-device/activation fields was blindly rerun.

Retained FR21/04/25/26/33/28/20/30/10/17/32/checklist/13/14 reports were hashed and their checkpoint ancestry verified in evidence/FINAL02-retained-features.json. This preserves bounded historical acceptance, not independent reruns. FR14 remains NOT FUNCTIONALLY ACCEPTED. FR13 Android and FR30 Android acceptance do not accept iOS; FR26/10 accounting does not confirm money settlement; FR33 remains the approved email alternative; FR32 provider/email quota and optional load limits remain.

Actual own-profile Realtime lifecycle passed12checks: positive delivery before expiry/local revocation, then no delivery on the same websocket during bounded10second observations after each denial. Unchanged marked-fixture name writes supplied events. This does not establish every private tracking/broadcast topic. Installation capability:8rollback-only SQL function checks covered live resolution, wrong secret/installation/snapshot, absolute/earlier-provider deadlines and session snapshot mismatch.10additional actual anonymous HTTP checks covered positive resolution, wrong secrets, absolute deadline and normal local logout revocation. Two marked synthetic notices/private jobs were created without INSERT-trigger fanout; due_at is later than expires_at, so they cannot dispatch. Fixtures retained; no worker/provider call or new native push receipt claimed. Remaining gates: complete conditional rendered/handler evidence; remaining private Realtime topics and authorized-owner Storage/media lifecycles; complete physical error/retry and secure-storage fault checks; independent retained-definer/legacy-operation coverage. Optional biometric enrollment/fault work remains Stage3 per existing policy. FR42/43/44 remain PARTIAL. Missing later-stage features are classified rather than implemented or claimed accepted. See evidence/FINAL02-acceptance.json for precise executed checks and limitations.
'''
for filename in ('UI-control-inventory.md', 'UI-control-reconciliation.md', 'SRDS-traceability.md',
                 'FINAL-implementation-roadmap.md', 'FINAL-progress.md', 'FINAL-security-audit.md',
                 'FINAL-stage-0-1-acceptance.md', 'FINAL01-security-verification.md'):
    path = DOCS / filename
    text = path.read_text(encoding='utf-8-sig')
    marker = '\n## FINAL02 current checkpoint'
    summary = checkpoint if filename == 'FINAL-stage-0-1-acceptance.md' else '''## FINAL02 current checkpoint — 2026-10-23 (Asia/Karachi)

Stage0 PARTIAL; Stage1 PARTIAL — SECURITY ACCEPTANCE PENDING; Stage2 readiness NO. This supersedes earlier pending-approval/device/activation labels while preserving their history. A/B/C approvals remain granted within their exact scopes.

Canonical inventory:56files,410source templates,295noncontrol references,707historical crosswalk rows. Corrects the earlier406/297checkpoint for three interactive maps/PageView; passive map preview remains composition. Source-template counts are not runtime pass counts. See [canonical controls](FINAL02-ui-canonical.md) and [rendered-state evidence](FINAL02-rendered-states.md).

TEST0004applied once after successful readiness/25rollback checks;25post checks passed. Current42versions/83RLS-enabled tables/174functions. Post-activation108four-role,13boundary,20targeted,5real signed-CNIC deadline,12own-profile Realtime,8rollback-only and10actual anonymous installation-capability,11physical/hosted lifecycle checks passed within their named scopes. Installed TEST APK/source hashes match; four-role routing/restoration, blocked/re-login and revoked/logout observations recorded individually. Marked customer confirmed active; phone logged out. Final affected18PASS; scoped analysis0issues. Historical290Flutter/2skips,175Deno and173hosted results are not new full-suite runs or additive totals.

See [current acceptance checkpoint](FINAL-stage-0-1-acceptance.md#final02-current-checkpoint--2026-10-23-asiakarachi), [policy/validation/Admin-audit matrix](FINAL02-security-matrix.md), [current evidence](evidence/FINAL02-acceptance.json) and [retained feature reconciliation](evidence/FINAL02-retained-features.json). Remaining evidence: full conditional rendering/handlers, other private Realtime topics/media paths, physical error/retry and secure-storage faults, independent retained-definer/legacy-operation proof. FR42/43/44 PARTIAL; FR14 NOT FUNCTIONALLY ACCEPTED. No Stage2–5 work, production modification, reset/replay, push or merge.
'''
    text = text.split(marker)[0].rstrip() + '\n\n' + summary
    pointer = '> Current status: see the FINAL02 current checkpoint at the end and docs/evidence/FINAL02-acceptance.json. Earlier checkpoints are historical.\n\n'
    if pointer not in text:
        first, rest = text.split('\n', 1)
        text = first + '\n\n' + pointer + rest.lstrip('\n')
    path.write_text(text, encoding='utf-8')
changed = set()
for args in (['diff', '--name-only', '-z', 'afcc765'], ['ls-files', '--others', '--exclude-standard', '-z']):
    changed.update(subprocess.check_output(['git', *args], cwd=ROOT).decode().split('\0'))
changed.discard('')
changed.add('docs/evidence/FINAL02-files.txt')
(DOCS / 'evidence/FINAL02-files.txt').write_text('\n'.join(sorted(changed)) + '\n', encoding='utf-8')
print(json.dumps({'project': deployment['project'], 'versions': 42, 'operation_rows': len(operations),
                  'rendered_state_files': len(state_rows), 'retained_features': len(retained),
                  'stage0': evidence['stage0'], 'stage1': evidence['stage1']}))
