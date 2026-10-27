import '../../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../chat_rooms_screen.dart';
import '../../widgets/support_contact_card.dart';

const _kPurple = AppColors.primaryDark;
const _kBg = AppColors.bgLight;
const _kCard = Color(0xFFFFFFFF);
const _kText = AppColors.textPrimary;
const _kTextSub = AppColors.textSecondary;

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  String _query = '';

  final List<Map<String, dynamic>> _faqs = [
    {
      'q': 'How do I track my order?',
      'a':
          'Go to the Orders tab and tap on your active order. You\'ll see the live status and rider location on the map.',
      'icon': '📦',
    },
    {
      'q': 'Can I cancel my order?',
      'a':
          'Open Order details to check the actions currently available for that order. Cancellation is confirmed only after the server accepts it.',
      'icon': '❌',
    },
    {
      'q': 'How do I add a new delivery address?',
      'a':
          'Go to Profile → Saved Addresses → tap the + button to add a new address.',
      'icon': '📍',
    },
    {
      'q': 'What payment methods are accepted?',
      'a':
          'Only Cash on Delivery is currently available. Online payments are not configured.',
      'icon': '💳',
    },
    {
      'q': 'How do I contact my rider?',
      'a':
          'Once your order is on the way, you\'ll see a "Call Rider" button in the order tracking screen.',
      'icon': '📞',
    },
    {
      'q': 'What if my order arrives late?',
      'a':
          'Review the latest tracking status and contact an existing order participant through Inbox when a conversation is available.',
      'icon': '⏰',
    },
    {
      'q': 'Can I change my delivery address after ordering?',
      'a':
          'The delivery address cannot be edited after placing an order. Check Order details for the available cancellation actions before placing a corrected order.',
      'icon': '🔄',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredFaqs {
    if (_query.isEmpty) return _faqs;
    final q = _query.toLowerCase();
    return _faqs
        .where(
          (f) =>
              (f['q'] as String).toLowerCase().contains(q) ||
              (f['a'] as String).toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPurple,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help Center',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'FAQ'),
            Tab(text: 'Contact Us'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_faqTab(), _contactTab()],
      ),
    );
  }

  Widget _faqTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _kPurple.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search FAQs...',
                hintStyle: TextStyle(color: _kTextSub, fontSize: 13),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _kPurple.withValues(alpha: 0.5),
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),

        Expanded(
          child: _filteredFaqs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🔍', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      Text(
                        'No results for "$_query"',
                        style: TextStyle(color: _kTextSub),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: _filteredFaqs.length,
                  itemBuilder: (_, i) => _buildFaqTile(_filteredFaqs[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildFaqTile(Map<String, dynamic> faq) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Text(
            faq['icon'] as String,
            style: const TextStyle(fontSize: 22),
          ),
          title: Text(
            faq['q'] as String,
            style: const TextStyle(
              color: _kText,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          iconColor: _kPurple,
          collapsedIconColor: _kTextSub,
          children: [
            Text(
              faq['a'] as String,
              style: TextStyle(color: _kTextSub, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        _contactCard(
          emoji: '💬',
          title: 'Existing chats',
          sub: 'Open conversations associated with your orders.',
          color: _kPurple,
          label: 'Inbox',
          onTap: () => Get.to(() => const ChatRoomsScreen()),
        ),
        const SizedBox(height: 16),
        const SupportContactCard(),
      ],
    );
  }

  Widget _contactCard({
    required String emoji,
    required String title,
    required String sub,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _kText,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: TextStyle(color: _kTextSub, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
