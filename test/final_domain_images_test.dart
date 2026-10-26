import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The existing image_picker dependency provides this platform testing seam.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:flutter_application_1/services/cnic_document.dart';
import 'package:flutter_application_1/services/dispute_service.dart';

class _Picker extends ImagePickerPlatform {
  String? path;
  ImagePickerOptions? options;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    this.options = options;
    return path == null ? null : XFile(path!);
  }
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff23a67c), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

// A valid ancillary PNG chunk verifies privacy stripping independently of size.
Uint8List _withComment(Uint8List png) {
  final payload = utf8.encode('Comment\u0000synthetic-private-location');
  final typeAndPayload = [...ascii.encode('tEXt'), ...payload];
  var crc = 0xffffffff;
  for (final byte in typeAndPayload) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  final length = ByteData(4)..setUint32(0, payload.length);
  final checksum = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
  return Uint8List.fromList([
    ...png.take(33),
    ...length.buffer.asUint8List(),
    ...typeAndPayload,
    ...checksum.buffer.asUint8List(),
    ...png.skip(33),
  ]);
}

// Synthetic 2x3 JPEG generated locally; contains no personal image data.
Uint8List _jpeg() => base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAADAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD8qqKKKAP/2Q==',
);

Future<void> _dimensions(Uint8List bytes, int width, int height) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  try {
    expect(image.width, width);
    expect(image.height, height);
  } finally {
    image.dispose();
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ImagePickerPlatform platform;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tez-private-images-');
    platform = ImagePickerPlatform.instance;
  });
  tearDown(() async {
    ImagePickerPlatform.instance = platform;
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });
  Future<File> file(Uint8List bytes) async =>
      File('${directory.path}/synthetic-image').writeAsBytes(bytes);

  test(
    'CNIC PNG re-encoding strips ancillary private metadata without losing pixels',
    () async {
      final bytes = _withComment(await _png(37, 29));
      expect(latin1.decode(bytes), contains('synthetic-private-location'));
      final source = await file(bytes);
      final prepared = await CnicImageService().read(source.path);
      expect(
        latin1.decode(prepared.bytes),
        isNot(contains('synthetic-private-location')),
      );
      expect(prepared.sourcePath, source.path);
      expect(prepared.mime, 'image/png');
      await _dimensions(prepared.bytes, 37, 29);
    },
  );

  test(
    'portrait dispute evidence is resized proportionally and metadata removed',
    () async {
      final source = await file(_withComment(await _png(1000, 3000)));
      final prepared = await DisputeImagePicker().read(source.path);
      expect(
        latin1.decode(prepared.bytes),
        isNot(contains('synthetic-private-location')),
      );
      expect(prepared.sourcePath, source.path);
      await _dimensions(prepared.bytes, 533, 1600);
    },
  );

  test(
    'small dispute evidence retains its resolution instead of upscaling',
    () async {
      final source = await file(await _png(21, 33));
      await _dimensions(
        (await DisputeImagePicker().read(source.path)).bytes,
        21,
        33,
      );
    },
  );

  test(
    'CNIC rejects over-limit PNG dimensions before accepting a document',
    () async {
      for (final dimensions in [(2049, 1), (1, 2049)]) {
        final source = await file(await _png(dimensions.$1, dimensions.$2));
        await expectLater(
          CnicImageService().read(source.path),
          throwsFormatException,
        );
      }
      final source = await file(await _png(2048, 1));
      await _dimensions(
        (await CnicImageService().read(source.path)).bytes,
        2048,
        1,
      );
    },
  );

  test(
    'dispute rejects a decoded image exceeding its sixteen-megapixel limit',
    () async {
      final source = await file(await _png(4001, 4000));
      await expectLater(
        DisputeImagePicker().read(source.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Select a smaller image.',
          ),
        ),
      );
    },
  );

  test(
    'JPEG evidence is decoded and converted to PNG while CNIC retains JPEG format',
    () async {
      final bytes = _jpeg();
      final source = await file(bytes);
      final cnic = await CnicImageService().read(source.path);
      expect(cnic.mime, 'image/jpeg');
      expect(cnic.bytes, bytes);
      await _dimensions(cnic.bytes, 2, 3);
      final dispute = await DisputeImagePicker().read(source.path);
      expect(dispute.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      await _dimensions(dispute.bytes, 2, 3);
    },
  );

  test(
    'JPEG signature alone cannot bypass actual decoder validation',
    () async {
      final source = await file(Uint8List.fromList([255, 216, 255, 0, 0, 0]));
      await expectLater(
        CnicImageService().read(source.path),
        throwsFormatException,
      );
      await expectLater(
        DisputeImagePicker().read(source.path),
        throwsFormatException,
      );
    },
  );

  test(
    'picker cancellation creates no evidence and successful selection suppresses metadata',
    () async {
      final picker = _Picker();
      ImagePickerPlatform.instance = picker;
      expect(await DisputeImagePicker().pick(ImageSource.gallery), isNull);
      expect(await CnicImageService().pick(ImageSource.camera), isNull);
      final source = await file(await _png(17, 23));
      picker.path = source.path;
      final evidence = await DisputeImagePicker().pick(ImageSource.gallery);
      expect(evidence, isNotNull);
      expect(picker.options?.requestFullMetadata, isFalse);
      await _dimensions(evidence!.bytes, 17, 23);
      if (!Platform.isAndroid) {
        expect(await CnicImageService().lostSelection(), isNull);
        expect(await DisputeImagePicker().recover(), isNull);
      }
    },
  );

  test(
    'secure evidence drafts preserve request identity and isolate accounts',
    () async {
      final entries = <String, String>{};
      var unavailable = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              if (unavailable) throw PlatformException(code: 'UNAVAILABLE');
              final args = Map<String, dynamic>.from(call.arguments as Map);
              final key = args['key'] as String;
              switch (call.method) {
                case 'write':
                  entries[key] = args['value'] as String;
                  return null;
                case 'read':
                  return entries[key];
                case 'delete':
                  entries.remove(key);
                  return null;
              }
              throw StateError('Unexpected storage operation');
            },
          );
      final cnic = CnicDraftStore();
      final disputes = SecureDisputeDraftStore();
      await cnic.save(
        'OWNER@example.test',
        '3520212345671',
        '/private/source',
        'stable-request',
      );
      expect(
        (await cnic.read('owner@example.test'))?['request_id'],
        'stable-request',
      );
      expect(await cnic.read('other@example.test'), isNull);
      const draft = {
        'request_id': 'dispute-request',
        'order_id': 9,
        'source_paths': ['/evidence'],
      };
      await disputes.save('owner', draft);
      expect(await disputes.read('owner'), draft);
      expect(await disputes.read('other'), isNull);
      await disputes.clear('other');
      expect(await disputes.read('owner'), draft);
      await cnic.clear('owner@example.test');
      expect(await cnic.read('OWNER@example.test'), isNull);
      await disputes.clear('owner');
      expect(await disputes.read('owner'), isNull);
      unavailable = true;
      await expectLater(
        cnic.read('owner@example.test'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        disputes.save('owner', draft),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
