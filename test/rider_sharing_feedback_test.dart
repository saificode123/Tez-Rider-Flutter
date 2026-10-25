import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/rider_controller.dart';
import 'package:flutter_application_1/core/app_translations.dart';
import 'package:flutter_application_1/core/stage2_ui_strings.dart';
import 'support/closure_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  tearDown(Get.reset);
  test(
    'offline share explains the condition without requesting permission or publishing',
    () async {
      // Construct without onInit: no presence listener or native sensor starts.
      final controller = RiderController();
      controller.currentOrder.value = {
        'type': 'order',
        'id': 7,
        'order_status': 'on_the_way',
      };
      transport.requests.clear();
      await controller.shareDeliveryLocation();
      expect(
        controller.location.message.value,
        'Go online before sharing delivery location.',
      );
      expect(controller.location.sharing.value, false);
      expect(controller.location.busy.value, false);
      expect(transport.requests, isEmpty);
      Get.addTranslations(AppTranslations().keys);
      Get.locale = const Locale('ur', 'PK');
      expect(
        controller.location.message.value.uiMessage,
        'ترسیل کی لوکیشن شیئر کرنے سے پہلے آن لائن ہوں۔',
      );
      await controller.location.stop();
      expect(transport.requests, isEmpty);
    },
  );
}
