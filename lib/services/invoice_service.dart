import 'package:supabase_flutter/supabase_flutter.dart';

Uri validateInvoiceUrl(Map<String, dynamic> result, String base) {
  final uri = Uri.tryParse(result['url']?.toString() ?? '');
  final expected = Uri.parse(base);
  if (result['code'] != 'READY' ||
      result['expires_in'] != 900 ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.origin != expected.origin ||
      !uri.path.startsWith('/storage/v1/object/sign/invoices/') ||
      !uri.queryParameters.containsKey('token')) {
    throw const FormatException('Invoice access was not confirmed. Retry.');
  }
  return uri;
}

class InvoiceService {
  Future<Uri> signedUrl(int orderId) async {
    try {
      final response = await Supabase.instance.client.functions
          .invoke('fr32-invoice-url', body: {'order_id': orderId})
          .timeout(const Duration(seconds: 30));
      return validateInvoiceUrl(
        Map<String, dynamic>.from(response.data as Map),
        const String.fromEnvironment(
          'SUPABASE_URL',
          defaultValue: 'https://igeisilhtmglgnqvllrx.supabase.co',
        ),
      );
    } on FunctionException catch (error) {
      if (error.status == 409) {
        throw const FormatException(
          'No paid invoice is available yet. Uncollected COD orders have no paid invoice.',
        );
      }
      throw const FormatException('Invoice access was not confirmed. Retry.');
    }
  }
}
