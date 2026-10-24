import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/profile_service.dart';

void main() {
  Map<String, dynamic> profile([String role = 'customer']) => {
    'id': 1,
    'name': 'Owner',
    'phone': '+92 300 1234567',
    'email': 'owner@example.test',
    'role': role,
  };
  for (final role in ProfileService.roles) {
    test(
      '$role edit sends only name/phone to the existing trusted API',
      () async {
        Map<String, dynamic>? sent;
        final service = ProfileService(
          identity: () => 'account-a',
          read: (_) async => profile(role),
          write: (p) async {
            sent = p;
            return {'code': 'OK', ...profile(role)};
          },
        );
        expect((await service.load())['role'], role);
        expect(
          (await service.save(' Owner ', '+92 300 1234567 '))['name'],
          'Owner',
        );
        expect(sent, {
          'p_name': 'Owner',
          'p_phone': '+92 300 1234567',
          'p_update_profile': true,
        });
      },
    );
  }
  test('validation prevents malformed data before a request', () async {
    var calls = 0;
    final service = ProfileService(
      identity: () => 'a',
      write: (_) async {
        calls++;
        return null;
      },
    );
    for (final input in [
      ['', '1234'],
      ['Owner', '---'],
      ['Owner\u0000', '1234'],
      ['Owner', 'owner@example.test'],
    ]) {
      await expectLater(
        service.save(input[0], input[1]),
        throwsFormatException,
      );
    }
    expect(calls, 0);
  });
  test('account switching rejects an old account read and write', () async {
    String? account = 'a';
    final read = Completer<dynamic>(), write = Completer<dynamic>();
    final service = ProfileService(
      identity: () => account,
      read: (_) => read.future,
      write: (_) => write.future,
    );
    final reading = expectLater(service.load(), throwsStateError);
    final saving = expectLater(
      service.save('Owner', '+92 300 1234567'),
      throwsStateError,
    );
    account = 'b';
    read.complete(profile());
    write.complete({'code': 'OK', ...profile()});
    await Future.wait([reading, saving]);
    expect(service.busy, isFalse);
  });
  test(
    'uncertain write is never reported as saved and duplicate in-flight submit is rejected',
    () async {
      var calls = 0;
      final pending = Completer<dynamic>();
      final service = ProfileService(
        identity: () => 'a',
        write: (_) {
          calls++;
          return pending.future;
        },
      );
      final saving = expectLater(
        service.save('Owner', '+92 300 1234567'),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(service.save('Different', '1234'), throwsStateError);
      pending.completeError(TimeoutException('injected response loss'));
      await saving;
      expect(calls, 1);
      expect(service.busy, isFalse);
    },
  );
  test(
    'unconfirmed response, denied and signed-out requests remain failures',
    () async {
      final malformed = ProfileService(
        identity: () => 'a',
        write: (_) async => {'code': 'OK', ...profile(), 'name': 'Wrong'},
      );
      await expectLater(
        malformed.save('Owner', '+92 300 1234567'),
        throwsFormatException,
      );
      final denied = ProfileService(
        identity: () => 'a',
        write: (_) async => throw StateError('blocked'),
      );
      await expectLater(denied.save('Owner', '1234'), throwsStateError);
      var calls = 0;
      final signedOut = ProfileService(
        identity: () => null,
        read: (_) async {
          calls++;
          return profile();
        },
      );
      await expectLater(signedOut.load(), throwsStateError);
      expect(calls, 0);
    },
  );
}
