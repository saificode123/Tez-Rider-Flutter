import 'package:supabase_flutter/supabase_flutter.dart';
import 'private_photo_service.dart';

/// Uses the established account-fenced, immutable retry and private byte-view
/// contract, through the optional modules' separate trusted server boundary.
class OptionalMediaService extends PrivatePhotoService {
  OptionalMediaService({
    super.kind = 'tailoring',
    super.orderId,
    super.identity,
    PrivatePhotoCall? call,
  }) : super(call: call ?? _invoke);

  static Future<dynamic> _invoke(Map<String, dynamic> body) async =>
      (await Supabase.instance.client.functions
              .invoke('optional-private-media', body: body)
              .timeout(const Duration(seconds: 50)))
          .data;
}
