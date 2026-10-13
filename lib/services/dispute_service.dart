import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cnic_document.dart' show cnicRequestId;

const disputeSuccess = 'Dispute submitted. Under review within 48 h.';
const disputeExpired = 'The dispute window for this order has closed.';

bool disputeOrderEligible(Map<String, dynamic> order, DateTime now) {
  final time = DateTime.tryParse(order['delivered_at']?.toString() ?? '');
  return order['order_status'] == 'delivered' &&
      time != null &&
      !time.isAfter(now) &&
      !now.isAfter(time.add(const Duration(hours: 24)));
}

String? validateDispute(
  String? reason,
  String description,
  int imageCount,
  List<String> reasons,
  int limit,
) {
  if (!reasons.contains(reason)) return 'Select a valid dispute reason.';
  final length = description.trim().runes.length;
  if (length == 0 || length > limit) {
    return 'Enter a description of 1–$limit characters.';
  }
  if (imageCount < 1 || imageCount > 3) return 'Select 1–3 evidence images.';
  return null;
}

String disputeError(Object error) {
  if (error is FormatException) return error.message;
  if (error is PostgrestException) {
    if (['22023', 'PT422', 'PT409', 'PT429'].contains(error.code)) {
      return error.message;
    }
    if (error.code == '42501') {
      return 'You are not authorized for this dispute.';
    }
  }
  return 'The operation was not confirmed. Check your connection and Retry.';
}

class DisputeImage {
  const DisputeImage(this.bytes, this.sourcePath);
  final Uint8List bytes;
  final String sourcePath;
}

