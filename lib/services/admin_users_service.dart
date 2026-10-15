import 'dart:async';
import 'dart:math';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String blockRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String accountOperationMessage(
  Map<String, dynamic> result,
) => switch (result['code']) {
  'OK' =>
    result['is_blocked'] == true
        ? 'Account blocked. Auth access and sessions revoked.'
        : 'Account unblocked. The user can sign in again.',
  'NO_CHANGE' || 'ALREADY_APPLIED' =>
    'Request already applied. Current server status restored.',
  'AUTH_SYNC_PENDING' || 'PENDING' =>
    'Account remains blocked. Auth synchronization is not confirmed. Retry synchronization.',
  'BUSY' =>
    'Another account change is pending. Refresh and retry its synchronization.',
  'SELF_FORBIDDEN' => 'You cannot block your own account.',
  'ADMIN_PROTECTED' => 'Administrator accounts cannot be blocked.',
  'NOT_FOUND' => 'Account not found.',
  'FORBIDDEN' => 'Only an authorized administrator can manage accounts.',
  'REQUEST_CONFLICT' =>
    'The request does not match the pending account change.',
  'AUTH_IDENTITY_MISSING' =>
    'The Auth identity is missing. No account change was made.',
  _ => 'The account change was not confirmed. Retry the same request.',
};

abstract interface class AdminUsersBackend {
  Future<List<Map<String, dynamic>>> list({
    required String search,
    String? role,
    bool? blocked,
    Map<String, dynamic>? before,
  });
  Future<Map<String, dynamic>> change(int id, bool blocked, String request);
}

class SupabaseAdminUsersBackend implements AdminUsersBackend {
  SupabaseClient get client => Supabase.instance.client;
  @override
  Future<List<Map<String, dynamic>>> list({
    required String search,
    String? role,
    bool? blocked,
    Map<String, dynamic>? before,
  }) async {
    final result = await client
        .rpc(
          'fr28_user_list',
          params: {
            'p_search': search,
            'p_role': role,
            'p_blocked': blocked,
            'p_before_at': before?['created_at'],
            'p_before_id': before?['id'],
            'p_limit': 25,
          },
        )
        .timeout(const Duration(seconds: 12));
    return (result as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> change(
    int id,
    bool blocked,
    String request,
  ) async {
    try {
      final response = await client.functions
          .invoke(
            'admin-user-status',
            body: {'target_id': id, 'blocked': blocked, 'request_id': request},
          )
          .timeout(const Duration(seconds: 40));
      if (response.data is! Map) throw StateError('Unconfirmed');
      return Map<String, dynamic>.from(response.data as Map);
    } on FunctionException catch (e) {
      if (e.details is Map) {
        final details = Map<String, dynamic>.from(e.details as Map);
        if (details['code'] is String) return details;
      }
      rethrow;
    }
  }
}

mixin AdminUsersState on GetxController {
  AdminUsersBackend get usersBackend;
  final managedUsers = <Map<String, dynamic>>[].obs;
  final usersLoading = false.obs, usersMore = false.obs;
  final usersError = RxnString(), userActionMessage = RxnString();
  final userAction = RxnInt();
  final searchText = ''.obs,
      roleFilter = RxnString(),
      blockedFilter = RxnBool();
  Map<String, dynamic>? lastActionResult;
  final Map<int, ({bool blocked, String request})> _requests = {};
  Timer? _searchDebounce;
  int _usersGeneration = 0;
  bool _usersDisposed = false;
  void searchUsers(String value) {
    searchText.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(loadManagedUsers()),
    );
  }

  void filterUsers({String? role, bool? blocked}) {
    roleFilter.value = role;
    blockedFilter.value = blocked;
    unawaited(loadManagedUsers());
  }

  Future<void> loadManagedUsers({bool append = false}) async {
    if (_usersDisposed || (append && usersLoading.value)) return;
    final generation = ++_usersGeneration;
    usersLoading.value = true;
    try {
      final rows = await usersBackend.list(
        search: searchText.value.trim(),
        role: roleFilter.value,
        blocked: blockedFilter.value,
        before: append && managedUsers.isNotEmpty ? managedUsers.last : null,
      );
      if (_usersDisposed || generation != _usersGeneration) return;
      if (append) {
        final ids = managedUsers.map((u) => u['id']).toSet();
        managedUsers.addAll(rows.where((u) => !ids.contains(u['id'])));
      } else {
        managedUsers.assignAll(rows);
      }
      usersMore.value = rows.length == 25;
      usersError.value = null;
    } catch (_) {
      if (!_usersDisposed && generation == _usersGeneration) {
        usersError.value = 'Could not load accounts. Retry.';
      }
    } finally {
      if (!_usersDisposed && generation == _usersGeneration) {
        usersLoading.value = false;
      }
    }
  }

  Future<Map<String, dynamic>?> changeManagedUser(
    Map<String, dynamic> user,
    bool blocked,
  ) async {
    if (_usersDisposed ||
        userAction.value != null ||
        user['role'] == 'admin' ||
        user['id'] is! int) {
      return null;
    }
    final id = user['id'] as int;
    userAction.value = id;
    userActionMessage.value = null;
    final pending = user['operation_id'];
    final desired = user['desired_blocked'];
    var request = _requests[id];
    if (pending is String && desired is bool) {
      request = (blocked: desired, request: pending);
    } else {
      request ??= (blocked: blocked, request: blockRequestId());
    }
    // An uncertain request must reconcile before a different intention is allowed.
    _requests[id] = request;
    try {
      Map<String, dynamic>? result;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          result = await usersBackend.change(
            id,
            request.blocked,
            request.request,
          );
          break;
        } catch (_) {
          if (attempt == 1) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (_usersDisposed) return null;
        }
      }
      if (_usersDisposed) return null;
      result ??= {'code': 'OPERATION_UNCONFIRMED'};
      lastActionResult = result;
      userActionMessage.value = accountOperationMessage(result);
      if (const [
        'OK',
        'NO_CHANGE',
        'ALREADY_APPLIED',
        'NOT_FOUND',
        'SELF_FORBIDDEN',
        'ADMIN_PROTECTED',
        'FORBIDDEN',
      ].contains(result['code'])) {
        _requests.remove(id);
      }
      await loadManagedUsers();
      return result;
    } catch (_) {
      if (!_usersDisposed) {
        userActionMessage.value =
            'The account change was not confirmed. Retry the same request.';
        lastActionResult = {'code': 'OPERATION_UNCONFIRMED'};
      }
      return lastActionResult;
    } finally {
      if (!_usersDisposed) userAction.value = null;
    }
  }

  void disposeManagedUsers() {
    _usersDisposed = true;
    _usersGeneration++;
    _searchDebounce?.cancel();
    _requests.clear();
  }
}
