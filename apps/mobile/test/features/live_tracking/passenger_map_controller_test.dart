import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/location/user_location_provider.dart';
import 'package:konekta_mobile/core/websocket/ws_client.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_position_stream.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';
import 'package:konekta_mobile/features/live_tracking/state/passenger_map_controller.dart';
import 'package:latlong2/latlong.dart';

class _FakeLocation implements UserLocationProvider {
  LocationPermissionState permission = LocationPermissionState.denied;
  LocationPermissionState afterRequest = LocationPermissionState.granted;
  final fixes = StreamController<UserLocation>.broadcast();
  int requests = 0;

  @override
  Future<LocationPermissionState> permissionState() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async {
    requests++;
    return permission = afterRequest;
  }

  @override
  Future<UserLocation?> getCurrent() async => null;

  @override
  Stream<UserLocation> stream() => fixes.stream;
}

class _FakePositions implements FeederPositionStream {
  final controllers = <String, StreamController<FeederPosition>>{};
  final cancelled = <String>[];

  @override
  Stream<FeederPosition> subscribe(String feederId) =>
      (controllers[feederId] = StreamController<FeederPosition>(onCancel: () => cancelled.add(feederId))).stream;

  @override
  Stream<FeederPosition> subscribeCorridor(String corridorId) => const Stream.empty();

  @override
  FeederPosition? lastKnown(String feederId) => null;
}

FeederPosition _position(String feederId, {double lat = -6.9175, double lng = 107.6191, int occupancy = 2}) =>
    FeederPosition(
      feederId: feederId,
      lat: lat,
      lng: lng,
      occupancy: occupancy,
      updatedAt: DateTime.utc(2026, 10, 16, 8),
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late ValueNotifier<ActiveTrip?> trip;
  late _FakeLocation location;
  late _FakePositions positions;
  late StreamController<WsConnectionState> connection;
  late DateTime now;

  PassengerMapController controller() => PassengerMapController(
        trip: trip,
        positions: positions,
        location: location,
        connection: connection.stream,
        clock: () => now,
        staleCheckInterval: const Duration(milliseconds: 5),
      );

  setUp(() {
    trip = ValueNotifier(null);
    location = _FakeLocation();
    positions = _FakePositions();
    connection = StreamController<WsConnectionState>.broadcast();
    now = DateTime.utc(2026, 10, 16, 8);
  });

  test('without a trip there is nothing to track', () async {
    final map = controller();
    await map.start();
    expect(map.status, FeederTrackingStatus.none);
    expect(positions.controllers, isEmpty);
    map.dispose();
  });

  test('searching until booking assigns a feeder, then waits for its first position', () async {
    final map = controller();
    await map.start();
    trip.value = const ActiveTrip(pickup: LatLng(-6.92, 107.61), pickupName: 'Halte A');
    expect(map.status, FeederTrackingStatus.searching);

    trip.value = const ActiveTrip(feederId: 'K1-03', pickup: LatLng(-6.92, 107.61));
    expect(map.status, FeederTrackingStatus.waiting);
    expect(positions.controllers.keys, ['K1-03']);

    positions.controllers['K1-03']!.add(_position('K1-03', lat: -6.9175, lng: 107.6100));
    await _settle();
    expect(map.status, FeederTrackingStatus.live);
    expect(map.feeder!.feederId, 'K1-03');
    expect(map.feederToPickupM, closeTo(278, 5));
    map.dispose();
  });

  test('no distance to pickup once on board', () async {
    final map = controller();
    trip.value = const ActiveTrip(feederId: 'K1-03', pickup: LatLng(-6.92, 107.61), onBoard: true);
    await map.start();
    positions.controllers['K1-03']!.add(_position('K1-03'));
    await _settle();
    expect(map.feederToPickupM, isNull);
    map.dispose();
  });

  test('switching feeder cancels the old subscription and clears its position', () async {
    final map = controller();
    trip.value = const ActiveTrip(feederId: 'K1-03');
    await map.start();
    positions.controllers['K1-03']!.add(_position('K1-03'));
    await _settle();

    trip.value = const ActiveTrip(feederId: 'K2-01');
    await _settle();
    expect(positions.cancelled, ['K1-03']);
    expect(map.feeder, isNull);
    expect(map.status, FeederTrackingStatus.waiting);

    trip.value = null;
    await _settle();
    expect(positions.cancelled, ['K1-03', 'K2-01']);
    expect(map.status, FeederTrackingStatus.none);
    map.dispose();
  });

  test('feeder goes stale after 30 s without a position and recovers on the next one', () async {
    final map = controller();
    trip.value = const ActiveTrip(feederId: 'K1-03');
    await map.start();
    positions.controllers['K1-03']!.add(_position('K1-03'));
    await _settle();

    now = now.add(const Duration(seconds: 29));
    await _settle();
    expect(map.status, FeederTrackingStatus.live);

    now = now.add(const Duration(seconds: 1));
    await _settle();
    expect(map.status, FeederTrackingStatus.stale);
    expect(map.feeder, isNotNull, reason: 'last position stays on the map, greyed out');

    positions.controllers['K1-03']!.add(_position('K1-03'));
    await _settle();
    expect(map.status, FeederTrackingStatus.live);
    map.dispose();
  });

  test('a feeder that never reports goes stale too', () async {
    final map = controller();
    trip.value = const ActiveTrip(feederId: 'K1-03');
    await map.start();
    now = now.add(PassengerMapController.staleAfter);
    await _settle();
    expect(map.status, FeederTrackingStatus.stale);
    expect(map.feeder, isNull);
    map.dispose();
  });

  test('does not prompt for location on start; follows it once enabled', () async {
    final map = controller();
    await map.start();
    expect(location.requests, 0);
    expect(map.permission, LocationPermissionState.denied);

    await map.enableMyLocation();
    expect(location.requests, 1);
    location.fixes.add(UserLocation(lat: -6.91, lng: 107.6, at: now));
    await _settle();
    expect(map.myLocation!.lat, -6.91);
    map.dispose();
  });

  test('already granted permission shows location right away', () async {
    location.permission = LocationPermissionState.granted;
    final map = controller();
    await map.start();
    location.fixes.add(UserLocation(lat: -6.91, lng: 107.6, at: now));
    await _settle();
    expect(map.myLocation, isNotNull);
    expect(location.requests, 0);
    map.dispose();
  });

  test('revoked permission hides the location', () async {
    location.permission = LocationPermissionState.granted;
    final map = controller();
    await map.start();
    location.fixes.add(UserLocation(lat: -6.91, lng: 107.6, at: now));
    await _settle();

    location.permission = LocationPermissionState.deniedForever;
    await map.refreshPermission();
    expect(map.myLocation, isNull);
    expect(map.permission, LocationPermissionState.deniedForever);
    map.dispose();
  });

  test('reports reconnecting while the WebSocket is down', () async {
    final map = controller();
    await map.start();
    expect(map.isReconnecting, isFalse);
    connection.add(WsConnectionState.reconnecting);
    await _settle();
    expect(map.isReconnecting, isTrue);
    connection.add(WsConnectionState.connected);
    await _settle();
    expect(map.isReconnecting, isFalse);
    map.dispose();
  });
}
