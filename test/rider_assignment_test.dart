import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/rider_assignment_service.dart';

class Backend implements RiderAssignmentBackend {
  final calls = <String>[];
  Future<Map<String, dynamic>> Function() mutation = () async => {
    'code': 'ASSIGNED_5KM',
  };
  Future<Map<String, dynamic>> Function() lookup = () async => {
    'code': 'UNASSIGNED',
  };
  @override
  Future<Map<String, dynamic>> assign(int id) {
    calls.add('assign:$id');
    return mutation();
  }

  @override
  Future<Map<String, dynamic>> status(int id) {
    calls.add('status:$id');
    return lookup();
  }
}

void main() {
  test('no eligible admin does not claim notification delivery', () async {
    final backend = Backend()
      ..mutation = () async => {
        'code': 'NO_RIDER_AVAILABLE',
        'admin_notified': false,
      };
    final message = await RiderAssignmentFlow(backend).assign(42);
    expect(message, contains('no eligible administrator'));
    expect(message, isNot(contains('Administrators notified')));
  });
  for (final entry in {
    'ASSIGNED_5KM': 'within 5 km',
    'ASSIGNED_10KM': 'expanding the search to 10 km',
    'ALREADY_ASSIGNED': 'already assigned',
    'NO_RIDER_AVAILABLE': 'Administrators notified for manual assignment',
    'FORBIDDEN': 'owning this order',
    'INVALID_ORDER_STATE': 'no longer eligible',
    'PICKUP_LOCATION_REQUIRED': 'Set your store location',
    'RETRYABLE_CONFLICT': 'busy',
  }.entries) {
    test('maps confirmed ${entry.key} without client distance rules', () async {
      final backend = Backend()..mutation = () async => {'code': entry.key};
      final flow = RiderAssignmentFlow(backend);
      expect(await flow.assign(42), contains(entry.value));
      expect(flow.messages['42'], contains(entry.value));
      expect(backend.calls, ['assign:42']);
      expect(flow.busy, isEmpty);
    });
  }

  test(
    'loading excludes duplicate mutation but allows another order',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final backend = Backend()..mutation = () => pending.future;
      final flow = RiderAssignmentFlow(backend);
      final first = flow.assign(1);
      expect(flow.busy.contains('1'), isTrue);
      expect(await flow.assign(1), contains('already in progress'));
      final other = flow.assign(2);
      expect(backend.calls, ['assign:1', 'assign:2']);
      pending.complete({'code': 'NO_RIDER_AVAILABLE'});
      await Future.wait([first, other]);
      expect(flow.busy, isEmpty);
    },
  );

  test(
    'timeout reconciles committed assignment without another mutation',
    () async {
      final backend = Backend();
      backend.mutation = () async => throw TimeoutException('response lost');
      backend.lookup = () async => {'code': 'ALREADY_ASSIGNED'};
      final flow = RiderAssignmentFlow(backend);
      expect(await flow.assign(1), contains('already assigned'));
      expect(backend.calls, ['assign:1', 'status:1']);
      expect(flow.uncertain, isEmpty);
    },
  );

  test(
    'offline retains uncertainty; retry checks saved escalation first',
    () async {
      final backend = Backend();
      backend.mutation = () async => throw StateError('offline');
      backend.lookup = () async => throw StateError('offline');
      final flow = RiderAssignmentFlow(backend);
      expect(await flow.assign(1), contains('not confirmed'));
      expect(flow.uncertain, contains(1));
      backend.lookup = () async => {'code': 'NO_RIDER_AVAILABLE'};
      expect(await flow.assign(1), contains('Administrators notified'));
      expect(backend.calls, ['assign:1', 'status:1', 'status:1']);
      expect(flow.uncertain, isEmpty);
    },
  );

  test(
    'explicit retry after authoritative unassigned can mutate once',
    () async {
      final backend = Backend()
        ..mutation = () async => throw TimeoutException('timeout');
      final flow = RiderAssignmentFlow(backend);
      expect(await flow.assign(1), contains('not confirmed'));
      backend.mutation = () async => {'code': 'ASSIGNED_10KM'};
      expect(await flow.assign(1), contains('10 km'));
      expect(backend.calls, ['assign:1', 'status:1', 'status:1', 'assign:1']);
    },
  );

  test('unauthorized exception does not claim successful assignment', () async {
    final backend = Backend()
      ..mutation = () async =>
          throw const PostgrestException(message: 'denied', code: '42501');
    final flow = RiderAssignmentFlow(backend);
    expect(await flow.assign(1), contains('approved vendor'));
    expect(backend.calls, ['assign:1']);
  });

  test('unknown success-shaped payload remains unconfirmed', () async {
    final backend = Backend()
      ..mutation = () async => {'message': 'success', 'rider_id': 1};
    final flow = RiderAssignmentFlow(backend);
    expect(await flow.assign(1), contains('not confirmed'));
    expect(flow.uncertain, contains(1));
  });
}
