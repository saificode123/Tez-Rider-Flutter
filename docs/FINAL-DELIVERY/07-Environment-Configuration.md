# Environment configuration

TEST project: igeisilhtmglgnqvllrx. Production: arrqsvejrfdbacfwtpcc. TEST package: com.example.flutter_application_1.fr21test. Never install a production-connected artifact without owner approval.

Mobile defines: SUPABASE_URL, SUPABASE_ANON_KEY (public anon/publishable only), FR21_ISOLATED_TEST (real boolean), optional existing FR30_ANDROID_PUSH and FR30_FIREBASE_PROJECT_ID. The build helper rejects unrecognized/private defines and mismatched environments. Use ignored .fr21-local/public-defines.json for existing TEST. tool/production-defines.example.json is a template, not a configured production credential file.

Server secrets remain in Supabase secrets/Vault: service role, gateway proof, route provider, AI provider, invoice/email transport, FCM service account and worker keys. Secret values are deliberately absent here. Agent/private DPAPI stores are not portable production configuration.

Owner supplies approved production application ID, private upload keystore and android/key.properties; sample names only in android/key.properties.example. Keystore/private properties must remain ignored. Firebase/APNs registration, email deliverability and production secrets are not qualified by TEST success.

Zero cost limits: Geoapify Free currently lists 3,000 daily credits with attribution/rate/feature constraints (https://www.geoapify.com/pricing/; https://apidocs.geoapify.com/docs/routing/). Supabase Free can pause low-activity projects after seven days (https://supabase.com/docs/guides/platform/free-project-pausing); free backups require a verified export plan (https://supabase.com/docs/guides/platform/backups). Check account quotas before delivery; no unlimited-use or 99.9% free SLA promise. Sources checked 2026-10-25.

Provider checks2026-10-26: Groq documents a free plan with model-specific limits; current listed gpt-oss-120b baseline is30requests/minute,1000/day,8000tokens/minute,200000/day (https://console.groq.com/docs/rate-limits). Actual account plan/remaining quota is not certified by one successful request; owner must retain free-plan limits. Firebase lists FCM as a no-cost product (https://firebase.google.com/pricing); no Firebase paid Cloud Functions were introduced. Apple normally lists USD99/year membership with signing/push capabilities (https://developer.apple.com/programs/whats-included/); an existing eligible membership/waiver must be verified. Free in-app iOS notifications are only a proposed interim alternative; required native-push limitation is not silently approved.
