# TezRider FR-21 Android testing

Use **TezRider TEST** only. The separate package is `com.example.flutter_application_1.fr21test`; it can coexist with the existing application. This guide does not certify unrelated payment, prescription, chat or document-upload workflows.

1. On your Android phone, open Settings → About phone and tap Build number seven times. In Developer options enable USB debugging. Connect a data-capable USB cable and accept the computer's RSA prompt. **Expected:** Android Studio's device selector shows your phone.
2. Install `build/fr21-apk/TezRider-FR21-Test-debug.apk` by copying it to the phone and opening it, allowing installation for that file app when Android asks. Alternatively run the install command below in Android Studio's terminal. **Expected:** a separate **TezRider TEST** icon; after launch an orange TEST banner. Do not use an older APK.
3. Open `%LOCALAPPDATA%\TezRider-FR21\device-accounts.txt` privately on this computer. Sign in with the `rider` account. **Expected:** rider dashboard loads without schema/permission errors, and its initial status is Offline. Keep passwords private; these are synthetic TEST accounts.
4. Switch Online, tap repeatedly, wait at least 55 seconds, close normally and reopen. **Expected:** requests are single-flight, no conflicting success message, and state agrees with the server. Backgrounding/normal close may intentionally persist Offline; a fresh foreground restart restores the latest stored status. Logout/relogin should restore Offline.
5. Turn off Wi-Fi/mobile data and change availability. **Expected:** loading ends, an actionable error/Retry appears, and the toggle reconciles rather than pretending success. Reconnect and Retry. **Expected:** availability and requests recover.
6. While the rider is Online, force-stop TezRider TEST in Android settings and wait over 121 seconds. Sign in as `vendor` and press **Mark Ready & Call Rider** for the seeded order (latest order IDs are in `build/fr21-hosted-evidence/integration.json`). **Expected:** no expired rider assignment; the order stays Ready. Signing back into the rider account should restore Offline after expiry.
7. Put the approved rider Online again. Use a second phone/session for the vendor, or sign out/in on the same phone and then restore the rider session; retry **Mark Ready & Call Rider**. **Expected:** one eligible rider is reserved, order changes to On the way, and the rider sees the delivery. Repeated requests must not create another assignment. Because logout sets Offline, simultaneous testing is easier with two devices/sessions.
8. Sign in as `customer` to see the seeded order and its delivery OTP; return to the assigned rider and use **Enter OTP**. Try an incorrect value, then the correct value. **Expected:** incorrect OTP fails; correct OTP completes once, vendor history changes to Delivered and the rider becomes available. Synthetic order/product records are real TEST rows.
9. Sign in as `pending-rider`. **Expected:** the app blocks normal rider access or the server refuses Online/assignment. Customer/vendor accounts must not be able to alter another rider's availability.
10. Disconnect/reconnect the network while viewing a dashboard, then logout. **Expected:** a reconnect/error state followed by fresh data, no duplicate subscriptions/actions, and best-effort Offline. Record unexpected behavior with role, time and steps; do not include passwords or tokens.

## Android Studio run configuration

Open this existing Flutter project; do not create a replacement project. Open Run → Edit Configurations, select the Flutter `lib/main.dart` configuration, and put the following in **Additional run args**, then choose your phone and Run:

```text
--flavor fr21test --dart-define-from-file=build/fr21-public-defines.json
```

The private local public-defines file already exists. Running without it fails closed because no client key is embedded in source. Never substitute production keys or a service-role key.

To install the prepared APK from the terminal (no build required):

```powershell
& "$env:LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" devices
& "$env:LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" install -r 'build/fr21-apk/TezRider-FR21-Test-debug.apk'
```

No physical phone was connected during automated preparation, so installation, GPS permissions, lifecycle behavior and visible dashboard updates on your phone remain manual checks. With a single phone, switching accounts logs the rider out and marks them Offline; do not interpret that as an assignment defect. Synthetic fixture coordinates are test values; actual device GPS may change nearest-rider selection.

Verified APK minimum: **Android 7.0 / API 24**. Final APK SHA256: `40be279d8a767bd644765a3c8f7cd1a2417534d171df10e097ba07b3e5cfe2b7`. Package, TEST backend/key and absence of privileged credentials were checked after the successful final build.
