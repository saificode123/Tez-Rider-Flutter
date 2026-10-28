import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/admin_broadcast_service.dart';
import 'package:flutter_application_1/services/admin_dispute_service.dart';
import 'package:flutter_application_1/services/cart_persistence.dart';
import 'package:flutter_application_1/services/cnic_document.dart';
import 'package:flutter_application_1/services/dispute_service.dart';
import 'package:flutter_application_1/services/ai_service.dart';
import 'package:flutter_application_1/services/invoice_service.dart';
import 'support/closure_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UiTransport transport;

  setUp(() async {
    transport = UiTransport();
    await initializeClosureClient(transport);
  });
  tearDown(() async => Supabase.instance.dispose());

  test(
    'dispute read transport preserves pagination and selected case',
    () async {
      final backend = SupabaseDisputeBackend();
      final results = <Object>[
        {
          'reasons': ['Missing item'],
        },
        [
          {'id': 7},
        ],
        [
          {'id': 8},
        ],
        {'id': 9},
      ];
      transport.respond = (_) async =>
          UiTransport.jsonResponse(results.removeAt(0));
      expect((await backend.options())['reasons'], ['Missing item']);
      expect((await backend.eligible(before: 20)).single['id'], 7);
      expect((await backend.history(before: 15)).single['id'], 8);
      expect((await backend.detail(9))['id'], 9);
      expect(transport.requests.map((r) => r.url.path), [
        '/rest/v1/rpc/fr25_options',
        '/rest/v1/rpc/fr25_eligible_orders',
        '/rest/v1/rpc/fr25_history',
        '/rest/v1/rpc/fr25_detail',
      ]);
      expect(jsonDecode(transport.requests[1].body), {'p_before': 20});
      expect(jsonDecode(transport.requests[2].body), {'p_before': 15});
      expect(jsonDecode(transport.requests[3].body), {'p_id': 9});
    },
  );

  test(
    'dispute retry identity and evidence ownership travel in server requests',
    () async {
      final backend = SupabaseDisputeBackend();
      transport.respond = (request) async {
        if (request.url.path.endsWith('fr25_prepare')) {
          return UiTransport.jsonResponse(null);
        }
        if (request.url.path.endsWith('create_dispute')) {
          return UiTransport.jsonResponse({'id': 11});
        }
        if (request.url.path.endsWith('fr25_request_status')) {
          return UiTransport.jsonResponse({'id': 11});
        }
        final body = jsonDecode(request.body) as Map;
        return UiTransport.jsonResponse(
          body['action'] == 'upload' ? {'path': 'owner/request/image.png'} : {},
        );
      };
      await backend.prepare('request', 7);
      expect(
        await backend.upload(
          'request',
          DisputeImage(Uint8List.fromList([1, 2]), 'source'),
        ),
        'owner/request/image.png',
      );
      expect(
        (await backend.submit('request', 7, 'Missing item', 'One missing', [
          'owner/request/image.png',
        ]))['id'],
        11,
      );
      expect((await backend.lookup('request'))?['id'], 11);
      await backend.cleanup('request');
      final bodies = transport.requests
          .map((r) => jsonDecode(r.body) as Map)
          .toList();
      expect(bodies[0], {'p_request_id': 'request', 'p_order_id': 7});
      expect(bodies[1], {
        'action': 'upload',
        'request_id': 'request',
        'mime_type': 'image/png',
        'image_base64': 'AQI=',
      });
      expect(bodies[2], {
        'p_request_id': 'request',
        'p_order_id': 7,
        'p_reason': 'Missing item',
        'p_description': 'One missing',
        'p_evidence_paths': ['owner/request/image.png'],
      });
      expect(bodies[3], {'p_request_id': 'request'});
      expect(bodies[4], {'action': 'cleanup', 'request_id': 'request'});
    },
  );

  test(
    'dispute lookup absence and evidence viewing require confirmed lifetime',
    () async {
      final backend = SupabaseDisputeBackend();
      transport.respond = (_) async => UiTransport.jsonResponse(null);
      expect(await backend.lookup('not-saved'), isNull);
      transport.respond = (_) async => UiTransport.jsonResponse({
        'url': 'https://example.test/private',
        'expires_in': 900,
      });
      expect(await backend.signedUrl(11, 2), 'https://example.test/private');
      expect(jsonDecode(transport.requests.last.body), {
        'action': 'view',
        'dispute_id': 11,
        'index': 2,
      });
      transport.respond = (_) async => UiTransport.jsonResponse({
        'url': 'https://example.test/private',
        'expires_in': 3600,
      });
      await expectLater(backend.signedUrl(11, 2), throwsFormatException);
    },
  );

  test(
    'dispute server denials and uncertain failures never become confirmed uploads',
    () async {
      final backend = SupabaseDisputeBackend();
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'error': 'Evidence denied'}, 403);
      await expectLater(
        backend.cleanup('request'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Evidence denied',
          ),
        ),
      );
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'error': 'Internal failure'}, 503);
      await expectLater(backend.cleanup('request'), throwsA(isA<Exception>()));
      transport.respond = (_) async => UiTransport.jsonResponse([], 200);
      await expectLater(backend.cleanup('request'), throwsFormatException);
    },
  );

  test(
    'admin dispute queue uses stable two-part cursor and server decisions',
    () async {
      final backend = SupabaseAdminDisputeBackend();
      transport.respond = (request) async => UiTransport.jsonResponse(
        request.url.path.endsWith('fr26_queue') ||
                request.url.path.endsWith('fr26_vendors')
            ? [
                {'id': 4},
              ]
            : {'id': 4},
      );
      expect((await backend.options())['id'], 4);
      expect(
        (await backend.queue(
          status: 'OPEN',
          before: {'id': 8, 'created_at': '2026-10-26T10:00:00Z'},
        )).single['id'],
        4,
      );
      expect((await backend.detail(4))['id'], 4);
      expect((await backend.vendors(4, before: 9)).single['id'], 4);
      expect(
        (await backend.decide(4, 'REJECT', '  Evidence insufficient  '))['id'],
        4,
      );
      expect(jsonDecode(transport.requests[1].body), {
        'p_status': 'OPEN',
        'p_before_at': '2026-10-26T10:00:00Z',
        'p_before_id': 8,
        'p_limit': 30,
      });
      expect(jsonDecode(transport.requests[3].body), {
        'p_id': 4,
        'p_before': 9,
      });
      expect(jsonDecode(transport.requests.last.body), {
        'p_dispute_id': 4,
        'p_decision': 'REJECT',
        'p_note': 'Evidence insufficient',
      });
    },
  );

  test(
    'broadcast estimate, history and idempotent send use real response data',
    () async {
      final backend = SupabaseAdminBroadcastBackend();
      transport.respond = (request) async {
        if (request.url.path.endsWith('fr30_estimate')) {
          return UiTransport.jsonResponse(13);
        }
        if (request.url.path.endsWith('admin_broadcasts')) {
          return UiTransport.jsonResponse([
            {'id': 'broadcast'},
          ]);
        }
        return UiTransport.jsonResponse({
          'code': 'ALREADY_SENT',
          'recipient_count': 13,
        });
      };
      expect(await backend.estimate('RIDERS'), 13);
      expect((await backend.history(null)).single['id'], 'broadcast');
      final request = {
        'p_request_id': 'request',
        'p_audience': 'RIDERS',
        'p_title': 'Notice',
        'p_message': 'Message',
      };
      expect((await backend.send(request))['code'], 'ALREADY_SENT');
      expect(jsonDecode(transport.requests.first.body), {
        'p_audience': 'RIDERS',
      });
      expect(jsonDecode(transport.requests.last.body), request);
      expect(transport.requests[1].url.queryParameters['limit'], '25');
      expect(
        transport.requests[1].url.queryParameters['order'],
        'created_at.desc.nullslast,id.desc.nullslast',
      );
    },
  );

  test(
    'broadcast cursor rejects filter injection before any HTTP read',
    () async {
      final backend = SupabaseAdminBroadcastBackend();
      await expectLater(
        backend.history({
          'id': 'id),or(status.eq.secret)',
          'created_at': '2026-10-26T10:00:00Z',
        }),
        throwsStateError,
      );
      expect(transport.requests, isEmpty);
      transport.respond = (_) async => UiTransport.jsonResponse([]);
      await backend.history({
        'id': '00000000-0000-4000-8000-000000000001',
        'created_at': '2026-10-26T15:00:00+05:00',
      });
      final filter = transport.requests.single.url.queryParameters['or']!;
      expect(filter, contains('2026-10-26T10:00:00.000Z'));
      expect(filter, contains('id.lt.00000000-0000-4000-8000-000000000001'));
    },
  );

  test(
    'CNIC submission requires explicit server persistence confirmation',
    () async {
      final backend = SupabaseCnicBackend();
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'document_valid': true});
      expect((await backend.status())['document_valid'], isTrue);
      final image = CnicImage(
        Uint8List.fromList([1, 2]),
        'image/png',
        'source',
      );
      await expectLater(
        backend.upload(image, '3520212345671', 'request'),
        throwsFormatException,
      );
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'submission_status': 'submitted'});
      await backend.upload(image, '3520212345671', 'request');
      expect(jsonDecode(transport.requests.last.body), {
        'action': 'upload',
        'cnic': '3520212345671',
        'request_id': 'request',
        'mime_type': 'image/png',
        'image_base64': 'AQI=',
      });
    },
  );

  test('CNIC viewer rejects foreign buckets and unexpected expiry', () async {
    final backend = SupabaseCnicBackend();
    const base = 'https://igeisilhtmglgnqvllrx.supabase.co';
    for (final response in [
      {'url': 'https://attacker.example/document', 'expires_in': 900},
      {
        'url': '$base/storage/v1/object/sign/rider-cnic/file',
        'expires_in': 3600,
      },
      {'url': '$base/storage/v1/object/sign/public/file', 'expires_in': 900},
    ]) {
      transport.respond = (_) async => UiTransport.jsonResponse(response);
      await expectLater(backend.signedUrl(userId: '27'), throwsFormatException);
    }
    transport.respond = (_) async => UiTransport.jsonResponse({
      'url': '$base/storage/v1/object/sign/rider-cnic/file',
      'expires_in': 900,
    });
    expect(
      await backend.signedUrl(userId: '27'),
      '$base/storage/v1/object/sign/rider-cnic/file',
    );
    expect(jsonDecode(transport.requests.last.body), {
      'action': 'view',
      'user_id': '27',
    });
    transport.respond = (_) async =>
        UiTransport.jsonResponse({'error': 'Access denied'}, 403);
    await expectLater(
      backend.signedUrl(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Access denied',
        ),
      ),
    );
  });

  test(
    'assistant server errors stay private and rate limits stay actionable',
    () async {
      final service = AIService();
      transport.respond = (_) async => UiTransport.jsonResponse({
        'code': 'OK',
        'text': 'Compare verified products.',
      });
      expect(
        await service.getRecommendation('  Recommend a meal  '),
        'Compare verified products.',
      );
      expect(jsonDecode(transport.requests.last.body), {
        'prompt': 'Recommend a meal',
        'history': [],
      });
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'error': 'private provider detail'}, 429);
      expect(
        await service.getRecommendation('Question'),
        contains('Too many requests'),
      );
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'error': 'private provider detail'}, 500);
      expect(
        await service.getRecommendation('Question'),
        'The assistant is unavailable. Please try again later.',
      );
      transport.respond = (_) async => UiTransport.jsonResponse([], 200);
      expect(
        await service.getRecommendation('Question'),
        'The assistant is unavailable. Please try again later.',
      );
    },
  );

  test(
    'unpaid invoice response never produces a downloadable paid invoice',
    () async {
      final service = InvoiceService();
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'error': 'unpaid'}, 409);
      await expectLater(
        service.signedUrl(17),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Uncollected COD'),
          ),
        ),
      );
      expect(jsonDecode(transport.requests.last.body), {'order_id': 17});
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'error': 'private detail'}, 403);
      await expectLater(
        service.signedUrl(17),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invoice access was not confirmed. Retry.',
          ),
        ),
      );
    },
  );

  test(
    'cart transport retains revision and request identity with confirmed price',
    () async {
      final persistence = SupabaseCartPersistence();
      transport.respond = (_) async => UiTransport.jsonResponse({
        'code': 'OK',
        'revision': 5,
        'items': [
          {'product_id': 7, 'qty': 2, 'price': 125.5},
        ],
      });
      expect((await persistence.load()).items.single['price'], 125.5);
      final saved = await persistence.replace(4, 'stable-request', [
        {'product_id': 7, 'qty': 2},
      ]);
      expect(saved.revision, 5);
      expect(jsonDecode(transport.requests.last.body), {
        'p_revision': 4,
        'p_request_id': 'stable-request',
        'p_items': [
          {'product_id': 7, 'qty': 2},
        ],
      });
      transport.respond = (_) async =>
          UiTransport.jsonResponse({'code': '42501', 'message': 'denied'}, 403);
      await expectLater(
        persistence.replace(4, 'stable-request', []),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}
