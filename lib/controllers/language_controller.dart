import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LanguageController extends GetxController {
  static LanguageController get to => Get.find();

  static const _storage = FlutterSecureStorage();
  static const _key = 'tr_language';

  final _locale = const Locale('en', 'US').obs;
  Locale get locale => _locale.value;
  bool get isUrdu => _locale.value.languageCode == 'ur';

  String get languageLabel => isUrdu ? 'اردو' : 'English';
  String get languageFlag => isUrdu ? '🇵🇰' : '🇬🇧';

  @override
  void onInit() {
    super.onInit();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await _storage.read(key: _key);
    if (saved == 'ur') {
      _locale.value = const Locale('ur', 'PK');
      Get.updateLocale(const Locale('ur', 'PK'));
    }
  }

  void setEnglish() {
    _locale.value = const Locale('en', 'US');
    Get.updateLocale(const Locale('en', 'US'));
    _storage.write(key: _key, value: 'en');
  }

  void setUrdu() {
    _locale.value = const Locale('ur', 'PK');
    Get.updateLocale(const Locale('ur', 'PK'));
    _storage.write(key: _key, value: 'ur');
  }

  void toggle() {
    if (isUrdu) {
      setEnglish();
    } else {
      setUrdu();
    }
  }
}
