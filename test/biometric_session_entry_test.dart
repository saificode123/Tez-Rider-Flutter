import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/services/session_credentials.dart';

import 'support/closure_harness.dart';

class Sensor extends LocalAuthentication {
  bool fail = false;
  Completer<bool>? pending;
  @override
  Future<bool> get canCheckBiometrics async => true;
  @override
  Future<bool> isDeviceSupported() async => true;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => [
    BiometricType.fingerprint,
  ];
  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const [],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    if (fail) throw PlatformException(code: 'LockedOut');
    return pending == null ? true : pending!.future;
  }

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  late VaultDouble vault;
  late SessionCredentials credentials;
  late Sensor sensor;
  late AuthController auth;
  setUp(() async {
    vault = VaultDouble()..install();
    credentials = SessionCredentials(fence: MemoryFence());
    sensor = Sensor();
    auth = AuthController(
      localAuthentication: sensor,
      sessionCredentials: credentials,
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
    await credentials.remember(unitSession(), 'customer');
  });
  tearDown(() => Supabase.instance.client.auth.signOut());
  test('cold enrolled session cannot restore before verified entry', () async {
    await credentials.setBiometricEnabled(unitSession().user.id, true);
    expect(await auth.sessionRestorationAllowed(), isFalse);
    auth.confirmSessionEntry(unitSession().user.id);
    expect(await auth.sessionRestorationAllowed(), isTrue);
    final restarted = AuthController(
      localAuthentication: sensor,
      sessionCredentials: credentials,
    );
    expect(await restarted.sessionRestorationAllowed(), isFalse);
  });
  test('non-enrolled session retains normal restoration', () async {
    expect(await auth.sessionRestorationAllowed(), isTrue);
    expect(auth.localSessionEntered, isTrue);
    expect(await credentials.biometricEnabled(unitSession().user.id), isFalse);
  });
  test('storage read failure cannot bypass biometric entry', () async {
    await credentials.setBiometricEnabled(unitSession().user.id, true);
    vault.failures.add('read:bio_enabled');
    expect(await auth.sessionRestorationAllowed(), isFalse);
  });
  test('local entry grant cannot authorize another account', () async {
    await credentials.setBiometricEnabled(unitSession().user.id, true);
    auth.confirmSessionEntry('other');
    expect(auth.localSessionEntered, isFalse);
    expect(await auth.sessionRestorationAllowed(), isFalse);
  });
  test('sensor lockout denies and clears busy state', () async {
    auth.isBioSupported.value = true;
    sensor.fail = true;
    expect(await auth.authenticateWithBiometrics(), isFalse);
    expect(auth.isLoading.value, isFalse);
  });
  test('logout rejects a late successful biometric response', () async {
    auth.onInit();
    auth.isBioSupported.value = true;
    sensor.pending = Completer<bool>();
    final attempt = auth.authenticateWithBiometrics();
    await Future<void>.delayed(Duration.zero);
    await auth.logout(navigate: false);
    sensor.pending!.complete(true);
    expect(await attempt, isFalse);
    expect(auth.localSessionEntered, isFalse);
    expect(await credentials.read(), isNull);
    auth.onClose();
  });
}
