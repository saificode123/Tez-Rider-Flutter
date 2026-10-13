import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter_application_1/services/dispute_service.dart';
import 'package:flutter_application_1/controllers/dispute_controller.dart';
import 'package:flutter_application_1/widgets/dispute_evidence_viewer.dart';

class MemoryDrafts implements DisputeDraftStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read(String account) async => value;
  @override
  Future<void> save(String account, Map<String, dynamic> draft) async {
    value = Map.from(draft);
  }

  @override
  Future<void> clear(String account) async {
    value = null;
  }
}

class FakeDisputes implements DisputeBackend {
  @override
  String accountId = 'customer-a';
  int submissions = 0, uploads = 0, cleanups = 0;
  bool loseResponse = false, lookupsFail = false;
  String? failure;
  Map<String, dynamic>? result;
  Completer<void>? gate;
  final requests = <String>[];
  @override
  Future<Map<String, dynamic>> options() async => {
    'reasons': ['Other'],
    'description_limit': 2000,
  };
  @override
  Future<List<Map<String, dynamic>>> eligible({int? before}) async => [
    {'id': 1},
  ];
  @override
  Future<List<Map<String, dynamic>>> history({int? before}) async =>
      result == null ? [] : [result!];
  @override
  Future<Map<String, dynamic>> detail(int id) async => result!;
  @override
  Future<void> prepare(String requestId, int orderId) async {
    requests.add(requestId);
  }

  @override
  Future<String> upload(String requestId, DisputeImage image) async {
    uploads++;
    return '$accountId/$requestId/$uploads.png';
  }

  @override
  Future<Map<String, dynamic>> submit(
    String requestId,
    int orderId,
    String reason,
    String description,
    List<String> paths,
  ) async {
    submissions++;
    if (gate != null) await gate!.future;
    if (failure != null) throw FormatException(failure!);
    result = {'id': 5, 'status': 'Open', 'request_id': requestId};
    if (loseResponse) throw const FormatException('Lost response.');
    return result!;
  }

  @override
  Future<Map<String, dynamic>?> lookup(String requestId) async {
    if (lookupsFail) throw TimeoutException('offline');
    return result;
  }

  @override
  Future<void> cleanup(String requestId) async {
    cleanups++;
  }

  @override
  Future<String> signedUrl(int disputeId, int index) async {
    if (failure != null) throw FormatException(failure!);
    return 'https://example.test/private';
  }
}

