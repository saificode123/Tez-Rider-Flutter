import 'package:get/get.dart';
import '../services/admin_broadcast_service.dart';
import '../services/admin_users_service.dart' show blockRequestId;

class AdminBroadcastController extends GetxController {
  AdminBroadcastController({AdminBroadcastBackend? backend})
    : backend = backend ?? SupabaseAdminBroadcastBackend();
  final AdminBroadcastBackend backend;
  final audience = 'ALL'.obs;
  final estimate = RxnInt();
  final estimating = false.obs,
      sending = false.obs,
      loading = false.obs,
      hasMore = false.obs;
  final history = <Map<String, dynamic>>[].obs;
  final estimateError = RxnString(),
      historyError = RxnString(),
      feedback = RxnString();
  final uncertain = false.obs;
  Map<String, dynamic>? _pending;
  int _estimateVersion = 0;
  bool _closed = false;
  bool _historyDirty = false;

  Future<void> refreshEstimate([String? selected]) async {
    if (selected != null) audience.value = selected;
    final version = ++_estimateVersion;
    estimate.value = null;
    estimating.value = true;
    estimateError.value = null;
    try {
      final count = await backend.estimate(audience.value);
      if (!_closed && version == _estimateVersion) estimate.value = count;
    } catch (_) {
      if (!_closed && version == _estimateVersion) {
        estimateError.value = 'Recipient estimate unavailable. Retry.';
      }
    } finally {
      if (!_closed && version == _estimateVersion) estimating.value = false;
    }
  }

  Future<void> loadHistory({bool append = false}) async {
    if (_closed) return;
    if (loading.value) {
      if (!append) _historyDirty = true;
      return;
    }
    loading.value = true;
    historyError.value = null;
    try {
      final rows = await backend.history(
        append && history.isNotEmpty ? history.last : null,
      );
      if (_closed) return;
      if (append) {
        final ids = history.map((row) => row['id']).toSet();
        history.addAll(rows.where((row) => !ids.contains(row['id'])));
      } else {
        history.assignAll(rows);
      }
      hasMore.value = rows.length == 25;
    } catch (_) {
      if (!_closed) {
        historyError.value = 'Broadcast history unavailable. Retry.';
      }
    } finally {
      if (!_closed) loading.value = false;
      if (!_closed && _historyDirty) {
        _historyDirty = false;
        await loadHistory();
      }
    }
  }

  Future<bool> send(String title, String message) async {
    if (sending.value || _closed) return false;
    if (_pending == null &&
        (title.trim().isEmpty ||
            title.trim().runes.length > 100 ||
            message.trim().isEmpty ||
            message.trim().runes.length > 1000 ||
            !broadcastAudiences.containsKey(audience.value))) {
      feedback.value = broadcastResultMessage({'code': 'INVALID_INPUT'});
      return false;
    }
    sending.value = true;
    _pending ??= {
      'p_request_id': blockRequestId(),
      'p_title': title.trim(),
      'p_message': message.trim(),
      'p_audience': audience.value,
    };
    try {
      final result = await backend.send(Map.from(_pending!));
      if (_closed) return false;
      feedback.value = broadcastResultMessage(result);
      final success =
          result['code'] == 'SENT' || result['code'] == 'ALREADY_SENT';
      uncertain.value =
          !success &&
          !{
            'FORBIDDEN',
            'INVALID_INPUT',
            'COOLDOWN',
            'DAILY_LIMIT',
            'IDEMPOTENCY_CONFLICT',
          }.contains(result['code']);
      if (!uncertain.value) _pending = null;
      if (success) await loadHistory();
      return success;
    } catch (_) {
      if (!_closed) {
        uncertain.value = true;
        feedback.value = broadcastResultMessage({'code': 'RETRYABLE_ERROR'});
      }
      return false;
    } finally {
      if (!_closed) sending.value = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _estimateVersion++;
    super.onClose();
  }
}
