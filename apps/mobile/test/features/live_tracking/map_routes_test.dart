import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/location/user_location_provider.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_position_stream.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';
import 'package:konekta_mobile/features/live_tracking/state/feeder_fleet_controller.dart';
import 'package:konekta_mobile/features/live_tracking/state/passenger_map_controller.dart';
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

void main() {
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
