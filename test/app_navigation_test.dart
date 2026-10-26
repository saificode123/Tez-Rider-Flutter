import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/widgets/app_navigation.dart';

class _Counter extends StatefulWidget {
  const _Counter(this.label);
  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('${widget.label}:$count'),
  );
}

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('tab changes preserve page state and select only one page', (
    tester,
  ) async {
    var index = 0;
    late StateSetter change;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return AppTabStack(
              index: index,
              children: const [_Counter('first'), _Counter('second')],
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('first:0'));
    await tester.pump();
    change(() => index = 1);
    await tester.pumpAndSettle();
    expect(find.text('first:1'), findsNothing);
    expect(find.text('second:0'), findsOneWidget);
    await tester.tap(find.text('second:0'));
    await tester.pump();
    change(() => index = 0);
    await tester.pumpAndSettle();
    expect(find.text('first:1'), findsOneWidget);
    expect(find.text('second:1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion changes tabs without a transition frame', (
    tester,
  ) async {
    var index = 0;
    late StateSetter change;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return AppTabStack(
              index: index,
              children: const [Text('A'), Text('B')],
            );
          },
        ),
        reduced: true,
      ),
    );
    change(() => index = 1);
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find.byType(FadeTransition).first,
    );
    final slide = tester.widget<SlideTransition>(
      find.byType(SlideTransition).first,
    );
    expect(fade.opacity.value, 1);
    expect(slide.position.value, Offset.zero);
    expect(find.text('B'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fade.opacity.value, 1);
    expect(slide.position.value, Offset.zero);
  });

  testWidgets(
    'tab semantics expose all labels, selection and real tap callback',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Row(
            children: [
              AppNavigationItem(
                selected: true,
                activeIcon: Icons.home,
                inactiveIcon: Icons.home_outlined,
                label: 'Home',
                onTap: () => taps++,
              ),
              AppNavigationItem(
                selected: false,
                activeIcon: Icons.receipt,
                inactiveIcon: Icons.receipt_outlined,
                label: 'Orders',
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      );
      final home = tester.getSemantics(find.bySemanticsLabel('Home'));
      expect(home.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(home.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(home.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Orders'))
            .hasFlag(SemanticsFlag.isSelected),
        isFalse,
      );
      await tester.tap(find.text('Orders'));
      await tester.pump();
      expect(taps, 1);
      semantics.dispose();
    },
  );

  testWidgets('four Urdu tabs fit a narrow RTL screen with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const labels = ['جائزہ', 'آرڈرز', 'درزی کے کام', 'پروفائل'];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              bottomNavigationBar: Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    AppNavigationItem(
                      selected: i == 0,
                      activeIcon: Icons.home,
                      inactiveIcon: Icons.home_outlined,
                      label: labels[i],
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
      expect(find.byTooltip(label), findsOneWidget);
    }
    final bounds = tester.getRect(find.byType(InkWell).first);
    expect(bounds.height, greaterThanOrEqualTo(48));
    expect(bounds.width, greaterThanOrEqualTo(48));
  });
}
