import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String normalizeCnic(String value) {
  if (!RegExp(r'^([0-9]{13}|[0-9]{5}-[0-9]{7}-[0-9])$').hasMatch(value)) {
    throw const FormatException('Enter 13 digits or the standard CNIC format.');
  }
  return value.replaceAll('-', '');
}

String maskCnic(String value) {
  final number = normalizeCnic(value);
  return '${number[0]}***${number[4]}-*******-*';
}

class CnicImage {
  const CnicImage(this.bytes, this.mime, this.sourcePath);
  final Uint8List bytes;
  final String mime;
  final String sourcePath;
}

String cnicImageMime(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('The image must be no larger than 5 MB.');
  }
  const png = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length >= 33 &&
      List.generate(8, (i) => bytes[i] == png[i]).every((v) => v)) {
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(16) > 2048 || header.getUint32(20) > 2048) {
      throw const FormatException('Select a smaller image.');
    }
    return 'image/png';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'image/jpeg';
  }
  throw const FormatException('Select a JPEG or PNG image.');
}

bool cnicDraftWasSubmitted(
  Map<String, dynamic> status,
  Map<String, dynamic> draft,
) {
  final path = status['document_path'];
  if (status['document_valid'] != true || path is! String) return false;
  final segments = path.split('/');
  return segments.length == 3 && segments[1] == draft['request_id'];
}

class CnicImageService {
  CnicImageService({ImagePicker? picker}) : picker = picker ?? ImagePicker();
  final ImagePicker picker;

  Future<CnicImage?> pick(ImageSource source) async {
    final file = await picker.pickImage(
      source: source,
      // Gallery originals must pass the size check before native compression.
      imageQuality: source == ImageSource.camera ? 75 : null,
      maxWidth: source == ImageSource.camera ? 1600 : null,
      maxHeight: source == ImageSource.camera ? 1600 : null,
      requestFullMetadata: false,
    );
    return file == null ? null : read(file.path);
  }

  Future<CnicImage?> lostSelection() async {
    if (!Platform.isAndroid) return null;
    final lost = await picker.retrieveLostData();
    if (lost.exception != null) {
      throw const FormatException(
        'Image selection was interrupted. Select the image again.',
      );
    }
    return lost.files?.isNotEmpty == true ? read(lost.files!.first.path) : null;
  }

  Future<CnicImage> read(String path) async {
    final file = File(path);
    if (await file.length() > 5 * 1024 * 1024) {
      throw const FormatException('The image must be no larger than 5 MB.');
    }
    final bytes = await file.readAsBytes();
    final mime = cnicImageMime(bytes);
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      if (image.width > 2048 || image.height > 2048) {
        throw const FormatException('Select a smaller image.');
      }
      if (mime == 'image/png') {
        // Re-encode pixels to strip metadata and compress the PNG payload.
        final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
        if (encoded == null) {
          throw const FormatException('Could not prepare the image.');
        }
        final compressed = encoded.buffer.asUint8List();
        cnicImageMime(compressed);
        return CnicImage(compressed, mime, path);
      }
      // JPEG compression/resizing was performed by image_picker above.
      return CnicImage(bytes, mime, path);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException(
        'This file is not a valid JPEG or PNG image.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

abstract class CnicBackend {
  Future<Map<String, dynamic>> status();
  Future<void> upload(CnicImage image, String cnic, String requestId);
  Future<String> signedUrl({String? userId});
}

Future<T> invokeCnicWithRegionFallback<T>(
  Future<T> Function(String? region) invoke,
) async {
  // This dedicated TEST backend's database is in Tokyo. Keep the same JWT,
  // payload and upload request ID when falling back to automatic routing.
  final elapsed = Stopwatch()..start();
  Future<T> attempt(String? region, Duration limit) {
    final remaining = const Duration(seconds: 45) - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Document operation timed out.');
    }
    return invoke(region).timeout(remaining < limit ? remaining : limit);
  }

  try {
    return await attempt('ap-northeast-1', const Duration(seconds: 30));
  } on TimeoutException {
    return attempt(null, const Duration(seconds: 45));
  } on FunctionException catch (error) {
    if (error.status != 0 && error.status < 500) rethrow;
    return attempt(null, const Duration(seconds: 45));
  }
}

class SupabaseCnicBackend implements CnicBackend {
  final _client = Supabase.instance.client;
  @override
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
    await _client
            .rpc('fr04_application_status')
            .timeout(const Duration(seconds: 10))
        as Map,
  );

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await invokeCnicWithRegionFallback(
        (region) =>
            _client.functions.invoke('fr04-cnic', body: body, region: region),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (response.status != 200) {
        throw const FormatException(
          'Document operation was not confirmed. Retry.',
        );
      }
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      throw FormatException(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'Document operation was not confirmed. Retry.',
      );
    }
  }

  @override
  Future<void> upload(CnicImage image, String cnic, String requestId) async {
    final result = await _invoke({
      'action': 'upload',
      'cnic': cnic,
      'request_id': requestId,
      'mime_type': image.mime,
      'image_base64': base64Encode(image.bytes),
    });
    if (result['submission_status'] != 'submitted') {
      throw const FormatException('Document submission was not confirmed.');
    }
  }

  @override
  Future<String> signedUrl({String? userId}) async {
    final result = await _invoke({
      'action': 'view',
      if (userId != null) 'user_id': userId,
    });
    if (result['expires_in'] != 900 || result['url'] is! String) {
      throw const FormatException('Document viewing is unavailable.');
    }
    final url = result['url'] as String;
    const base = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://igeisilhtmglgnqvllrx.supabase.co',
    );
    if (!url.startsWith('$base/storage/v1/object/sign/rider-cnic/')) {
      throw const FormatException('Invalid private document response.');
    }
    return url;
  }
}

class CnicDraftStore {
  final _storage = const FlutterSecureStorage();
  String _key(String email) => 'fr04-draft-${email.toLowerCase()}';
  Future<void> save(
    String email,
    String number,
    String path,
    String requestId,
  ) => _storage.write(
    key: _key(email),
    value: jsonEncode({'cnic': number, 'path': path, 'request_id': requestId}),
  );
  Future<Map<String, dynamic>?> read(String email) async {
    final value = await _storage.read(key: _key(email));
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> clear(String email) => _storage.delete(key: _key(email));
}

String cnicRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
