import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

typedef ProductImageCall = Future<dynamic> Function(Map<String, dynamic> body);
bool isProductImage(String value) => RegExp(
  r'^tezproduct:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);

Future<dynamic> callProductImage(Map<String, dynamic> body) async =>
    (await Supabase.instance.client.functions
            .invoke('final2-product-image', body: body)
            .timeout(const Duration(seconds: 50)))
        .data;

class ProductImageData {
  const ProductImageData(this.bytes, this.expiresIn);
  final Uint8List bytes;
  final int expiresIn;
}

class ProductImageService {
  ProductImageService({ProductImageCall? call, String? Function()? identity})
    : call = call ?? callProductImage,
      identity =
          identity ?? (() => Supabase.instance.client.auth.currentUser?.id);
  final ProductImageCall call;
  final String? Function() identity;
  Map<String, dynamic>? _pending;
  String? _owner, _saved;
  bool busy = false;
  bool get hasPendingUpload => _pending != null && _saved == null;
  Future<String> upload(Uint8List bytes) async {
    if (busy) throw StateError('An image upload is already in progress.');
    final owner = identity();
    if (owner == null || (_owner != null && owner != _owner)) {
      throw StateError('Account changed. Open the product again.');
    }
    if (bytes.isEmpty || bytes.length > 5242880) {
      throw StateError('Select a JPEG or PNG image up to 5 MB.');
    }
    final mime = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
        ? 'image/png'
        : bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216
        ? 'image/jpeg'
        : null;
    if (mime == null) throw StateError('Select a JPEG or PNG image.');
    final encoded = base64Encode(bytes);
    if (_saved != null && _pending!['image_base64'] != encoded) {
      _saved = null;
      _pending = null;
    }
    if (_pending != null && _pending!['image_base64'] != encoded) {
      throw StateError('Retry the original image before selecting another.');
    }
    _owner = owner;
    _pending ??= {
      'action': 'upload',
      'request_id': blockRequestId(),
      'image_base64': encoded,
      'mime_type': mime,
    };
    if (_saved != null) return _saved!;
    busy = true;
    try {
      final result = await call(Map<String, dynamic>.from(_pending!));
      if (identity() != owner) {
        throw StateError('Account changed. Open the product again.');
      }
      if (result is! Map ||
          result['reference'] is! String ||
          !isProductImage(result['reference'])) {
        throw const FormatException('Image upload was not confirmed. Retry.');
      }
      _saved = result['reference'];
      return _saved!;
    } on FunctionException catch (error) {
      if ([400, 413, 415, 422].contains(error.status)) _pending = null;
      throw StateError(
        error.details is Map && error.details['error'] is String
            ? error.details['error']
            : 'Image upload was not confirmed. Retry the same image.',
      );
    } finally {
      busy = false;
    }
  }

  Future<ProductImageData> read(String reference) async {
    if (!isProductImage(reference)) {
      throw const FormatException('Invalid image reference.');
    }
    final owner = identity();
    if (owner == null) throw StateError('Sign in to view product images.');
    final value = await call({
      'action': 'view',
      'image_id': reference.substring(11),
    });
    if (identity() != owner) throw StateError('Account changed.');
    if (value is! Map ||
        value['image_base64'] is! String ||
        !['image/jpeg', 'image/png'].contains(value['mime_type']) ||
        value['expires_in'] is! int ||
        value['expires_in'] < 1 ||
        value['expires_in'] > 900 ||
        (value['image_base64'] as String).length > 6990508) {
      throw const FormatException('Image could not be verified.');
    }
    final bytes = base64Decode(value['image_base64']);
    if (bytes.isEmpty || bytes.length > 5242880) {
      throw const FormatException('Invalid image.');
    }
    return ProductImageData(bytes, value['expires_in']);
  }
}
