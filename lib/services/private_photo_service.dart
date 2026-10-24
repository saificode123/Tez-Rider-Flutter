import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users_service.dart' show blockRequestId;

typedef PrivatePhotoCall = Future<dynamic> Function(Map<String, dynamic> body);
bool isPrivatePhoto(String value) => RegExp(
  r'^tezphoto:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);

Future<dynamic> callPrivatePhoto(Map<String, dynamic> body) async =>
    (await Supabase.instance.client.functions
            .invoke('final2-private-photo', body: body)
            .timeout(const Duration(seconds: 50)))
        .data;

class PrivatePhotoData {
  const PrivatePhotoData(this.bytes, this.expiresIn);
  final Uint8List bytes;
  final int expiresIn;
}

class PrivatePhotoService {
  PrivatePhotoService({
    this.kind = 'avatar',
    this.orderId,
    PrivatePhotoCall? call,
    String? Function()? identity,
  }) : call = call ?? callPrivatePhoto,
       identity =
           identity ?? (() => Supabase.instance.client.auth.currentUser?.id);
  final String kind;
  final int? orderId;
  final PrivatePhotoCall call;
  final String? Function() identity;
  Map<String, dynamic>? _pending;
  String? _owner, _saved;
  bool busy = false;
  bool get hasPendingUpload => _pending != null && _saved == null;
  Future<String> upload(Uint8List bytes) async {
    if (busy) throw StateError('An image upload is already in progress.');
    final owner = identity();
    if (owner == null || (_owner != null && owner != _owner)) {
      throw StateError('Account changed. Open this photo again.');
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
      'kind': kind,
      'order_id': orderId,
      'request_id': blockRequestId(),
      'image_base64': encoded,
      'mime_type': mime,
    };
    if (_saved != null) return _saved!;
    busy = true;
    try {
      final result = await call(Map<String, dynamic>.from(_pending!));
      if (identity() != owner) {
        throw StateError('Account changed. Open this photo again.');
      }
      if (result is! Map ||
          result['reference'] is! String ||
          !isPrivatePhoto(result['reference'])) {
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

  Future<PrivatePhotoData> read(String reference) async {
    if (!isPrivatePhoto(reference)) {
      throw const FormatException('Invalid image reference.');
    }
    final owner = identity();
    if (owner == null) throw StateError('Sign in to view private photos.');
    final value = await call({
      'action': 'view',
      'image_id': reference.substring(9),
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
    return PrivatePhotoData(bytes, value['expires_in']);
  }
}
