import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/email_verification.dart';
import '../screens/email_verification_screen.dart';

import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'rider_controller.dart';
import 'cart_controller.dart';
import '../services/account_session_service.dart';
import '../services/android_broadcast_push_service.dart';
import '../services/session_credentials.dart';

class AuthController extends GetxController {
  AuthController({
    LocalAuthentication? localAuthentication,
    SessionCredentials? sessionCredentials,
  }) : _auth = localAuthentication ?? LocalAuthentication(),
       credentials = sessionCredentials ?? SessionCredentials();
  final SessionCredentials credentials;

  final LocalAuthentication _auth;

  late final AccountSessionGate accountGate;
  StreamSubscription<AuthState>? _sessionChanges;
  bool _denying = false;
  String? _unlockedAccount;
  int _biometricGeneration = 0;
  bool get localSessionEntered =>
      _unlockedAccount != null &&
      _unlockedAccount == Supabase.instance.client.auth.currentUser?.id;

  /// A cold opted-in session cannot enter a dashboard before local verification.
  Future<bool> sessionRestorationAllowed() async {
    if (!await credentials.restorationAllowed()) return false;
    final account = Supabase.instance.client.auth.currentUser?.id;
    if (account == null) return false;
    if (_unlockedAccount == account) return true;
    try {
      final allowed =
          !await credentials.biometricRequired(account) &&
          account == Supabase.instance.client.auth.currentUser?.id;
      if (allowed) _unlockedAccount = account;
      return allowed;
    } catch (_) {
      return false;
    }
  }

  void confirmSessionEntry(String account) {
    if (account == Supabase.instance.client.auth.currentUser?.id) {
      _unlockedAccount = account;
    }
  }

  Future<void> lockForBiometricSignIn() async {
    final account = Supabase.instance.client.auth.currentUser?.id;
    if (account == null || !await credentials.biometricRequired(account)) {
      return;
    }
    if (account != Supabase.instance.client.auth.currentUser?.id) return;
    _unlockedAccount = null;
    Get.offAllNamed('/login');
  }

  Future<bool> enforceAccountAccess({bool passwordLogin = false}) async {
    if (!passwordLogin && !await sessionRestorationAllowed()) return false;
    final result = await accountGate.check();
    return result == AccountDisposition.allowed ||
        result == AccountDisposition.missing;
  }

  void handleAccountFailure(String code) {
    if (code == 'FR28_ACCOUNT_BLOCKED') {
      unawaited(_denyAccount(AccountDisposition.blocked));
    }
    if (code == 'FR28_SESSION_REVOKED') {
      unawaited(_denyAccount(AccountDisposition.expired));
    }
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
    _sessionChanges = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) {
          _unlockedAccount = null;
          _biometricGeneration++;
          unawaited(accountGate.reset());
        } else if (state.session != null) {
          // Keep Auth SDK calls outside its synchronous event callback.
          unawaited(
            Future<void>(() async {
              if (state.event == AuthChangeEvent.tokenRefreshed) {
                await credentials.synchronize(state.session!);
              }
              await accountGate.check();
              if (state.event == AuthChangeEvent.signedIn &&
                  AuthEmailLink.consume() &&
                  Get.currentRoute != '/') {
                Get.offAllNamed('/');
              }
            }),
          );
        }
      },
      onError: (Object error, StackTrace stack) {
        if (AuthEmailLink.consume()) {
          unawaited(
            Future<void>(() {
              Get.offAll(
                () => const EmailVerificationScreen(
                  notice: 'This verification link is expired or invalid. Request a new link.',
                ),
              );
            }),
          );
        }
      },
    );
  }

  @override
  void onReady() {
    super.onReady();
    // Native keystore callbacks must not compete with pre-frame bootstrap.
    unawaited(refreshBiometricState());
  }

  Future<void> refreshBiometricState() async {
    await _checkBioSupport();
    await _loadBioPreference();
  }

  Future<void> _checkBioSupport() async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      isBioSupported.value = false;
      return;
    }
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      final enrolled = await _auth.getAvailableBiometrics();
      isBioSupported.value =
          canCheck && isDeviceSupported && enrolled.isNotEmpty;
    } catch (_) {
      isBioSupported.value = false;
    }
  }

  Future<void> _loadBioPreference() async {
    try {
      final saved = await credentials.read();
      isBioEnabled.value =
          saved != null && await credentials.biometricEnabled(saved.account);
    } catch (_) {
      isBioEnabled.value = false;
    }
  }

  Future<void> setBioPreference(bool val) async {
    final account = Supabase.instance.client.auth.currentUser?.id;
    if (account == null) throw StateError(secureSessionUnavailable);
    if (val) {
      if (!await enforceAccountAccess() ||
          !await authenticateWithBiometrics()) {
        return;
      }
      if (account != Supabase.instance.client.auth.currentUser?.id) return;
    }
    await credentials.setBiometricEnabled(account, val);
    isBioEnabled.value = val;
    if (val) confirmSessionEntry(account);
  }

  Future<bool> authenticateWithBiometrics() async {
    if (isLoading.value) return false;
    isLoading.value = true;
    final generation = _biometricGeneration;
    try {
      if (!isBioSupported.value ||
          (await _auth.getAvailableBiometrics()).isEmpty) {
        return false;
      }
      final verified = await _auth.authenticate(
        localizedReason:
            'Verify your identity with biometrics to sign in to TezRider',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: false,
        ),
      );
      return verified && generation == _biometricGeneration;
    } catch (_) {
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  @override
  void onClose() {
    unawaited(_sessionChanges?.cancel());
    unawaited(accountGate.dispose());
    super.onClose();
  }

  Future<void> logout({bool navigate = true}) async {
    _unlockedAccount = null;
    _biometricGeneration++;
    if (isLoading.value) {
      try {
        await _auth.stopAuthentication().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    if (Get.isRegistered<CartController>()) {
      Get.find<CartController>().forgetSession();
    }
    final invalidation = credentials.invalidate();
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    if (Get.isRegistered<AndroidBroadcastPushService>()) {
      await attempt(
        () => Get.find<AndroidBroadcastPushService>().unregisterBeforeLogout(),
      );
    }
    await attempt(() => accountGate.reset());
    if (Get.isRegistered<RiderController>()) {
      await attempt(() => Get.find<RiderController>().goOffline());
    }
    await attempt(() => Supabase.instance.client.auth.signOut());
    await invalidation;
    isBioEnabled.value = false;
    if (navigate) Get.offAllNamed('/login');
  }
}