class DisputeImagePicker {
  final _picker = ImagePicker();
  Future<DisputeImage?> pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      requestFullMetadata: false,
    );
    return file == null ? null : read(file.path);
  }

  Future<DisputeImage?> recover() async {
    if (!Platform.isAndroid) return null;
    final result = await _picker.retrieveLostData();
    if (result.exception != null) {
      throw const FormatException('Select the interrupted image again.');
    }
    return result.files?.isNotEmpty == true
        ? read(result.files!.first.path)
        : null;
  }

  Future<DisputeImage> read(String path) async {
    final file = File(path);
    if (await file.length() > 5242880) {
      throw const FormatException('Maximum image size is 5 MB.');
    }
    final bytes = await file.readAsBytes();
    final png =
        bytes.length >= 8 &&
        [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ].asMap().entries.every((e) => bytes[e.key] == e.value);
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!png && !jpeg) {
      throw const FormatException('Select a JPEG or PNG image.');
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 16000000) {
        throw const FormatException('Select a smaller image.');
      }
      final scale =
          (1600 /
                  (descriptor.width > descriptor.height
                      ? descriptor.width
                      : descriptor.height))
              .clamp(0.0, 1.0);
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round(),
        targetHeight: (descriptor.height * scale).round(),
      );
      image = (await codec.getNextFrame()).image;
      // Lossless compression of resized pixels strips EXIF and location metadata.
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null || encoded.lengthInBytes > 5242880) {
        throw const FormatException(
          'Maximum prepared image size is 5 MB. Select a smaller image.',
        );
      }
      return DisputeImage(encoded.buffer.asUint8List(), path);
    } catch (e) {
      if (e is FormatException) rethrow;
      throw const FormatException(
        'This file is not a valid JPEG or PNG image.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

abstract class DisputeBackend {
  String get accountId;
  Future<Map<String, dynamic>> options();
  Future<List<Map<String, dynamic>>> eligible({int? before});
  Future<List<Map<String, dynamic>>> history({int? before});
  Future<Map<String, dynamic>> detail(int id);
  Future<void> prepare(String requestId, int orderId);
  Future<String> upload(String requestId, DisputeImage image);
  Future<Map<String, dynamic>> submit(
    String requestId,
    int orderId,
    String reason,
    String description,
    List<String> paths,
  );
  Future<Map<String, dynamic>?> lookup(String requestId);
  Future<void> cleanup(String requestId);
  Future<String> signedUrl(int disputeId, int index);
}

class SupabaseDisputeBackend implements DisputeBackend {
  final _client = Supabase.instance.client;
  @override
  String get accountId => _client.auth.currentUser?.id ?? '';
  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) =>
      _client.rpc(name, params: params).timeout(const Duration(seconds: 15));
  @override
  Future<Map<String, dynamic>> options() async =>
      Map<String, dynamic>.from(await _rpc('fr25_options') as Map);
  @override
  Future<List<Map<String, dynamic>>> eligible({int? before}) async =>
      List<Map<String, dynamic>>.from(
        await _rpc('fr25_eligible_orders', {'p_before': before}) as List,
      );
  @override
  Future<List<Map<String, dynamic>>> history({int? before}) async =>
      List<Map<String, dynamic>>.from(
        await _rpc('fr25_history', {'p_before': before}) as List,
      );
  @override
  Future<Map<String, dynamic>> detail(int id) async =>
      Map<String, dynamic>.from(await _rpc('fr25_detail', {'p_id': id}) as Map);
  @override
  Future<void> prepare(String requestId, int orderId) async {
    await _rpc('fr25_prepare', {
      'p_request_id': requestId,
      'p_order_id': orderId,
    });
  }

  Future<Map<String, dynamic>> _edge(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions
          .invoke('fr25-evidence', body: body)
          .timeout(const Duration(seconds: 45));
      if (response.status != 200 || response.data is! Map) {
        throw const FormatException(
          'Evidence operation was not confirmed. Retry.',
        );
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (e) {
      if (e.status >= 500 || e.status == 0) {
        throw TimeoutException('Evidence operation was not confirmed. Retry.');
      }
      throw FormatException(
        e.details is Map && e.details['error'] is String
            ? e.details['error'] as String
            : 'Evidence operation was not confirmed. Retry.',
      );
    }
  }

  @override
  Future<String> upload(String requestId, DisputeImage image) async =>
      (await _edge({
            'action': 'upload',
            'request_id': requestId,
            'mime_type': 'image/png',
            'image_base64': base64Encode(image.bytes),
          }))['path']
          as String;
  @override
  Future<Map<String, dynamic>> submit(
    String requestId,
    int orderId,
    String reason,
    String description,
    List<String> paths,
  ) async => Map<String, dynamic>.from(
    await _rpc('create_dispute', {
          'p_request_id': requestId,
          'p_order_id': orderId,
          'p_reason': reason,
          'p_description': description,
          'p_evidence_paths': paths,
        })
        as Map,
  );
  @override
  Future<Map<String, dynamic>?> lookup(String requestId) async {
    final result = await _rpc('fr25_request_status', {
      'p_request_id': requestId,
    });
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> cleanup(String requestId) async {
    await _edge({'action': 'cleanup', 'request_id': requestId});
  }

  @override
  Future<String> signedUrl(int disputeId, int index) async {
    final result = await _edge({
      'action': 'view',
      'dispute_id': disputeId,
      'index': index,
    });
    if (result['expires_in'] != 900) {
      throw const FormatException('Invalid viewing lifetime.');
    }
    return result['url'] as String;
  }
}

abstract class DisputeDraftStore {
  Future<Map<String, dynamic>?> read(String account);
  Future<void> save(String account, Map<String, dynamic> draft);
  Future<void> clear(String account);
}

class SecureDisputeDraftStore implements DisputeDraftStore {
  final _storage = const FlutterSecureStorage();
  @override
  Future<Map<String, dynamic>?> read(String account) async {
    final value = await _storage.read(key: 'fr25-draft-$account');
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  @override
  Future<void> save(String account, Map<String, dynamic> draft) =>
      _storage.write(key: 'fr25-draft-$account', value: jsonEncode(draft));
  @override
  Future<void> clear(String account) =>
      _storage.delete(key: 'fr25-draft-$account');
}

String newDisputeRequestId() => cnicRequestId();
