import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/private_photo_service.dart';
import 'package:flutter_application_1/widgets/private_photo_editor.dart';
import 'package:flutter_application_1/widgets/rider_identity_card.dart';

const ref = 'tezphoto:11111111-2222-4333-8444-555555555555';
const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGD4DwAChAGA+gVWHQAAAABJRU5ErkJggg==';
Map<String, dynamic> context({String status = 'on_the_way', Map? rider}) => {
  'order_id': 7,
  'order_status': status,
  'rider': rider,
};
void main() {
  testWidgets('legacy status never invents earlier completed milestones', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderIdentityCard(
            orderId: 7,
            identity: () => 'c',
            read: (_) async => context(
              status: 'delivered',
              rider: {
                'name': 'Legacy Rider',
                'rating_count': 0,
                'rating': null,
                'cnic_masked': null,
              },
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.text('CNIC unavailable in this record.'), findsOneWidget);
    final label = t.widget<Text>(find.text('Placed'));
    expect(label.style?.color, const Color(0xFF263238));
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'delivery photo retry keeps original request and has no delivery success',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      var picks = 0;
      final service = PrivatePhotoService(
        kind: 'delivery',
        orderId: 7,
        identity: () => 'r',
        call: (body) async {
          if (body['action'] == 'view') {
            return {
              'image_base64': pixel,
              'mime_type': 'image/png',
              'expires_in': 10,
            };
          }
          calls.add(body);
          if (calls.length == 1) throw TimeoutException('lost response');
          return {'reference': ref};
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivatePhotoEditor(
              orderId: 7,
              service: service,
              pick: (_) async {
                picks++;
                return base64Decode(pixel);
              },
            ),
          ),
        ),
      );
      await t.tap(find.text('Choose delivery photo'));
      await t.pumpAndSettle();
      expect(find.text('Photo was not confirmed. Retry.'), findsOneWidget);
      expect(find.text('Photo saved.'), findsNothing);
      await t.tap(find.text('Retry original photo'));
      await t.pumpAndSettle();
      expect(calls.length, 2);
      expect(calls[0], calls[1]);
      expect(picks, 1);
      expect(calls.last['kind'], 'delivery');
      expect(calls.last['order_id'], 7);
      expect(find.text('Photo saved.'), findsOneWidget);
      expect(find.text('Delivery Complete!'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'cancelled picker never uploads; account switch removes pending photo',
    (t) async {
      String? account = 'a';
      final auth = StreamController<void>.broadcast(sync: true);
      var calls = 0;
      final service = PrivatePhotoService(
        identity: () => account,
        call: (_) async {
          calls++;
          throw TimeoutException('fail');
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivatePhotoEditor(
              service: service,
              accountChanges: auth.stream,
              pick: (_) async => null,
            ),
          ),
        ),
      );
      await t.tap(find.text('Choose profile photo'));
      await t.pumpAndSettle();
      expect(calls, 0);
      account = 'b';
      auth.add(null);
      await t.pump();
      expect(find.text('Choose profile photo'), findsNothing);
      expect(
        find.text('Account changed. Open this photo again.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await auth.close();
    },
  );
  testWidgets(
    'actual identity card displays approved rating masked CNIC and current status',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RiderIdentityCard(
              orderId: 7,
              identity: () => 'c',
              read: (_) async => context(
                rider: {
                  'name': 'Assigned Rider',
                  'photo': null,
                  'rating': 4.25,
                  'rating_count': 8,
                  'verification_status': 'approved',
                  'cnic_masked': '1***5-*******-*',
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Assigned Rider'), findsOneWidget);
      expect(find.text('Rating 4.25 / 5 (8)'), findsOneWidget);
      expect(find.text('CNIC: 1***5-*******-*'), findsOneWidget);
      expect(find.text('Order status: on the way'), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'identity failure Retry and reassignment clear old data; account switch cannot expose it',
    (t) async {
      var calls = 0;
      String? account = 'c';
      final auth = StreamController<void>.broadcast(sync: true);
      void Function()? update;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RiderIdentityCard(
              orderId: 7,
              identity: () => account,
              accountChanges: auth.stream,
              watch: (_, changed) {
                update = changed;
                return () {};
              },
              read: (_) async {
                if (++calls == 1) throw TimeoutException('offline');
                return context(status: calls == 2 ? 'ready' : 'cancelled');
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Retry rider identity'));
      await t.pumpAndSettle();
      expect(
        find.text('A verified Rider has not been assigned.'),
        findsOneWidget,
      );
      expect(find.text('Order status: ready'), findsOneWidget);
      update!();
      await t.pumpAndSettle();
      expect(find.text('Order cancelled.'), findsOneWidget);
      account = 'other';
      auth.add(null);
      await t.pumpAndSettle();
      expect(find.text('Order cancelled.'), findsNothing);
      expect(calls, 3);
      await t.pumpWidget(const SizedBox());
      await auth.close();
    },
  );
  testWidgets('unmasked identity data is rejected before rendering', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RiderIdentityCard(
            orderId: 7,
            identity: () => 'c',
            read: (_) async => context(
              rider: {
                'name': 'Unsafe',
                'rating_count': 0,
                'rating': null,
                'cnic_masked': '12345-1234567-1',
              },
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Unsafe'), findsNothing);
    expect(find.textContaining('12345'), findsNothing);
    expect(find.text('Retry rider identity'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
