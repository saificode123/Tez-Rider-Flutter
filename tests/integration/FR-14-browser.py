"""Protected TEST customer browser login; no credentials in tool or shell text."""
import importlib.util,subprocess,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr14',Path(__file__).with_name('FR-14-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
cli=['npx.cmd','--yes','agent-browser','--session','fr14-60194cb55fe7']
a=h.state['accounts']['physical-customer']
def call(args,stdin=None):
 p=subprocess.run(cli+args,input=stdin,capture_output=True,text=True,timeout=60)
 assert p.returncode==0,'Protected browser operation failed; credentials suppressed'
 return p.stdout.replace(a['email'],'[TEST account]').replace(a['password'],'[redacted]')
def login():
 # Selectors/submit ID were inspected on the actual Flutter login DOM.
 call(['auth','save','fr14-physical-customer','--url','http://127.0.0.1:8788','--username',a['email'],'--password-stdin',
  '--username-selector','input[type=text]','--password-selector','input[type=password]','--submit-selector','#flt-semantic-node-16'],a['password']+'\n')
 # Flutter requires real keyboard events; DOM-only fill does not update its form.
 for kind,value in [('text',a['email']),('password',a['password'])]:
  call(['click','input[type='+kind+']']);call(['press','Control+a']);call(['keyboard','type',value])
 call(['click','#flt-semantic-node-16'])
 print('Protected TEST customer browser login submitted; verify actual UI')
if __name__=='__main__':
 if sys.argv[1]=='login':login()
 elif sys.argv[1]=='snapshot':print(call(['snapshot','-i']))
 else:raise ValueError('Unsupported browser action')
