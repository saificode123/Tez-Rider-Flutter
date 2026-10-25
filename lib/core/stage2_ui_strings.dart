import 'package:get/get.dart';

/// Substitute display values once: user data must never become another token.
extension Stage2UiStrings on String {
  String uiTr(Map<String, String> values) => tr.replaceAllMapped(
    RegExp(r'@slot\d+end'),
    (match) => values[match[0]!.substring(1)] ?? match[0]!,
  );
}
