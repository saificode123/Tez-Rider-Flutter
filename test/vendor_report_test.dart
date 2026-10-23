import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/vendor_report_service.dart';
import 'package:flutter_application_1/screens/vendor/vendor_analytics_screen.dart';

Map<String, dynamic> report({int id = 2, bool more = false, int vendor = 10}) =>
    {
      'code': 'OK',
      'vendor_id': vendor,
      'currency': 'PKR',
      'summary': {
        'total_orders': 2,
        'delivered_orders': 1,
        'delivered_sales': 10.25,
        'amounts_requiring_review': 0,
        'status_counts': {'delivered': 1, 'pending': 1},
      },
      'top_products': [
        {'product_id': 8, 'name': 'Unit delivered item', 'quantity': 2},
      ],
      'items': [
        {
          'order_id': id,
          'vendor_order_id': id,
          'delivered': true,
          'subtotal': 10.25,
          'order_status': 'delivered',
          'portion_status': 'delivered',
          'source': 'vendor_order',
          'created_at': '2026-10-23T10:00:00Z',
          'items_require_review': false,
          'items': [
            {
              'id': 1,
              'name': 'Unit delivered item',
              'quantity': 2,
              'unit_price': 5.125,
            },
          ],
          'payment': {
            'state': 'CASH_RECORDED',
            'refunds': [
              {'state': 'PENDING'},
            ],
          },
        },
      ],
      'has_more': more,
      'next_cursor': more ? {'order_id': id, 'vendor_order_id': id} : null,
    };
void main() {
  test(
    'fractional delivered gross and pending refund context are preserved',
    () {
      final r = VendorReport.parse(report());
      expect(r.summary['delivered_sales'], 10.25);
      expect(r.items.single['payment']['refunds'].single['state'], 'PENDING');
      expect(r.cursor, isNull);
    },
  );
  test(
    'unknown, nonfinite, inconsistent and malformed report responses fail closed',
    () {
      for (final v in [
        {...report(), 'code': 'UNKNOWN'},
        {...report(), 'vendor_id': 0},
        {
          ...report(),
          'summary': {...report()['summary'], 'delivered_sales': double.nan},
        },
        {
          ...report(),
          'summary': {...report()['summary'], 'delivered_orders': 3},
        },
        {
          ...report(more: true),
          'next_cursor': {'order_id': 1, 'vendor_order_id': 1},
        },
        {
          ...report(),
          'next_cursor': {'order_id': 2, 'vendor_order_id': 2},
        },
      ]) {
        expect(() => VendorReport.parse(v), throwsFormatException);
      }
    },
  );
  testWidgets(
    'initial failure Retry reads actual report and exposes breakdown',
    (t) async {
      var reads = 0;
      final service = VendorReportService(
        reader: (_) async {
          if (++reads == 1) throw StateError('offline');
          return report();
        },
      );
      await t.pumpWidget(
        MaterialApp(home: VendorAnalyticsBody(service: service)),
      );
      await t.pumpAndSettle();
      expect(find.text('Delivered sales'), findsNothing);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('PKR 10.25'), findsOneWidget);
      await t.ensureVisible(find.text('Order #2'));
      await t.tap(find.text('Order #2'));
      await t.pumpAndSettle();
      expect(find.text('Payment: CASH_RECORDED'), findsOneWidget);
      expect(
        find.textContaining('Whole-order refund: PENDING'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'next-page failure retains rows and Retry uses the confirmed cursor once',
    (t) async {
      var pageReads = 0;
      final pending = Completer<dynamic>();
      final service = VendorReportService(
        reader: (after) async {
          if (after == null) return report(more: true);
          expect(after, {'order_id': 2, 'vendor_order_id': 2});
          pageReads++;
          if (pageReads == 1) throw StateError('offline');
          return pending.future;
        },
      );
      await t.pumpWidget(
        MaterialApp(home: VendorAnalyticsBody(service: service)),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Load more orders'));
      await t.tap(find.text('Load more orders'));
      await t.pumpAndSettle();
      expect(find.text('Order #2'), findsOneWidget);
      await t.ensureVisible(find.text('Retry more orders'));
      await t.tap(find.text('Retry more orders'));
      await t.pump();
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Load more orders'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(report(id: 1));
      await t.pumpAndSettle();
      expect(pageReads, 2);
      expect(find.text('Order #1'), findsOneWidget);
      expect(find.text('Order #2'), findsOneWidget);
      expect(find.text('Load more orders'), findsNothing);
    },
  );
  testWidgets(
    'changed-account page is rejected without appending foreign rows',
    (t) async {
      final service = VendorReportService(
        reader: (after) async =>
            after == null ? report(more: true) : report(id: 1, vendor: 99),
      );
      await t.pumpWidget(
        MaterialApp(home: VendorAnalyticsBody(service: service)),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Load more orders'));
      await t.tap(find.text('Load more orders'));
      await t.pumpAndSettle();
      expect(find.text('Order #1'), findsNothing);
      expect(find.text('Order #2'), findsOneWidget);
      expect(find.text('More orders could not be loaded.'), findsOneWidget);
    },
  );
}
