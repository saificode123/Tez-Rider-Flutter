import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_screen.dart';
import 'customer/dispute_screen.dart';

class ChatRoomsScreen extends StatefulWidget {
  const ChatRoomsScreen({super.key});

  @override
  State<ChatRoomsScreen> createState() => _ChatRoomsScreenState();
}

class _ChatRoomsScreenState extends State<ChatRoomsScreen> {
  final _supabase = Supabase.instance.client;
  final List<Map<String, dynamic>> _enrichedRooms = [];
  bool isLoading = true;
  int? currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  String? _error;
  bool _openingChat = false;
  bool _hasMore = true;
  Future<void> _fetchRooms({bool more = false}) async {
    if (more && isLoading) return;
    if (mounted) {
      setState(() {
        isLoading = true;
        _error = null;
      });
    }
    try {
      final rows = await _supabase
          .rpc(
            'fr25_chat_list',
            params: {
              'p_before': more && _enrichedRooms.isNotEmpty
                  ? _enrichedRooms.last['room_id']
                  : null,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          if (!more) _enrichedRooms.clear();
          _enrichedRooms.addAll(List<Map<String, dynamic>>.from(rows as List));
          _hasMore = rows.length == 30;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Chats could not be loaded. Retry.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _startDisputeWithAdmin() async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    try {
      final room = await _supabase
          .rpc('fr25_support_chat')
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      await Get.to(
        () => ChatScreen(roomId: room as int, title: 'Chat with Admin'),
      );
      await _fetchRooms();
    } catch (_) {
      Get.snackbar('Chat unavailable', 'The chat could not be opened. Retry.');
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
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
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
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
                  'Submit a structured dispute or chat with Admin for help.',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.gavel_rounded, size: 20),
                    label: const Text(
                      'Open Dispute with Admin',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => Get.to(() => const DisputeScreen()),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _openingChat ? null : _startDisputeWithAdmin,
            child: const Text('Chat with Admin'),
          ),
          if (_error != null) Text(_error!),
          if (_error != null)
            TextButton(
              onPressed: () => _fetchRooms(),
              child: const Text('Retry'),
            ),
          if (_hasMore && _enrichedRooms.isNotEmpty)
            TextButton(
              onPressed: isLoading ? null : () => _fetchRooms(more: true),
              child: const Text('Load more chats'),
            ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF1B5E20)),
                  )
                : _enrichedRooms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 60,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No active chats.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _enrichedRooms.length,
                    itemBuilder: (context, index) {
                      final room = _enrichedRooms[index];
                      final name = room['other_name'] as String;
                      final initial = name.isNotEmpty
                          ? name[0].toUpperCase()
                          : '?';

                      return InkWell(
                        onTap: () {
                          Get.to(
                            () => ChatScreen(
                              roomId: room['room_id'],
                              title: name,
                            ),
                          );
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
                                backgroundColor: const Color(
                                  0xFF1B5E20,
                                ).withValues(alpha: 0.12),
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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      room['last_message'],
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatTime(room['last_time']),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
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
