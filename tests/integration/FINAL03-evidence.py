"""Publish bounded FINAL03 evidence without credentials, object refs or raw logs."""
from pathlib import Path
import ast, hashlib, json, re, subprocess
ROOT=Path(__file__).resolve().parents[2]
PRIVATE=ROOT/'.fr21-local/final03'
OUT=ROOT/'docs/evidence'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rows(name):
 result=[]
 for line in (PRIVATE/name).read_text(encoding='utf-8-sig',errors='replace').splitlines():
  try:r=json.loads(line)
  except (ValueError,TypeError):continue
  if r.get('result')=='PASS':result.append({k:r[k]for k in ('check','result','surface','observed_at')if k in r})
 return result
logs={'media':'media.log','chat':'chat.log','legacy':'legacy-post.log','audit':'audit.log','tracking':'tracking-session-topics.log','notifications':'realtime-notifications.log','vendor_orders':'realtime-vendor.log','rider_assignments':'realtime-rider.log','catalog':'catalog-final.log','blocked_media':'media-faults.log'}
checks={k:rows(v)for k,v in logs.items()}
checks['disputes_and_orders']=[r for r in rows('realtime-attempt2.log')if r['check'].startswith(('disputes:','orders:'))]
assert {k:len(v)for k,v in checks.items()}=={'media':60,'chat':6,'legacy':5,'audit':4,'tracking':27,'notifications':13,'vendor_orders':12,'rider_assignments':12,'catalog':5,'disputes_and_orders':16,'blocked_media':6}
registry=json.loads((PRIVATE/'tracking-registry-post.log').read_text().strip().splitlines()[-1])
assert registry['passed']==10 and registry['rolled_back']
flutter=(PRIVATE/'flutter-final-all.log').read_text(errors='replace')
assert '+74: All tests passed!'in flutter
assert 'No issues found!'in (PRIVATE/'analyze-scoped-final.log').read_text()
analyzer=(PRIVATE/'analyze-final-all.log').read_text(errors='replace')
assert '57 issues found.'in analyzer and not re.search(r'^\s*error - ',analyzer,re.M)
deno=(PRIVATE/'deno.log').read_text(errors='replace')
assert re.search(r'17 passed',deno) and re.search(r'0 failed',deno)
build=json.loads((PRIVATE/'build-evidence.json').read_text(encoding='utf-8-sig'))
assert build['project']=='igeisilhtmglgnqvllrx'
for item in build['sources']:assert digest(ROOT/item['path']).upper()==item['sha256'].upper()
retained=json.loads((OUT/'FINAL02-retained-features.json').read_text())
for r in retained:
 assert digest(ROOT/r['report'])==r['sha256']
 assert subprocess.run(['git','merge-base','--is-ancestor',r['checkpoint'],'HEAD'],cwd=ROOT).returncode==0
for p in (ROOT/'tests/integration').glob('FINAL03-*.py'):ast.parse(p.read_text(encoding='utf-8-sig'))
native=rows('native-results.jsonl')
last_install=max(i for i,r in enumerate(native)if 'APK installed' in r['check'])
final_native=native[last_install:]
assert sum(r['check']=='observed native My Location'for r in final_native)==2
assert sum(r['check']=='observed native Sign in as Customer'for r in final_native)>=3
assert any('connectivity recovery:'in r['check']for r in final_native)
assert final_native[-1]['check']=='observed native Sign in as Customer'

