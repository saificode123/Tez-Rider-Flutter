import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/ai_service.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final AIService aiService = Get.put(AIService());
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {
      'isBot': true,
      'text': "Hi! 👋 I'm your TezRider AI Assistant.\n\nAsk me for gift ideas, cake + flower combos, or anything for a special occasion! 🎁"
    }
  ];

  bool _isTyping = false;

  void _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isTyping) return;

    _msgCtrl.clear();
    setState(() {
      _messages.add({'isBot': false, 'text': text});
      _isTyping = true;
    });
    _scrollToBottom();

    final reply = await aiService.getRecommendation(text);
    if (!mounted) return;

    setState(() {
      _isTyping = false;
      _messages.add({'isBot': true, 'text': reply});
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F1F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            const Text('Smart Assistant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Get.back(),
        ),
      ),
      body: Column(
        children: [
          Container(
            height: 50,
            color: Colors.white,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _suggestionChip("Birthday gift for mom"),
                _suggestionChip("Best flowers for anniversary"),
                _suggestionChip("Luxury cake combo"),
              ],
            ),
          ),
          
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isBot = msg['isBot'];

                return Align(
                  alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: isBot ? Colors.white : const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isBot ? const Radius.circular(4) : const Radius.circular(16),
                        bottomRight: isBot ? const Radius.circular(16) : const Radius.circular(4),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))
                      ]
                    ),
                    child: Text(
                      msg['text'],
                      style: TextStyle(color: isBot ? Colors.black87 : Colors.white, fontSize: 14, height: 1.4),
                    ),
                  ),
                );
              },
            ),
          ),
          
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B5E20)),
                    ),
                    const SizedBox(width: 8),
                    Text("AI is typing...", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ),
            
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: "Ask for recommendations...",
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFFF4F4F8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _suggestionChip(String text) {
    return InkWell(
      onTap: () {
        _msgCtrl.text = text;
        _sendMessage();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1B5E20).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1B5E20).withValues(alpha: 0.3)),
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFF1B5E20), fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}