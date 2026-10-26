import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/services/prescription_service.dart';
import 'package:flutter_application_1/services/tailoring_service.dart';
import 'package:flutter_application_1/services/optional_media_service.dart';
import 'package:flutter_application_1/controllers/prescription_controller.dart';
import 'package:flutter_application_1/widgets/prescription_upload_widget.dart';

const reference = 'tezphoto:29bfe933-69bc-46cb-a314-dd95529f98a1';
Map<String, dynamic> persisted() => {
  'id': 3,
  'vendor_order_id': 7,
  'customer_id': 9,
  'vendor_id': 11,
  'status': 'pending',
  'prescription_image_url': reference,
};

void main() {
  tearDown(Get.reset);
  test(
    'tailoring retries original payload and confirms actual saved row',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = TailoringService(
        identity: () => 'owner',
        call: (name, body) async {
          expect(name, 'optional_submit_tailoring');
          calls.add(Map.from(body));
          if (calls.length == 1) throw TimeoutException('uncertain');
          return {
            'id': 2,
            'status': 'pickup_requested',
            'instructions': 'Shirt',
          };
        },
      );
      await expectLater(
        service.submit(instructions: ' Shirt ', measurements: {'length': '40'}),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        service.submit(instructions: 'Changed', measurements: {}),
        throwsStateError,
      );
      final saved = await service.submit(
        instructions: ' Shirt ',
        measurements: {'length': '40'},
      );
      expect(saved['id'], 2);
      expect(calls[0], calls[1]);
    },
  );
  test(
    'tailoring rejects unconfirmed results and account-switch completion',
    () async {
      var account = 'owner';
      final pending = Completer<dynamic>();
      final service = TailoringService(
        identity: () => account,
        call: (_, _) => pending.future,
      );
      final result = service.submit(instructions: 'Shirt', measurements: {});
      account = 'another';
      pending.complete({
        'id': 2,
        'status': 'pickup_requested',
        'instructions': 'Shirt',
      });
      await expectLater(result, throwsStateError);
      final invalid = TailoringService(
        identity: () => 'owner',
        call: (_, _) async => {},
      );
      await expectLater(
        invalid.submit(instructions: 'Shirt', measurements: {}),
        throwsFormatException,
      );
    },
  );
  test(
    'prescription retry retains request identity after uncertain response',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = PrescriptionService(
        identity: () => 'owner',
        call: (name, body) async {
          expect(name, 'optional_save_prescription');
          calls.add(Map.from(body));
          if (calls.length == 1) throw TimeoutException('uncertain');
          return persisted();
        },
      );
      Future<dynamic> submit() => service.uploadPrescription(
        vendorOrderId: '7',
        customerId: '9',
        prescriptionImageUrl: reference,
      );
      await expectLater(submit(), throwsA(isA<TimeoutException>()));
      expect((await submit()).id, '3');
      expect(calls[0], calls[1]);
    },
  );
  test(
    'prescription never saves a legacy URL or absent vendor-order id',
    () async {
      var calls = 0;
      final service = PrescriptionService(
        identity: () => 'owner',
        call: (_, _) async {
          calls++;
          return persisted();
        },
      );
      expect(
        await service.uploadPrescription(
          vendorOrderId: '',
          customerId: '9',
          prescriptionImageUrl: reference,
        ),
        isNull,
      );
      expect(
        await service.uploadPrescription(
          vendorOrderId: '7',
          customerId: '9',
          prescriptionImageUrl: 'https://private.example/image.png',
        ),
        isNull,
      );
      expect(calls, 0);
    },
  );
  test(
    'prescription review requires returned persisted review, not empty success',
    () async {
      final missing = PrescriptionService(
        identity: () => 'owner',
        call: (_, _) async => {},
      );
      await expectLater(
        missing.approvePrescription('3', '', null),
        throwsFormatException,
      );
      final confirmed = PrescriptionService(
        identity: () => 'owner',
        call: (_, _) async => {
          ...persisted(),
          'status': 'approved',
          'reviewed_by': 11,
          'reviewed_at': '2026-10-25T12:00:00Z',
        },
      );
      expect(await confirmed.approvePrescription('3', '', null), isTrue);
    },
  );
  test(
    'read failures propagate and account-switch response cannot display old records',
    () async {
      final failed = PrescriptionService(
        identity: () => 'owner',
        call: (_, _) async => throw StateError('denied'),
      );
      await expectLater(failed.list(), throwsStateError);
      var account = 'owner';
      final pending = Completer<dynamic>();
      final service = PrescriptionService(
        identity: () => account,
        call: (_, _) => pending.future,
      );
      final result = service.list();
      account = 'other';
      pending.complete([persisted()]);
      await expectLater(result, throwsStateError);
    },
  );
  testWidgets(
    'upload waits for validated media and confirmed record before success callback',
    (tester) async {
      final mediaDone = Completer<dynamic>();
      final rowDone = Completer<dynamic>();
      var mediaCalls = 0, recordCalls = 0, confirmed = 0;
      final media = OptionalMediaService(
        kind: 'prescription',
        orderId: 7,
        identity: () => 'owner',
        call: (_) {
          mediaCalls++;
          return mediaDone.future;
        },
      );
      final service = PrescriptionService(
        identity: () => 'owner',
        call: (_, _) {
          recordCalls++;
          return rowDone.future;
        },
      );
      final controller = PrescriptionController(service: service);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PrescriptionUploadWidget(
                vendorOrderId: '7',
                customerId: '9',
                controller: controller,
                media: media,
                picker: (_) async => png,
                onUploadSuccess: () => confirmed++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('From Gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload Prescription'));
      await tester.pump();
      expect(mediaCalls, 1);
      expect(recordCalls, 0);
      expect(confirmed, 0);
      mediaDone.complete({'reference': reference});
      await tester.pump();
      expect(recordCalls, 1);
      expect(confirmed, 0);
      rowDone.complete(persisted());
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(
        find.text('Prescription uploaded. Waiting for vendor review.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
