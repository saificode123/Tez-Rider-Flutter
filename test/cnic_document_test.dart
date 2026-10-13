import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/cnic_document.dart';
import 'package:flutter_application_1/controllers/cnic_document_controller.dart';
import 'package:flutter_application_1/widgets/cnic_document_viewer.dart';

class TestBackend implements CnicBackend {
  int calls = 0;
  int failures = 0;
  bool valid = true;
  bool wrongRequest = false;
  String? viewUrl;
  int viewCalls = 0;
  final ids = <String>[];
  Completer<void>? gate;
  @override
  Future<void> upload(CnicImage image, String cnic, String id) async {
    calls++;
    ids.add(id);
    if (failures-- > 0) throw TimeoutException('test transport interruption');
    await gate?.future;
  }

  @override
  Future<Map<String, dynamic>> status() async => {
    'submission_status': 'submitted',
    'document_valid': valid,
    'verification_status': 'pending',
    'document_path':
        'test-owner/${wrongRequest || ids.isEmpty ? "other-request" : ids.last}/cnic.png',
  };
  @override
  Future<String> signedUrl({String? userId}) async {
    viewCalls++;
    return viewUrl ??
        (throw const FormatException('Document not available. Retry.'));
  }
}

class TestImages extends CnicImageService {
  TestImages(this.selected);
  final CnicImage selected;
  final sources = <ImageSource>[];
  @override
  Future<CnicImage?> pick(ImageSource source) async {
    sources.add(source);
    return selected;
  }
}

