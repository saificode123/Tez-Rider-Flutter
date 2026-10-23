import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/services/account_session_service.dart';
import 'package:flutter_application_1/services/session_credentials.dart';
import 'package:flutter_application_1/widgets/role_access_gate.dart';
import 'support/closure_harness.dart';

class ReviewStatusBackend implements AccountSessionBackend {
  String approval = 'approved';
  int subscriptions = 0, unsubscriptions = 0;
  @override
  String? get accountId => unitSession().user.id;
  @override
  Future<Map<String, dynamic>> status() async => state;
  Map<String, dynamic> get state => {
    'code': 'OK',
    'id': 1,
    'role': 'vendor',
    'verification_status': approval,
    'is_blocked': false,
  };
  @override
  Future<void> subscribe(int profile, void Function() changed) async {
    subscriptions++;
  }

  @override
  Future<void> unsubscribe() async {
    unsubscriptions++;
  }
}

class ReviewAuth extends AuthController {
  ReviewAuth(this.backend)
    : super(sessionCredentials: SessionCredentials(fence: MemoryFence()));
  final ReviewStatusBackend backend;
  @override
  // Uses the real gate without native sensor listeners.
  // ignore: must_call_super
  void onInit() {
    accountGate = AccountSessionGate(backend, (_) async {});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  tearDown(Get.reset);
  testWidgets(
    'live review status hides and restores the vendor dashboard using the existing account watcher',
    (tester) async {
      Get.testMode = true;
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(unitSession().toJson()),
      );
      final backend = ReviewStatusBackend();
      final auth = Get.put<AuthController>(ReviewAuth(backend));
      transport.respond = (_) async => UiTransport.jsonResponse(backend.state);
      await auth.accountGate.check();
      await tester.pumpWidget(
        GetMaterialApp(
          home: RoleAccessGate(
            role: 'vendor',
            builder: (_) =>
                const Scaffold(body: Text('CONFIRMED VENDOR DASHBOARD')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CONFIRMED VENDOR DASHBOARD'), findsOneWidget);
      backend.approval = 'rejected';
      await auth.accountGate.check();
      await tester.pumpAndSettle();
      expect(find.text('CONFIRMED VENDOR DASHBOARD'), findsNothing);
      expect(
        find.text('Account access could not be confirmed for this screen.'),
        findsOneWidget,
      );
      backend.approval = 'approved';
      await auth.accountGate.check();
      await tester.pumpAndSettle();
      expect(find.text('CONFIRMED VENDOR DASHBOARD'), findsOneWidget);
      expect(
        backend.subscriptions,
        1,
        reason:
            'Role gate reuses the account watcher rather than adding a channel',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
