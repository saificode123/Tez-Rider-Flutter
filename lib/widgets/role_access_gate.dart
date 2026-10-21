import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/account_access.dart';

bool roleAccessAllowed(Map<String, dynamic> status, String role) {
  if (status['code'] != 'OK' || status['is_blocked'] == true) return false;
  try {
    final access = AccountAccess.fromProfile(status);
    return access.role == role && !access.needsApproval;
  } catch (_) {
    return false;
  }
}

/// Resolve the current server account before constructing a role dashboard.
class RoleAccessGate extends StatefulWidget {
  const RoleAccessGate({super.key, required this.role, required this.builder});
  final String role;
  final WidgetBuilder builder;
  @override
  State<RoleAccessGate> createState() => _RoleAccessGateState();
}

class _RoleAccessGateState extends State<RoleAccessGate>
    with WidgetsBindingObserver {
  Future<bool>? _access;
  StreamSubscription<AuthState>? _changes;
  final _client = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _access = _check();
    _changes = _client.auth.onAuthStateChange.listen((_) => _reload());
  }

  Future<bool> _check() async {
    final account = _client.auth.currentUser?.id;
    if (account == null) return false;
    final status = await _client
        .rpc('fr28_account_status')
        .timeout(const Duration(seconds: 10));
    return account == _client.auth.currentUser?.id &&
        status is Map &&
        roleAccessAllowed(Map<String, dynamic>.from(status), widget.role);
  }

  void _reload() {
    if (mounted) setState(() => _access = _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _access,
    builder: (context, snapshot) {
      // Never render stale allowed data while another account is checked.
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data == true && !snapshot.hasError) {
        return widget.builder(context);
      }
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Account access could not be confirmed for this screen.',
                ),
                TextButton(onPressed: _reload, child: const Text('Retry')),
                TextButton(
                  onPressed: () => Get.offAllNamed('/login'),
                  child: const Text('Return to sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
