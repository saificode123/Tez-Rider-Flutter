# Native push decision — FR-30

Status: Android TEST FCM explicitly approved by the user on 2026-10-15.
Real client/server configuration verified for project `tez-rider-fe12b` (display
name `tez-rider`) and package `com.example.flutter_application_1.fr21test`.
Server-only secrets configured in isolated Supabase TEST; dispatch enabled after
readiness checks. Foreground/background/normal-terminated OS delivery passed on
the authorized phone. Final APK/security reruns are recorded in acceptance/progress.
iOS/APNs remains a separate unresolved platform dependency.

SRDS §2.3.8 (PDF p9) explicitly includes multi-channel push for admin broadcasts.
FR30 itself (p16), UC08 step4 (p22) and composer interface (p28) also require admin
notifications. In-app database/Realtime delivery satisfies that workflow, but does
not satisfy delivery through the operating-system notification service. Android FR30
acceptance therefore includes separate OS delivery evidence, now recorded below.
The rendered use-case diagram (PDF p18, printed p17) explicitly links Admin to
Manage Notifications; it adds no channel detail. FR44/SEC07 require audit, SEC01 RLS;
S01 explicitly covers destructive confirmations; broadcast confirmation is also an
explicit requirement of this task. No SRDS requirement has been silently waived.

Initial inspection found legacy `android/app/google-services.json`, but no firebase_messaging,
flutter_local_notifications, registration storage/rotation, server push sender, or
POST_NOTIFICATIONS permission. Legacy config does not prove a functioning push path.

## Approved Android TEST implementation scope

1. Register/verify Firebase Android app `com.example.flutter_application_1.fr21test`
   in a user-approved Firebase project. Keep configuration scoped to TEST flavor.
2. Add current compatible Flutter Firebase messaging integration and Android permission
   handling after approval. Use the supported registration/installation identity
   lifecycle; current docs are transitioning from legacy registration tokens to FIDs.
3. Register installations only through authenticated owner-scoped server operations;
   keep tokens private, handle rotation/logout/revocation/blocking and stale registrations.
4. Add a durable server-only dispatch/outbox path bound to the existing immutable
   broadcast recipient snapshot. Keep Firebase server credentials in server secrets.
   Recheck blocked access, use bounded retries/deduplication and distinguish provider
   acceptance from actual device receipt. Do not add Firebase paid Cloud Functions.
5. Verify authorized physical Android foreground/background/terminated delivery,
   permission denial, expiry/retry, targeting, logout and blocked-user exclusions.

FCM is listed as **no-cost** by [Firebase pricing](https://firebase.google.com/pricing).
It requires both a trusted sender and a configured platform client:
[FCM architecture](https://firebase.google.com/docs/cloud-messaging) and
[Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).
Do not assume an existing file makes a TEST app registered correctly. Android setup
requires compatible Google Play services. Supported registration lifecycle:
[registration management](https://firebase.google.com/docs/cloud-messaging/manage-tokens).
Delivery is subject to expiry, device/network state and throttling; provider acceptance
is not guaranteed receipt: [lifespan](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan)
and [quotas](https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas).

## iOS zero-cost dependency

Firebase's [Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
requires APNs authentication and iOS push capabilities. Apple's program lists push
notifications as a membership benefit and normally costs USD99/year:
[membership details](https://developer.apple.com/programs/whats-included/).
An existing eligible membership/fee waiver must be verified; this project cannot
assume iOS native push is zero-cost. Proposed free interim behavior is existing
in-app notifications on iOS, subject to explicit approval of that SRDS limitation.
No paid account, enrollment or Firebase project was created by the agent. The approved
sender uses the existing Supabase TEST Edge/cron infrastructure.

Official sources checked 2026-10-15. Android TEST Firebase approval/configuration is
recorded; iOS APNs/zero-cost availability remains separate.

## Approved preparation and remaining configuration

Android TEST scope was explicitly approved. Compatible resolved packages are
`firebase_core 5.0.0`, `firebase_messaging 17.0.0`, and
`flutter_local_notifications 19.5.0`. Runtime activation requires TEST flavor,
exact TEST Supabase endpoint and `FR30_ANDROID_PUSH=true`; default is off.
Only a real Firebase client entry for `com.example.flutter_application_1.fr21test`
may be placed at `android/app/src/fr21test/google-services.json`. Existing original
application configuration is preserved. No iOS/APNs capabilities were added.

Current registration uses FID `register`/`onRegistered` and HTTP v1 `message.fid`;
legacy token methods are not mixed. See [FCM Flutter registration](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
and [HTTP v1 message fields](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages).
The server sends only kind/broadcast UUID, with Android TEST package restriction.
The app resolves private text through a scoped encrypted device capability tied
to its existing unread snapshot, live Auth session and one-hour job expiry.
Logout erases that credential; blocking/revocation/rebinding prevent old lookups.

The worker is deployed to TEST and fails closed without server configuration.
Migration006 defaulted to `android_push_enabled=false`; the operator enabled it
only after real configuration and server readiness passed. Its durable outbox,
bounded leases/retries and free Supabase cron worker are tested using synthetic
rollback data. Firebase service-account JSON must be stored only in Edge secret
`FR30_FIREBASE_SERVICE_ACCOUNT`; matching worker key belongs only in Edge secret
`FR30_PUSH_WORKER_KEY` and Vault entry `fr30_android_push_worker`.
No credential is committed or embedded in Flutter. The user supplied external
paths to the real TEST client JSON and dedicated sender service-account JSON;
private-key contents never entered chat or command output. The TEST client file
is ignored by the flavor's own `.gitignore`; the server key remains external.
Real Google OAuth authorization and deployed worker readiness passed before
activation. The verified client config and opt-in define are included only in the
ignored configured TEST build. Physical checks distinguish OS receipt from
in-app visibility. Cold-start taps retain the existing customer sign-in flow and
open the intended notification after authentication; no broader session-restoration
behavior was changed.
Provider acceptance remains distinct from device receipt; retries may repeat hints,
so display uses a stable broadcast tag and bounded local deduplication cache.
