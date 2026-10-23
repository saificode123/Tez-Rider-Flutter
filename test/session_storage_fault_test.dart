import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/rider_controller.dart';
import 'package:flutter_application_1/services/session_credentials.dart';
import 'support/closure_harness.dart';

class FailingRider extends RiderController {
  @override
  // No native presence subscriptions in the fault harness.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onClose() {}
  @override
  Future<void> goOffline() async =>
      throw StateError('injected cleanup failure');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  late VaultDouble vault;
  late MemoryFence fence;
  late SessionCredentials credentials;
  setUp(() {
    Get.testMode = true;
    vault = VaultDouble()..install();
    fence = MemoryFence();
    credentials = SessionCredentials(fence: fence);
    transport.respond = null;
  });
  tearDown(Get.reset);

  test(
    'a corrupted logout fence denies restoration until a confirmed password session replaces it',
    () async {
      fence.value = 'corrupted-state';
      expect(await credentials.restorationAllowed(), isFalse);
      expect(await credentials.read(), isNull);
      await credentials.remember(unitSession(), 'customer');
      expect(await credentials.restorationAllowed(), isTrue);
    },
  );
  test(
    'confirmed credentials are account bound and a successful password session clears the logout fence',
    () async {
      await credentials.remember(unitSession(), 'customer');
      expect(
        (await credentials.read(
          currentAccount: unitSession().user.id,
        ))?.refreshToken,
        unitSession().refreshToken,
      );
      expect(await credentials.read(currentAccount: 'other-account'), isNull);
      expect(fence.value, isNull);
    },
  );
  test(
    'one failed deletion does not skip other keys and a new process denies leftover credentials',
    () async {
      await credentials.remember(unitSession(), 'customer');
      vault.failures.add('delete:tr_refresh');
      await credentials.invalidate();
      expect(vault.data['tr_refresh'], isNotNull);
      expect(vault.data['tr_role'], isNull);
      expect(vault.data['tr_account'], isNull);
      expect(vault.data['user_logged_in'], 'false');
      expect(await SessionCredentials(fence: fence).read(), isNull);
      expect(
        await SessionCredentials(fence: fence).restorationAllowed(),
        isFalse,
      );
    },
  );
  test('partial credential write never enables remembered sign-in', () async {
    vault.failures.add('write:tr_role');
    await expectLater(
      credentials.remember(unitSession(), 'customer'),
      throwsStateError,
    );
    expect(await credentials.read(), isNull);
    expect(fence.value, 'pending');
    expect(vault.data['tr_refresh'], isNull);
  });
  test(
    'unreadable secure storage fails closed without an unhandled plugin error',
    () async {
      await credentials.remember(unitSession(), 'customer');
      vault.failures.add('read:tr_refresh');
      expect(await credentials.read(), isNull);
      expect(fence.value, 'pending');
    },
  );
  test(
    'corrupt stored refresh data cannot authenticate or cross an account boundary',
    () async {
      await credentials.remember(unitSession(), 'customer');
      vault.data['tr_refresh'] = 'invalid\nprivate-value';
      expect(await credentials.read(), isNull);
    },
  );
  test('legacy unbound stored credentials require password login', () async {
    vault.data.addAll({
      'user_logged_in': 'true',
      'tr_refresh': 'legacy-unit-refresh',
      'tr_role': 'admin',
    });
    expect(await credentials.read(), isNull);
  });
  test(
    'unavailable logout fence denies restoration and recovers only after a successful new credential write',
    () async {
      fence.fail = true;
      expect(await credentials.restorationAllowed(), isFalse);
      fence.fail = false;
      await credentials.remember(unitSession(), 'customer');
      expect(await credentials.restorationAllowed(), isTrue);
    },
  );
  test('account switch overwrites all credential identity fields', () async {
    await credentials.remember(unitSession(), 'admin');
    final next = unitSession('00000000-0000-0000-0000-000000000002');
    await credentials.remember(next, 'vendor');
    expect(
      await credentials.read(currentAccount: unitSession().user.id),
      isNull,
    );
    expect(
      (await credentials.read(currentAccount: next.user.id))?.refreshToken,
      next.refreshToken,
    );
    expect(vault.data['tr_role'], 'vendor');
  });
  test(
    'logout clears the SDK session despite presence, remote request and secure-key deletion failures',
    () async {
      final client = Supabase.instance.client;
      await client.auth.recoverSession(jsonEncode(unitSession().toJson()));
      expect(client.auth.currentSession, isNotNull);
      await credentials.remember(unitSession(), 'rider');
      vault.failures.add('delete:tr_refresh');
      transport.respond = UiTransport.offline;
      Get.put<RiderController>(FailingRider());
      final controller = Get.put(QuietAuth(credentials: credentials));
      await controller.logout(navigate: false);
      expect(client.auth.currentSession, isNull);
      expect(
        await SessionCredentials(fence: fence).restorationAllowed(),
        isFalse,
      );
      expect(vault.calls, contains('delete:tr_role'));
    },
  );
}
