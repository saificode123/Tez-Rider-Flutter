import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/chat_controller.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final int roomId;
  final String title;

  const ChatScreen({super.key, required this.roomId, required this.title});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController chatCtrl = Get.put(
    ChatController(),
    tag: 'chat-${widget.roomId}',
  );
  late final Worker _messageWorker;
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    chatCtrl.joinRoom(widget.roomId);

    _messageWorker = ever(chatCtrl.messages, (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  Future<void> _sendMessage() async {
    if (_msgCtrl.text.trim().isNotEmpty) {
      if (await chatCtrl.sendMessage(_msgCtrl.text) && mounted) {
        _msgCtrl.clear();
      }
    }
  }

  @override
  void dispose() {
    _messageWorker.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    Get.delete<ChatController>(tag: 'chat-${widget.roomId}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F1F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: Column(
        children: [
          Obx(
            () => chatCtrl.error.value.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    chatCtrl.error.value,
                    style: const TextStyle(color: Colors.red),
                  ),
          ),
          TextButton(
            onPressed: () => chatCtrl.joinRoom(widget.roomId),
            child: const Text('Refresh messages'),
          ),
          Obx(
            () => chatCtrl.hasOlder.value
                ? TextButton(
                    onPressed: chatCtrl.isLoading.value
                        ? null
                        : chatCtrl.loadOlder,
                    child: const Text('Older messages'),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Obx(() {
              if (chatCtrl.isLoading.value) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1B5E20)),
                );
              }
              if (chatCtrl.messages.isEmpty) {
                return const Center(
                  child: Text(
                    "No messages yet. Say hi!",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: chatCtrl.messages.length,
                itemBuilder: (context, index) {
                  final msg = chatCtrl.messages[index];
                  final isMe = msg.senderId == chatCtrl.currentUserBigintId;

                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF1B5E20) : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isMe
                              ? const Radius.circular(16)
                              : const Radius.circular(4),
                          bottomRight: isMe
                              ? const Radius.circular(4)
                              : const Radius.circular(16),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.message,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('hh:mm a').format(msg.createdAt),
                            style: TextStyle(
                              color: isMe
                                  ? Colors.white70
                                  : Colors.grey.shade500,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.attach_file_rounded,
                      color: Colors.grey,
                    ),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Secure attachments are not configured. No file was attached.')),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF4F4F8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1B5E20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
