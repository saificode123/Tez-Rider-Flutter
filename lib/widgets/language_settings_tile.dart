import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/language_controller.dart';

/// The same device preference is available from each role's navigation/settings.
class LanguageSettingsTile extends StatelessWidget {
  const LanguageSettingsTile({super.key, this.controller});
  final LanguageController? controller;
  @override
  Widget build(BuildContext context) {
    final LanguageController language =
        controller ??
        (Get.isRegistered<LanguageController>()
            ? LanguageController.to
            : Get.put(LanguageController(), permanent: true));
    return Obx(
      () => PopupMenuButton<String>(
        tooltip: 'language'.tr,
        onSelected: (code) async {
          final saved = await (code == 'ur'
              ? language.setUrdu()
              : language.setEnglish());
          if (!saved) {
            Get.snackbar(
              'Language preference not saved'.tr,
              'Please retry the language setting.'.tr,
            );
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'en', child: Text('English')),
          PopupMenuItem(value: 'ur', child: Text('اردو')),
        ],
        child: ListTile(
          leading: const Icon(Icons.language),
          title: Text('language'.tr),
          subtitle: Text(language.languageLabel),
          trailing: const Icon(Icons.expand_more),
        ),
      ),
    );
  }
}
