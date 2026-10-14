import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/admin_controller.dart';
import 'package:flutter_application_1/screens/admin_disputes_screen.dart';
import 'package:flutter_application_1/services/admin_dispute_service.dart';

class TestAdminBackend implements AdminDisputeBackend {
  @override
  String accountId = 'synthetic-admin-test';
  Map<String, dynamic> row = {
    'id': 1,
    'order_id': 2,
    'customer_id': 3,
    'status': 'Open',
    'reason': 'Other',
    'description': 'Synthetic test description',
    'created_at': '2026-10-13T10:00:00Z',
    'evidence_count': 0,
    'vendors': <Map<String, dynamic>>[],
    'decision': null,
  };
  int writes = 0, reads = 0, subscriptions = 0, removed = 0;
  final calls = <Map<String, dynamic>>[];
  void Function()? change, disconnected;
  bool lostReply = false, queueError = false;
  Completer<List<Map<String, dynamic>>>? delayedQueue;
  Completer<Map<String, dynamic>>? delayedDecision;
  @override
  Future<Map<String, dynamic>> options() async => {
    'note_min': 5,
    'note_max': 2000,
    'open_count': 1,
    'statuses': [
      'OPEN',
      'UNDER_REVIEW',
      'RESOLVED',
      'CLOSED',
      'ESCALATED',
      'REJECTED',
    ],
  };
  @override
  Future<List<Map<String, dynamic>>> queue({
    String? status,
    Map<String, dynamic>? before,
  }) async {
    calls.add({'status': status, 'before': before});
    if (queueError) throw TimeoutException('Synthetic transport failure');
    if (delayedQueue != null) {
      final delayed = delayedQueue!;
      delayedQueue = null;
      return delayed.future;
    }
    return status == 'REJECTED'
        ? []
        : List.generate(
            before == null ? 30 : 2,
            (i) => {
              'id': before == null ? 100 - i : 70 - i,
              'created_at': '2026-10-13T10:00:00Z',
              'status': 'Open',
              'reason': 'Other',
              'order_id': i + 1,
            },
          );
  }

  @override
  Future<Map<String, dynamic>> detail(int id) async {
    reads++;
    return Map.of(row);
  }

  @override
  Future<List<Map<String, dynamic>>> vendors(int id, {int? before}) async => [];
  @override
  Future<Map<String, dynamic>> decide(
    int id,
    String decision,
    String note,
  ) async {
    writes++;
    if (delayedDecision != null) return delayedDecision!.future;
    row = {
      ...row,
      'decision': decision,
      'status': decision,
      'admin_note': note,
      'refund_pending': decision == 'RESOLVED',
    };
    if (lostReply) {
      lostReply = false;
      throw TimeoutException('Synthetic lost response after commit');
    }
    return Map.of(row);
  }

