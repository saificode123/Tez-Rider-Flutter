import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/profile_email_service.dart';

class ProfileEmailPanel extends StatefulWidget {
  const ProfileEmailPanel({super.key, this.service, this.onConfirmed});
  final ProfileEmailService? service;
  final ValueChanged<String>? onConfirmed;
  @override
  State<ProfileEmailPanel> createState() => _ProfileEmailPanelState();
}

class _ProfileEmailPanelState extends State<ProfileEmailPanel>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? ProfileEmailService();
  final _email = TextEditingController();
  StreamSubscription<void>? _subscription;
  ProfileEmailState? _state;
  String? _notice, _owner;
  bool _busy = false, _canRequest = false, _changedAccount = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _owner = _service.account;
    _subscription = _service.accountChanges.listen((_) {
      if (!mounted) return;
      if (_owner != _service.account) {
        ++_generation;
        setState(() {
          _changedAccount = true;
          _state = null;
          _email.clear();
          _notice = null;
        });
      } else if (!_busy) {
        unawaited(_check());
      }
    });
    unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && !_changedAccount)
      unawaited(_check());
  }

  Future<void> _check() async {
    if (_busy || _changedAccount) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await _service.load();
      if (!mounted || generation != _generation) return;
      final previous = _state?.email;
      setState(() {
        _state = result;
        _canRequest = result.pendingEmail == null;
        if (previous != null && previous != result.email) {
          _email.clear();
          _notice = 'Confirmed email change is now saved to your profile.';
        }
      });
      widget.onConfirmed?.call(result.email);
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _canRequest = false;
          _notice =
              'Email status could not be verified. Check your connection and retry.';
        });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    if (_busy || !_canRequest || _changedAccount) return;
    final target = _email.text.trim();
    if (!ProfileEmailService.valid(target) ||
        target.toLowerCase() == _state?.email.toLowerCase()) {
      setState(() => _notice = 'Enter a valid new email address.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Request email change?'.tr),
        content: Text(
          'Your current sign-in email stays unchanged until Supabase Auth confirms the new address.'
              .tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Request change'.tr),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _changedAccount) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _notice = null;
      _canRequest = false;
    });
    try {
      final result = await _service.request(target);
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = result;
        _canRequest = result.pendingEmail == null;
        _notice = result.email.toLowerCase() == target.toLowerCase()
            ? 'Confirmed email change is now saved to your profile.'
            : 'Request accepted. Follow Supabase Auth confirmation instructions. Email delivery and the change are not yet confirmed.';
      });
      widget.onConfirmed?.call(result.email);
    } catch (_) {
      if (mounted && generation == _generation)
        setState(
          () => _notice =
              'Email change was not confirmed. Check email status before retrying.',
        );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    if (_changedAccount) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sign-in email'.tr,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (_state != null) SelectableText(_state!.email),
        if (_state?.pendingEmail != null) ...[
          Text('Awaiting Auth confirmation'.tr),
          SelectableText(_state!.pendingEmail!),
        ],
        TextField(
          controller: _email,
          enabled: !_busy && _canRequest,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          maxLength: 254,
          decoration: InputDecoration(labelText: 'New email address'.tr),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_notice != null) Text(_notice!.tr),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy || !_canRequest ? null : _request,
              child: Text('Request email change'.tr),
            ),
            TextButton(
              onPressed: _busy ? null : _check,
              child: Text('Check email status'.tr),
            ),
          ],
        ),
      ],
    );
  }
}
