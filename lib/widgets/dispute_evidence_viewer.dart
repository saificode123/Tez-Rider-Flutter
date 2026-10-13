import 'dart:async';
import 'package:flutter/material.dart';
import '../services/dispute_service.dart';

class DisputeEvidenceViewer extends StatefulWidget {
  const DisputeEvidenceViewer({
    super.key,
    required this.disputeId,
    required this.index,
    this.backend,
  });
  final int disputeId, index;
  final DisputeBackend? backend;
  @override
  State<DisputeEvidenceViewer> createState() => _DisputeEvidenceViewerState();
}

class _DisputeEvidenceViewerState extends State<DisputeEvidenceViewer> {
  String? url, error;
  bool loading = false;
  Timer? expiry;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    if (loading) return;
    expiry?.cancel();
    if (url != null) unawaited(NetworkImage(url!).evict());
    setState(() {
      loading = true;
      url = null;
      error = null;
    });
    try {
      final link = await (widget.backend ?? SupabaseDisputeBackend()).signedUrl(
        widget.disputeId,
        widget.index,
      );
      if (!mounted) return;
      setState(() => url = link);
      expiry = Timer(const Duration(seconds: 900), () {
        unawaited(NetworkImage(link).evict());
        if (mounted) {
          setState(() {
            url = null;
            error = 'The private viewing link expired. Tap Retry.';
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = disputeError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    expiry?.cancel();
    if (url != null) unawaited(NetworkImage(url!).evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Private dispute evidence'),
    content: SizedBox(
      width: 340,
      height: 360,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : url == null
          ? Center(child: Text(error ?? 'Evidence unavailable.'))
          : Image.network(
              url!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Text('Image unavailable. Tap Retry.')),
            ),
    ),
    actions: [
      TextButton(onPressed: loading ? null : load, child: const Text('Retry')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
