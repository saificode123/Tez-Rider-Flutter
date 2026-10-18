import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ChecklistBackend {
  String get accountId;
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> parameters,
  );
}

class SupabaseChecklistBackend implements ChecklistBackend {
  SupabaseClient get _client => Supabase.instance.client;
  @override
  String get accountId => _client.auth.currentUser?.id ?? '';
  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> parameters,
  ) async => Map<String, dynamic>.from(
    await _client
            .rpc(name, params: parameters)
            .timeout(const Duration(seconds: 12))
        as Map,
  );
}

String checklistMessage(String? code) => switch (code) {
  'FORBIDDEN' =>
    'Only the assigned approved rider can continue. Refresh your session.',
  'ASSIGNMENT_REQUIRED' => 'No active assignment. Refresh your jobs.',
  'INACTIVE_ASSIGNMENT' =>
    'This assignment is cancelled or finished. Refresh your jobs.',
  'PICKUP_REQUIRED' =>
    'Wait until every vendor is ready, then accept the pickup.',
  'INVALID_VERSION' =>
    'The checklist changed. Refresh and confirm the current items.',
  'INVALID_CONFIRMATIONS' => 'Confirm every required item before submitting.',
  'CHECKLIST_REQUIRED' =>
    'Complete and submit the pickup checklist before starting delivery.',
  _ =>
    'The server did not confirm this action. Check your connection and Retry.',
};

class _ChecklistFailure implements Exception {
  _ChecklistFailure(this.message);
  final String message;
}

class PreDeliveryChecklistFlow {
  PreDeliveryChecklistFlow(this.backend);
  final ChecklistBackend backend;
  final items = <Map<String, dynamic>>[].obs;
  final selected = <String>{}.obs;
  final busy = false.obs;
  final loaded = false.obs;
  final completed = false.obs;
  final legacy = false.obs;
  final error = RxnString();
  final assignmentId = RxnInt();
  final version = RxnInt();
  final assignmentStatus = ''.obs;
  final orderStatus = ''.obs;
  int? _order;
  String _account = '';
  int _generation = 0;
  bool _disposed = false;

  bool get canSubmit =>
      loaded.value &&
      !busy.value &&
      !completed.value &&
      assignmentId.value != null &&
      assignmentStatus.value == 'Accepted' &&
      orderStatus.value == 'ready' &&
      items.isNotEmpty &&
      items.every((item) => selected.contains(item['id']));
  bool get canStart =>
      loaded.value &&
      !busy.value &&
      completed.value &&
      assignmentStatus.value == 'Accepted' &&
      orderStatus.value == 'ready';

  void choose(String id, bool checked) {
    if (busy.value || completed.value || !items.any((i) => i['id'] == id)) {
      return;
    }
    if (checked) {
      selected.add(id);
    } else {
      selected.remove(id);
    }
  }

  Future<void> open(int? order) async {
    final account = backend.accountId;
    if (_order == order && _account == account && loaded.value) {
      await refresh();
      return;
    }
    if (_order != order || _account != account) {
      _generation++;
      _order = order;
      _account = account;
      items.clear();
      selected.clear();
      assignmentId.value = null;
      version.value = null;
      loaded.value = false;
      completed.value = false;
      legacy.value = false;
      assignmentStatus.value = '';
      orderStatus.value = '';
      error.value = null;
      busy.value = false;
    }
    if (order != null) await refresh();
  }

  Future<void> refresh() async {
    if (_disposed || _order == null || busy.value) return;
    final generation = _generation;
    busy.value = true;
    try {
      final data = await backend.call('pre_delivery_checklist', {
        'p_order_id': _order,
      });
      if (!_current(generation)) return;
      if (data['code'] != 'OK') {
        throw _ChecklistFailure(checklistMessage(data['code']));
      }
      final next = (data['items'] as List)
          .map((i) => Map<String, dynamic>.from(i as Map))
          .toList();
      if (next.isEmpty ||
          next.any((i) => i['id'] is! String || i['label'] is! String) ||
          data['version'] is! int ||
          data['completed'] is! bool) {
        throw _ChecklistFailure(checklistMessage(null));
      }
      if (assignmentId.value != data['assignment_id'] ||
          version.value != data['version']) {
        selected.clear();
      }
      items.assignAll(next);
      assignmentId.value = data['assignment_id'] as int?;
      version.value = data['version'] as int;
      assignmentStatus.value = data['assignment_status'] as String? ?? '';
      orderStatus.value = data['order_status'] as String? ?? '';
      completed.value = data['completed'] == true;
      legacy.value = data['legacy_exempt'] == true;
      loaded.value = true;
      error.value = null;
    } catch (e) {
      if (_current(generation)) {
        loaded.value = false;
        error.value = e is _ChecklistFailure
            ? e.message.toString()
            : checklistMessage(null);
      }
    } finally {
      if (_current(generation)) busy.value = false;
    }
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;
    final generation = _generation;
    busy.value = true;
    try {
      final data = await backend.call('submit_pre_delivery_checklist', {
        'p_assignment_id': assignmentId.value,
        'p_version': version.value,
        'p_confirmations': items
            .map(
              (i) => {'id': i['id'], 'confirmed': selected.contains(i['id'])},
            )
            .toList(),
      });
      if (!_current(generation)) return false;
      if (data['code'] != 'COMPLETED' ||
          data['completed'] != true ||
          data['assignment_id'] != assignmentId.value ||
          data['completed_at'] is! String) {
        throw _ChecklistFailure(checklistMessage(data['code']));
      }
      completed.value = true;
      error.value = null;
      return true;
    } catch (e) {
      if (_current(generation)) {
        error.value = e is _ChecklistFailure
            ? e.message
            : checklistMessage(null);
      }
      return false;
    } finally {
      if (_current(generation)) busy.value = false;
    }
  }

  Future<bool> start() async {
    if (!canStart) return false;
    final generation = _generation;
    busy.value = true;
    try {
      final data = await backend.call('start_checklisted_delivery', {
        'p_assignment_id': assignmentId.value,
      });
      if (!_current(generation)) return false;
      if (data['code'] != 'STARTED' || data['order_status'] != 'on_the_way') {
        throw _ChecklistFailure(checklistMessage(data['code']));
      }
      orderStatus.value = 'on_the_way';
      error.value = null;
      return true;
    } catch (e) {
      if (_current(generation)) {
        error.value = e is _ChecklistFailure
            ? e.message
            : checklistMessage(null);
      }
      return false;
    } finally {
      if (_current(generation)) busy.value = false;
    }
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && backend.accountId == _account;
  void dispose() {
    _disposed = true;
    _generation++;
  }
}
