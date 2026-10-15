# Native push decision — FR-30

Status: approval required; no Firebase dependencies, registration tables, credentials,
notification permissions, sender infrastructure, or platform build changes introduced.

SRDS §2.3.8 (PDF p9) explicitly includes multi-channel push for admin broadcasts.
FR30 itself (p16), UC08 step4 (p22) and composer interface (p28) also require admin
notifications. In-app database/Realtime delivery satisfies that workflow, but does
not satisfy delivery through the operating-system notification service. Full FR30
acceptance therefore remains pending native push approval and verification.
The rendered use-case diagram (PDF p18, printed p17) explicitly links Admin to
Manage Notifications; it adds no channel detail. FR44/SEC07 require audit, SEC01 RLS;
S01 explicitly covers destructive confirmations; broadcast confirmation is also an
explicit requirement of this task. No SRDS requirement has been silently waived.

Inspection found legacy `android/app/google-services.json`, but no firebase_messaging,
flutter_local_notifications, registration storage/rotation, server push sender, or
POST_NOTIFICATIONS permission. Legacy config does not prove a functioning push path.

## Concrete Android TEST proposal (not implemented)

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
No paid account, enrollment, Firebase project or external infrastructure was created.

Official sources checked 2026-10-15. Approval must identify Android TEST Firebase
scope and separately resolve the iOS APNs/zero-cost dependency.
