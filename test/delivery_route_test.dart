import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_application_1/services/delivery_destination.dart';
import 'package:flutter_application_1/services/delivery_location.dart';
import 'package:flutter_application_1/services/delivery_route.dart';

Map<String, dynamic> routeData(DateTime at, {bool fallback = false}) => {
  'orderId': 1,
  'geometry': fallback
      ? null
      : {
          'type': 'LineString',
          'coordinates': [
            [73.05, 33.7],
            [73.06, 33.7],
            [73.06, 33.71],
          ],
        },
  'distanceMeters': 2000,
  'durationSeconds': 600,
  'computedAt': at.toIso8601String(),
  'expiresAt': at.add(const Duration(minutes: 4)).toIso8601String(),
  'isApproximate': fallback,
  'source': fallback ? 'straight_line' : 'geoapify',
};
void main() {
  test(
    'destination starts unconfirmed and explicit methods persist provenance',
    () {
      final d = DeliveryDestination();
      expect(d.confirmed, false);
      d.confirm(33.7, 73.05, 'map_pin');
      expect(d.provenance, {
        'destination_confirmed': true,
        'destination_source': 'map_pin',
      });
      expect(d.latitude, 33.7);
      d.confirm(33.71, 73.06, 'my_location');
      expect(d.source, 'my_location');
    },
  );
  test('destination rejects fake source and invalid coordinates', () {
    final d = DeliveryDestination();
    expect(() => d.confirm(91, 73, 'map_pin'), throwsArgumentError);
    expect(() => d.confirm(33, double.nan, 'map_pin'), throwsArgumentError);
    expect(() => d.confirm(33, 73, 'automatic'), throwsArgumentError);
    expect(d.confirmed, false);
  });
  test('GeoJSON decoding swaps longitude latitude exactly once', () {
    final r = DeliveryRoute.fromJson(routeData(DateTime.utc(2026)));
    expect(r.points.first, const LatLng(33.7, 73.05));
    expect(r.points.last, const LatLng(33.71, 73.06));
  });
  test('invalid polyline geometry rejected', () {
    for (final geometry in [
      {
        'type': 'LineString',
        'coordinates': [
          [181, 33],
          [73, 33],
        ],
      },
      {
        'type': 'Point',
        'coordinates': [73, 33],
      },
      {'type': 'LineString', 'coordinates': []},
    ]) {
      expect(
        () => DeliveryRoute.decodeGeometry(geometry),
        throwsFormatException,
      );
    }
  });
  test('fallback never fabricates a route', () {
    final r = DeliveryRoute.fromJson(
      routeData(DateTime.utc(2026), fallback: true),
    );
    expect(r.points, isEmpty);
    expect(r.approximate, true);
  });
  test('ETA formatting and unavailable state', () {
    expect(routeEtaLabel(480), 'Arriving in 8 min');
    expect(routeEtaLabel(480, approximate: true), 'Approximately 8 min');
    expect(routeEtaLabel(null), 'ETA unavailable');
    expect(routeEtaLabel(0), 'Arriving in 1 min');
  });
  test('projection accounts for all remaining road segments', () {
    final r = DeliveryRoute.fromJson(routeData(DateTime.utc(2026)));
    final p = projectOnRoute(r.points, const LatLng(33.7, 73.055));
    expect(p.offRoute, lessThan(1));
    expect(p.total - p.along, greaterThan(1500));
    expect(p.along, greaterThan(400));
  });
  test('off route distance uses segment projection', () {
    final r = DeliveryRoute.fromJson(routeData(DateTime.utc(2026)));
    expect(
      projectOnRoute(r.points, const LatLng(33.72, 73.04)).offRoute,
      greaterThan(150),
    );
  });
  test(
    'cached road projection preserves lengths and refreshes for movement',
    () {
      final r = DeliveryRoute.fromJson(routeData(DateTime.utc(2026)));
      final first = r.projector.project(const LatLng(33.7, 73.055));
      final stationary = r.projector.project(const LatLng(33.7, 73.055));
      expect(identical(first, stationary), true);
      final total =
          const Distance().as(LengthUnit.Meter, r.points[0], r.points[1]) +
          const Distance().as(LengthUnit.Meter, r.points[1], r.points[2]);
      expect(first.total, closeTo(total, 0.001));
      final moved = r.projector.project(const LatLng(33.705, 73.06));
      expect(moved.along, greaterThan(first.along));
      expect(moved.offRoute, lessThan(1));
      expect(moved.total, first.total);
      expect(
        r.projector.project(const LatLng(33.72, 73.04)).offRoute,
        greaterThan(150),
      );
    },
  );
  test(
    'projection snapshot survives source mutation and duplicate vertices',
    () {
      final points = <LatLng>[
        const LatLng(33.7, 73.05),
        const LatLng(33.7, 73.05),
        const LatLng(33.7, 73.06),
      ];
      final projector = RouteProjector(points);
      points.clear();
      final result = projector.project(const LatLng(33.7, 73.055));
      expect(result.total, greaterThan(900));
      expect(result.offRoute, lessThan(1));
      expect(result.along / result.total, closeTo(0.5, 0.001));
      final empty = RouteProjector([]).project(const LatLng(33.7, 73.05));
      expect(empty.total, 0);
      expect(empty.offRoute, double.infinity);
    },
  );
  group('route controller', () {
    late DateTime clock;
    late CustomerLocationState state;
    late DeliveryRouteController controller;
    late int calls;
    Map<String, dynamic>? response;
    Completer<Map<String, dynamic>>? pending;
    bool fail = false;
    void fix(double lat, double lng, {double accuracy = 10}) {
      state.position.value = DeviceFix(lat, lng, accuracy, clock);
      state.stale.value = false;
    }

    Future<void> flush() => Future<void>.delayed(Duration.zero);
    setUp(() {
      clock = DateTime.utc(2026, 10, 19, 12);
      state = CustomerLocationState(now: () => clock);
      calls = 0;
      response = null;
      pending = null;
      fail = false;
      controller = DeliveryRouteController(1, state, (_) async {
        calls++;
        if (fail) throw StateError('offline');
        return pending != null
            ? pending!.future
            : response ?? {'code': 'OK', 'route': routeData(clock)};
      }, now: () => clock);
    });
    tearDown(() => controller.onClose());
    test('no HTTP without fresh FR13 location', () async {
      await controller.refreshRoute();
      expect(calls, 0);
      expect(controller.label.value, 'ETA unavailable');
    });
    test('initial route then stationary ETA does not count down', () async {
      fix(33.7, 73.05);
      await controller.refreshRoute();
      final label = controller.label.value;
      clock = clock.add(const Duration(seconds: 90));
      fix(33.7, 73.05);
      controller.consider();
      expect(controller.label.value, label);
      expect(calls, 1);
    });
    test(
      'movement adjusts remaining road duration and marks approximate',
      () async {
        fix(33.7, 73.05);
        await controller.refreshRoute();
        for (var i = 1; i <= 5; i++) {
          clock = clock.add(const Duration(seconds: 20));
          fix(33.7, 73.05 + i * .001);
          controller.consider();
        }
        expect(controller.label.value, startsWith('Approximately'));
        expect(controller.label.value, isNot('Approximately 10 min'));
      },
    );
    test(
      'GPS backwards noise does not increase progress or trigger HTTP',
      () async {
        fix(33.7, 73.055);
        await controller.refreshRoute();
        final label = controller.label.value;
        clock = clock.add(const Duration(seconds: 5));
        fix(33.7, 73.05499);
        controller.consider();
        expect(controller.label.value, label);
        expect(calls, 1);
      },
    );
    test('low accuracy does not reduce duration', () async {
      fix(33.7, 73.05);
      await controller.refreshRoute();
      final label = controller.label.value;
      clock = clock.add(const Duration(seconds: 5));
      fix(33.7, 73.055, accuracy: 80);
      controller.consider();
      expect(
        controller.label.value,
        label.replaceFirst('Arriving in', 'Approximately'),
      );
    });
    test('one in-flight HTTP request', () async {
      fix(33.7, 73.05);
      pending = Completer();
      final a = controller.refreshRoute();
      clock = clock.add(const Duration(minutes: 2));
      await controller.refreshRoute();
      expect(calls, 1);
      pending!.complete({'code': 'OK', 'route': routeData(clock)});
      await a;
    });
    test('off-route recompute throttled then allowed after minute', () async {
      fix(33.7, 73.05);
      await controller.refreshRoute();
      clock = clock.add(const Duration(seconds: 5));
      fix(33.72, 73.04);
      controller.consider();
      await flush();
      expect(calls, 1);
      clock = clock.add(const Duration(seconds: 60));
      controller.consider();
      await flush();
      expect(calls, 2);
    });
    test('expired cache refreshes', () async {
      fix(33.7, 73.05);
      await controller.refreshRoute();
      clock = clock.add(const Duration(minutes: 5));
      fix(33.7, 73.05);
      controller.consider();
      await flush();
      expect(calls, 2);
    });
    test(
      'stale hides ETA, recovery restores without duplicate requests',
      () async {
        fix(33.7, 73.05);
        await controller.refreshRoute();
        state.stale.value = true;
        controller.consider();
        expect(controller.label.value, 'ETA unavailable');
        state.stale.value = false;
        controller.consider();
        expect(controller.label.value, startsWith('Arriving'));
        expect(calls, 1);
      },
    );
    test('historical unconfirmed destination remains unavailable', () async {
      response = {'code': 'DESTINATION_UNCONFIRMED', 'route': null};
      fix(33.7, 73.05);
      await controller.refreshRoute();
      expect(controller.route.value, isNull);
      expect(controller.label.value, 'ETA unavailable');
      expect(controller.notice.value, contains('not been confirmed'));
    });
    test('network failure clears route and never simulates success', () async {
      fix(33.7, 73.05);
      await controller.refreshRoute();
      fail = true;
      clock = clock.add(const Duration(minutes: 5));
      await controller.refreshRoute();
      expect(controller.route.value, isNull);
      expect(controller.label.value, 'ETA unavailable');
    });
    test(
      'unauthorized response clears route and stops automatic requests',
      () async {
        fix(33.7, 73.05);
        response = {'code': 'FORBIDDEN'};
        await controller.refreshRoute();
        clock = clock.add(const Duration(minutes: 5));
        controller.consider();
        await flush();
        expect(calls, 1);
        expect(controller.route.value, isNull);
      },
    );
    test('completion/disposal invalidates pending responses', () async {
      fix(33.7, 73.05);
      pending = Completer();
      final work = controller.refreshRoute();
      controller.onClose();
      pending!.complete({'code': 'OK', 'route': routeData(clock)});
      await work;
      expect(controller.route.value, isNull);
    });
    test('disposed listeners do not issue refreshes', () async {
      controller.start();
      controller.onClose();
      fix(33.7, 73.05);
      await flush();
      expect(calls, 0);
    });
  });
  testWidgets('road polyline renders via existing flutter_map layer', (
    tester,
  ) async {
    final r = DeliveryRoute.fromJson(routeData(DateTime.utc(2026)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(33.7, 73.05),
              initialZoom: 14,
            ),
            children: [
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: r.points,
                    color: Colors.green,
                    strokeWidth: 5,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(PolylineLayer), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
