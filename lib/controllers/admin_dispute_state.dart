import 'dart:async';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_dispute_service.dart';

mixin AdminDisputeState on GetxController {
  AdminDisputeBackend get disputeBackend;
  RxList<Map<String, dynamic>> get disputes;
  final disputeLoading = false.obs, hasMoreDisputes = false.obs;
  final disputeError = RxnString(), disputeFilter = RxnString();
  final disputeStatuses = <String>[].obs;
  final openDisputeCount = RxnInt();
  final decisionBusy = false.obs, detailLoading = false.obs;
  final decisionError = RxnString(), decisionMessage = RxnString();
  final disputeDetail = Rxn<Map<String, dynamic>>();
  final disputeVendors = <Map<String, dynamic>>[].obs;
  final vendorsLoading = false.obs, moreDisputeVendors = false.obs;
  int noteMinimum = 5, noteMaximum = 2000;
  bool _disputeClosed = false, _queueActive = false, _dirty = false;
  int _queueRevision = 0, _detailRevision = 0;
  Timer? _refreshTimer;
  Future<void> Function()? _unsubscribe;
  int? _attemptId;
  String? _attemptDecision, _attemptNote;
  bool get decisionUncertain => _attemptId != null;
  String? get pendingDecision => _attemptDecision;
  String? get pendingNote => _attemptNote;
  int? get pendingDisputeId => _attemptId;

  Future<void> loadDisputeOptions() async {
    final account = disputeBackend.accountId;
    try {
      final data = await disputeBackend.options();
      if (_disputeClosed || account != disputeBackend.accountId) return;
      noteMinimum = data['note_min'] as int;
      noteMaximum = data['note_max'] as int;
      disputeStatuses.assignAll(List<String>.from(data['statuses'] as List));
      openDisputeCount.value = data['open_count'] as int?;
    } catch (e) {
      if (!_disputeClosed) disputeError.value = adminDisputeError(e);
    }
  }

  Future<void> openDisputeQueue() async {
    if (_disputeClosed || _queueActive) return;
    _queueActive = true;
    await loadDisputeOptions();
    if (_disputeClosed || !_queueActive || disputeStatuses.isEmpty) return;
    _unsubscribe ??= disputeBackend.subscribe(_queueChanged, () {
      if (!_disputeClosed && _queueActive) {
        disputeError.value =
            'Live updates disconnected. Tap Retry to reconnect.';
      }
    });
    await refreshDisputes();
  }

  void _queueChanged() {
    if (!_queueActive || _disputeClosed) return;
    _refreshTimer ??= Timer(const Duration(milliseconds: 350), () {
      _refreshTimer = null;
      if (disputeLoading.value) {
        _dirty = true;
      } else {
        unawaited(refreshDisputes());
      }
    });
  }

  void closeDisputeQueue() {
    _queueActive = false;
    _queueRevision++;
    _dirty = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final remove = _unsubscribe;
    _unsubscribe = null;
    if (remove != null) unawaited(remove());
  }

  Future<void> filterDisputes(String? status) async {
    if (status == disputeFilter.value) return;
    disputeFilter.value = status;
    _queueRevision++;
    disputes.clear();
    if (disputeLoading.value) {
      _dirty = true;
      return;
    }
    await refreshDisputes();
  }

  Future<void> refreshDisputes({bool append = false}) async {
    if (_disputeClosed || disputeLoading.value || !_queueActive) return;
    final revision = _queueRevision, account = disputeBackend.accountId;
    disputeLoading.value = true;
    disputeError.value = null;
    try {
      final rows = await disputeBackend.queue(
        status: disputeFilter.value,
        before: append && disputes.isNotEmpty ? disputes.last : null,
      );
      if (_disputeClosed ||
          !_queueActive ||
          revision != _queueRevision ||
          account != disputeBackend.accountId) {
        return;
      }
      if (append) {
        final ids = disputes.map((d) => d['id']).toSet();
        disputes.addAll(rows.where((r) => !ids.contains(r['id'])));
      } else {
        disputes.assignAll(rows);
      }
      hasMoreDisputes.value = rows.length == 30;
      unawaited(loadDisputeOptions());
    } catch (e) {
      if (!_disputeClosed && revision == _queueRevision) {
        disputeError.value = adminDisputeError(e);
        if (e is PostgrestException && e.code == '42501') {
          disputes.clear();
          disputeStatuses.clear();
          closeDisputeQueue();
        }
      }
    } finally {
      if (!_disputeClosed) disputeLoading.value = false;
      if (_dirty && _queueActive && !_disputeClosed) {
        _dirty = false;
        unawaited(refreshDisputes());
      }
    }
  }

  Future<void> retryDisputes() async {
    closeDisputeQueue();
    await openDisputeQueue();
  }

  Future<void> loadDisputeDetail(int id) async {
    if (_disputeClosed || detailLoading.value) return;
    final revision = ++_detailRevision, account = disputeBackend.accountId;
    detailLoading.value = true;
    decisionError.value = null;
    try {
      final data = await disputeBackend.detail(id);
      if (_disputeClosed ||
          revision != _detailRevision ||
          account != disputeBackend.accountId) {
        return;
      }
      disputeDetail.value = data;
      disputeVendors.assignAll(
        List<Map<String, dynamic>>.from(data['vendors'] as List),
      );
      moreDisputeVendors.value = disputeVendors.length == 20;
    } catch (e) {
      if (!_disputeClosed &&
          revision == _detailRevision &&
          account == disputeBackend.accountId) {
        disputeDetail.value = null;
        decisionError.value = adminDisputeError(e);
      }
    } finally {
      if (!_disputeClosed) detailLoading.value = false;
    }
  }

  Future<void> loadMoreDisputeVendors(int id) async {
    if (vendorsLoading.value || !moreDisputeVendors.value || _disputeClosed) {
      return;
    }
    vendorsLoading.value = true;
    try {
      final rows = await disputeBackend.vendors(
        id,
        before: disputeVendors.last['id'] as int,
      );
      if (_disputeClosed || disputeDetail.value?['id'] != id) return;
      disputeVendors.addAll(rows);
      moreDisputeVendors.value = rows.length == 20;
    } catch (e) {
      if (!_disputeClosed) decisionError.value = adminDisputeError(e);
    } finally {
      if (!_disputeClosed) vendorsLoading.value = false;
    }
  }

  Future<void> submitDisputeDecision(
    int id,
    String decision,
    String note,
  ) async {
    if (_disputeClosed || decisionBusy.value) return;
    if (!const ['RESOLVED', 'REJECTED'].contains(decision)) {
      decisionError.value = 'Choose Resolve or Reject.';
      return;
    }
    final error = validateAdminNote(note, noteMinimum, noteMaximum);
    if (error != null) {
      decisionError.value = error;
      return;
    }
    if (_attemptId != null &&
        (_attemptId != id ||
            _attemptDecision != decision ||
            _attemptNote != note.trim())) {
      decisionError.value =
          'Retry the unchanged decision while confirmation is unavailable.';
      return;
    }
    decisionBusy.value = true;
    decisionError.value = null;
    decisionMessage.value = null;
    final account = disputeBackend.accountId;
    final detailRevision = _detailRevision;
    _attemptId = id;
    _attemptDecision = decision;
    _attemptNote = note.trim();
    try {
      for (var attempt = 0; ; attempt++) {
        try {
          // Reconcile server state before every write/retry. A lost response
          // cannot overwrite another admin's winning decision or note.
          final current = await disputeBackend.detail(id);
          if (_disputeClosed || account != disputeBackend.accountId) return;
          Map<String, dynamic> outcome;
          if (current['decision'] != null) {
            if (current['decision'] != decision) {
              if (detailRevision == _detailRevision) {
                disputeDetail.value = current;
              }
              throw const PostgrestException(
                message: 'Another decision has already finalized this dispute.',
                code: 'PT409',
              );
            }
            outcome = current;
          } else {
            outcome = await disputeBackend.decide(id, decision, note);
          }
          if (_disputeClosed || account != disputeBackend.accountId) return;
          if (outcome['decision'] != decision ||
              outcome['admin_note'] == null ||
              (decision == 'RESOLVED' && outcome['refund_pending'] != true)) {
            throw StateError('Decision confirmation incomplete');
          }
          if (detailRevision == _detailRevision) {
            disputeDetail.value = outcome;
            decisionMessage.value = decision == 'RESOLVED'
                ? refundInitiated
                : disputeRejected;
          }
          _attemptId = null;
          _attemptDecision = null;
          _attemptNote = null;
          break;
        } catch (e) {
          if (e is PostgrestException &&
              const ['42501', 'PT404', 'PT409', 'PT422'].contains(e.code)) {
            _attemptId = null;
            _attemptDecision = null;
            _attemptNote = null;
            rethrow;
          }
          if (attempt >= 2) rethrow;
          await Future<void>.delayed(
            Duration(milliseconds: 400 * (1 << attempt)),
          );
          if (_disputeClosed || account != disputeBackend.accountId) return;
        }
      }
    } catch (e) {
      if (!_disputeClosed &&
          account == disputeBackend.accountId &&
          detailRevision == _detailRevision) {
        decisionError.value = adminDisputeError(e);
      }
    } finally {
      if (!_disputeClosed) decisionBusy.value = false;
    }
  }

  void leaveDisputeDetail() {
    _detailRevision++;
    disputeDetail.value = null;
    decisionMessage.value = null;
    decisionError.value = null;
  }

  void disposeDisputes() {
    _disputeClosed = true;
    closeDisputeQueue();
    _detailRevision++;
  }
}
