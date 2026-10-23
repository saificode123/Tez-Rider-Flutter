"""Reconcile source-site UI templates without counting callbacks as controls.

This lexical inventory is not a Dart semantic analyzer or a runtime pass. Every
historical row is retained as a reference in the crosswalk, never silently lost.
"""
from pathlib import Path
import collections,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/evidence/FINAL03-ui-inventory.json'
types=set('TextField TextFormField IconButton TextButton ElevatedButton OutlinedButton FilledButton FloatingActionButton GestureDetector InkWell InkResponse ListTile Checkbox CheckboxListTile Radio RadioListTile RadioGroup Switch SwitchListTile Slider RangeSlider DropdownButton DropdownButtonFormField PopupMenuButton PopupMenuItem CheckedPopupMenuItem TabBar BottomNavigationBar NavigationBar Dismissible RefreshIndicator ExpansionTile BackButton CloseButton DrawerButton SearchBar SegmentedButton ChoiceChip FilterChip ActionChip InputChip Chip ReorderableListView'.split())
types.update(('FlutterMap','PageView'))
patterns=re.compile(r"/\*[\s\S]*?\*/|//[^\n]*|(?:r)?'''[\s\S]*?'''|(?:r)?\"\"\"[\s\S]*?\"\"\"|(?:r)?'(?:\\.|[^'\\])*'|(?:r)?\"(?:\\.|[^\"\\])*\"")
def mask(s):return patterns.sub(lambda m:''.join('\n'if c=='\n'else' 'for c in m[0]),s)
def role(p):
 if 'admin' in p:return 'Admin'
 if '/vendor/'in p or 'vendor_dashboard'in p:return 'Vendor'
 if 'rider_dashboard'in p:return 'Rider'
 if '/customer/'in p or any(k in p for k in('customer_dashboard','product_','search_screen')):return 'Customer'
 return 'Shared/inherited'
