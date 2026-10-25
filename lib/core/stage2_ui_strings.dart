import 'package:get/get.dart';

/// Substitute display values once: user data must never become another token.
extension Stage2UiStrings on String {
  /// Services retain English state text; only these numeric display templates
  /// are expanded when rendered, so an open screen follows the current locale.
  String get uiMessage {
    for (final entry in _numericMessages.entries) {
      final match = entry.key.firstMatch(this);
      if (match != null) {
        return entry.value.uiTr({'slot0end': match[1]!});
      }
    }
    return tr;
  }

  String uiTr(Map<String, String> values) => tr.replaceAllMapped(
    RegExp(r'@slot\d+end'),
    (match) => values[match[0]!.substring(1)] ?? match[0]!,
  );
}

final _numericMessages = <RegExp, String>{
  RegExp(r'^Incorrect OTP\. (\d+) attempts remaining\.$'):
      'Incorrect OTP. @slot0end attempts remaining.',
  RegExp(r'^Wait (\d+) seconds before requesting another code\.$'):
      'Wait @slot0end seconds before requesting another code.',
  RegExp(r'^Please wait (\d+) seconds before another broadcast\.$'):
      'Please wait @slot0end seconds before another broadcast.',
  RegExp(
    r'^Accepted for (\d+) recipients\. In-app delivery is available when they connect\.$',
  ): 'Accepted for @slot0end recipients. In-app delivery is available when they connect.',
  RegExp(r'^Approximately (\d+) min$'): 'Approximately @slot0end min',
  RegExp(r'^Arriving in (\d+) min$'): 'Arriving in @slot0end min',
};
