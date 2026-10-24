import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/feedback_service.dart';
import '../services/rating_watch.dart';

class RatingSummaryScreen extends StatefulWidget {
  const RatingSummaryScreen({super.key});
  @override
  State<RatingSummaryScreen> createState() => _RatingSummaryScreenState();
}

class _RatingSummaryScreenState extends State<RatingSummaryScreen> {
  final service = FeedbackService();
  RatingWatch? watch;
  Map<String, dynamic>? summary;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      summary = null;
      error = null;
    });
    try {
      final account = service.account;
      if (account == null) throw StateError('Sign in required');
      final user = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('auth_user_id', account)
          .single()
          .timeout(const Duration(seconds: 15));
      if (service.account != account) throw StateError('Account changed');
      final value = await service.summary(user['id'] as int);
      if (!mounted || request != generation) return;
      setState(() => summary = value);
      if (watch == null || watch!.isClosed) {
        watch = RatingWatch(load, targetId: user['id'] as int);
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error =
              'Ratings could not be loaded. Check your connection and account access.',
        );
      }
    }
  }

  @override
  void dispose() {
    ++generation;
    watch?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ratings & reviews'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!, textAlign: TextAlign.center),
                TextButton(onPressed: load, child: const Text('Retry')),
              ],
            ),
          )
        : summary == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                summary!['count'] == 0
                    ? 'No verified ratings yet'
                    : '${summary!['average']} / 5 · ${summary!['count']} verified ratings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text(
                'Feedback from completed deliveries. Most recent 10 reviews.',
              ),
              for (final row in summary!['recent'])
                Card(
                  child: ListTile(
                    title: Text('${row['rating']} / 5'),
                    subtitle: Text(
                      '${row['comment'] ?? ''}\n${row['created_at']}',
                    ),
                  ),
                ),
            ],
          ),
  );
}