unreachable={'lib/screens/customer/cart_screen_new.dart','lib/screens/order_picked_screen.dart','lib/screens/payment_screen.dart','lib/screens/product_screen.dart','lib/screens/qr_pickup_screen.dart','lib/screens/vendor/prescription_review_screen.dart','lib/widgets/rate_order_sheet.dart','lib/widgets/empty_state.dart','lib/widgets/shimmer_cards.dart'}
rows=[];references=[];files=sorted([*ROOT.glob('lib/screens/**/*.dart'),*ROOT.glob('lib/widgets/*.dart')]);file_summary=[]
for path in files:
 p=path.relative_to(ROOT).as_posix();s=path.read_text(encoding='utf-8-sig');masked=mask(s);pairs={};stack=[]
 for i,c in enumerate(masked):
  if c=='(':stack.append(i)
  elif c==')'and stack:pairs[stack.pop()]=i
 helpers=set(re.findall(r'\bWidget\s+(_\w+)\s*\(',masked));calls=[];pointer_wrappers=[]
 for m in re.finditer(r'\b([A-Za-z_]\w*)(?:\.(\w+))?\s*(?:<[^<>\n]*>)?\s*\(',masked):
  start=masked.find('(',m.start(),m.end());end=pairs.get(start)
  if end is None:continue
  kind=m[1]
  if kind in ('IgnorePointer','AbsorbPointer'):
   disabled='ignoring'if kind=='IgnorePointer'else'absorbing'
   if not re.search(r'\b'+disabled+r'\s*:\s*false\b',masked[start:end]):pointer_wrappers.append((start,end))
  if re.search(r'\bWidget\s*$',masked[max(0,m.start()-20):m.start()]):continue
  if kind in types or kind in helpers or kind=='AppBar':calls.append({'start':m.start(),'open':start,'end':end,'kind':kind,'callbacks':[]})
 for m in re.finditer(r'\b(on[A-Z]\w*|validator)\s*:',masked):
  if m[1]=='onConflict':continue
  owners=[c for c in calls if c['open']<m.start()<c['end']]
  owner=min(owners,key=lambda c:c['end']-c['open'])if owners else None
  ref={'source':p,'line':s.count('\n',0,m.start())+1,'callback':m[1],'owner':None}
  if owner:owner['callbacks'].append(ref)
  else:references.append(dict(ref,classification='callback outside recognized control template; inspect lifecycle/custom composition'))
 for c in calls:
  if c['kind']=='FlutterMap'and any(start<c['start']<end for start,end in pointer_wrappers):
   references.append({'source':p,'line':s.count('\n',0,c['start'])+1,'classification':'passive map preview under IgnorePointer; no independent gesture control','helper':'FlutterMap'});continue
  if c['kind']in helpers and not c['callbacks']:
   references.append({'source':p,'line':s.count('\n',0,c['start'])+1,'classification':'helper invocation; no independent interactive-control count','helper':c['kind']});continue
  if c['kind']=='AppBar':
   # Only an inferred runtime affordance, not an observed Back/Drawer button.
   references.append({'source':p,'line':s.count('\n',0,c['start'])+1,'classification':'conditional framework leading; explicit leading overrides','helper':'AppBar'});continue
  line=s.count('\n',0,c['start'])+1;identifier=p+':'+str(line)+':'+c['kind'];frag=s[c['open']:c['end']+1]
  next_stage='Stage2 functionality / Stage4 UI; preserve approved B dispositions'
  if any(k in p for k in('login','signup','splash','pending_verification','role_access_gate')):next_stage='Stage1 access checks; Stage3 auth UX'
  status='UNREACHABLE-SOURCE'if p in unreachable else 'SHARED-TEMPLATE'if '/widgets/'in p else 'SOURCE-CONNECTED / RENDERING-UNVERIFIED'
  labels=re.findall(r"(?:Text|Tooltip)\(\s*['\"]([^'\"\n]{1,90})",frag)
  row={'id':identifier,'role':role(p),'screen':path.stem,'control':c['kind']+(' / '+', '.join(labels[:2])if labels else ''),'source':p+':'+str(line),'status':status,'evidence':'Current source constructor and callback range; docs/FINAL03-rendered-states.md maps actual evidence and untested conditions; no template-wide physical acceptance','next_stage':next_stage,'callback_lines':[r['line']for r in c['callbacks']],'callback_kinds':[r['callback']for r in c['callbacks']],'conditional':bool(re.search(r'\bif\b|\?|\.map\(|itemBuilder|on\w+:\s*null',frag)),'physical_verified':False}
  for ref in c['callbacks']:ref['owner']=identifier
  rows.append(row)
 file_summary.append({'source':p,'role':role(p),'unreachable_source_variant':p in unreachable,'templates':sum(r['source'].startswith(p+':')for r in rows),'scope':'source complete; state evidence tracked separately'})
historical=[]
for line in(ROOT/'docs/UI-control-reconciliation.md').read_text(encoding='utf-8').splitlines():
 if not line.startswith('| '):continue
 cells=[x.strip().replace('\\|','|')for x in re.split(r'(?<!\\)\|',line)[1:-1]]
 if len(cells)!=8 or not cells[3].startswith('lib/'):continue
 source=re.sub(r':\d+$','',cells[3]);number=re.search(r':(\d+)$',cells[3]);n=int(number[1])if number else None
 candidates=[r for r in rows if r['source'].startswith(source+':')and(n in r['callback_lines']or r['source']==cells[3])]
 category='template-reference'if candidates else 'helper-reference'if cells[2].startswith('helper ')else 'conditional-framework-reference'if cells[2].startswith('AppBar ')else 'historical-source-reference; current line may have moved'
 historical.append({'row':len(historical)+1,'source':cells[3],'control':cells[2],'classification':category,'canonical_ids':[r['id']for r in candidates]})
