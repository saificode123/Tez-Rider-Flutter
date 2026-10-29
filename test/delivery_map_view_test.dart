import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_application_1/core/stage2_ui_translations.dart';
import 'package:flutter_application_1/services/delivery_location.dart';
import 'package:flutter_application_1/services/delivery_map_stops.dart';
import 'package:flutter_application_1/services/delivery_route.dart';
import 'package:flutter_application_1/widgets/delivery_map_view.dart';
import 'package:flutter_application_1/widgets/rider_navigation_map.dart';

class _Tiles extends TileProvider {
  @override
  ImageProvider getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGD4DwAChAGA+gVWHQAAAABJRU5ErkJggg==',
    ),
  );
}

class _Translations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {'en': {}, 'ur': stage2UiUrdu};
}

DeliveryRoute road() {
  final now = DateTime.now().toUtc();
  return DeliveryRoute.fromJson({
    'orderId': 1,
    'distanceMeters': 1200,
    'durationSeconds': 360,
    'computedAt': now.toIso8601String(),
    'expiresAt': now.add(const Duration(minutes: 4)).toIso8601String(),
    'source': 'geoapify',
    'cacheStatus': 'cached',
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        [73.05, 33.7],
        [73.06, 33.71],
      ],
    },
  });
}

void main() {
  tearDown(Get.reset);
  Future<void> show(
    WidgetTester tester, {
    DeviceFix? fix,
    bool stale = false,
    DeliveryRoute? route,
    Locale locale = const Locale('en'),
    Size size = const Size(390, 780),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GetMaterialApp(
        locale: locale,
        translations: _Translations(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: DeliveryMapView(
              key: const ValueKey('map'),
              tileProvider: _Tiles(),
              fix: fix,
              stale: stale,
              route: route,
              eta: 'Arriving in 6 min',
              onBack: () {},
              stops: const DeliveryMapStops(
                pickup: LatLng(33.7, 73.05),
                destination: LatLng(33.71, 73.06),
                status: 'on_the_way',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  DeviceFix fix([double lat = 33.7, double lng = 73.05]) =>
      DeviceFix(lat, lng, 4, DateTime.now().toUtc());
  testWidgets(
    'actual endpoints, confirmed Rider, cached road and ETA are distinct',
    (tester) async {
      await show(tester, fix: fix(), route: road());
      await tester.tap(find.byTooltip('Route overview'));
      await tester.pump();
      expect(find.byTooltip('Pickup point'), findsOneWidget);
      expect(find.byTooltip('Delivery destination'), findsOneWidget);
      expect(find.byTooltip('Confirmed Rider position'), findsOneWidget);
      expect(find.text('Cached road route'), findsOneWidget);
      expect(find.text('1.2 km'), findsOneWidget);
      expect(find.text('Arriving in 6 min'), findsOneWidget);
      expect(
        tester
            .widget<PolylineLayer>(find.byType(PolylineLayer))
            .polylines
            .last
            .points
            .length,
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('stale confirmed pin has timestamp and cannot claim live ETA', (
    tester,
  ) async {
    await show(tester, fix: fix(), stale: true, route: road());
    expect(find.text('Last known · not live'), findsOneWidget);
    expect(find.byTooltip('Last confirmed Rider position'), findsOneWidget);
    expect(find.text('ETA unavailable'), findsOneWidget);
    expect(find.textContaining('Last update:'), findsOneWidget);
    expect(find.text('Arriving in 6 min'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'no confirmed position means no Rider marker or fabricated fallback',
    (tester) async {
      await show(tester, stale: true);
      final markers = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers;
      expect(
        markers.length,
        2,
      ); // Only the two explicitly supplied test endpoints.
      expect(find.text('Location unavailable'), findsOneWidget);
      expect(find.text('Road route unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'animation is bounded by the two actual fixes and ends exactly at target',
    (tester) async {
      await show(tester, fix: fix());
      final next = fix(33.7005, 73.0505);
      await show(tester, fix: next);
      final point = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .last
          .point;
      expect(point.latitude, closeTo(next.latitude, 1e-10));
      await tester.pump(const Duration(seconds: 5));
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.last.point,
        point,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'manual panning suspends follow across new fixes; recenter restores it',
    (tester) async {
      await show(tester, fix: fix());
      await tester.drag(find.byType(FlutterMap), const Offset(-65, 40));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byTooltip('Recenter and follow'), findsOneWidget);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final center = controller.camera.center;
      await show(tester, fix: fix(33.7005, 73.0505));
      expect(
        controller.camera.center.latitude,
        closeTo(center.latitude, .000001),
      );
      await tester.tap(find.byTooltip('Recenter and follow'));
      await tester.pump();
      expect(find.byTooltip('Following Rider'), findsOneWidget);
      expect(controller.camera.center.latitude, closeTo(33.7005, .000001));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('route overview fits both endpoints without resuming follow', (
    tester,
  ) async {
    await show(tester, fix: fix(), route: road());
    await tester.tap(find.byTooltip('Route overview'));
    await tester.pump();
    expect(find.byTooltip('Recenter and follow'), findsOneWidget);
    final bounds = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera
        .visibleBounds;
    expect(bounds.contains(const LatLng(33.7, 73.05)), true);
    expect(bounds.contains(const LatLng(33.71, 73.06)), true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Urdu RTL small screen with enlarged text keeps controls reachable',
    (tester) async {
      await show(
        tester,
        fix: fix(),
        stale: true,
        route: road(),
        locale: const Locale('ur'),
        size: const Size(320, 568),
        textScale: 1.7,
      );
      expect(
        Directionality.of(tester.element(find.byType(FlutterMap))),
        TextDirection.rtl,
      );
      expect(find.byTooltip(stage2UiUrdu['Route overview']!), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'actual Rider layout keeps at least half the screen for the map with tall action forms',
    (tester) async {
      const size = Size(390, 780);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: RiderMapLayout(
              map: DeliveryMapView(
                compact: true,
                tileProvider: _Tiles(),
                fix: fix(),
                stale: false,
                route: road(),
                eta: 'Arriving in 6 min',
                footer: const Text('Navigation to customer'),
              ),
              actions: SingleChildScrollView(
                child: Column(
                  children: List.generate(
                    30,
                    (i) => ListTile(title: Text('Checklist item $i')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.getSize(find.byType(FlutterMap)).height,
        greaterThanOrEqualTo(size.height * .49),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
