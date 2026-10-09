import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_screen.dart';
import '../data/mock_data.dart';

class ChatRoomsScreen extends StatefulWidget {
  const ChatRoomsScreen({super.key});

  @override
  State<ChatRoomsScreen> createState() => _ChatRoomsScreenState();
}

class _ChatRoomsScreenState extends State<ChatRoomsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _enrichedRooms = [];
  bool isLoading = true;
  int? currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    try {
      final email = _supabase.auth.currentUser?.email;
      if (email == null) return;

      final userRes = await _supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      if (userRes == null) return;
      currentUserId = userRes['id'];

      // Query chat_rooms directly — covers all rooms regardless of chat_participants entries
      final directRooms = await _supabase
          .from('chat_rooms')
          .select('id, user1_id, user2_id')
          .or('user1_id.eq.$currentUserId,user2_id.eq.$currentUserId') as List;

      // Also union rooms from chat_participants (fallback for participant-only entries)
      final participantRooms = await _supabase
          .from('chat_participants')
          .select('room_id')
          .eq('user_id', currentUserId!) as List;

      final Set<dynamic> allRoomIds = {
        ...directRooms.map((r) => r['id']),
        ...participantRooms.map((p) => p['room_id']),
      };

      if (allRoomIds.isEmpty) {
        // No real rooms found — show mock conversations so the screen is not blank.
        if (mounted) {
          setState(() {
            _enrichedRooms = MockData.chatRooms;
            isLoading = false;
          });
        }
        return;
      }

      final List<Map<String, dynamic>> enriched = [];
      for (final roomId in allRoomIds) {
        // Resolve other participant from the direct-room record first (fastest)
        int? otherId;
        final directRoom = directRooms.cast<Map<String, dynamic>>()
            .where((r) => r['id'] == roomId)
            .firstOrNull;
        if (directRoom != null) {
          final u1 = directRoom['user1_id'] as int?;
          final u2 = directRoom['user2_id'] as int?;
          otherId = (u1 != currentUserId) ? u1 : u2;
        }

        // Fall back to chat_participants if not resolved
        if (otherId == null) {
          final parts = await _supabase
              .from('chat_participants')
              .select('user_id')
              .eq('room_id', roomId) as List;
          otherId = parts
              .map((p) => p['user_id'] as int?)
              .firstWhere((id) => id != currentUserId, orElse: () => null);
        }

        String otherName = 'Unknown';
        if (otherId != null) {
          final otherUser = await _supabase
              .from('users')
              .select('name')
              .eq('id', otherId)
              .maybeSingle();
          otherName = otherUser?['name'] ?? 'User';
        }

        final msgs = await _supabase
            .from('chat_messages')
            .select('message, created_at')
            .eq('room_id', roomId)
            .order('created_at', ascending: false)
            .limit(1) as List;

        enriched.add({
          'room_id': roomId,
          'other_name': otherName,
          'last_message': msgs.isNotEmpty ? (msgs.first['message'] ?? '') : 'No messages yet',
          'last_time':    msgs.isNotEmpty ? (msgs.first['created_at'] ?? '') : '',
        });
      }

      if (mounted) {
        setState(() {
          _enrichedRooms = enriched;
          isLoading = false;
        });
      }
    } catch (e) {
      // Backend unavailable — fall back to mock conversations.
      if (mounted) {
        setState(() {
          _enrichedRooms = MockData.chatRooms;
          isLoading = false;
        });
      }
    }
  }

  Future<void> _startDisputeWithAdmin() async {
    if (currentUserId == null) return;

    final adminRes = await _supabase
        .from('users')
        .select('id')
        .eq('role', 'admin')
        .maybeSingle();
    if (adminRes == null) {
      Get.snackbar('Error', 'No admin found.');
      return;
    }
    final adminId = adminRes['id'];

    final room = await _supabase.from('chat_rooms').insert({
      'user1_id': currentUserId,
      'user2_id': adminId,
    }).select('id').single();

    await _supabase.from('chat_participants').insert([
      {'room_id': room['id'], 'user_id': currentUserId},
      {'room_id': room['id'], 'user_id': adminId},
    ]);

    Get.to(() => ChatScreen(roomId: room['id'], title: 'Dispute with Admin'));
    _fetchRooms();
  }

  String _formatTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F1F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        title: const Text(
          'Inbox',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                const Text(
                  'Need help? Open a dispute with the Admin or view your active chats below.',
                  style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.gavel_rounded, size: 20),
                    label: const Text(
                      'Open Dispute with Admin',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _startDisputeWithAdmin,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)))
                : _enrichedRooms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            const Text('No active chats.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _enrichedRooms.length,
                        itemBuilder: (context, index) {
                          final room = _enrichedRooms[index];
                          final name = room['other_name'] as String;
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

                          return InkWell(
                            onTap: () {
                              Get.to(() => ChatScreen(
                                    roomId: room['room_id'],
                                    title: name,
                                  ));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Color(0xFF1B5E20),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          room['last_message'],
                                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatTime(room['last_time']),
                                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}