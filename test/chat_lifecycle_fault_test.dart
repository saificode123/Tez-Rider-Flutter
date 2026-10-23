import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/chat_controller.dart';
import 'support/closure_harness.dart';

Map<String, dynamic> message(int id, int room) => {
  'id': id,
  'room_id': room,
  'sender_id': 1,
  'message': 'unit room $room',
  'created_at': '2026-10-23T00:00:00Z',
  'is_read': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    transport.requests.clear();
    transport.respond = (request) async => UiTransport.jsonResponse(
      request.url.path.endsWith('/users')
          ? [
              {'id': 1},
            ]
          : [],
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
  });
  tearDown(() async {
    Get.reset();
    await Supabase.instance.client.removeAllChannels();
  });

  test(
    'late first-room response cannot replace a different room or its subscription',
    () async {
      final first = Completer<http.Response>();
      transport.respond = (request) async {
        if (request.url.path.endsWith('/users')) {
          return UiTransport.jsonResponse([
            {'id': 1},
          ]);
        }
        if (request.url.queryParameters['room_id'] == 'eq.10') {
          return first.future;
        }
        return UiTransport.jsonResponse([message(20, 20)]);
      };
      final controller = Get.put(ChatController());
      expect(
        await Supabase.instance.client.from('users').select('id').maybeSingle(),
        {'id': 1},
      );
      final old = controller.joinRoom(10);
      await Future<void>.delayed(Duration.zero);
      await controller.joinRoom(20);
      first.complete(UiTransport.jsonResponse([message(10, 10)]));
      await old;
      expect(
        controller.error.value,
        isEmpty,
        reason: transport.requests
            .map((r) => '${r.method} ${r.url.path}')
            .join(', '),
      );
      expect(controller.currentRoomId, 20);
      expect(controller.messages.map((row) => row.roomId), [20]);
      expect(Supabase.instance.client.getChannels(), hasLength(1));
    },
  );

  test(
    'batched realtime event from previous room is discarded on room switch',
    () async {
      final controller = Get.put(ChatController());
      await controller.joinRoom(10);
      expect(
        controller.error.value,
        isEmpty,
        reason: transport.requests
            .map((r) => '${r.method} ${r.url.path}')
            .join(', '),
      );
      final channel = Supabase.instance.client.getChannels().single;
      // SDK event injection deliberately emulates a queued transport callback.
      // ignore: invalid_use_of_internal_member
      channel.trigger('INSERT', {
        'schema': 'public',
        'table': 'chat_messages',
        'commit_timestamp': '2026-10-23T00:00:00Z',
        'type': 'INSERT',
        'columns': <Map<String, dynamic>>[],
        'record': message(11, 10),
        'old_record': <String, dynamic>{},
      });
      await controller.joinRoom(20);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(controller.messages, isEmpty);
      expect(controller.currentRoomId, 20);
    },
  );

  test(
    'account switch clears private data and ignores the old pending response',
    () async {
      final pending = Completer<http.Response>();
      transport.respond = (request) async => request.url.path.endsWith('/users')
          ? UiTransport.jsonResponse([
              {'id': 1},
            ])
          : pending.future;
      final controller = Get.put(ChatController());
      final load = controller.joinRoom(10);
      await Future<void>.delayed(Duration.zero);
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode(
          unitSession('00000000-0000-0000-0000-000000000002').toJson(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      pending.complete(UiTransport.jsonResponse([message(1, 10)]));
      await load;
      expect(controller.messages, isEmpty);
      expect(controller.currentRoomId, isNull);
      expect(controller.currentUserBigintId, isNull);
      expect(Supabase.instance.client.getChannels(), isEmpty);
    },
  );

  test(
    'late pagination cannot expose the previous room in a new conversation',
    () async {
      final pending = Completer<http.Response>();
      transport.respond = (request) async {
        if (request.url.path.endsWith('/users')) {
          return UiTransport.jsonResponse([
            {'id': 1},
          ]);
        }
        if (request.url.queryParameters.containsKey('id')) {
          return pending.future;
        }
        return UiTransport.jsonResponse([
          message(
            30,
            int.parse(request.url.queryParameters['room_id']!.substring(3)),
          ),
        ]);
      };
      final controller = Get.put(ChatController());
      await controller.joinRoom(10);
      controller.hasOlder.value = true;
      final older = controller.loadOlder();
      await Future<void>.delayed(Duration.zero);
      await controller.joinRoom(20);
      pending.complete(UiTransport.jsonResponse([message(2, 10)]));
      await older;
      expect(controller.messages.every((row) => row.roomId == 20), isTrue);
    },
  );

  test(
    'denied message mutation never reports a confirmed send and logout removes private channel state',
    () async {
      transport.respond = (request) async {
        if (request.url.path.endsWith('/users')) {
          return UiTransport.jsonResponse([
            {'id': 1},
          ]);
        }
        if (request.method == 'POST') {
          return UiTransport.jsonResponse({
            'code': '42501',
            'message': 'Denied',
          }, 403);
        }
        return UiTransport.jsonResponse([]);
      };
      final controller = Get.put(ChatController());
      await controller.joinRoom(10);
      expect(await controller.sendMessage('unit message'), isFalse);
      expect(controller.error.value, contains('not confirmed'));
      await Supabase.instance.client.auth.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentRoomId, isNull);
      expect(controller.messages, isEmpty);
      expect(Supabase.instance.client.getChannels(), isEmpty);
    },
  );
}
