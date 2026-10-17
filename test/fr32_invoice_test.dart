import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/invoice_service.dart';
import 'package:flutter_application_1/widgets/invoice_button.dart';

void main() {
  const base = 'https://igeisilhtmglgnqvllrx.supabase.co';
  test(
    'invoice URL requires owned server response, private bucket and900s',
    () {
      final result = {
        'code': 'READY',
        'expires_in': 900,
        'url':
            '$base/storage/v1/object/sign/invoices/1/2/id.pdf?token=synthetic',
      };
      expect(validateInvoiceUrl(result, base).host, Uri.parse(base).host);
      for (final patch in [
        {'expires_in': 3600},
        {'url': 'https://example.test/invoice.pdf'},
        {'url': '$base/storage/v1/object/public/invoices/a.pdf'},
      ]) {
        expect(
          () => validateInvoiceUrl({...result, ...patch}, base),
          throwsFormatException,
        );
      }
    },
  );
  testWidgets(
    'invoice loading prevents duplicate requests and opens server URL',
    (tester) async {
      final pending = Completer<Uri>();
      var requested = 0;
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvoiceButton(
              orderId: 123,
              load: (id) {
                expect(id, 123);
                requested++;
                return pending.future;
              },
              open: (uri) async {
                opened = uri;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Invoice'));
      await tester.pump();
      expect(find.text('Opening…'), findsOneWidget);
      await tester.tap(find.text('Opening…'));
      expect(requested, 1);
      final uri = Uri.parse(
        '$base/storage/v1/object/sign/invoices/1/123/id.pdf?token=synthetic',
      );
      pending.complete(uri);
      await tester.pumpAndSettle();
      expect(opened, uri);
      expect(find.text('Invoice'), findsOneWidget);
    },
  );
  testWidgets('unready invoice displays failure and permits retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvoiceButton(
            orderId: 123,
            load: (_) async => throw const FormatException(
              'No paid invoice is available yet.',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Invoice'));
    await tester.pumpAndSettle();
    expect(find.text('No paid invoice is available yet.'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });
}
