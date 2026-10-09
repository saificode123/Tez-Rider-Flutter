import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _kPurple  = Color(0xFF1B5E20);
const _kBg      = Color(0xFFF8F7FF);
const _kCard    = Color(0xFFFFFFFF);
const _kText    = Color(0xFF1A1340);
const _kTextSub = Color(0xFF6B6B8A);
const _kGreen   = Color(0xFF10B981);

class AboutTezRiderScreen extends StatelessWidget {
  const AboutTezRiderScreen({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPurple,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('About TezRider',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D3B12), _kPurple],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: _kPurple.withValues(alpha: 0.30), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: const Center(
              child: Text('⚡', style: TextStyle(fontSize: 52)),
            ),
          ),

          const SizedBox(height: 20),
          const Text('TezRider',
              style: TextStyle(
                  color: _kText, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('Version 1.0.0 (Build 1)',
              style: TextStyle(color: _kTextSub, fontSize: 14)),

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kGreen.withValues(alpha: 0.25)),
            ),
            child: const Text('Up to date',
                style: TextStyle(color: _kGreen, fontWeight: FontWeight.w700, fontSize: 13)),
          ),

          const SizedBox(height: 32),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 4))],
            ),
            child: const Text(
              'TezRider is Pakistan\'s trusted on-demand delivery platform. '
              'We connect customers with local vendors, grocery stores, pharmacies, '
              'and tailoring services — all delivered to your door by our verified riders.\n\n'
              'Whether you need food, groceries, medicine, or clothes altered, '
              'TezRider has you covered — fast, reliable, and affordable.',
              style: TextStyle(color: _kText, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 24),

          Row(children: [
            _statCard('🚀', '5 min', 'Avg Delivery'),
            const SizedBox(width: 12),
            _statCard('⭐', '4.8', 'App Rating'),
            const SizedBox(width: 12),
            _statCard('🛵', '500+', 'Riders'),
          ]),

          const SizedBox(height: 28),

          _sectionTitle('Links'),
          const SizedBox(height: 12),
          _linkTile('🌐', 'Website', 'www.tezrider.pk', 'https://www.tezrider.pk'),
          const SizedBox(height: 10),
          _linkTile('📜', 'Privacy Policy', 'How we use your data', 'https://www.tezrider.pk/privacy'),
          const SizedBox(height: 10),
          _linkTile('📋', 'Terms of Service', 'Our terms & conditions', 'https://www.tezrider.pk/terms'),
          const SizedBox(height: 10),
          _linkTile('💼', 'Careers', 'Join the TezRider team', 'https://www.tezrider.pk/careers'),

          const SizedBox(height: 28),

          _sectionTitle('Follow Us'),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: _socialBtn('📘', 'Facebook', Color(0xFF1877F2),
                'https://facebook.com/tezrider')),
            const SizedBox(width: 10),
            Expanded(child: _socialBtn('📸', 'Instagram', Color(0xFFE1306C),
                'https://instagram.com/tezrider')),
            const SizedBox(width: 10),
            Expanded(child: _socialBtn('🐦', 'Twitter', Color(0xFF1DA1F2),
                'https://twitter.com/tezrider')),
          ]),

          const SizedBox(height: 36),

          Text('Made with ❤️ in Pakistan',
              style: TextStyle(color: _kTextSub, fontSize: 13)),
          const SizedBox(height: 4),
          Text('© 2025 TezRider. All rights reserved.',
              style: TextStyle(color: _kTextSub.withValues(alpha: 0.6), fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _statCard(String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(color: _kText, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: _kTextSub, fontSize: 10),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(title.toUpperCase(),
          style: TextStyle(
              color: _kTextSub, fontSize: 11,
              fontWeight: FontWeight.w800, letterSpacing: 1.4)),
    );
  }

  Widget _linkTile(String emoji, String title, String sub, String url) {
    return Builder(builder: (context) => GestureDetector(
      onTap: () => _launch(url),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 14)),
            Text(sub, style: TextStyle(color: _kTextSub, fontSize: 11)),
          ])),
          Icon(Icons.open_in_new_rounded, color: _kPurple, size: 16),
        ]),
      ),
    ));
  }

  Widget _socialBtn(String emoji, String label, Color color, String url) {
    return GestureDetector(
      onTap: () => _launch(url),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}