# Align stable source-site sequences with the accepted checkpoint; line offsets
# cannot safely identify callbacks after edits. Keep uncertain legacy refs explicit.
import difflib
prior=json.loads((ROOT/'docs/evidence/FINAL02-ui-inventory.json').read_text())
remap={}
for file in file_summary:
 old=[r for r in prior['controls'] if r['source'].rsplit(':',1)[0]==file['source']]
 new=[r for r in rows if r['source'].rsplit(':',1)[0]==file['source']]
 signature=lambda r:(r['control'].split(' / ')[0],tuple(r['callback_kinds']))
 matcher=difflib.SequenceMatcher(a=[signature(r)for r in old],b=[signature(r)for r in new],autojunk=False)
 for block in matcher.get_matching_blocks():
  for i in range(block.size):remap[old[block.a+i]['id']]=new[block.b+i]['id']
for old,now in zip(prior['historical_crosswalk'],historical):
 assert old['row']==now['row'] and old['source']==now['source']
 now['checkpoint_ids']=old['canonical_ids']
 now['canonical_ids']=[remap[i]for i in old['canonical_ids']if i in remap]
 now['classification']='checkpoint-aligned template reference'if now['canonical_ids']else old['classification']
assert len(historical)==707,'Every historical row must remain accounted for'
assert len({r['id']for r in rows})==len(rows)
delegates={'onAddToCart':'lib/widgets/recommendation_card.dart','onUploadSuccess':'lib/widgets/prescription_upload_widget.dart','onSuccess':'lib/screens/rider_dashboard.dart::_OtpVerifySheet','onAccept':'lib/widgets/pre_delivery_checklist_card.dart','onStart':'lib/widgets/pre_delivery_checklist_card.dart','onAction':'lib/widgets/empty_state.dart::EmptyStateWidget','onSubmit':'lib/widgets/rate_order_sheet.dart::RateOrderSheet'}
for ref in references:
 if ref.get('owner')is None and ref.get('callback')in delegates:
  ref['classification']='delegated callback into shared/custom component; control owned by component template, not an independent control'
  ref['target']=delegates[ref['callback']]
evidence={'baseline':subprocess.check_output(['git','rev-parse','cb18c2b'],cwd=ROOT).decode().strip(),'method':'lexical constructor/callback ownership; distinct source templates, not runtime instances; nested controls intentionally distinct','files':file_summary,'counts':{'files':len(files),'screens':sum('/screens/'in str(p).replace('\\','/')for p in files),'unique_source_templates':len(rows),'by_status':dict(collections.Counter(r['status']for r in rows)),'noncontrol_references':len(references),'historical_crosswalk':len(historical),'observed_rendered_controls':'not inferred; see physical/widget evidence'},'controls':rows,'references':references,'historical_crosswalk':historical}
evidence['checkpoint_template_crosswalk']=[{'checkpoint_id':r['id'],'current_id':remap.get(r['id']),'method':'ordered constructor/callback-kind alignment; source review, not execution'}for r in prior['controls']]
evidence['previous_checkpoint']={'unique_source_templates':410,'noncontrol_references':295,'reconciliation':'Two explicit error Retry controls added for saved addresses and favourites; all410baseline templates and707historical rows retained. Line numbers changed after fixes; runtime instances remain data-dependent.'}
OUT.write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
lines=['# Canonical source-control inventory','','Supersedes additive counting of the707overlapping historical rows. All707remain in the JSON crosswalk. Unique source-site templates are not unique runtime widgets or passing tests. Repeated list instances have data-dependent cardinality; shared template invocations remain separate references. Classification of unreachable variants is based on the earlier import/caller reconciliation, not deletion permission.','',json.dumps(evidence['counts'],ensure_ascii=False),'','| Role | Screen | Control | Source | Status | Evidence | Next Stage |','|---|---|---|---|---|---|---|']
for r in rows:lines.append('| '+' | '.join(str(r[k]).replace('|','/').replace('\n',' ')for k in('role','screen','control','source','status','evidence','next_stage'))+' |')
(ROOT/'docs/FINAL03-ui-canonical.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps(evidence['counts']))
