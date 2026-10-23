import 'dart:async';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';

class ChatController extends GetxController {
  ChatController({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;
  final SupabaseClient _supabase;
  StreamSubscription<AuthState>? _auth;
  String? _account;
  int _generation = 0;

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
    _account = _supabase.auth.currentUser?.id;
    _auth = _supabase.auth.onAuthStateChange.listen((_) {
      final account = _supabase.auth.currentUser?.id;
      if (account != _account) {
        _account = account;
        _clearRoom();
        currentUserBigintId = null;
      }
    });
    _fetchCurrentUserBigintId();
  }

  void _clearRoom() {
    _generation++;
    currentRoomId = null;
    _flush?.cancel();
    _flush = null;
    _pending.clear();
    messages.clear();
    hasOlder.value = false;
    sending.value = false;
    isLoading.value = false;
    error.value = '';
    final old = _subscription;
    _subscription = null;
    if (old != null) unawaited(_removeChannel(old));
  }

  Future<void> _removeChannel(RealtimeChannel channel) async {
    try {
      await _supabase.removeChannel(channel);
    } catch (_) {}
  }

  Future<void> _fetchCurrentUserBigintId() async {
    try {
      final account = _supabase.auth.currentUser?.id;
      final generation = _generation;
      if (account == null) return;
      final record = await _supabase
          .from('users')
          .select('id')
          .eq('auth_user_id', account)
          .maybeSingle();
      if (!_closed &&
          generation == _generation &&
          account == _supabase.auth.currentUser?.id &&
          record != null) {
        currentUserBigintId = record['id'] as int;
      }
    } catch (_) {}
  }

  Future<void> joinRoom(int roomId) async {
    _clearRoom();
    final generation = _generation;
    final account = _supabase.auth.currentUser?.id;
    if (account == null) {
      error.value = 'Sign in to view messages.';
      return;
    }
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

      if (_closed ||
          generation != _generation ||
          account != _supabase.auth.currentUser?.id ||
          currentRoomId != roomId) {
        return;
      }
      messages.value = data.reversed
          .map((e) => ChatMessage.fromJson(e))
          .toList();
      hasOlder.value = data.length == 100;
      isLoading.value = false;

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
              if (!_closed &&
                  generation == _generation &&
                  account == _supabase.auth.currentUser?.id &&
                  currentRoomId == roomId) {
                final newMsg = ChatMessage.fromJson(payload.newRecord);
                _pending.add(newMsg);
                _flush ??= Timer(const Duration(milliseconds: 150), () {
                  _flush = null;
                  if (_closed ||
                      generation != _generation ||
                      account != _supabase.auth.currentUser?.id) {
                    return;
                  }
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
      if (!_closed && generation == _generation) {
        error.value = 'Messages could not be loaded. Retry.';
      }
    } finally {
      if (!_closed && generation == _generation) isLoading.value = false;
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
    final generation = _generation;
    final room = currentRoomId;
    try {
      final data = await _supabase
          .from('chat_messages')
          .select('id,room_id,sender_id,message,image_url,created_at,is_read')
          .eq('room_id', room!)
          .lt('id', messages.first.id)
          .order('id', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 15));
      if (!_closed && generation == _generation) {
        messages.insertAll(
          0,
          data.reversed.map((e) => ChatMessage.fromJson(e)),
        );
        hasOlder.value = data.length == 50;
      }
    } catch (_) {
      if (!_closed && generation == _generation) {
        error.value = 'Older messages could not be loaded. Retry.';
      }
    } finally {
      if (!_closed && generation == _generation) isLoading.value = false;
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
    final generation = _generation;
    final room = currentRoomId;
    final account = _supabase.auth.currentUser?.id;
    error.value = '';
    try {
      if (currentUserBigintId == null) await _fetchCurrentUserBigintId();
      if (currentUserBigintId == null ||
          _closed ||
          generation != _generation ||
          account != _supabase.auth.currentUser?.id) {
        return false;
      }
      await _supabase
          .from('chat_messages')
          .insert({
            'room_id': room,
            'sender_id': currentUserBigintId,
            'message': text.trim(),
          })
          .timeout(const Duration(seconds: 15));
      return !_closed &&
          generation == _generation &&
          account == _supabase.auth.currentUser?.id;
    } catch (_) {
      if (!_closed && generation == _generation) {
        error.value =
            'Message was not confirmed. Check the conversation before retrying.';
      }
      return false;
    } finally {
      if (!_closed && generation == _generation) sending.value = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _clearRoom();
    unawaited(_auth?.cancel());
    super.onClose();
  }
}