result={'iteration':'FINAL03','status':{'stage0':'COMPLETE: audit/classification; bounded named runtime evidence, not whole-app implementation','stage1':'SECURITY ACCEPTED: active/deny-default TEST scope','stage2_ready':True,'stage2_started':False},'date':'2026-10-23 Asia/Karachi','baseline':'cb18c2b','project':'igeisilhtmglgnqvllrx','production_modified':False,
 'scope':'Stage0/1; no Stage2 implementation, Docker, load test, push or merge',
 'flutter':{'pass':74,'fail':0,'skip':0,'method':'final serial ten-file affected suite','log_sha256':digest(PRIVATE/'flutter-final-all.log')},
 'deno':{'pass':17,'fail':0,'skip':0,'scope':'fr13-location handler and publication','log_sha256':digest(PRIVATE/'deno.log')},
 'analyzer':{'errors':0,'warnings':14,'infos':43,'exit':1,'status':'57 inherited diagnostics; not a clean analyzer pass','focused_issues':0,'focused_log_sha256':digest(PRIVATE/'analyze-scoped-final.log'),'log_sha256':digest(PRIVATE/'analyze-final-all.log')},
 'checks':checks,'evidence_source_hashes':{name:digest(PRIVATE/name)for name in sorted(set(logs.values())|{'realtime-attempt2.log','tracking-registry-post.log','native-results.jsonl','android-network.log','media-faults.log'})},'registry_post':registry,'check_counts':{**{k:len(v)for k,v in checks.items()},'reader_registry_rollback':10},
 'hosted_assertion_records':sum(map(len,checks.values()))+10,
 'integrity':{'python_helper_ast':'PASS','powershell_helper_parser':'PASS','historical_FINAL01_FINAL02_unchanged':True,'diff_check':'PASS: git -c core.whitespace=cr-at-eol diff cb18c2b --check; Windows migration CRLF retained'},
 'protected_scan':json.loads((PRIVATE/'protected-scan.json').read_text()),
 'android':{'observations':native,'network_recovery':rows('android-network.log'),'storage_fault_level':'10 mocked fault cases; no phone storage corruption','final_install':'PASS: final source-verified APK installed; customer login/restart, physical offline/retry, logout and restart signed-out observed','final_build_observations':final_native,'final_build':{'package':build['package'],'sha256':build['sha256'],'sources':build['sources']}},
 'deployment':{'versions':45,'rls_tables':84,'functions':175,'new_versions':['202610230001','202610230002','202610230003'],'0004_replayed':False,'edge':'fr13-location via hosted API; no Docker','prior_grants_and_policies_preserved':True},
 'retained_reports':retained,
 'attempts':[
  'Original tracking revocation test FAILED: cached private shared channel leaked subsequent events. Fixed with session topics and fresh publication authorization; final27 PASS.',
  'First session fanout included dormant synthetic Admin sessions and timed out. Added private reader registry; final27 websocket plus10 rollback PASS.',
  'Initial Realtime no-op signal did not emit; bounded description signal restored in finally. Missing notification participant fixture corrected; final scope-specific runs pass.',
  'UI tests exposed Material ancestors and narrow-screen overflows; source fixed. Gift test had expected SnackBar covering next tap; dismissed it explicitly. Final74 PASS.',
  'Vendor logout assertion initially checked before confirmation. Cancel and confirmed logout then verified separately.',
  'Default diff whitespace check treated Windows SQL CRLF as trailing whitespace. Windows-aware check passes; extra new-helper EOF blank lines removed. No SQL behavior or deployment changed.',
  'Final APK installation first failed because target device was absent. After user USB debugging reconnection, final installation and native lifecycle/network checks passed. Failed attempts are not passes.'
 ],
 'limits':['Bounded denied websocket windows, not an SLA or scale guarantee.','Retained290 Flutter/2 inherited skips and175 Deno are historical overlapping baselines, not current totals.','FR14 road-route, ETA and physical movement remain NOT FUNCTIONALLY ACCEPTED.','No production/iOS/paid-provider/1000-user acceptance.','Private evidence remains ignored; published rows omit tokens, private links and document paths.']}
(OUT/'FINAL03-acceptance.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'flutter':74,'deno':17,'hosted_assertion_records':result['hosted_assertion_records'],'retained_reports':len(retained),'android_final_install':result['android']['final_install']}))
