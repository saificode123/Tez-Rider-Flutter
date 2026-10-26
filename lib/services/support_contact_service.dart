import 'package:supabase_flutter/supabase_flutter.dart';

class SupportContactService {
  SupportContactService({Future<dynamic> Function()? read})
    : _read = read ?? _invoke;
  final Future<dynamic> Function() _read;
  static Future<dynamic> _invoke() async {
    final response = await Supabase.instance.client.functions
        .invoke('support-contact', method: HttpMethod.get)
        .timeout(const Duration(seconds: 10));
    if (response.status != 200) throw StateError('Support contact unavailable');
    return response.data;
  }

  Future<String> load() async {
    final result = await _read();
    final email = result is Map ? result['email'] : null;
    if (result is! Map ||
        result['code'] != 'OK' ||
        email is! String ||
        email.length > 254 ||
        !RegExp(
          r'^[^@\s\x00-\x1f\x7f]+@[^@\s\x00-\x1f\x7f]+\.[^@\s\x00-\x1f\x7f]+$',
        ).hasMatch(email))
      throw const FormatException('Support contact unavailable');
    return email;
  }
}
