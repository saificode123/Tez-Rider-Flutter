"""Protected credential handoff to isolated browser vault; no secret output."""
import importlib.util,json,subprocess,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fr13',Path(__file__).with_name('FR-13-hosted.py'))
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
def main():
 account=h.state['accounts']['physical-customer']
 cli=['npx.cmd','--yes','agent-browser','--session','fr13-60194cb55fe7']
 profile='fr13-test-customer'
 options=['--username-selector','input[type=text]','--password-selector','input[type=password]','--submit-selector','#flt-semantic-node-16']
 result=subprocess.run(cli+['auth','save',profile,'--url','http://127.0.0.1:8787','--username',account['email'],'--password-stdin']+options,input=account['password']+'\n',capture_output=True,text=True,timeout=45)
 assert result.returncode==0,'Protected vault handoff failed; private output suppressed'
 result=subprocess.run(cli+['auth','login',profile,'--no-navigate'],capture_output=True,text=True,timeout=60)
 assert result.returncode==0,'Protected browser login failed; private output suppressed'
 # Flutter discards synthetic DOM input; use trusted browser keyboard events.
 # Arguments are generated only inside this protected process, never shell text.
 for kind,value in [('text',account['email']),('password',account['password'])]:
  for args in [['click','input[type='+kind+']'],['press','Control+a'],['keyboard','type',value]]:
   result=subprocess.run(cli+args,capture_output=True,text=True,timeout=30)
   assert result.returncode==0,'Protected observed-field input failed; private output suppressed'
 print('Protected TEST customer browser login submitted; verify actual UI')
if __name__=='__main__':main()