  @override
  Future<void> Function() subscribe(
    void Function() onChange,
    void Function() onError,
  ) {
    subscriptions++;
    change = onChange;
    disconnected = onError;
    return () async {
      removed++;
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  late TestAdminBackend backend;
  late AdminController controller;
  setUp(() {
    backend = TestAdminBackend();
    controller = AdminController(disputesBackend: backend);
  });
  tearDown(() {
    controller.onClose();
    Get.reset();
  });

  test('note validation uses trimmed Unicode code points and exact bounds', () {
    expect(validateAdminNote('    ', 5, 2000), isNotNull);
    expect(validateAdminNote('abcd', 5, 2000), isNotNull);
    expect(validateAdminNote('  😀😀😀😀😀  ', 5, 2000), isNull);
    expect(validateAdminNote(List.filled(2000, 'x').join(), 5, 2000), isNull);
    expect(
      validateAdminNote(List.filled(2001, 'x').join(), 5, 2000),
      isNotNull,
    );
  });
  test('only supported nonterminal owned disputes expose actions', () {
    for (final s in ['Open', 'UNDER_REVIEW', 'Escalated']) {
      expect(disputeDecisionAllowed({...backend.row, 'status': s}), isTrue);
    }
    for (final s in ['Resolved', 'REJECTED', 'Closed', 'unknown']) {
      expect(disputeDecisionAllowed({...backend.row, 'status': s}), isFalse);
    }
    expect(
      disputeDecisionAllowed({...backend.row, 'customer_id': null}),
      isFalse,
    );
    expect(
      disputeDecisionAllowed({...backend.row, 'decision': 'RESOLVED'}),
      isFalse,
    );
  });
  test('queue cursor appends bounded pages without duplicating IDs', () async {
    await controller.openDisputeQueue();
    await controller.refreshDisputes(append: true);
    expect(controller.disputes.length, 32);
    expect(controller.hasMoreDisputes.value, isFalse);
    expect(backend.calls.last['before']['id'], 71);
  });
  test(
    'filter changes discard in-flight stale response and fetch new filter',
    () async {
      final delayed = Completer<List<Map<String, dynamic>>>();
      backend.delayedQueue = delayed;
      final pending = controller.openDisputeQueue();
      await Future<void>.delayed(Duration.zero);
      await controller.filterDisputes('REJECTED');
      delayed.complete([backend.row]);
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(controller.disputes, isEmpty);
      expect(backend.calls.last['status'], 'REJECTED');
    },
  );
  test(
    'transport failure produces error without fake disputes; Retry recovers',
    () async {
      backend.queueError = true;
      await controller.openDisputeQueue();
      expect(controller.disputes, isEmpty);
      expect(controller.disputeError.value, contains('not confirmed'));
      backend.queueError = false;
      await controller.retryDisputes();
      expect(controller.disputes.length, 30);
    },
  );
  testWidgets(
    'one channel coalesces events and disposes without late refresh',
    (tester) async {
      await controller.openDisputeQueue();
      await controller.openDisputeQueue();
      expect(backend.subscriptions, 1);
      for (var i = 0; i < 20; i++) {
        backend.change!();
      }
      await tester.pump(const Duration(milliseconds: 351));
      expect(backend.calls.length, 2);
      controller.closeDisputeQueue();
      expect(backend.removed, 1);
      backend.change!();
      await tester.pump(const Duration(seconds: 1));
      expect(backend.calls.length, 2);
      await controller.openDisputeQueue();
      backend.change!();
      await tester.pump(const Duration(milliseconds: 351));
      expect(backend.subscriptions, 2);
      expect(backend.calls.length, 4);
    },
  );
  test('disposal ignores a delayed queue response', () async {
    final delayed = Completer<List<Map<String, dynamic>>>();
    backend.delayedQueue = delayed;
    final pending = controller.openDisputeQueue();
    await Future<void>.delayed(Duration.zero);
    controller.disposeDisputes();
    delayed.complete([backend.row]);
    await pending;
    expect(controller.disputes, isEmpty);
    expect(backend.removed, 1);
  });
  test(
    'detail includes server vendor page and errors remain explicit',
    () async {
      await controller.loadDisputeDetail(1);
      expect(controller.disputeDetail.value?['id'], 1);
      expect(controller.disputeVendors, isEmpty);
      expect(controller.moreDisputeVendors.value, isFalse);
    },
  );
  test('invalid note never invokes decision endpoint', () async {
    await controller.submitDisputeDecision(1, 'RESOLVED', 'bad');
    expect(backend.writes, 0);
    expect(controller.decisionError.value, contains('5–2000'));
  });
  test(
    'Resolve requires confirmed pending refund; Reject creates none',
    () async {
      await controller.submitDisputeDecision(
        1,
        'RESOLVED',
        'Synthetic refund note',
      );
      expect(controller.decisionMessage.value, refundInitiated);
      expect(controller.disputeDetail.value?['refund_pending'], isTrue);
      backend.row = {...backend.row, 'decision': null, 'status': 'Open'};
      await controller.submitDisputeDecision(
        1,
        'REJECTED',
        'Synthetic rejection note',
      );
      expect(controller.decisionMessage.value, disputeRejected);
      expect(controller.disputeDetail.value?['refund_pending'], isFalse);
    },
  );
  test('double taps cannot submit concurrent decisions', () async {
    backend.delayedDecision = Completer<Map<String, dynamic>>();
    final first = controller.submitDisputeDecision(
      1,
      'REJECTED',
      'Synthetic note',
    );
    await Future<void>.delayed(Duration.zero);
    await controller.submitDisputeDecision(1, 'RESOLVED', 'Synthetic opposite');
    expect(backend.writes, 1);
    backend.delayedDecision!.complete({
      ...backend.row,
      'decision': 'REJECTED',
      'admin_note': 'Synthetic note',
      'status': 'Rejected',
      'refund_pending': false,
    });
    await first;
    expect(controller.decisionBusy.value, isFalse);
  });
  test(
    'lost success response refetches outcome without a second write',
    () async {
      backend.lostReply = true;
      await controller.submitDisputeDecision(
        1,
        'RESOLVED',
        'Synthetic refund note',
      );
      expect(backend.writes, 1);
      expect(backend.reads, 2);
      expect(controller.decisionMessage.value, refundInitiated);
      expect(controller.decisionUncertain, isFalse);
    },
  );
  test(
    'opposite finalized outcome returns conflict and never writes',
    () async {
      backend.row = {
        ...backend.row,
        'decision': 'REJECTED',
        'status': 'Rejected',
        'admin_note': 'Winning admin note',
      };
      await controller.submitDisputeDecision(
        1,
        'RESOLVED',
        'Losing admin note',
      );
      expect(backend.writes, 0);
      expect(controller.decisionError.value, contains('already finalized'));
      expect(
        controller.disputeDetail.value?['admin_note'],
        'Winning admin note',
      );
    },
  );
  test('internal database errors are not exposed to the user', () {
    expect(
      adminDisputeError(
        const PostgrestException(
          message: 'private database details',
          code: 'XX000',
        ),
      ),
      isNot(contains('private')),
    );
    expect(
      adminDisputeError(
        const PostgrestException(message: 'internal', code: '42501'),
      ),
      'Admin authorization required.',
    );
  });
  test('unsupported client decision never reaches the backend', () async {
    await controller.submitDisputeDecision(
      1,
      'CLOSED',
      'Synthetic invalid action',
    );
    expect(backend.writes, 0);
    expect(backend.reads, 0);
  });
  test('late decision cannot replace a different open detail', () async {
    await controller.loadDisputeDetail(1);
    backend.delayedDecision = Completer<Map<String, dynamic>>();
    final pending = controller.submitDisputeDecision(
      1,
      'REJECTED',
      'Synthetic note',
    );
    await Future<void>.delayed(Duration.zero);
    controller.leaveDisputeDetail();
    backend.row = {...backend.row, 'id': 2};
    await controller.loadDisputeDetail(2);
    backend.delayedDecision!.complete({
      ...backend.row,
      'id': 1,
      'decision': 'REJECTED',
      'status': 'Rejected',
      'admin_note': 'Synthetic note',
      'refund_pending': false,
    });
    await pending;
    expect(controller.disputeDetail.value?['id'], 2);
    expect(controller.decisionMessage.value, isNull);
  });
  testWidgets('Resolve confirmation Cancel leaves backend untouched', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(home: AdminDisputeDetails(id: 1, controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic decision note');
    await tester.ensureVisible(find.text('Resolve'));
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(find.text('Resolve this dispute?'), findsOneWidget);
    expect(find.textContaining('Money will not be returned'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Reject confirmation commits only after explicit approval', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(home: AdminDisputeDetails(id: 1, controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic rejection note');
    await tester.ensureVisible(find.text('Reject'));
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(backend.writes, 0);
    await tester.tap(find.text('Confirm decision'));
    await tester.pumpAndSettle();
    expect(backend.writes, 1);
    expect(find.text(disputeRejected), findsOneWidget);
    expect(find.text('Reject'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('finalized dispute is read-only with its original note', (
    tester,
  ) async {
    backend.row = {
      ...backend.row,
      'decision': 'REJECTED',
      'status': 'Rejected',
      'admin_note': 'Winning note',
    };
    await tester.pumpWidget(
      GetMaterialApp(home: AdminDisputeDetails(id: 1, controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resolve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Admin note: Winning note'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
