"""Owner-identified TEST Rider inspection; never signs in or sends mail."""
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('auth_private_backend', HERE / 'FR-04-hosted.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


def main():
    b.target()
    target = json.loads(b.crypt((b.PRIVATE / 'rider-auth-verification.dpapi').read_bytes(), True))
    assert set(target) == {'email', 'auth_id', 'profiles'}, 'Protected identity checkpoint only; no password accepted'
    status, auth = b.api('/auth/v1/admin/users/' + target['auth_id'], admin=True)
    assert status == 200 and auth['id'] == target['auth_id'] and auth['email'].lower() == target['email'].lower()
    status, profiles = b.api('/rest/v1/users?auth_user_id=eq.' + target['auth_id'] +
        '&select=id,role,verification_status,cnic_submission_status,cnic_submitted_at,cnic_image_digest,is_blocked', admin=True)
    assert status == 200 and len(profiles) == 1 and profiles[0]['id'] == 999 and profiles[0]['role'] == 'rider'
    profile = profiles[0]
    raw = (b.PRIVATE / 'auth-review/rider-acceptance.private.json').read_text(encoding='utf-8-sig')
    inspection = json.JSONDecoder().raw_decode(raw[raw.index('{'):])[0]['rows'][0]['acceptance']
    assert inspection['rider_profile_id'] == profile['id'] and inspection['email_confirmed'] == bool(auth.get('email_confirmed_at'))
    assert dt.datetime.fromisoformat(inspection['submitted_at']).timestamp() == dt.datetime.fromisoformat(profile['cnic_submitted_at']).timestamp()
    samples = {hashlib.sha256(b.image(kind)).hexdigest() for kind in ('PNG', 'JPEG')}
    known_synthetic = profile['cnic_image_digest'] in samples
    assert not known_synthetic, 'Known synthetic identity document cannot qualify'
    result = {'project': b.REF, 'utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              **inspection, 'confirmation_sent_at': auth.get('confirmation_sent_at'),
              'last_sign_in_at': auth.get('last_sign_in_at'), 'known_synthetic_document_match': known_synthetic,
              'owner_corrected_email_matches_existing_rider': True,
              'verification_resends_triggered_by_this_work': 0,
              'new_accounts_created': 0, 'password_signins_by_agent': 0,
              'password_requested_or_logged': False, 'production_modified': False,
              'scope': 'Read-only canonical Auth/profile and current-document/Admin audit evidence. Existing confirmed account needs no signup resend. No document contents, CNIC number, password, token, email address or private Storage URL published. Government identity authenticity is not inferred by the model.'}
    (b.ROOT / 'docs/evidence/AUTH-rider-state.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