class CompressingPicker extends ImagePicker {
  CompressingPicker(this.original, this.compressed);
  final String original;
  final String compressed;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => XFile(imageQuality == null ? original : compressed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('CNIC regional transport fallback preserves the request', () async {
    final regions = <String?>[];
    final result = await invokeCnicWithRegionFallback((region) async {
      regions.add(region);
      if (region != null) throw const FunctionException(status: 503);
      return 'confirmed';
    });
    expect(result, 'confirmed');
    expect(regions, ['ap-northeast-1', null]);
  });
  test('CNIC routing never retries forbidden or invalid requests', () async {
    for (final status in [401, 403, 409, 422]) {
      var calls = 0;
      await expectLater(
        invokeCnicWithRegionFallback((region) async {
          calls++;
          throw FunctionException(status: status);
        }),
        throwsA(isA<FunctionException>()),
      );
      expect(calls, 1);
    }
  });
  test('CNIC routing fallback remains bounded after timeout', () async {
    var calls = 0;
    await expectLater(
      invokeCnicWithRegionFallback((region) async {
        calls++;
        throw TimeoutException('transport');
      }),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 2);
  });
  test(
    'old valid document does not discard an interrupted replacement draft',
    () {
      final draft = <String, dynamic>{'request_id': 'new-request'};
      expect(
        cnicDraftWasSubmitted({
          'document_valid': true,
          'document_path': 'owner/old-request/cnic.jpg',
        }, draft),
        isFalse,
      );
      expect(
        cnicDraftWasSubmitted({
          'document_valid': true,
          'document_path': 'owner/new-request/cnic.png',
        }, draft),
        isTrue,
      );
      expect(
        cnicDraftWasSubmitted({
          'document_valid': false,
          'document_path': 'owner/new-request/cnic.png',
        }, draft),
        isFalse,
      );
      expect(
        cnicDraftWasSubmitted({
          'document_valid': true,
          'document_path': null,
        }, draft),
        isFalse,
      );
    },
  );
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 32, 24),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 24);
    final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
    png = encoded!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  test(
    'Gallery rejects oversized original before native compression',
    () async {
      final directory = await Directory.systemTemp.createTemp('fr04-size-');
      try {
        final original = File('${directory.path}/original.png');
        final compressed = File('${directory.path}/compressed.png');
        await original.writeAsBytes(Uint8List(5 * 1024 * 1024 + 1));
        await compressed.writeAsBytes(png);
        final images = CnicImageService(
          picker: CompressingPicker(original.path, compressed.path),
        );
        await expectLater(
          images.pick(ImageSource.gallery),
          throwsA(isA<FormatException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test('normalizes exactly 13 digits and standard dashed format', () {
    expect(normalizeCnic('3200012345671'), '3200012345671');
    expect(normalizeCnic('32000-1234567-1'), '3200012345671');
    for (final value in [
      '',
      '123',
      '32000123456712',
      '320001234567X',
      '32000/1234567/1',
      '3200-01234567-1',
      ' 3200012345671',
    ]) {
      expect(() => normalizeCnic(value), throwsFormatException);
    }
    expect(maskCnic('32000-1234567-1'), '3***0-*******-*');
  });
  test(
    'signature and upload size validation cannot accept PDF or excess bytes',
    () {
      expect(cnicImageMime(png), 'image/png');
      expect(
        () => cnicImageMime(Uint8List.fromList('%PDF'.codeUnits)),
        throwsFormatException,
      );
      expect(
        () => cnicImageMime(Uint8List(5 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );
  test('actual image decoder rejects spoof and compresses valid PNG', () async {
    final directory = await Directory.systemTemp.createTemp('fr04-unit-');
    try {
      final valid = File('${directory.path}/valid.png');
      await valid.writeAsBytes(png);
      final result = await CnicImageService().read(valid.path);
      expect(result.mime, 'image/png');
      expect(result.bytes.length, lessThanOrEqualTo(5 * 1024 * 1024));
      final fake = File('${directory.path}/spoof.png');
      final bytes = Uint8List.fromList([
        ...png.take(33),
        ...List.filled(40, 0),
      ]);
      await fake.writeAsBytes(bytes);
      await expectLater(
        CnicImageService().read(fake.path),
        throwsFormatException,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test(
    'camera/gallery selection and replacement reset submission identity',
    () async {
      final images = TestImages(CnicImage(png, 'image/png', 'test-only'));
      final controller = CnicDocumentController(
        backend: TestBackend(),
        images: images,
      );
      await controller.select(ImageSource.camera);
      final first = controller.requestId;
      await controller.select(ImageSource.gallery);
      expect(images.sources, [ImageSource.camera, ImageSource.gallery]);
      expect(controller.requestId, isNot(first));
      controller.onClose();
    },
  );
  test('duplicate submission blocked even during draft save', () async {
    final backend = TestBackend();
    final gate = Completer<void>();
    final controller = CnicDocumentController(backend: backend)
      ..image.value = CnicImage(png, 'image/png', 'test-only');
    final first = controller.submit(
      '3200012345671',
      persistDraft: (_, __, ___) => gate.future,
    );
    expect(await controller.submit('3200012345671'), isFalse);
    expect(backend.calls, 0);
    gate.complete();
    expect(await first, isTrue);
    expect(backend.calls, 1);
    expect(controller.application['verification_status'], 'pending');
    controller.onClose();
  });
  test(
    'valid older document cannot confirm a different upload request',
    () async {
      final backend = TestBackend()..wrongRequest = true;
      final controller = CnicDocumentController(backend: backend)
        ..image.value = CnicImage(png, 'image/png', 'test-only');
      expect(await controller.submit('3200012345671'), isFalse);
      expect(controller.error.value, isNotNull);
      controller.onClose();
    },
  );
  test(
    'safe transport retries preserve id; no simulated completion on missing object',
    () async {
      final backend = TestBackend()..failures = 2;
      final controller = CnicDocumentController(backend: backend)
        ..image.value = CnicImage(png, 'image/png', 'test-only');
      expect(await controller.submit('3200012345671'), isTrue);
      expect(backend.calls, 3);
      expect(backend.ids.toSet().length, 1);
      backend.valid = false;
      expect(await controller.submit('3200012345671'), isFalse);
      expect(controller.error.value, isNotNull);
      controller.onClose();
    },
  );
  test(
    'interrupted status recovery and changed CNIC get a fresh request id',
    () async {
      final backend = TestBackend();
      final controller = CnicDocumentController(backend: backend);
      await controller.loadStatus();
      expect(controller.application['document_valid'], isTrue);
      controller.prepareRequest('3200012345671');
      final first = controller.requestId;
      controller.prepareRequest('3200012345672');
      expect(controller.requestId, isNot(first));
      controller.onClose();
    },
  );
  testWidgets(
    'expired private links are removed and Retry requests a new link',
    (tester) async {
      final backend = TestBackend()
        ..viewUrl = 'https://example.test/private-test-image';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CnicDocumentViewer(backend: backend)),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      await tester.pump(const Duration(seconds: 901));
      expect(find.byType(Image), findsNothing);
      expect(
        find.text('The private viewing link expired. Tap Retry.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(backend.viewCalls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'private viewer handles authorization failure without exposing URL',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CnicDocumentViewer(backend: TestBackend())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Document not available. Retry.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
