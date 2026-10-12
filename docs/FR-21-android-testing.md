# TezRider FR-21 Android testing

Use **TezRider TEST** only. The separate package is `com.example.flutter_application_1.fr21test`; it can coexist with the existing application. This guide does not certify unrelated payment, prescription, chat or document-upload workflows.

1. On your Android phone, open Settings → About phone and tap Build number seven times. In Developer options enable USB debugging. Connect a data-capable USB cable and accept the computer's RSA prompt. **Expected:** Android Studio's device selector shows your phone.
2. Install `.fr21-local/TezRider-FR21-Test-debug.apk` by copying it to the phone and opening it, allowing installation for that file app when Android asks. Alternatively run the install command below in Android Studio's terminal. **Expected:** a separate **TezRider TEST** icon; after launch an orange TEST banner. Do not use an older APK.
3. Open `%LOCALAPPDATA%\TezRider-FR21\device-accounts.txt` privately on this computer. Sign in with the `approved-rider` account. **Expected:** rider dashboard loads without schema/permission errors, and its initial status is Offline. Keep passwords private; these are synthetic TEST accounts.
4. Switch Online, tap repeatedly, wait at least 55 seconds, close normally and reopen. **Expected:** requests are single-flight, no conflicting success message, and state agrees with the server. Backgrounding/normal close may intentionally persist Offline; a fresh foreground restart restores the latest stored status. Logout/relogin should restore Offline.
5. Turn off Wi-Fi/mobile data and change availability. **Expected:** loading ends, an actionable error/Retry appears, and the toggle reconciles rather than pretending success. Reconnect and Retry. **Expected:** availability and requests recover.
6. While the rider is Online, force-stop TezRider TEST in Android settings and wait over 121 seconds. Sign in as `vendor` and press **Mark Ready & Call Rider** for the seeded order (latest order IDs are in `build/fr21-hosted-evidence/integration.json`). **Expected:** no expired rider assignment; the order stays Ready. Signing back into the rider account should restore Offline after expiry.
7. Put the approved rider Online again. Keep the rider app foreground and use a second phone/session for the vendor (or ask the assistant to perform the synthetic TEST vendor action); retry **Mark Ready & Call Rider**. **Expected:** one eligible rider is reserved, order changes to On the way, and the rider sees the delivery. Repeated requests must not create another assignment. Switching accounts or backgrounding the rider on the same phone can set Offline, so it cannot prove simultaneous online assignment.
8. Sign in as `customer` to see the seeded order and its delivery OTP; return to the assigned rider and use **Enter OTP**. Try an incorrect value, then the correct value. **Expected:** incorrect OTP fails; correct OTP completes once, vendor history changes to Delivered and the rider becomes available. Synthetic order/product records are real TEST rows.
9. Sign in as `pending-rider`. **Expected:** the app blocks normal rider access or the server refuses Online/assignment. Customer/vendor accounts must not be able to alter another rider's availability.
10. Disconnect/reconnect the network while viewing a dashboard, then logout. **Expected:** a reconnect/error state followed by fresh data, no duplicate subscriptions/actions, and best-effort Offline. Record unexpected behavior with role, time and steps; do not include passwords or tokens.

## Android Studio run configuration

Open this existing Flutter project; do not create a replacement project. Open Run → Edit Configurations, select the Flutter `lib/main.dart` configuration, and put the following in **Additional run args**, then choose your phone and Run:

```text
--flavor fr21test --dart-define-from-file=.fr21-local/public-defines.json
```

The private local public-defines file already exists. Running without it fails closed because no client key is embedded in source. Never substitute production keys or a service-role key.

To install the prepared APK from the terminal (no build required):

```powershell
& "$env:LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" devices
& "$env:LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" install -r '.fr21-local/TezRider-FR21-Test-debug.apk'
```

During the initial preparation no phone was connected. Installation and rider login have since been verified; GPS permissions, presence lifecycle behavior and visible presence updates remain manual checks. With a single phone, switching accounts logs the rider out and marks them Offline; do not interpret that as an assignment defect. Synthetic fixture coordinates are test values; actual device GPS may change nearest-rider selection.

Verified APK minimum: **Android 7.0 / API 24**. Final APK SHA256: `34feaaeff5fac97e146682a94f076daf487fd5ca4e52b789a3c3ffeea2d1d332`. Package, TEST backend/key and absence of privileged credentials were checked after the successful final build.

## Connected-phone verification — 2026-10-12

The connected phone now has the exact verified TEST APK: the final artifact passed backend and credential checks, and installation succeeded. Password sign-in and the approved Rider Dashboard have now been verified on this physical phone. Full manual presence/assignment/lifecycle checks remain to be completed. Account headings in the private file are approved-rider, second-rider, pending-rider, customer, vendor, admin and other-vendor.

For a genuine crash-expiry check, keep the rider foreground while it is Online and have the assistant force-stop the TEST package over USB, then observe the server without reopening the app. Entering Android Settings first may cause a normal background Offline write; that proves lifecycle handling but cannot independently prove heartbeat expiry. If the server already reports Offline immediately after stopping, mark the crash-expiry scenario inconclusive and use the automated expiry evidence or repeat a controlled test. Do not switch accounts on the rider phone to perform the vendor check.

## Login and verification correction — 2026-10-12

The synthetic approved-rider password is synchronized with the value supplied by the user and verified against TEST. No password is recorded here; private account files remain under LOCALAPPDATA/TezRider-FR21. The user’s personal password and account approval were not changed. The reported personal account’s email was already confirmed even though its old link redirected to localhost. Email verification is separate from rider/vendor admin approval.

TEST Auth now uses the exact native callback `tezrider-fr21-test://login-callback/` for Site URL and its redirect allowlist. Email confirmation remains enabled. The TEST-only Android manifest registers this callback and lets the existing Supabase/app_links integration handle it. A real signed synthetic callback reached the installed app and produced a valid approved-rider TEST session. No website or paid service was added. Older emails may retain their original localhost redirect; the already-confirmed account can sign in without clicking that consumed link again.

New-profile recovery inserts an own pending profile with the server-confirmed email, instead of using an upsert that needs forbidden updates to email/role. Duplicate creation is handled by re-reading the existing own profile. RLS and approval guards were retained; no new SQL migration was required. Hosted Auth regression confirms protected upserts are denied, own-profile insertion works and a pending rider cannot go Online.

Repeat the narrow hosted regression with `./tests/integration/FR-21-run.ps1 -Kind auth`. The final arm64 debug APK is 101,303,203 bytes; it was installed with app data preserved. ZIP integrity, TEST backend/key and absence of production references, service-role keys and fixture passwords were checked. Flutter suite: 18 passed, 2 conditional hosted tests skipped; login analysis has one info diagnostic from the pre-existing user error-display edit, no errors. That edit was preserved.

## Final acceptance

All mandatory FR-21 device checks are now verified. See [FR-21-acceptance.md](FR-21-acceptance.md) for the final table and durable sanitized evidence. Earlier pending statements above are historical. The installed TEST APK matches the latest application source and the hash above. The phone is left Offline; original Wi-Fi/mobile data are restored. Reusable isolated probes: ./tests/integration/FR-21-run.ps1 -Kind device -DeviceAction reject, crashbegin, or crashend. Start rejected-write testing from a synchronized Offline approved synthetic rider dashboard; crashbegin requires fresh Online presence, crashend must follow the real two-minute wait.
