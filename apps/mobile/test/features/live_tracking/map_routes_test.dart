import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/location/user_location_provider.dart';
import 'package:konekta_mobile/core/strings/live_tracking_strings.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_position_stream.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';
import 'package:konekta_mobile/features/live_tracking/state/feeder_fleet_controller.dart';
import 'package:konekta_mobile/features/live_tracking/state/passenger_map_controller.dart';
import 'package:konekta_mobile/features/live_tracking/ui/route_detail_page.dart';
import 'package:konekta_mobile/features/passenger/tabs/map_tab.dart';
import 'package:latlong2/latlong.dart';

class _NoPositions implements FeederPositionStream {
  @override
  FeederPosition? lastKnown(String feederId) => null;

  @override
  Stream<FeederPosition> subscribe(String feederId) => const Stream.empty();

  @override
  Stream<FeederPosition> subscribeCorridor(String corridorId) => const Stream.empty();
}

class _NoLocation implements UserLocationProvider {
  @override
  Future<LocationPermissionState> permissionState() async => LocationPermissionState.denied;

  @override
  Future<LocationPermissionState> requestPermission() async => LocationPermissionState.denied;

  @override
  Future<UserLocation?> getCurrent() async => null;

  @override
  Stream<UserLocation> stream() => const Stream.empty();
}

Future<CorridorRoute> _noStops(String corridorId, RouteDirection direction) async =>
    CorridorRoute(id: corridorId, name: corridorId, stops: const []);

Future<List<StopArrivals>> _noArrivals(String corridorId, RouteDirection direction) async => const [];

void main() {
  late ValueNotifier<ActiveTrip?> trip;
  late PassengerMapController map;
  late FeederFleetController fleet;

  Future<void> pumpTwoRoutes(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    trip = ValueNotifier<ActiveTrip?>(null);
    final positions = _NoPositions();
    map = PassengerMapController(trip: trip, positions: positions, location: _NoLocation());
    fleet = FeederFleetController(
      loadCorridors: () async => const [
        CorridorOption(id: 'K1', name: 'Koridor Dago', feeders: []),
        CorridorOption(id: 'K2', name: 'Koridor Buah Batu', feeders: []),
      ],
      loadLive: () async => [],
      positions: positions,
    );
    await map.start();
    await fleet.start();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTab(
      controller: map,
      fleet: fleet,
      loadRoutePath: (id) async => id == 'K1'
          ? const [LatLng(-6.94, 107.64), LatLng(-6.92, 107.62)]
          : const [LatLng(-6.95, 107.63), LatLng(-6.93, 107.61)],
      loadRouteStops: _noStops,
      loadArrivals: _noArrivals,
    ))));
    await tester.pump();
  }

  Future<void> tearDownTab(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    fleet.dispose();
    map.dispose();
    trip.dispose();
  }

  testWidgets('the sheet lists routes; tapping one opens its detail page', (tester) async {
    await pumpTwoRoutes(tester);
    expect(find.text('Koridor Dago'), findsOneWidget);
    expect(find.text('Koridor Buah Batu'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text('Koridor Dago'));
    await tester.pumpAndSettle();
    expect(find.byType(RouteDetailPage), findsOneWidget);

    // Ikuti: back on the map, watching only that route.
    await tester.tap(find.text(LiveTrackingStrings.follow));
    await tester.pumpAndSettle();
    expect(fleet.corridorFilters, {'K1'});
    expect(tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines, hasLength(1));
    await tearDownTab(tester);
  });

  testWidgets('corridors sharing a route code are listed and watched as one route', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    trip = ValueNotifier<ActiveTrip?>(null);
    final positions = _NoPositions();
    map = PassengerMapController(trip: trip, positions: positions, location: _NoLocation());
    fleet = FeederFleetController(
      loadCorridors: () async => const [
        CorridorOption(id: 'K1', name: 'Kiaracondong - Pasar Baru', routeCode: 'FD-1', feeders: []),
        CorridorOption(id: 'K2', name: 'Pasar Baru - Kiaracondong', routeCode: 'FD-1', isDummy: true, feeders: []),
      ],
      loadLive: () async => [],
      positions: positions,
    );
    await map.start();
    await fleet.start();
    final stopsLoadedFor = <String>{};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTab(
      controller: map,
      fleet: fleet,
      loadRoutePath: (_) async => const [LatLng(-6.94, 107.64), LatLng(-6.92, 107.62)],
      loadRouteStops: (corridorId, direction) {
        stopsLoadedFor.add(corridorId);
        return _noStops(corridorId, direction);
      },
      loadArrivals: _noArrivals,
    ))));
    await tester.pump();

    expect(find.text('Kiaracondong - Pasar Baru'), findsOneWidget);
    expect(find.text('Pasar Baru - Kiaracondong'), findsNothing);
    expect(find.text('FD-1'), findsOneWidget);

    await tester.tap(find.text('Kiaracondong - Pasar Baru'));
    await tester.pumpAndSettle();
    expect(stopsLoadedFor, {'K1'}); // the corridor with geometry stands for the route
    await tester.tap(find.text(LiveTrackingStrings.follow));
    await tester.pumpAndSettle();
    expect(fleet.corridorFilters, {'K1', 'K2'});
    await tearDownTab(tester);
  });

  testWidgets('Pantau beberapa: tick routes, then watch them', (tester) async {
    await pumpTwoRoutes(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.text(LiveTrackingStrings.watchRoutes(0)), findsOneWidget);

    await tester.tap(find.text('Koridor Dago'));
    await tester.tap(find.text('Koridor Buah Batu'));
    await tester.pump();
    await tester.tap(find.text(LiveTrackingStrings.watchRoutes(2)));
    await tester.pump();

    expect(fleet.corridorFilters, {'K1', 'K2'});
    expect(find.byType(Checkbox), findsNothing); // back to normal mode
    expect(find.text(LiveTrackingStrings.watchingRoutes(const ['a', 'b'])), findsOneWidget);

    await tester.tap(find.text(LiveTrackingStrings.showAllRoutes));
    await tester.pump();
    expect(fleet.corridorFilters, isEmpty);
    await tearDownTab(tester);
  });

  testWidgets('shows the corridor without an active feeder and highlights a booked corridor', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final trip = ValueNotifier<ActiveTrip?>(null);
    final positions = _NoPositions();
    final map = PassengerMapController(trip: trip, positions: positions, location: _NoLocation());
    final fleet = FeederFleetController(
      loadCorridors: () async => const [CorridorOption(id: 'K1', name: 'K1', feeders: [])],
      loadLive: () async => [],
      positions: positions,
    );
    await map.start();
    await fleet.start();
    var loads = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapTab(
      controller: map,
      fleet: fleet,
      loadRoutePath: (_) async {
        loads++;
        return const [LatLng(-6.94, 107.64), LatLng(-6.92, 107.62)];
      },
      loadRouteStops: _noStops,
      loadArrivals: _noArrivals,
    ))));
    await tester.pump();
    expect(loads, 1);
    var line = tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines.single;
    expect(line.points, hasLength(2));
    expect(line.strokeWidth, 4);

    trip.value = const ActiveTrip(corridorId: 'K1');
    await tester.pump();
    line = tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines.single;
    expect(line.strokeWidth, 8);

    await tester.pumpWidget(const SizedBox());
    fleet.dispose();
    map.dispose();
    trip.dispose();
  });
}
