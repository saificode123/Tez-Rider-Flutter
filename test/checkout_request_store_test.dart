import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/checkout_request_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final memory = <String, String>{};
  String? account;
  var discardWrites = false;
  setUp(() {
    memory.clear();
    account = 'synthetic-account-a';
    discardWrites = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final key = args['key'] as String;
          switch (call.method) {
            case 'read':
              return memory[key];
            case 'write':
              if (!discardWrites) memory[key] = args['value'] as String;
              return null;
            case 'delete':
              memory.remove(key);
              return null;
            default:
              throw StateError('Unexpected storage operation');
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  final request = <String, dynamic>{
    'p_request_id': '00000000-0000-4000-8000-000000000001',
    'p_items': [
      {'product_id': 224, 'quantity': 1},
    ],
    'p_delivery': {'address': 'synthetic private destination'},
  };
  test(
    'journal survives recreation in secure account-scoped storage',
    () async {
      await SecureCheckoutRequestStore(
        currentAccount: () => account,
      ).write(request);
      final restored = SecureCheckoutRequestStore(
        currentAccount: () => account,
      );
      expect(await restored.read(), request);
      expect(memory.keys.single, endsWith('.synthetic-account-a'));
      await restored.clear();
      expect(await restored.read(), isNull);
    },
  );
  test(
    'another signed-in account cannot read or clear the first journal',
    () async {
      final first = SecureCheckoutRequestStore(currentAccount: () => account);
      await first.write(request);
      account = 'synthetic-account-b';
      expect(
        await SecureCheckoutRequestStore(currentAccount: () => account).read(),
        isNull,
      );
      await expectLater(first.read(), throwsStateError);
      await expectLater(first.clear(), throwsStateError);
      expect(memory.length, 1);
    },
  );
  test('unconfirmed native write fails before a request can be sent', () async {
    discardWrites = true;
    await expectLater(
      SecureCheckoutRequestStore(currentAccount: () => account).write(request),
      throwsStateError,
    );
  });
  test('corrupt saved bytes are never treated as an empty journal', () async {
    memory['tezrider.checkout.pending.v1.synthetic-account-a'] = '{corrupt';
    await expectLater(
      SecureCheckoutRequestStore(currentAccount: () => account).read(),
      throwsFormatException,
    );
  });
  test('signed-out account cannot create a journal', () async {
    account = null;
    await expectLater(
      SecureCheckoutRequestStore(currentAccount: () => account).write(request),
      throwsStateError,
    );
    expect(memory, isEmpty);
  });
  test(
    'late construction cannot bind an old checkout screen to another account',
    () async {
      account = 'synthetic-account-b';
      final store = SecureCheckoutRequestStore(
        currentAccount: () => account,
        expectedAccount: 'synthetic-account-a',
      );
      expect(store.identity, isNull);
      await expectLater(store.write(request), throwsStateError);
      expect(memory, isEmpty);
    },
  );
}
