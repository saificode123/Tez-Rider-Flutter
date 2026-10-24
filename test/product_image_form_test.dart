import 'package:flutter_application_1/services/product_image_service.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/screens/vendor/product_form_screen.dart';
import 'support/closure_harness.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGD4DwAChAGA+gVWHQAAAABJRU5ErkJggg==';
const ref = 'tezproduct:11111111-2222-4333-8444-555555555555';

class MemoryPickedImage extends XFile {
  MemoryPickedImage() : super('unit.png');
  @override
  Future<Uint8List> readAsBytes() async => base64Decode(pixel);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  final imageCalls = <Map<String, dynamic>>[];
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    transport.requests.clear();
    imageCalls.clear();
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
  });
  tearDown(Get.reset);
  Future<void> show(
    WidgetTester t, {
    bool failUpload = false,
    bool failProductOnce = false,
    bool failUploadOnce = false,
    Completer<dynamic>? pending,
  }) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var productCalls = 0;
    transport.respond = (r) async {
      if (r.url.path.endsWith('/categories')) {
        return UiTransport.jsonResponse([
          {'name': 'Food'},
        ]);
      }
      if (r.url.path.endsWith('/fr17_save_product')) {
        productCalls++;
        if (failProductOnce && productCalls == 1) {
          throw TimeoutException('injected uncertain product save');
        }
        return UiTransport.jsonResponse({
          'code': 'UPDATED',
          'product_id': 7,
          'stock_version': 1,
        });
      }
      return UiTransport.jsonResponse([]);
    };
    await t.pumpWidget(
      GetMaterialApp(
        home: ProductFormScreen(
          vendorId: 10,
          imagePicker: () async => MemoryPickedImage(),
          imageService: ProductImageService(
            identity: () => Supabase.instance.client.auth.currentUser?.id,
            call: (body) async {
              imageCalls.add(body);
              if (failUploadOnce && imageCalls.length == 1) {
                throw TimeoutException('injected uncertain image upload');
              }
              if (pending != null) return pending.future;
              if (failUpload) {
                throw const FunctionException(
                  status: 422,
                  details: {'error': 'Injected invalid contents'},
                );
              }
              return {'reference': ref};
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final entry in {
      'Product Name': 'Unit image product',
      'Price (PKR)': '12.25',
      'Confirmed stock quantity': '2',
    }.entries) {
      final field = find.widgetWithText(TextField, entry.key);
      await t.ensureVisible(field);
      await t.enterText(field, entry.value);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    final pick = find.text('Choose Product Image');
    await t.ensureVisible(pick);
    await t.pumpAndSettle();
    await t.tap(pick);
    await t.pumpAndSettle();
  }

  testWidgets(
    'actual form picker and Save upload bytes before attaching confirmed reference',
    (t) async {
      await show(t);
      expect(find.textContaining('Selected image: '), findsOneWidget);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final calls = transport.requests
          .where(
            (r) =>
                r.url.path.endsWith('/final2-product-image') ||
                r.url.path.endsWith('/fr17_save_product'),
          )
          .toList();
      expect(calls.length, 1);
      expect(imageCalls.single['image_base64'], pixel);
      final save = jsonDecode(calls.last.body);
      expect(save['p_data']['image_url'], ref);
      expect(save['p_data']['price'], 12.25);
      expect(save['p_stock'], 2);
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed upload never sends product mutation or shows a saved result',
    (t) async {
      await show(t, failUpload: true);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(
        transport.requests.where(
          (r) => r.url.path.endsWith('/fr17_save_product'),
        ),
        isEmpty,
      );
      expect(find.text('Save not confirmed'), findsOneWidget);
      expect(find.text('Product and stock saved successfully.'), findsNothing);
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'remove selected image clears pending selection before actual Save',
    (t) async {
      await show(t);
      final remove = find.text('Remove product image');
      await t.ensureVisible(remove);
      await t.pumpAndSettle();
      await t.tap(remove);
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(imageCalls, isEmpty);
      final save = transport.requests.singleWhere(
        (r) => r.url.path.endsWith('/fr17_save_product'),
      );
      expect(jsonDecode(save.body)['p_data']['image_url'], '');
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'account switch during image upload clears form and cannot create a new-account product',
    (t) async {
      final pending = Completer<dynamic>();
      await show(t, pending: pending);
      await t.tap(find.text('Save'));
      await t.pump();
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(
          unitSession('00000000-0000-0000-0000-000000000002').toJson(),
        ),
      );
      await t.pump();
      expect(
        find.text('Account changed. Open the product again.'),
        findsOneWidget,
      );
      pending.complete({'reference': ref});
      await t.pumpAndSettle();
      expect(
        transport.requests.where(
          (r) => r.url.path.endsWith('/fr17_save_product'),
        ),
        isEmpty,
      );
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'uncertain product save locks original fields/image and Retry reuses one upload and exact inventory request',
    (t) async {
      await show(t, failProductOnce: true);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(imageCalls.length, 1);
      expect(
        find.text(
          'Product save is unconfirmed. Retry Save with the same values.',
        ),
        findsOneWidget,
      );
      expect(
        t
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == false),
        isTrue,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Change Product Image'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Remove product image'),
            )
            .onPressed,
        isNull,
      );
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final saves = transport.requests
          .where((r) => r.url.path.endsWith('/fr17_save_product'))
          .toList();
      expect(saves.length, 2);
      expect(jsonDecode(saves[0].body), jsonDecode(saves[1].body));
      expect(imageCalls.length, 1);
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'uncertain upload locks image replacement/removal and actual Save retry submits identical bytes/UUID',
    (t) async {
      await show(t, failUploadOnce: true);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Image upload is unconfirmed. Retry Save with the selected image.',
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Change Product Image'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Remove product image'),
            )
            .onPressed,
        isNull,
      );
      expect(
        transport.requests.where(
          (r) => r.url.path.endsWith('/fr17_save_product'),
        ),
        isEmpty,
      );
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(imageCalls.length, 2);
      expect(imageCalls[0], imageCalls[1]);
      expect(
        transport.requests
            .where((r) => r.url.path.endsWith('/fr17_save_product'))
            .length,
        1,
      );
      if (Get.isSnackbarOpen) {
        final closing = Get.closeCurrentSnackbar();
        await t.pumpAndSettle();
        await closing;
      }
      await t.pumpWidget(const SizedBox());
    },
  );
}
