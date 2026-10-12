"""Load protected synthetic credentials into the Flutter test process only."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys

source = Path(__file__).with_name('FR-21-hosted.py')
spec = importlib.util.spec_from_file_location('fr21_private_fixture', source)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
env = dict(os.environ)
env.pop('FR21_TEST_KEYS_JSON', None)  # Flutter receives no privileged key.
for label, account in [('RIDER', 'approved-rider'), ('CUSTOMER', 'customer')]:
    record = fixture.state['accounts'][account]
    env[f'FR21_{label}_EMAIL'] = record['email']
    env[f'FR21_{label}_PASSWORD'] = record['password']
sdk = Path('C:/Users/urreh/Downloads/flutter')
command = [str(sdk/'bin/cache/dart-sdk/bin/dart.exe'),
           '--packages='+str(sdk/'packages/flutter_tools/.dart_tool/package_config.json'),
           str(sdk/'packages/flutter_tools/bin/flutter_tools.dart'),
           'test', 'test/fr21_hosted_test.dart', '--reporter', 'expanded']
with (fixture.ROOT/'build/fr21-hosted-evidence/flutter-hosted.log').open('w', encoding='utf-8') as log:
    result = subprocess.run(command, cwd=fixture.ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
print('Hosted Flutter test exit:', result.returncode)
sys.exit(result.returncode)