DisputeController ready(FakeDisputes backend, MemoryDrafts store) {
  final controller = DisputeController(backend: backend, store: store);
  controller.reasons.assignAll(['Other']);
  controller.orderId = 1;
  controller.reason = 'Other';
  controller.description = 'Missing synthetic item';
  controller.images.add(
    DisputeImage(Uint8List.fromList([1, 2]), '/synthetic.png'),
  );
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('uploaded draft restores without deleted temporary originals', () async {
    final backend = FakeDisputes();
    final store = MemoryDrafts()
      ..value = {
        'request_id': 'original-request',
        'order_id': 1,
        'reason': 'Other',
        'description': 'Already uploaded evidence',
        'paths': ['confirmed.png'],
        'source_paths': ['/deleted-picker-original.png'],
        'uncertain': true,
      };
    final controller = DisputeController(backend: backend, store: store);
    await controller.initialize();
    expect(controller.error.value, isEmpty);
    await controller.submit();
    expect(controller.message.value, disputeSuccess);
    expect(backend.uploads, 0);
    expect(backend.requests, ['original-request']);
  });
  test(
    'image preparation resizes actual pixels and rejects invalid/oversized input',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'fr25-synthetic-image-',
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.green, BlendMode.src);
      final picture = recorder.endRecording();
      final original = await picture.toImage(3000, 1000);
      final data = await original.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${temp.path}/synthetic.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      try {
        final prepared = await DisputeImagePicker().read(file.path);
        final codec = await ui.instantiateImageCodec(prepared.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1600);
        expect(frame.image.height, 533);
        expect(prepared.bytes.length, lessThanOrEqualTo(5242880));
        frame.image.dispose();
        codec.dispose();
        await file.writeAsBytes([1, 2, 3]);
        await expectLater(
          DisputeImagePicker().read(file.path),
          throwsFormatException,
        );
        await file.writeAsBytes(Uint8List(5242881));
        await expectLater(
          DisputeImagePicker().read(file.path),
          throwsFormatException,
        );
      } finally {
        original.dispose();
        picture.dispose();
        await temp.delete(recursive: true);
      }
    },
  );
  testWidgets('evidence viewer maps an actual signing failure to Retry', (
    tester,
  ) async {
    final backend = FakeDisputes();
    backend.failure = 'Evidence denied';
    await tester.pumpWidget(
      MaterialApp(
        home: DisputeEvidenceViewer(disputeId: 1, index: 1, backend: backend),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Evidence denied'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'eligible window uses actual delivery time and inclusive exact boundary',
    () {
      final now = DateTime.utc(2026, 10, 13);
      final row = {
        'order_status': 'delivered',
        'delivered_at': now
            .subtract(const Duration(hours: 24))
            .toIso8601String(),
      };
      expect(disputeOrderEligible(row, now), true);
      expect(
        disputeOrderEligible(row, now.add(const Duration(microseconds: 1))),
        false,
      );
      expect(disputeOrderEligible({'order_status': 'delivered'}, now), false);
      expect(
        disputeOrderEligible({...row, 'order_status': 'placed'}, now),
        false,
      );
      expect(
        disputeOrderEligible({
          ...row,
          'delivered_at': now.add(const Duration(minutes: 1)).toIso8601String(),
        }, now),
        false,
      );
    },
  );
  test(
    'server-provided reasons and Unicode description length are validated',
    () {
      expect(validateDispute('Other', 'Evidence', 1, ['Other'], 2000), null);
      expect(
        validateDispute('Unknown', 'Evidence', 1, ['Other'], 2000),
        isNotNull,
      );
      expect(validateDispute('Other', '   ', 1, ['Other'], 2000), isNotNull);
      expect(validateDispute('Other', '😀' * 2000, 3, ['Other'], 2000), null);
      expect(
        validateDispute('Other', 'x' * 2001, 1, ['Other'], 2000),
        isNotNull,
      );
      expect(
        validateDispute('Other', 'Evidence', 0, ['Other'], 2000),
        isNotNull,
      );
      expect(
        validateDispute('Other', 'Evidence', 4, ['Other'], 2000),
        isNotNull,
      );
    },
  );
  test(
    'successful submission clears local draft only after confirmation',
    () async {
      final backend = FakeDisputes();
      final store = MemoryDrafts();
      final c = ready(backend, store);
      await c.submit();
      expect(backend.submissions, 1);
      expect(c.message.value, disputeSuccess);
      expect(store.value, null);
      expect(c.busy.value, false);
    },
  );
  test('duplicate tap is blocked during a real pending operation', () async {
    final backend = FakeDisputes()..gate = Completer();
    final c = ready(backend, MemoryDrafts());
    final first = c.submit();
    await Future<void>.delayed(Duration.zero);
    await c.submit();
    expect(backend.submissions, 1);
    expect(c.editable, false);
    backend.gate!.complete();
    await first;
  });
  test(
    'lost successful response reconciles without duplicate notification or cleanup',
    () async {
      final backend = FakeDisputes()..loseResponse = true;
      final c = ready(backend, MemoryDrafts());
      await c.submit();
      expect(c.message.value, disputeSuccess);
      expect(backend.submissions, 1);
      expect(backend.cleanups, 0);
    },
  );
  test('retry preserves request identifier and uploaded evidence', () async {
    final backend = FakeDisputes()..failure = 'Temporary rejection';
    final c = ready(backend, MemoryDrafts());
    await c.submit();
    final id = c.requestId;
    expect(c.message.value, isEmpty);
    expect(c.paths.length, 1);
    backend.failure = null;
    await c.submit();
    expect(backend.requests, [id, id]);
    expect(backend.uploads, 1);
    expect(c.message.value, disputeSuccess);
  });
  test('expiry is shown exactly and cleanup is authorized', () async {
    final backend = FakeDisputes()..failure = disputeExpired;
    final c = ready(backend, MemoryDrafts());
    await c.submit();
    expect(c.error.value, disputeExpired);
    expect(c.message.value, isEmpty);
    expect(backend.cleanups, 1);
  });
  test(
    'unknown result retains draft and never deletes potentially attached evidence',
    () async {
      final backend = FakeDisputes();
      final store = MemoryDrafts();
      final c = ready(backend, store);
      backend.lookupsFail = true;
      await c.submit();
      expect(store.value, isNotNull);
      expect(backend.cleanups, 0);
      expect(backend.submissions, 0);
    },
  );
  test('account switch prevents writes under another identity', () async {
    final backend = FakeDisputes();
    final c = ready(backend, MemoryDrafts());
    // Capture ownership before switching the backend account.
    expect(c.account, 'customer-a');
    backend.accountId = 'customer-b';
    await c.submit();
    expect(backend.submissions, 0);
  });
  test('discard abandons only the current draft', () async {
    final backend = FakeDisputes()..failure = 'Temporary rejection';
    final store = MemoryDrafts();
    final c = ready(backend, store);
    await c.submit();
    await c.discard();
    expect(backend.cleanups, 1);
    expect(store.value, null);
    expect(c.requestId, null);
  });
}
