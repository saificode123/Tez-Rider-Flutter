import 'dart:async';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../services/cnic_document.dart';

class CnicDocumentController extends GetxController {
  CnicDocumentController({CnicBackend? backend, CnicImageService? images})
    : backend = backend ?? SupabaseCnicBackend(),
      images = images ?? CnicImageService();
  final CnicBackend backend;
  final CnicImageService images;
  final image = Rxn<CnicImage>();
  final busy = false.obs;
  final error = RxnString();
  final application = <String, dynamic>{}.obs;
  String requestId = cnicRequestId();
  String? _requestNumber;
  bool _disposed = false;
  bool get _closed => _disposed || isClosed;

  void prepareRequest(String value) {
    final number = normalizeCnic(value);
    if (_requestNumber != null && _requestNumber != number) {
      requestId = cnicRequestId();
    }
    _requestNumber = number;
  }

  String _message(Object e) => e is FormatException
      ? e.message
      : 'Operation was not confirmed. Check your connection and retry.';

  Future<void> loadStatus() async {
    if (busy.value || _closed) return;
    busy.value = true;
    try {
      final value = await backend.status();
      if (!_closed) {
        application.assignAll(value);
        error.value = null;
      }
    } catch (e) {
      if (!_closed) error.value = _message(e);
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  Future<void> select(ImageSource source) async {
    if (busy.value || _closed) return;
    busy.value = true;
    try {
      final picked = await images.pick(source);
      if (!_closed && picked != null) {
        image.value = picked;
        requestId = cnicRequestId();
        _requestNumber = null;
        error.value = null;
      }
    } catch (e) {
      if (!_closed) error.value = _message(e);
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  Future<bool> submit(
    String value, {
    Future<void> Function(String number, String id, CnicImage image)?
    persistDraft,
  }) async {
    if (busy.value || _closed) return false;
    final selected = image.value;
    if (selected == null) {
      error.value = 'Please select your CNIC document image.';
      return false;
    }
    String number;
    try {
      number = normalizeCnic(value);
      cnicImageMime(selected.bytes);
    } catch (e) {
      error.value = _message(e);
      return false;
    }
    if (_requestNumber != null && _requestNumber != number) {
      requestId = cnicRequestId();
    }
    _requestNumber = number;
    busy.value = true;
    try {
      await persistDraft?.call(number, requestId, selected);
      // Retain the same idempotency key for all retries, including a lost response.
      for (var attempt = 0; ; attempt++) {
        try {
          await backend.upload(selected, number, requestId);
          break;
        } catch (e) {
          if (attempt == 2 || _closed || e is FormatException) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 400 * (1 << attempt)),
          );
        }
      }
      if (_closed) return false;
      final verified = await backend.status();
      if (_closed) return false;
      if (verified['submission_status'] != 'submitted' ||
          !cnicDraftWasSubmitted(verified, {'request_id': requestId})) {
        throw const FormatException(
          'Document submission was not verified. Retry.',
        );
      }
      if (!_closed) {
        application.assignAll(verified);
        error.value = null;
      }
      return true;
    } catch (e) {
      if (!_closed) error.value = _message(e);
      return false;
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  @override
  void onClose() {
    _disposed = true;
    image.value = null;
    super.onClose();
  }
}
