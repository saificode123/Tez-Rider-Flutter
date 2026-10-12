"""Load protected synthetic credentials into the Flutter test process only."""
import importlib.util
import hashlib
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
workspace = Path(os.environ.get('FR21_FLUTTER_WORKSPACE', str(fixture.ROOT)))
if workspace.resolve() != fixture.ROOT.resolve():
    for original in list((fixture.ROOT/'lib').rglob('*.dart')) + [fixture.ROOT/'test/fr21_hosted_test.dart', fixture.ROOT/'pubspec.lock']:
        copied = workspace/original.relative_to(fixture.ROOT)
        if not copied.exists() or hashlib.sha256(original.read_bytes()).digest() != hashlib.sha256(copied.read_bytes()).digest():
            raise RuntimeError('Hosted Flutter workspace differs from current source')
command = [str(sdk/'bin/cache/dart-sdk/bin/dart.exe'),
           str(sdk/'bin/cache/flutter_tools.snapshot'),
           'test', 'test/fr21_hosted_test.dart', '--reporter', 'expanded']
with (fixture.ROOT/'build/fr21-hosted-evidence/flutter-hosted.log').open('w', encoding='utf-8') as log:
    result = subprocess.run(command, cwd=workspace, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=240)
print('Hosted Flutter test exit:', result.returncode)
sys.exit(result.returncode)
