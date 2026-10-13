import 'dart:async';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';

class ChatController extends GetxController {
  final _supabase = Supabase.instance.client;

  var messages = <ChatMessage>[].obs;
  var isLoading = true.obs;
  final error = ''.obs;
  final sending = false.obs;
  final hasOlder = false.obs;
  bool _closed = false;
  Timer? _flush;
  final _pending = <ChatMessage>[];

  RealtimeChannel? _subscription;
  int? currentRoomId;
  int? currentUserBigintId; // BIGINT from public.users

  @override
  void onInit() {
    super.onInit();
    _fetchCurrentUserBigintId();
  }

  Future<void> _fetchCurrentUserBigintId() async {
    try {
      final email = _supabase.auth.currentUser?.email;
      if (email == null) return;
      final record = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      if (record != null) {
        currentUserBigintId = record['id'] as int;
      }
    } catch (_) {}
  }

  Future<void> joinRoom(int roomId) async {
    currentRoomId = roomId;
    isLoading.value = true;
    messages.clear();

    try {
      // Real Supabase room.
      if (currentUserBigintId == null) await _fetchCurrentUserBigintId();

      final data = await _supabase
          .from('chat_messages')
          .select('id,room_id,sender_id,message,image_url,created_at,is_read')
          .eq('room_id', roomId)
          .order('id', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 15));

      if (_closed || currentRoomId != roomId) return;
      messages.value = data.reversed
          .map((e) => ChatMessage.fromJson(e))
          .toList();
      hasOlder.value = data.length == 100;
      isLoading.value = false;

      _subscription?.unsubscribe();
      _subscription = _supabase
          .channel('chat_messages:room_id=eq.$roomId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: roomId,
            ),
            callback: (payload) {
              final newMsg = ChatMessage.fromJson(payload.newRecord);
              if (!_closed && currentRoomId == roomId) {
                _pending.add(newMsg);
                _flush ??= Timer(const Duration(milliseconds: 150), () {
                  _flush = null;
                  if (_closed) return;
                  final ids = messages.map((message) => message.id).toSet();
                  messages.addAll(
                    _pending.where((message) => ids.add(message.id)),
                  );
                  _pending.clear();
                });
              }
            },
          )
          .subscribe();
    } catch (_) {
      if (!_closed) error.value = 'Messages could not be loaded. Retry.';
    } finally {
      if (!_closed) isLoading.value = false;
    }
  }

  Future<void> loadOlder() async {
    if (isLoading.value ||
        !hasOlder.value ||
        messages.isEmpty ||
        currentRoomId == null) {
      return;
    }
    isLoading.value = true;
    try {
      final data = await _supabase
          .from('chat_messages')
          .select('id,room_id,sender_id,message,image_url,created_at,is_read')
          .eq('room_id', currentRoomId!)
          .lt('id', messages.first.id)
          .order('id', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 15));
      if (!_closed) {
        messages.insertAll(
          0,
          data.reversed.map((e) => ChatMessage.fromJson(e)),
        );
        hasOlder.value = data.length == 50;
      }
    } catch (_) {
      if (!_closed) error.value = 'Older messages could not be loaded. Retry.';
    } finally {
      if (!_closed) isLoading.value = false;
    }
  }

  Future<bool> sendMessage(String text, {String? imageUrl}) async {
    if (sending.value ||
        currentRoomId == null ||
        text.trim().isEmpty ||
        text.trim().runes.length > 2000) {
      return false;
    }
    sending.value = true;
    error.value = '';
    try {
      if (currentUserBigintId == null) await _fetchCurrentUserBigintId();
      if (currentUserBigintId == null) return false;
      await _supabase
          .from('chat_messages')
          .insert({
            'room_id': currentRoomId,
            'sender_id': currentUserBigintId,
            'message': text.trim(),
          })
          .timeout(const Duration(seconds: 15));
      return true;
    } catch (_) {
      if (!_closed) {
        error.value =
            'Message was not confirmed. Check the conversation before retrying.';
      }
      return false;
    } finally {
      if (!_closed) sending.value = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _flush?.cancel();
    _pending.clear();
    _subscription?.unsubscribe();
    super.onClose();
  }
}
