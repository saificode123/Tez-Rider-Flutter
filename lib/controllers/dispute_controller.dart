import 'dart:async';
import 'package:get/get.dart';
import '../services/dispute_service.dart';

class DisputeController extends GetxController {
  DisputeController({
    DisputeBackend? backend,
    DisputeDraftStore? store,
    DisputeImagePicker? picker,
  }) : backend = backend ?? SupabaseDisputeBackend(),
       store = store ?? SecureDisputeDraftStore(),
       picker = picker ?? DisputeImagePicker() {
    account = this.backend.accountId;
  }
  final DisputeBackend backend;
  final DisputeDraftStore store;
  final DisputeImagePicker picker;
  final busy = false.obs, loading = false.obs, uncertain = false.obs;
  final error = ''.obs, message = ''.obs;
  final reasons = <String>[].obs, orders = <Map<String, dynamic>>[].obs;
  final images = <DisputeImage>[].obs, paths = <String>[].obs;
  final completedImages = 0.obs;
  int descriptionLimit = 2000;
  int? orderId;
  String? reason, requestId;
  String description = '';
  bool _closed = false;
  late final String account;
  bool get editable => !busy.value && !uncertain.value && requestId == null;
  bool get _active =>
      !_closed && account.isNotEmpty && backend.accountId == account;
  Future<void> initialize({int? selectedOrder}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = '';
    try {
      final options = await backend.options();
      reasons.assignAll(List<String>.from(options['reasons'] as List));
      descriptionLimit = options['description_limit'] as int;
      orders.assignAll(await backend.eligible());
      final draft = await store.read(account);
      if (!_active) return;
      if (draft != null) {
        requestId = draft['request_id'] as String?;
        orderId = draft['order_id'] as int?;
        reason = draft['reason'] as String?;
        description = draft['description'] as String? ?? '';
        paths.assignAll(List<String>.from(draft['paths'] as List? ?? []));
        uncertain.value = draft['uncertain'] == true;
        if (requestId != null && await backend.lookup(requestId!) != null) {
          await store.clear(account);
          message.value = disputeSuccess;
          requestId = null;
          paths.clear();
          orderId = null;
          reason = null;
          description = '';
          uncertain.value = false;
        } else {
          final sources = List<String>.from(
            draft['source_paths'] as List? ?? [],
          );
          images.clear();
          // Once every selected image is confirmed uploaded, retry no longer
          // depends on Android retaining the image picker's temporary files.
          if (paths.length < sources.length) {
            for (final path in sources) {
              images.add(await picker.read(path));
            }
          }
        }
      } else {
        orderId = selectedOrder;
      }
      final lost = await picker.recover();
      if (lost != null && images.length < 3 && editable) images.add(lost);
    } catch (e) {
      if (_active) error.value = disputeError(e);
    } finally {
      if (!_closed) loading.value = false;
    }
  }

  Future<void> moreOrders() async {
    if (loading.value || orders.isEmpty) return;
    loading.value = true;
    try {
      orders.addAll(await backend.eligible(before: orders.last['id'] as int));
    } catch (e) {
      error.value = disputeError(e);
    } finally {
      if (!_closed) loading.value = false;
    }
  }

  Future<void> saveDraft() async {
    if (!_active) return;
    await store.save(account, {
      'request_id': requestId,
      'order_id': orderId,
      'reason': reason,
      'description': description,
      'paths': paths.toList(),
      'source_paths': images.map((e) => e.sourcePath).toList(),
      'uncertain': uncertain.value,
    });
  }

  Future<void> submit() async {
    if (busy.value || !_active) return;
    final validation = validateDispute(
      reason,
      description,
      images.length > paths.length ? images.length : paths.length,
      reasons,
      descriptionLimit,
    );
    if (orderId == null) {
      error.value = 'Select a delivered order.';
      return;
    }
    if (validation != null) {
      error.value = validation;
      return;
    }
    busy.value = true;
    error.value = '';
    message.value = '';
    try {
      requestId ??= newDisputeRequestId();
      await saveDraft();
      // Always reconcile first, including after a lost response. Never clean up an unknown result.
      final existing = await backend.lookup(requestId!);
      if (existing == null) {
        if (uncertain.value) uncertain.value = false;
        await backend.prepare(requestId!, orderId!);
        completedImages.value = paths.length;
        for (int i = paths.length; i < images.length; i++) {
          if (!_active) {
            throw const FormatException('Session changed. Sign in to resume.');
          }
          paths.add(await _retry(() => backend.upload(requestId!, images[i])));
          completedImages.value = paths.length;
          await saveDraft();
        }
        uncertain.value = true;
        await saveDraft();
        await _retry(
          () => backend.submit(
            requestId!,
            orderId!,
            reason!,
            description.trim(),
            paths.toList(),
          ),
        );
      }
      if (!_active) return;
      await store.clear(account);
      message.value = disputeSuccess;
      uncertain.value = false;
      requestId = null;
      paths.clear();
      images.clear();
    } catch (e) {
      if (!_active) return;
      if (uncertain.value) {
        try {
          if (await backend.lookup(requestId!) != null) {
            await store.clear(account);
            message.value = disputeSuccess;
            uncertain.value = false;
            requestId = null;
            paths.clear();
            images.clear();
            return;
          }
          uncertain.value = false;
        } catch (_) {
          error.value =
              'Submission confirmation is unavailable. Retry the same submission.';
          await saveDraft();
          return;
        }
      }
      error.value = disputeError(e);
      // Known terminal rejection: abandon atomically before removing unreferenced evidence.
      if (e is FormatException && e.message == disputeExpired ||
          error.value == disputeExpired ||
          error.value.contains('already has an open dispute')) {
        try {
          await backend.cleanup(requestId!);
          requestId = null;
          paths.clear();
        } catch (_) {
          error.value += ' Cleanup is pending; retry or discard this draft.';
        }
      }
      await saveDraft();
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  Future<T> _retry<T>(Future<T> Function() operation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt >= 2 ||
            (e is! TimeoutException &&
                disputeError(e) !=
                    'The operation was not confirmed. Check your connection and Retry.')) {
          rethrow;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 400 * (1 << attempt)),
        );
        if (!_active) {
          throw const FormatException('Session changed. Sign in to resume.');
        }
      }
    }
  }

  Future<void> discard() async {
    if (busy.value || !_active) return;
    busy.value = true;
    try {
      if (requestId != null) {
        if (await backend.lookup(requestId!) == null) {
          await backend.cleanup(requestId!);
        } else {
          message.value = disputeSuccess;
        }
      }
      await store.clear(account);
      requestId = null;
      paths.clear();
      images.clear();
      uncertain.value = false;
      error.value = '';
    } catch (e) {
      error.value = disputeError(e);
    } finally {
      if (!_closed) busy.value = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    super.onClose();
  }
}
