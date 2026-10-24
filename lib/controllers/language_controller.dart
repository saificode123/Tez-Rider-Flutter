import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

bool _languageAppReady() {
  try {
    return Get.context != null;
  } catch (_) {
    return false;
  }
}

Future<void> _applyLanguageLocale(Locale locale) async {
  Get.locale = locale;
  // Rebuild the GetMaterialApp root while retaining the current navigator and
  // role state. Full engine reassembly is unnecessary for a locale change.
  if (_languageAppReady()) Get.rootController.update();
}

abstract interface class LanguagePreferenceStore {
  Future<String?> read();
  Future<void> write(String language);
}

class SecureLanguagePreferenceStore implements LanguagePreferenceStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'tr_language';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String language) =>
      _storage.write(key: _key, value: language);
}

class LanguageController extends GetxController {
  LanguageController({
    LanguagePreferenceStore? store,
    Future<void> Function(Locale)? applyLocale,
    bool Function()? appReady,
  }) : _store = store ?? SecureLanguagePreferenceStore(),
       _apply = applyLocale ?? _applyLanguageLocale,
       _appReady = appReady ?? _languageAppReady;
  static LanguageController get to => Get.find();
  final LanguagePreferenceStore _store;
  final Future<void> Function(Locale) _apply;
  final bool Function() _appReady;
  final _locale = const Locale('en', 'US').obs;
  final persistenceError = RxnString();
  Future<void>? _restoring;
  Future<void> _writes = Future.value();
  int _revision = 0;
  Locale get locale => _locale.value;
  bool get isUrdu => locale.languageCode == 'ur';
  String get languageLabel => isUrdu ? 'اردو' : 'English';
  String get languageFlag => isUrdu ? '🇵🇰' : '🇬🇧';
  @override
  void onInit() {
    super.onInit();
    unawaited(restore());
  }

  // A bounded startup read cannot override a more recent user selection.
  Future<void> restore() => _restoring ??= _restore();
  Future<void> _restore() async {
    final revision = _revision;
    try {
      final saved = await _store.read().timeout(const Duration(seconds: 3));
      if (revision != _revision) return;
      _locale.value = saved == 'ur'
          ? const Locale('ur', 'PK')
          : const Locale('en', 'US');
      if (_appReady()) await _apply(locale);
    } catch (_) {
      if (revision == _revision) {
        persistenceError.value = 'Language preference could not be restored.';
      }
    }
  }

  Future<bool> _change(Locale next) async {
    final revision = ++_revision;
    final previous = locale;
    _locale.value = next;
    final applied = Future<void>.sync(() => _apply(next)).then(
      (_) => true,
      onError: (Object error, StackTrace stack) {
        if (revision == _revision) {
          _locale.value = previous;
          persistenceError.value = 'Language could not be changed.';
        }
        return false;
      },
    );
    var saved = false;
    // Reserve the write order before awaiting locale application. An earlier
    // slow update cannot persist after a later choice.
    _writes = _writes.then((_) async {
      if (!await applied) return;
      try {
        await _store.write(next.languageCode);
        saved = true;
        if (revision == _revision) persistenceError.value = null;
      } catch (_) {
        if (revision == _revision) {
          persistenceError.value = 'Language preference could not be saved.';
        }
      }
    });
    await _writes;
    return saved;
  }

  Future<bool> setEnglish() => _change(const Locale('en', 'US'));
  Future<bool> setUrdu() => _change(const Locale('ur', 'PK'));
  Future<bool> toggle() => isUrdu ? setEnglish() : setUrdu();
}
