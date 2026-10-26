import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

/// Optional account-bound sign-in shortcut. Normal session restore is separate.
class BiometricSettingsTile extends StatefulWidget {
  const BiometricSettingsTile({super.key});

  @override
  State<BiometricSettingsTile> createState() => _BiometricSettingsTileState();
}

class _BiometricSettingsTileState extends State<BiometricSettingsTile> {
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    if (!Get.isRegistered<AuthController>()) return const SizedBox.shrink();
    final auth = Get.find<AuthController>();
    return Obx(
      () => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: Text('Biometric sign-in'.tr),
            subtitle: Text(
              (auth.isBioSupported.value
                      ? 'Optional sign-in shortcut for this account. Password login remains available; this does not lock an already signed-in app.'
                      : 'Enroll biometrics in your device settings to use this shortcut.')
                  .tr,
            ),
            value: auth.isBioEnabled.value,
            onChanged: _saving || !auth.isBioSupported.value
                ? null
                : (enabled) async {
                    setState(() {
                      _saving = true;
                      _error = null;
                    });
                    try {
                      await auth.setBioPreference(enabled);
                      if (mounted && auth.isBioEnabled.value != enabled) {
                        setState(
                          () => _error =
                              'Biometric verification was not completed. Retry or use your password.',
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error =
                              'Biometric preference could not be saved. Retry.',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
          ),
          if (_saving) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
              child: Text(
                _error!.tr,
                semanticsLabel: _error!.tr,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
