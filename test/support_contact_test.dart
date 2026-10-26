import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/support_contact_service.dart';
import 'package:flutter_application_1/widgets/support_contact_card.dart';

void main() {
  test(
    'server configured public contact is returned without a user identity',
    () async {
      expect(
        await SupportContactService(
          read: () async => {'code': 'OK', 'email': 'support@example.test'},
        ).load(),
        'support@example.test',
      );
    },
  );
  test('missing, malformed or injected contact is rejected', () async {
    for (final value in [null, '', 'not-an-email', 'x\nheader@example.test']) {
      await expectLater(
        SupportContactService(
          read: () async => {'code': 'OK', 'email': value},
        ).load(),
        throwsFormatException,
      );
    }
  });
  testWidgets(
    'public contact Retry reads a new server address and opens a draft only',
    (tester) async {
      var reads = 0;
      Uri? opened;
      final service = SupportContactService(
        read: () async {
          if (++reads == 1) throw StateError('offline');
          return {'code': 'OK', 'email': 'support@example.test'};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportContactCard(
              service: service,
              open: (uri) async {
                opened = uri;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('support@example.test'), findsOneWidget);
      await tester.tap(find.text('Email support'));
      await tester.pumpAndSettle();
      expect(opened, Uri(scheme: 'mailto', path: 'support@example.test'));
      expect(find.textContaining('sent'), findsNothing);
    },
  );
  testWidgets(
    'missing email application keeps copyable contact and truthful failure',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupportContactCard(
              service: SupportContactService(
                read: () async => {
                  'code': 'OK',
                  'email': 'support@example.test',
                },
              ),
              open: (_) async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email support'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No email app opened'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    },
  );
}
