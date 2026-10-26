import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/support_contact_service.dart';

class SupportContactCard extends StatefulWidget {
  const SupportContactCard({super.key, this.service, this.open});
  final SupportContactService? service;
  final Future<bool> Function(Uri)? open;
  @override
  State<SupportContactCard> createState() => _SupportContactCardState();
}

class _SupportContactCardState extends State<SupportContactCard> {
  late final _service = widget.service ?? SupportContactService();
  String? _email, _error;
  bool _loading = true, _opening = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _email = null;
    });
    try {
      final email = await _service.load();
      if (mounted) setState(() => _email = email);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Support contact could not be loaded. Retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open() async {
    if (_email == null || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final uri = Uri(scheme: 'mailto', path: _email!);
      final opened =
          await (widget.open?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!opened && mounted)
        setState(
          () => _error =
              'No email app opened. Copy the address to contact support.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'No email app opened. Copy the address to contact support.',
        );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Support email'.tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh'.tr,
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_email != null) ...[
              SelectableText(_email!),
              Text(
                'Blocked or signed out? You can contact support using this address.'
                    .tr,
              ),
              TextButton.icon(
                onPressed: _opening ? null : _open,
                icon: const Icon(Icons.email_outlined),
                label: Text('Email support'.tr),
              ),
            ],
            if (_error != null) ...[
              Text(_error!.tr),
              if (!_loading)
                TextButton(onPressed: _load, child: Text('Retry'.tr)),
            ],
          ],
        ),
      ),
    );
  }
}
