import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/controllers/admin_controller.dart';
import 'package:flutter_application_1/screens/admin_users_screen.dart';
import 'package:flutter_application_1/services/admin_users_service.dart';

class Backend implements AdminUsersBackend {
  final calls = <Map<String, dynamic>>[];
  final requests = <String>[];
  bool fail = false;
  String code = 'OK';
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<List<Map<String, dynamic>>> list({
    required String search,
    String? role,
    bool? blocked,
    Map<String, dynamic>? before,
  }) async {
    calls.add({
      'search': search,
      'role': role,
      'blocked': blocked,
      'before': before,
    });
    if (fail) throw TimeoutException('synthetic');
    return List.generate(
      before == null ? 25 : 2,
      (i) => {
        'id': before == null ? 100 - i : 75 - i,
        'created_at': '2026-10-14T00:00:00Z',
        'role': 'customer',
        'is_blocked': false,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> change(
    int id,
    bool blocked,
    String request,
  ) async {
    requests.add(request);
    if (pending != null) return pending!.future;
    return {'code': code, 'is_blocked': blocked};
  }
}

class State extends GetxController with AdminUsersState {
  State(this.usersBackend);
  @override
  final Backend usersBackend;
}

class WidgetAdmin extends AdminController {
  WidgetAdmin(Backend backend) : super(managedUsersBackend: backend);
  @override
  // Live subscriptions are intentionally disabled in this isolated widget test.
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  testWidgets(
    'confirmation Cancel does not mutate; confirmed action displays partial result',
    (tester) async {
      Get.testMode = true;
      final backend = Backend()..code = 'AUTH_SYNC_PENDING';
      final controller = Get.put<AdminController>(WidgetAdmin(backend));
      await tester.pumpWidget(const GetMaterialApp(home: AdminUsersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').first);
      await tester.pumpAndSettle();
      expect(find.text('Block this user?'), findsOneWidget);
      expect(backend.requests, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.requests, isEmpty);
      await tester.tap(find.text('Block').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      expect(backend.requests.length, 1);
      expect(
        find.textContaining('Auth synchronization is not confirmed'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      controller.onClose();
      Get.reset();
    },
  );
  test('bounded pagination, search, filters and retry', () async {
    final backend = Backend();
    final state = State(backend);
    await state.loadManagedUsers();
    expect(state.managedUsers.length, 25);
    expect(state.usersMore.value, true);
    await state.loadManagedUsers(append: true);
    expect(state.managedUsers.length, 27);
    expect(state.usersMore.value, false);
    expect(backend.calls.last['before']['id'], 76);
    state.searchText.value = 'Alice';
    state.roleFilter.value = 'rider';
    state.blockedFilter.value = true;
    backend.fail = true;
    await state.loadManagedUsers();
    expect(state.usersError.value, isNotNull);
    expect(state.usersLoading.value, false);
    backend.fail = false;
    await state.loadManagedUsers();
    expect(state.usersError.value, isNull);
    expect(backend.calls.last['search'], 'Alice');
    expect(backend.calls.last['role'], 'rider');
    expect(backend.calls.last['blocked'], true);
    state.disposeManagedUsers();
  });
  test(
    'partial result retries same UUID and prevents duplicate taps',
    () async {
      final backend = Backend()..pending = Completer();
      final state = State(backend);
      final user = {'id': 2, 'role': 'customer', 'is_blocked': false};
      final first = state.changeManagedUser(user, true);
      expect(state.userAction.value, 2);
      expect(await state.changeManagedUser(user, true), isNull);
      backend.pending!.complete({'code': 'AUTH_SYNC_PENDING'});
      await first;
      expect(state.userActionMessage.value, contains('remains blocked'));
      backend.pending = null;
      await state.changeManagedUser(user, false);
      expect(backend.requests[0], backend.requests[1]);
      await state.changeManagedUser(user, false);
      expect(backend.requests[2], isNot(backend.requests[1]));
      state.disposeManagedUsers();
    },
  );
  test(
    'admin accounts protected; no-op and failure messages truthful',
    () async {
      final state = State(Backend());
      expect(
        await state.changeManagedUser({'id': 1, 'role': 'admin'}, true),
        isNull,
      );
      expect(
        accountOperationMessage({'code': 'NO_CHANGE'}),
        contains('already applied'),
      );
      expect(
        accountOperationMessage({'code': 'OPERATION_UNCONFIRMED'}),
        contains('not confirmed'),
      );
      state.disposeManagedUsers();
    },
  );
}
