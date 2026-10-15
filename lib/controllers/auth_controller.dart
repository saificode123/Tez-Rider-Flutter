import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rider_controller.dart';
import '../services/account_session_service.dart';
import '../services/android_broadcast_push_service.dart';

class AuthController extends GetxController {
  final LocalAuthentication _auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  late final AccountSessionGate accountGate;
  StreamSubscription<AuthState>? _sessionChanges;
  bool _denying = false;
  Future<bool> enforceAccountAccess() async {
    final result = await accountGate.check();
    return result == AccountDisposition.allowed ||
        result == AccountDisposition.missing;
  }

  void handleAccountFailure(String code) {
    if (code == 'FR28_ACCOUNT_BLOCKED')
      unawaited(_denyAccount(AccountDisposition.blocked));
    if (code == 'FR28_SESSION_REVOKED')
      unawaited(_denyAccount(AccountDisposition.expired));
  }

  Future<void> _denyAccount(AccountDisposition disposition) async {
    if (_denying) return;
    _denying = true;
    try {
      await logout(navigate: false);
      Get.offAllNamed(
        '/login',
        arguments: {
          'account_message': disposition == AccountDisposition.blocked
              ? blockedAccountMessage
              : 'Your session expired. Sign in again.',
        },
      );
    } finally {
      _denying = false;
    }
  }

  RxBool isBioSupported = false.obs;
  RxBool isBioEnabled = false.obs;
  RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    accountGate = AccountSessionGate(
      SupabaseAccountSessionBackend(),
      _denyAccount,
    );
    _sessionChanges = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.signedOut) {
        unawaited(accountGate.reset());
      } else if (state.session != null) {
        // Keep Auth SDK calls outside its synchronous event callback.
        unawaited(
          Future<void>(() async {
            await accountGate.check();
          }),
        );
      }
    });
    _checkBioSupport();
    _loadBioPreference();
  }

  Future<void> _checkBioSupport() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      isBioSupported.value = canCheck && isDeviceSupported;
    } catch (_) {
      isBioSupported.value = false;
    }
  }

  Future<void> _loadBioPreference() async {
    final val = await _storage.read(key: 'bio_enabled');
    isBioEnabled.value = val == 'true';
  }

  Future<void> setBioPreference(bool val) async {
    await _storage.write(key: 'bio_enabled', value: val.toString());
    isBioEnabled.value = val;
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      if (!isBioSupported.value) return false;
      return await _auth.authenticate(
        localizedReason: 'Scan your fingerprint to login to TezRider',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('Biometric error: $e');
      return false;
    }
  }

  @override
  void onClose() {
    unawaited(_sessionChanges?.cancel());
    unawaited(accountGate.dispose());
    super.onClose();
  }

  Future<void> logout({bool navigate = true}) async {
    if (Get.isRegistered<AndroidBroadcastPushService>()) {
      await Get.find<AndroidBroadcastPushService>().unregisterBeforeLogout();
    }
    await accountGate.reset();
    if (Get.isRegistered<RiderController>()) {
      await Get.find<RiderController>().goOffline();
    }
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await _storage.delete(key: 'tr_refresh');
    await _storage.delete(key: 'tr_role');
    await _storage.write(key: 'user_logged_in', value: 'false');
    if (navigate) Get.offAllNamed('/login');
  }
}
