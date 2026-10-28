import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/strings/live_tracking_strings.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';
import 'package:konekta_mobile/features/live_tracking/ui/route_detail_page.dart';

const _route = TransitRoute(id: 'K1', corridors: [CorridorOption(id: 'K1', name: 'Koridor 1', feeders: [])]);

CorridorRoute _stops(RouteDirection direction, {String? hours, int? fare}) => CorridorRoute(
      id: 'K1',
      name: 'Koridor 1',
      operatingHours: hours,
      fareFromIdr: fare,
      stops: direction == RouteDirection.forward
          ? const [
              CorridorRouteStop(position: 1, name: 'Dago'),
              CorridorRouteStop(position: 2, name: 'Simpang'),
              CorridorRouteStop(position: 3, name: 'Alun-alun'),
            ]
          : const [
              CorridorRouteStop(position: 1, name: 'Alun-alun'),
              CorridorRouteStop(position: 2, name: 'Dago'),
            ],
    );

Future<void> _pump(
  WidgetTester tester, {
  String? hours,
  int? fare,
  Future<List<StopArrivals>> Function(RouteDirection)? arrivals,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: RouteDetailPage(
      route: _route,
      loadStops: (direction) async => _stops(direction, hours: hours, fare: fare),
      loadArrivals: arrivals ?? (_) async => const [],
      feederNumber: (id) => id == 'K1-01' ? 1 : null,
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows stops per direction and only the info that is set', (tester) async {
    await _pump(tester, hours: '05.00-21.00');

    expect(find.text('Koridor 1'), findsOneWidget);
    expect(find.text('Dago - Alun-alun'), findsOneWidget);
    expect(find.text('Alun-alun - Dago'), findsOneWidget);
    expect(find.text(LiveTrackingStrings.operatingHours), findsOneWidget);
    expect(find.text(LiveTrackingStrings.operatingDays), findsNothing);
    expect(find.text(LiveTrackingStrings.fare), findsNothing);
    expect(find.text('Simpang'), findsOneWidget);

    await tester.tap(find.text('Alun-alun - Dago'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Simpang'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stop with a feeder due expands to show it', (tester) async {
    await _pump(tester, arrivals: (_) async => const [
          StopArrivals(position: 1, name: 'Dago', arrivals: []),
          StopArrivals(position: 2, name: 'Simpang', arrivals: [
            StopArrival(feederId: 'K1-01', etaS: 120, occupancy: 2, capacity: 8),
          ]),
        ]);

    expect(find.byIcon(Icons.expand_more), findsOneWidget); // only Simpang
    expect(find.text('2 min'), findsNothing);

    await tester.tap(find.text('Simpang'));
    await tester.pump();
    expect(find.text('Feeder 1'), findsOneWidget);
    expect(find.text('2 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ikuti pops true to watch the route on the map', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => RouteDetailPage(
                route: _route,
                loadStops: (direction) async => _stops(direction),
                loadArrivals: (_) async => const [],
              ),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(LiveTrackingStrings.follow));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
