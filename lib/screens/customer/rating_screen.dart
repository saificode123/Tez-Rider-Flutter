import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/feedback_service.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key, required this.orderId, this.service});
  final int orderId;
  final FeedbackService? service;
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  late final service = widget.service ?? FeedbackService();
  List<Map<String, dynamic>>? targets;
  String? error;
  StreamSubscription<void>? changes;
  String? account;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    account = service.account;
    changes = service.accountChanges.listen((_) {
      if (service.account != account) {
        account = service.account;
        load();
      }
    });
    load();
  }

  @override
  void dispose() {
    ++generation;
    unawaited(changes?.cancel());
    super.dispose();
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      targets = null;
      error = null;
    });
    try {
      final result = await service.context(widget.orderId);
      if (mounted && request == generation) setState(() => targets = result);
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error =
              'Could not load delivery feedback. Check your connection and account access.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Delivery feedback')),
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
        : targets == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Rate each Vendor and your assigned Rider separately. Submitted feedback cannot be edited.',
              ),
              if (targets!.isEmpty)
                const Text(
                  'No eligible feedback recipients for this delivery.',
                ),
              for (final target in targets!)
                _TargetFeedback(
                  key: ValueKey('${widget.orderId}-${target['target_id']}'),
                  target: target,
                  submission: FeedbackSubmission(
                    service,
                    widget.orderId,
                    target['target_id'],
                  ),
                ),
            ],
          ),
  );
}

class _TargetFeedback extends StatefulWidget {
  const _TargetFeedback({
    super.key,
    required this.target,
    required this.submission,
  });
  final Map<String, dynamic> target;
  final FeedbackSubmission submission;
  @override
  State<_TargetFeedback> createState() => _TargetFeedbackState();
}

class _TargetFeedbackState extends State<_TargetFeedback> {
  final comment = TextEditingController();
  int rating = 0;
  bool busy = false;
  String? error;
  Map<String, dynamic>? saved;
  @override
  void initState() {
    super.initState();
    saved = widget.target['review'] == null
        ? null
        : Map<String, dynamic>.from(widget.target['review']);
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.submission.submit(rating, comment.text);
      if (mounted) setState(() => saved = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = widget.submission.uncertain
              ? 'Result not confirmed. Retry the same feedback to check whether it was saved.'
              : 'Feedback was not saved. Check your account and delivered order, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = busy || widget.submission.uncertain;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.target['role'] == 'vendor' ? 'Vendor' : 'Rider'}: ${widget.target['name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (saved != null) ...[
              Text('Saved rating: ${saved!['rating']}/5'),
              if (saved!['comment'] != null) Text(saved!['comment'].toString()),
            ] else ...[
              Wrap(
                children: List.generate(
                  5,
                  (index) => IconButton(
                    tooltip: '${index + 1} stars',
                    onPressed: locked
                        ? null
                        : () => setState(() => rating = index + 1),
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: comment,
                enabled: !locked,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                ),
              ),
              if (error != null) Text(error!),
              ElevatedButton(
                onPressed: busy || rating == 0 ? null : submit,
                child: Text(
                  busy
                      ? 'Submitting…'
                      : widget.submission.uncertain
                      ? 'Retry same feedback'
                      : 'Submit feedback',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
