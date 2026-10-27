import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/widgets/role_access_gate.dart';
import 'support/closure_harness.dart';

class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      autofocus: true,
      onPressed: () => setState(() => count++),
      child: Text('tab-state:$count'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transport = UiTransport();
  Map<String, dynamic> allowed([int id = 1]) => {
    'code': 'OK',
    'id': id,
    'role': 'customer',
    'verification_status': 'approved',
    'is_blocked': false,
  };
  setUpAll(() => initializeClosureClient(transport));
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    Get.testMode = true;
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession().toJson()),
    );
    Get.put<AuthController>(QuietAuth());
    transport.respond = (_) async => UiTransport.jsonResponse(allowed());
  });
  tearDown(Get.reset);

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(
      GetMaterialApp(
        home: RoleAccessGate(
          role: 'customer',
          builder: (_) => const _Dashboard(),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('tab-state:0'));
    await t.pump();
    expect(find.text('tab-state:1'), findsOneWidget);
  }

  void resume(WidgetTester t) {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets(
    'same-account recheck hides content and retains dashboard state',
    (t) async {
      await open(t);
      final pending = Completer<void>();
      transport.respond = (_) async {
        await pending.future;
        return UiTransport.jsonResponse(allowed());
      };
      resume(t);
      await t.pump();
      expect(find.text('tab-state:1'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete();
      await t.pumpAndSettle();
      expect(find.text('tab-state:1'), findsOneWidget);
    },
  );

  testWidgets('denied recheck discards retained state before retry', (t) async {
    await open(t);
    transport.respond = (_) async => UiTransport.jsonResponse({
      'code': 'FR28_ACCOUNT_BLOCKED',
      'is_blocked': true,
    });
    resume(t);
    await t.pumpAndSettle();
    expect(find.byType(_Dashboard, skipOffstage: false), findsNothing);
    expect(
      find.text('Account access could not be confirmed for this screen.'),
      findsOneWidget,
    );
    transport.respond = (_) async => UiTransport.jsonResponse(allowed());
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('tab-state:0'), findsOneWidget);
  });

  testWidgets('account change immediately discards old dashboard state', (
    t,
  ) async {
    await open(t);
    final pending = Completer<void>();
    transport.respond = (_) async {
      await pending.future;
      return UiTransport.jsonResponse(allowed(2));
    };
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(unitSession('00000000-0000-0000-0000-000000000002').toJson()),
    );
    await t.pump();
    expect(find.byType(_Dashboard, skipOffstage: false), findsNothing);
    pending.complete();
    await t.pumpAndSettle();
    expect(find.text('tab-state:0'), findsOneWidget);
    expect(find.text('tab-state:1', skipOffstage: false), findsNothing);
  });

  testWidgets('failed access read discards state and exposes retry', (t) async {
    await open(t);
    transport.respond = (_) async =>
        UiTransport.jsonResponse({'message': 'injected unavailable'}, 503);
    resume(t);
    await t.pumpAndSettle();
    expect(find.byType(_Dashboard, skipOffstage: false), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('injected unavailable'), findsNothing);
  });
  testWidgets(
    'hidden dashboard cannot accept keyboard activation during checks',
    (t) async {
      await open(t);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(find.text('tab-state:2'), findsOneWidget);
      final pending = Completer<void>();
      transport.respond = (_) async {
        await pending.future;
        return UiTransport.jsonResponse(allowed());
      };
      resume(t);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      pending.complete();
      await t.pumpAndSettle();
      expect(find.text('tab-state:2'), findsOneWidget);
      expect(find.text('tab-state:3'), findsNothing);
    },
  );
}
