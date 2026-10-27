import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/language_controller.dart';

/// Uses the same persistent device preference as every role's settings.
class AppLanguageSelector extends StatelessWidget {
  const AppLanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final language = Get.isRegistered<LanguageController>()
        ? LanguageController.to
        : Get.put(LanguageController(), permanent: true);
    return Obx(
      () => SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'en', label: Text('English')),
          ButtonSegment(value: 'ur', label: Text('اردو')),
        ],
        selected: {language.locale.languageCode},
        onSelectionChanged: (selection) async {
          final saved = await (selection.single == 'ur'
              ? language.setUrdu()
              : language.setEnglish());
          if (!saved && context.mounted) {
            Get.snackbar(
              'Language preference not saved'.tr,
              'Please retry the language setting.'.tr,
            );
          }
        },
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(72, 48)),
          visualDensity: VisualDensity.standard,
        ),
      ),
    );
  }
}
