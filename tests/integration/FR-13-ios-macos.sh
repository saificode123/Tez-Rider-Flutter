#!/usr/bin/env bash
# Unsigned native compilation only. Signing and physical tests stay manual.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'NOT EXECUTED: macOS/Xcode required.' >&2
  exit 1
fi
for tool in flutter python3 xcodebuild xcrun ruby pod; do
  command -v "$tool" >/dev/null || { echo "Required tool unavailable: $tool" >&2; exit 1; }
done
if [[ $# -ne 1 ]]; then
  echo 'Usage: bash tests/integration/FR-13-ios-macos.sh /absolute/path/to/public-TEST-defines.json' >&2
  exit 1
fi
config="$1"
[[ "$config" = /* && -f "$config" ]] || { echo 'Existing absolute public TEST configuration path required.' >&2; exit 1; }
python3 - "$config" <<'PY'
import base64,json,sys
data=json.load(open(sys.argv[1],encoding='utf-8-sig'))
assert data['SUPABASE_URL']=='https://igeisilhtmglgnqvllrx.supabase.co'
assert data['FR21_ISOLATED_TEST']is True
key=data['SUPABASE_ANON_KEY'];assert isinstance(key,str)and key
assert not key.startswith('sb_secret_'),'Server credentials forbidden'
if key.startswith('eyJ'):
    claims=json.loads(base64.urlsafe_b64decode(key.split('.')[1]+'==='))
    assert claims.get('role')=='anon','Only the public client key is permitted'
else:
    assert key.startswith('sb_publishable_'),'Public client key required'
print('Public isolated TEST configuration validated; values suppressed.')
PY
cd "$(dirname "$0")/../.."
xcodebuild -version
flutter pub get
(cd ios && ruby -c Podfile && pod install)
flutter build ios --debug --no-codesign --dart-define-from-file="$config"
echo 'Unsigned native compilation completed. Signing and physical iPhone verification NOT EXECUTED by this script.'
