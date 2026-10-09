import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';
import '../data/mock_data.dart';

class ChatController extends GetxController {
  final _supabase = Supabase.instance.client;

  var messages = <ChatMessage>[].obs;
  var isLoading = true.obs;

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

    // Negative room IDs are mock rooms — load static messages, no Supabase call.
    if (roomId < 0) {
      await Future.delayed(const Duration(milliseconds: 350));
      messages.value = MockData.messagesForRoom(roomId, currentUserBigintId ?? 0);
      isLoading.value = false;
      return;
    }

    // Real Supabase room.
    if (currentUserBigintId == null) await _fetchCurrentUserBigintId();

    final data = await _supabase
        .from('chat_messages')
        .select()
        .eq('room_id', roomId)
        .order('created_at', ascending: true);

    messages.value = data.map((e) => ChatMessage.fromJson(e)).toList();
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
            messages.add(newMsg);
          },
        )
        .subscribe();
  }

  Future<void> sendMessage(String text, {String? imageUrl}) async {
    if (currentRoomId == null) return;
    if (text.trim().isEmpty && imageUrl == null) return;

    // Mock room — add message locally without Supabase.
    if (currentRoomId! < 0) {
      final newMsg = ChatMessage(
        id: 9000 + messages.length,
        roomId: currentRoomId!,
        senderId: currentUserBigintId ?? 0,
        message: text.trim(),
        imageUrl: imageUrl,
        createdAt: DateTime.now(),
      );
      messages.add(newMsg);
      return;
    }

    // Real room — persist to Supabase.
    if (currentUserBigintId == null) await _fetchCurrentUserBigintId();
    if (currentUserBigintId == null) return;

    await _supabase.from('chat_messages').insert({
      'room_id': currentRoomId,
      'sender_id': currentUserBigintId,
      'message': text.trim(),
      'image_url': imageUrl,
    });
  }

  @override
  void onClose() {
    _subscription?.unsubscribe();
    super.onClose();
  }
}
