# FR-21 files changed or added

Exact repository-relative paths for this continuation. The original presence migration and unrelated requirements were preserved. User-supplied AGENTS.md and SRDS PDF remain unstaged. The original schema export is added unchanged as provenance.

- `.gitignore`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `lib/controllers/rider_controller.dart`
- `lib/controllers/vendor_controller.dart`
- `lib/main.dart`
- `lib/screens/rider_dashboard.dart`
- `lib/services/backend_config.dart`
- `supabase/tests/FR-21.sql`
- `test/backend_config_test.dart`
- `tests/load/FR-21-local.py`
- `tests/load/FR-21.js`
- `docs/FR-21-android-testing.md`
- `docs/FR-21-app-backend-inventory.csv`
- `docs/FR-21-schema-validation.md`
- `docs/FR-21-test-migration-plan.csv`
- `docs/FR-21-test-readiness.md`
- `schema-export/tezrider-schema.sql`
- `supabase/inspection/FR-21-schema-contract.sql`
- `supabase/inspection/FR-21-test-environment.sql`
- `supabase/inspection/FR-21-test-project.sql`
- `supabase/migrations/202610080001_tezrider_baseline.sql`
- `supabase/migrations/202610110001_fr21_test_security.sql`
- `supabase/migrations/202610110002_fr21_dashboard_consistency.sql`
- `supabase/migrations/202610110003_fr21_presence_http_conflict.sql`
- `supabase/migrations/202610110004_fr21_delivery_receipt.sql`
- `supabase/migrations/202610110005_fr21_ready_state.sql`
- `supabase/migrations/202610110006_fr21_visibility_guards.sql`
- `supabase/test-environment/202610080001_tezrider_baseline.sql`
- `supabase/test-environment/202610110001_fr21_test_security.sql`
- `supabase/test-environment/FR-21-reviewed-manifest.json`
- `supabase/test-environment/prepare.ps1`
- `supabase/tests/FR-21-test-security.sql`
- `test/fr21_hosted_test.dart`
- `tests/integration/FR-21-flutter-hosted.py`
- `tests/integration/FR-21-hosted.py`
- `tests/integration/FR-21-run.ps1`
- `docs/FR-21-files-changed.md`
- `.gitattributes`

## Auth/mobile follow-up

- `.gitignore`: keeps TEST artifacts/public build defines outside files removed by flutter clean.
- `lib/screens/login_screen.dart`: canonical own-profile INSERT recovery; user error-display edit preserved.
- `android/app/src/fr21test/AndroidManifest.xml`: native TEST Auth callback only.
- `tests/integration/FR-21-auth-regression.py`: real protected-upsert/own-insert/pending-rider checks.
- `tests/integration/FR-21-run.ps1`: adds protected auth regression mode.
- `docs/FR-21-android-testing.md` and `docs/FR-21-test-readiness.md`: current device/Auth/APK evidence.

Final acceptance: tests/integration/FR-21-device.py, tests/integration/FR-21-run.ps1, tests/integration/FR-21-flutter-hosted.py, test/widget_test.dart, docs/FR-21-acceptance.md, docs/FR-21-test-readiness.md, docs/FR-21-android-testing.md, docs/evidence/FR-21-* (sanitized actual device/regression/schema/migration/APK evidence). No new application-source or SQL migration change in the final acceptance run.

Exact final-acceptance paths:
- test/widget_test.dart
- tests/integration/FR-21-device.py
- tests/integration/FR-21-run.ps1
- tests/integration/FR-21-flutter-hosted.py
- docs/FR-21-acceptance.md
- docs/FR-21-test-readiness.md
- docs/FR-21-android-testing.md
- docs/FR-21-files-changed.md
- docs/evidence/FR-21-device-20261012.jsonl
- docs/evidence/FR-21-final-analysis.log
- docs/evidence/FR-21-final-apk.json
- docs/evidence/FR-21-final-backend.json
- docs/evidence/FR-21-final-flutter.log
- docs/evidence/FR-21-final-hosted-flutter.log
- docs/evidence/FR-21-final-migrations.log
- docs/evidence/FR-21-final-schema.json
- docs/evidence/FR-21-final-source.json
- docs/evidence/FR-21-force-stop-baseline.json
