import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/private_photo_service.dart';
import 'package:flutter_application_1/widgets/private_photo.dart';

const reference = 'tezphoto:11111111-2222-4333-8444-555555555555';
const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGD4DwAChAGA+gVWHQAAAABJRU5ErkJggg==';
Uint8List bytes() => base64Decode(pixel);
Map<String, dynamic> viewed() => {
  'mime_type': 'image/png',
  'image_base64': pixel,
  'expires_in': 900,
};
void main() {
  test(
    'uncertain upload retries identical UUID and bytes, then reuses confirmed reference',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = PrivatePhotoService(
        identity: () => 'vendor',
        call: (body) async {
          calls.add(body);
          if (calls.length == 1) throw TimeoutException('network');
          return {'reference': reference};
        },
      );
      await expectLater(
        service.upload(bytes()),
        throwsA(isA<TimeoutException>()),
      );
      expect(await service.upload(bytes()), reference);
      expect(calls[0], calls[1]);
      expect(calls[1]['mime_type'], 'image/png');
      expect(await service.upload(bytes()), reference);
      expect(calls.length, 2);
    },
  );
  test('changed image cannot replace an unresolved upload', () async {
    var calls = 0;
    final service = PrivatePhotoService(
      identity: () => 'vendor',
      call: (_) async {
        calls++;
        throw TimeoutException('network');
      },
    );
    await expectLater(
      service.upload(bytes()),
      throwsA(isA<TimeoutException>()),
    );
    final changed = bytes()..[25] = 0;
    await expectLater(service.upload(changed), throwsStateError);
    expect(calls, 1);
  });
  test(
    'duplicate busy submission is rejected before another server call',
    () async {
      final pending = Completer<dynamic>();
      var calls = 0;
      final service = PrivatePhotoService(
        identity: () => 'vendor',
        call: (_) {
          calls++;
          return pending.future;
        },
      );
      final first = service.upload(bytes());
      await expectLater(service.upload(bytes()), throwsStateError);
      expect(calls, 1);
      pending.complete({'reference': reference});
      expect(await first, reference);
    },
  );
  test(
    'server validation failure permits corrected file with a new request',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = PrivatePhotoService(
        identity: () => 'vendor',
        call: (body) async {
          calls.add(body);
          if (calls.length == 1) {
            throw const FunctionException(
              status: 422,
              details: {'error': 'Invalid image contents.'},
            );
          }
          return {'reference': reference};
        },
      );
      await expectLater(service.upload(bytes()), throwsStateError);
      expect(await service.upload(bytes()), reference);
      expect(calls[0]['request_id'], isNot(calls[1]['request_id']));
    },
  );
  test(
    'missing, oversize and unsupported file never dispatch an upload',
    () async {
      var calls = 0;
      final service = PrivatePhotoService(
        identity: () => 'vendor',
        call: (_) async {
          calls++;
          return {};
        },
      );
      for (final value in [
        Uint8List(0),
        Uint8List(5242881),
        Uint8List.fromList([60, 115, 99, 114, 105, 112, 116]),
      ]) {
        await expectLater(service.upload(value), throwsStateError);
      }
      expect(calls, 0);
    },
  );
  test(
    'late upload response after account switch cannot authorize a product reference',
    () async {
      String? account = 'a';
      final pending = Completer<dynamic>();
      final service = PrivatePhotoService(
        identity: () => account,
        call: (_) => pending.future,
      );
      final upload = service.upload(bytes());
      account = 'b';
      pending.complete({'reference': reference});
      await expectLater(upload, throwsStateError);
      await expectLater(service.upload(bytes()), throwsStateError);
    },
  );
  test(
    'view dispatches canonical UUID only and rejects late account response',
    () async {
      String? account = 'a';
      final pending = Completer<dynamic>();
      Map<String, dynamic>? actual;
      final service = PrivatePhotoService(
        identity: () => account,
        call: (body) {
          actual = body;
          return pending.future;
        },
      );
      final read = service.read(reference);
      expect(actual, {
        'action': 'view',
        'image_id': '11111111-2222-4333-8444-555555555555',
      });
      account = 'b';
      pending.complete(viewed());
      await expectLater(read, throwsStateError);
    },
  );
  test(
    'malformed upload and view responses cannot become apparent success',
    () async {
      final service = PrivatePhotoService(
        identity: () => 'a',
        call: (_) async => {'reference': 'https://unverified.invalid/private'},
      );
      await expectLater(service.upload(bytes()), throwsFormatException);
      await expectLater(service.read(reference), throwsFormatException);
      await expectLater(
        service.read('tezphoto:not-a-uuid'),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'actual image error Retry performs authorized read and renders in-memory bytes',
    (tester) async {
      var calls = 0;
      final service = PrivatePhotoService(
        identity: () => 'a',
        call: (_) async {
          calls++;
          if (calls == 1) throw TimeoutException('network');
          return viewed();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PrivatePhoto(imageUrl: reference, service: service),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Retry private photo'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Retry private photo'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account change clears image immediately and ignores stale read after disposal',
    (tester) async {
      String? account = 'a';
      final auth = StreamController<void>.broadcast(sync: true);
      var calls = 0;
      final late = Completer<dynamic>();
      final service = PrivatePhotoService(
        identity: () => account,
        call: (_) {
          calls++;
          return calls == 1 ? Future.value(viewed()) : late.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PrivatePhoto(
            imageUrl: reference,
            service: service,
            accountChanges: auth.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      account = 'b';
      auth.add(null);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
      late.complete(viewed());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await auth.close();
    },
  );
  testWidgets(
    'image expires at the server viewing deadline and actual Retry reauthorizes',
    (tester) async {
      var calls = 0;
      final service = PrivatePhotoService(
        identity: () => 'a',
        call: (_) async {
          calls++;
          return {...viewed(), 'expires_in': 3};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PrivatePhoto(imageUrl: reference, service: service),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(Image), findsNothing);
      expect(find.bySemanticsLabel('Retry private photo'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Retry private photo'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('invalid or missing server viewing lifetime is rejected', () async {
    for (final ttl in [null, 0, -1, 901, '900']) {
      final service = PrivatePhotoService(
        identity: () => 'a',
        call: (_) async => {...viewed(), 'expires_in': ttl},
      );
      await expectLater(service.read(reference), throwsFormatException);
    }
  });
  testWidgets(
    'legacy private URL is never fetched without live authorization',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PrivatePhoto(imageUrl: 'https://example.invalid/legacy.png'),
        ),
      );
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
