import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';

class DeviceAuth extends LocalAuthentication {
  List<BiometricType> enrolled = [];
  bool result = true;
  int prompts = 0;
  AuthenticationOptions? options;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => enrolled;
  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object?> authMessages = const [],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    prompts++;
    this.options = options;
    return result;
  }
}

void main() {
  test(
    'unsupported or unenrolled device never authorizes local unlock',
    () async {
      final device = DeviceAuth();
      final controller = AuthController(localAuthentication: device);
      expect(await controller.authenticateWithBiometrics(), isFalse);
      controller.isBioSupported.value = true;
      expect(await controller.authenticateWithBiometrics(), isFalse);
      expect(device.prompts, 0);
    },
  );
  test(
    'biometric entry requires biometrics and preserves cancellation denial',
    () async {
      final device = DeviceAuth()..enrolled = [BiometricType.fingerprint];
      final controller = AuthController(localAuthentication: device);
      controller.isBioSupported.value = true;
      expect(await controller.authenticateWithBiometrics(), isTrue);
      expect(device.options!.biometricOnly, isTrue);
      device.result = false;
      expect(await controller.authenticateWithBiometrics(), isFalse);
      // This local result never creates a Supabase session or bypasses the server gate.
      expect(device.prompts, 2);
    },
  );
}
