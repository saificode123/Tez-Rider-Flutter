import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/account_access.dart';
import '../controllers/auth_controller.dart';

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
  StreamSubscription<void>? _accessChanges;
  final _client = Supabase.instance.client;
  Widget? _dashboard;
  String? _dashboardAccount;
  String? _dashboardRole;
  String? _checkedAccount;
  String? _checkedRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _access = _nextCheck();
    _changes = _client.auth.onAuthStateChange.listen((_) => _reload());
    if (Get.isRegistered<AuthController>()) {
      _accessChanges = Get.find<AuthController>().accountGate.accessChanges
          .listen((_) => _reload());
    }
  }

  Future<bool> _nextCheck() {
    _checkedAccount = _client.auth.currentUser?.id;
    _checkedRole = widget.role;
    return _check(_checkedAccount, widget.role);
  }

  Future<bool> _check(String? account, String role) async {
    if (account == null) return false;
    try {
      if (Get.isRegistered<AuthController>() &&
          !await Get.find<AuthController>().credentials.restorationAllowed()) {
        return false;
      }
      final status = await _client
          .rpc('fr28_account_status')
          .timeout(const Duration(seconds: 10));
      return account == _client.auth.currentUser?.id &&
          status is Map &&
          roleAccessAllowed(Map<String, dynamic>.from(status), role);
    } catch (_) {
      // The retry panel remains fail-closed even when a very fast failure
      // arrives before FutureBuilder subscribes to the new check.
      return false;
    }
  }

  void _discardDashboard() {
    _dashboard = null;
    _dashboardAccount = null;
    _dashboardRole = null;
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      if (_dashboardAccount != _client.auth.currentUser?.id ||
          _dashboardRole != widget.role) {
        _discardDashboard();
      }
      _access = _nextCheck();
    });
  }

  @override
  void didUpdateWidget(covariant RoleAccessGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role) {
      _discardDashboard();
      _access = _nextCheck();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    unawaited(_accessChanges?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return FutureBuilder<bool>(
      future: _access,
      builder: (context, snapshot) {
        final account = _client.auth.currentUser?.id;
        final checking = snapshot.connectionState != ConnectionState.done;
        final allowed =
            !checking &&
            snapshot.data == true &&
            !snapshot.hasError &&
            account != null &&
            account == _checkedAccount &&
            widget.role == _checkedRole;
        if (allowed) {
          _dashboardAccount = account;
          _dashboardRole = widget.role;
          _dashboard = KeyedSubtree(
            key: ValueKey('$account/${widget.role}'),
            child: widget.builder(context),
          );
        } else if (!checking ||
            account != _dashboardAccount ||
            widget.role != _dashboardRole) {
          _discardDashboard();
        }
        // Same-account rechecks retain tab/scroll state without painting,
        // exposing semantics, accepting focus, or ticking hidden animations.
        // Denial/error/account/role changes dispose the retained dashboard.
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_dashboard != null)
              Offstage(
                offstage: !allowed,
                child: ExcludeFocus(
                  excluding: !allowed,
                  child: TickerMode(enabled: allowed, child: _dashboard!),
                ),
              ),
            if (!allowed) _accessBarrier(checking),
          ],
        );
      },
    );
  }

  Widget _accessBarrier(bool checking) {
    if (checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Account access could not be confirmed for this screen.".tr),
              TextButton(onPressed: _reload, child: Text("Retry".tr)),
              TextButton(
                onPressed: () => Get.offAllNamed('/login'),
                child: Text("Return to sign in".tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
