import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/websocket/ws_client.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_position_stream.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';
import 'package:konekta_mobile/features/live_tracking/state/feeder_fleet_controller.dart';

class _FakePositions implements FeederPositionStream {
  final corridors = <String, StreamController<FeederPosition>>{};

  @override
  Stream<FeederPosition> subscribe(String feederId) => const Stream.empty();

  @override
  Stream<FeederPosition> subscribeCorridor(String corridorId) =>
      (corridors[corridorId] = StreamController<FeederPosition>()).stream;

  @override
  FeederPosition? lastKnown(String feederId) => null;
}

const _corridors = [
  CorridorOption(
    id: 'K1',
    name: 'Koridor 1 Dago',
    feeders: [FeederOption(id: 'K1-01', number: 1, capacity: 8, available: false)],
  ),
  CorridorOption(
    id: 'K2',
    name: 'Koridor 2 Buah Batu',
    feeders: [FeederOption(id: 'K2-01', number: 1, capacity: 8, available: false)],
  ),
];

FeederPosition _position(String feederId, String corridorId, {int second = 0, int occupancy = 2}) => FeederPosition(
      feederId: feederId,
      lat: -6.9,
      lng: 107.6,
      occupancy: occupancy,
      capacity: 8,
      corridorId: corridorId,
      updatedAt: DateTime.utc(2026, 10, 16, 8, 0, second),
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late _FakePositions positions;
  late StreamController<WsConnectionState> connection;
  late List<FeederPosition> live;
  late DateTime now;
  late int liveLoads;
  late FeederFleetController fleet;

  setUp(() {
    positions = _FakePositions();
    connection = StreamController<WsConnectionState>.broadcast();
    live = [_position('K1-01', 'K1')];
    now = DateTime.utc(2026, 10, 16, 8);
    liveLoads = 0;
    fleet = FeederFleetController(
      loadCorridors: () async => _corridors,
      loadLive: () async {
        liveLoads++;
        return live;
      },
      positions: positions,
      connection: connection.stream,
      clock: () => now,
      pruneInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    fleet.dispose();
    await connection.close();
  });

  test('starts from the snapshot and follows every corridor', () async {
    await fleet.start();
    expect(fleet.feeders.map((f) => f.feederId), ['K1-01']);
    expect(positions.corridors.keys, ['K1', 'K2']);

    positions.corridors['K2']!.add(_position('K2-01', 'K2'));
    positions.corridors['K1']!.add(_position('K1-01', 'K1', second: 5, occupancy: 8));
    positions.corridors['K1']!.add(_position('K1-01', 'K1', second: 1, occupancy: 0)); // older
    await _settle();

    expect(fleet.feeders.map((f) => f.feederId), ['K1-01', 'K2-01']);
    expect(fleet.feeders.first.isFull, isTrue);
    expect(fleet.onDutyOn('K1'), 1);
  });

  test('searches routes by name or id and filters the fleet', () async {
    await fleet.start();
    positions.corridors['K2']!.add(_position('K2-01', 'K2'));
    await _settle();

    expect(fleet.searchRoutes('dago').map((c) => c.id), ['K1']);
    expect(fleet.searchRoutes('k2').map((c) => c.id), ['K2']);
    expect(fleet.searchRoutes('  ').length, 2);
    expect(fleet.searchRoutes('cimahi'), isEmpty);

    fleet.filterByCorridor('K2');
    expect(fleet.feeders.map((f) => f.feederId), ['K2-01']);
    expect(fleet.selectedCorridor?.name, 'Koridor 2 Buah Batu');
    expect(fleet.onDutyCount, 2);

    fleet.filterByCorridor(null);
    expect(fleet.feeders.length, 2);
  });

  test('corridors sharing a route code are one route', () async {
    final grouped = FeederFleetController(
      loadCorridors: () async => const [
        CorridorOption(id: 'K1', name: 'Kiaracondong - Pasar Baru', routeCode: 'FD-1', feeders: []),
        CorridorOption(id: 'K2', name: 'Pasar Baru - Kiaracondong', routeCode: 'FD-1', isDummy: true, feeders: []),
        CorridorOption(id: 'K3', name: 'Cibiru', feeders: []),
      ],
      loadLive: () async => [_position('K1-01', 'K1'), _position('K2-01', 'K2')],
      positions: positions,
      clock: () => now,
    );
    await grouped.start();

    final [fd1, k3] = grouped.routes;
    expect((fd1.id, fd1.name, fd1.primary.id), ('FD-1', 'Kiaracondong - Pasar Baru', 'K1'));
    expect(fd1.corridorIds, {'K1', 'K2'});
    expect(fd1.isDummy, isFalse);
    expect(k3.id, 'K3');
    expect(grouped.onDutyOnRoute(fd1), 2);
    expect(grouped.searchRoutes('fd-1').single.id, 'FD-1');
    expect(grouped.searchRoutes('k2').single.id, 'FD-1');
    grouped.dispose();
  });

  test('watches several routes at once', () async {
    await fleet.start();
    positions.corridors['K2']!.add(_position('K2-01', 'K2'));
    await _settle();

    fleet.filterByCorridors({'K1', 'K2'});
    expect(fleet.corridorFilters, {'K1', 'K2'});
    expect(fleet.corridorFilter, isNull); // more than one
    expect(fleet.feeders.map((f) => f.feederId), ['K1-01', 'K2-01']);

    fleet.filterByCorridors({'K2'});
    expect(fleet.corridorFilter, 'K2');
    expect(fleet.feeders.map((f) => f.feederId), ['K2-01']);

    fleet.filterByCorridors(const {});
    expect(fleet.feeders.length, 2);
  });

  test('drops feeders not heard from for 30 s', () async {
    await fleet.start();
    now = now.add(const Duration(seconds: 20));
    positions.corridors['K2']!.add(_position('K2-01', 'K2'));
    await _settle();

    now = now.add(const Duration(seconds: 15)); // K1-01 at 35 s, K2-01 at 15 s
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fleet.feeders.map((f) => f.feederId), ['K2-01']);
  });

  test('re-reads the snapshot after reconnecting', () async {
    await fleet.start();
    expect(liveLoads, 1);

    live = [_position('K2-01', 'K2')];
    connection.add(WsConnectionState.reconnecting);
    connection.add(WsConnectionState.connected);
    await _settle();

    expect(liveLoads, 2);
    expect(fleet.feeders.map((f) => f.feederId), ['K2-01']);
  });

  test('flags a failed load and recovers on retry', () async {
    var fail = true;
    fleet = FeederFleetController(
      loadCorridors: () async => fail ? throw Exception('offline') : _corridors,
      loadLive: () async => live,
      positions: positions,
    );
    await fleet.start();
    expect(fleet.loadFailed, isTrue);

    fail = false;
    await fleet.load();
    expect(fleet.loadFailed, isFalse);
    expect(fleet.feeders.length, 1);
  });
}
