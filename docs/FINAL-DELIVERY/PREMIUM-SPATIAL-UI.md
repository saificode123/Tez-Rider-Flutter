# TezRider premium spatial frontend delivery

2026-11-04, Asia/Karachi. Baseline `9e51e9d9fca4f1e63cfbf94742fd33c1eaca9485`. Branch `feature/premium-spatial-ui-redesign`. Source commit `2c7e303ba8663d100a1ecb352415bfbae2d12037`. This branch is not merged into main.

## Scope and design

Presentation updated in all 48 existing screen files. Customer home, authentication, product detail, both carts, checkout, profile/order views, the role dashboards and operational forms share coral accents, warm backgrounds, rounded surfaces, readable typography and inset navigation. Primary text-bearing coral is darker than decorative coral to retain contrast. Existing data, controls, labels and destinations are retained.

The two supplied references informed the coral/cream composition, rounded image treatment, clear price hierarchy, grouped forms and floating navigation. TezRider branding is retained. No other application's logo or proprietary illustrations were copied. Existing catalogue image sources remain in use; no restaurants, ratings, discounts or products were added to the app for decoration.

Poppins and Noto Naskh Arabic are bundled in the already-declared asset directory with their SIL Open Font License notices. Sources: [Poppins](https://github.com/google/fonts/tree/main/ofl/poppins), [Noto Naskh Arabic](https://github.com/google/fonts/tree/main/ofl/notonaskharabic). Existing GoogleFonts handles asset discovery. No new package or pubspec change. The app's existing light-mode selection remains unchanged; shared dark tokens/fallback typography are maintained without adding a theme-switch feature.

## Reusable presentation components

New `SpatialSurface`, `SpatialSectionHeading`, `SpatialStatusBadge`, `SpatialBottomBar`, `SpatialPageHeader` and `SpatialHeadline`; centralized `AppTypography` Arabic-script fallback. Existing navigation, action/stat/product/recommendation cards, empty/loading states, timeline, invoice/payment presentation, Rider panels and map surfaces are refined without replacing their callbacks. Gift controls remain available in the scrolling cart body; totals and checkout actions grow/wrap at large text sizes.

## Visual evidence

[Open the before-and-after gallery](../evidence/premium-spatial-ui/index.html). The same offline rendering harness is used against the preserved baseline and redesigned source. It uses a mocked localhost Supabase transport and explicitly labelled fixture data. The screenshots demonstrate presentation, not a live delivery or backend acceptance. Material icons and bundled fonts are explicitly loaded because Flutter's widget runner disables automatic asset-font loading. Emoji and product images can appear as placeholders in this renderer.

Twelve major views: login, registration, Customer home, product detail, populated cart, checkout, orders, notifications, Rider, Vendor, Admin and broadcast form. Other screen files received theme/style/source review, not exhaustive screenshots or physical-device acceptance. Baseline Rider profile produced Material/ink assertions; its original screenshot is retained and the redesigned profile uses the proper Material surface. The initial populated-cart harness lacked a path-provider stub; that test harness issue was corrected, not hidden in app code.

## Functional boundary and verification

No changes to controllers, services, main startup, routes, Supabase code/migrations/policies/functions, Firebase/native configuration, dependencies, environment files, API contracts or FR acceptance criteria. No hosted production/TEST data was read or modified during this redesign. No real order, email, push, broadcast, payment, delivery, Online or location-sharing operation was triggered.

Existing functional tests retain their assertions. The legacy Rider timeline's hardcoded old text-color expectation is updated to `AppColors.textPrimary`; milestone/state assertions are unchanged. New tests cover spatial component contrast and 320px/200% text/RTL callbacks, plus offline rendering of major real screen widgets. Tests simulate backend responses and cannot replace physical E2E acceptance.

Completed checks:

- Preserved baseline regression: **763 PASS, 2 SKIP**.
- Final Flutter regression: **778 PASS, 2 SKIP, 0 FAIL**.
- `flutter analyze --no-pub lib test`: **PASS**, covering application source and tests.
- Small phone 320×568 at 200% text: **7 PASS**.
- Urdu RTL 390×844 at 130% text: **12 PASS**.
- Tablet 800×1100: **12 PASS**.
- Android TEST debug build: **PASS**; signature verified. Flutter engine ABI **arm64-v8a**. Other plugin ABIs in the archive do not make this a universal Flutter APK.

The two pre-existing skipped tests are opt-in hosted Rider tests requiring credentials, not weakened or newly skipped tests. Navigation/tab-state, authentication/verification, checkout recovery, inventory, OTP/proof, invoices, broadcasts, disputes, account access, optional modules and localization assertions remain covered by the existing mocked regression. This is not a hosted E2E claim.

APK: `.fr21-local/premium-ui/artifacts/tezrider-premium-fr21test-arm64-debug.apk`. Package `com.example.flutter_application_1.fr21test`, min SDK 24, target SDK 36; local debug certificate, not a store release.

SHA-256: `9690EB1B43DDCF63B32136798B7429C129AA58847DE1E86E8D8C2AE77C51312B`. Size: 106223752 bytes. Bundled Poppins, Noto Naskh Arabic and Material Icons were confirmed in the actual APK.

Final verification details are recorded in [the verification JSON](../evidence/PREMIUM-SPATIAL-UI-verification.json). Original regression, final regression, analysis, responsive and RTL logs are retained locally under `.fr21-local/premium-ui/`. Initial tool/compiler failures and intermediate lint/color failures are retained there; only completed final results qualify as passes. The independent visual review passed the inspected fixture composition; cross-provider review was unavailable. Its two remaining text issues were corrected and rerendered afterward.

Android physical installation/startup and device screenshots: **NOT RUN**, no connected device reported by adb. No success is claimed for physical GPS, push, camera, biometric hardware or live multi-role journeys. Existing functional acceptance gaps recorded in the portability audit remain separate from this visual delivery.

All screen files received presentation updates; individual physical/live validation of all 48 screens remains unexecuted. There is no separate invoice editor in the existing frontend: invoice actions and payment panels were refined, while generated invoice PDFs stay unchanged under the backend boundary. Emoji and live product imagery are the remaining fixture-rendering limitations. The shared contrast checks are bounded tests, not a full per-screen accessibility certification. Existing Gradle/Kotlin future-support warnings are retained in the build log; no build-tool changes were made.

## Files and classification

All mixed screens below are classification A: only presentation sections changed; request/state/lifecycle methods are preserved. Shared widgets/theme are classification B. The additional test files and this evidence are verification artifacts. Configuration/dependency/backend classes C/D/E were not edited.

### Screen files

- `lib/screens/admin_broadcasts_screen.dart`
- `lib/screens/admin_dashboard.dart`
- `lib/screens/admin_disputes_screen.dart`
- `lib/screens/admin_monitor_screen.dart`
- `lib/screens/admin_orders_screen.dart`
- `lib/screens/admin_users_screen.dart`
- `lib/screens/ai_assistant_screen.dart`
- `lib/screens/chat_rooms_screen.dart`
- `lib/screens/chat_screen.dart`
- `lib/screens/cnic_document_screen.dart`
- `lib/screens/customer/about_tezrider_screen.dart`
- `lib/screens/customer/cart_screen.dart`
- `lib/screens/customer/cart_screen_new.dart`
- `lib/screens/customer/change_delivery_destination_screen.dart`
- `lib/screens/customer/dispute_screen.dart`
- `lib/screens/customer/enhanced_checkout_screen.dart`
- `lib/screens/customer/help_center_screen.dart`
- `lib/screens/customer/notifications_screen.dart`
- `lib/screens/customer/order_detail_screen.dart`
- `lib/screens/customer/order_history_screen.dart`
- `lib/screens/customer/payment_methods_screen.dart`
- `lib/screens/customer/profile_screen.dart`
- `lib/screens/customer/rating_screen.dart`
- `lib/screens/customer/saved_addresses_screen.dart`
- `lib/screens/customer/saved_stores_screen.dart`
- `lib/screens/customer/tailoring_screen.dart`
- `lib/screens/customer_dashboard.dart`
- `lib/screens/email_verification_screen.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/map_screen.dart`
- `lib/screens/order_picked_screen.dart`
- `lib/screens/password_change_screen.dart`
- `lib/screens/payment_screen.dart`
- `lib/screens/pending_verification_screen.dart`
- `lib/screens/product_detail_screen.dart`
- `lib/screens/product_screen.dart`
- `lib/screens/qr_pickup_screen.dart`
- `lib/screens/rating_summary_screen.dart`
- `lib/screens/rider_dashboard.dart`
- `lib/screens/search_screen.dart`
- `lib/screens/signup_screen.dart`
- `lib/screens/splash_screen.dart`
- `lib/screens/vendor/prescription_review_screen.dart`
- `lib/screens/vendor/product_form_screen.dart`
- `lib/screens/vendor/store_settings_screen.dart`
- `lib/screens/vendor/vendor_analytics_screen.dart`
- `lib/screens/vendor/vendor_products_screen.dart`
- `lib/screens/vendor_dashboard.dart`

### Shared widgets

- `lib/widgets/app_drawer.dart`
- `lib/widgets/app_navigation.dart`
- `lib/widgets/app_stat_card.dart`
- `lib/widgets/delivery_map_view.dart`
- `lib/widgets/delivery_photo_panel.dart`
- `lib/widgets/empty_state.dart`
- `lib/widgets/invoice_button.dart`
- `lib/widgets/order_payment_panel.dart`
- `lib/widgets/order_timeline.dart`
- `lib/widgets/product_card_summary.dart`
- `lib/widgets/rate_order_sheet.dart`
- `lib/widgets/recommendation_card.dart`
- `lib/widgets/rider_availability_control.dart`
- `lib/widgets/rider_earnings_panel.dart`
- `lib/widgets/rider_identity_card.dart`
- `lib/widgets/rider_performance_panel.dart`
- `lib/widgets/shimmer_cards.dart`
- `lib/widgets/spatial_surface.dart`
- `lib/widgets/stock_indicator.dart`

Theme: `lib/theme/app_theme.dart`. Fonts/licenses: `assets/images/Poppins-*.ttf`, `Poppins-OFL.txt`, `NotoNaskhArabic-Regular.ttf`, `NotoNaskhArabic-OFL.txt`.

Tests: `test/premium_spatial_components_test.dart`, `test/premium_spatial_visual_test.dart`, `test/private_photo_flow_test.dart`.

## Git and review

Implementation commits: `076f7aa` (design system/fonts), `09c0f83` (Customer/account presentation), `ac50b24` (Rider/Vendor/Admin presentation), `163104b` (bright coral and large-text layouts), `2c7e303` (Urdu greeting and Rider heading). The later verification/handover commit adds tests/evidence only. No force-push and no merge into main.

Run using the existing .env and setup instructions. The VS Code launch shortcut continues to work. Review the branch and gallery before approving any future main merge.
