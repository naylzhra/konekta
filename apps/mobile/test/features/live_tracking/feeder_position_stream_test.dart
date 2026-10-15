import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/websocket/ws_client.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_position_stream.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';

class _FakeTransport implements WsTransport {
  final _incoming = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];

  void receive(String type, Map<String, dynamic> payload) =>
      _incoming.add(jsonEncode({'type': type, 'payload': payload}));

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _position(String feederId, String updatedAt, {double lat = -6.9175}) => {
      'feeder_id': feederId,
      'lat': lat,
      'lng': 107.6191,
      'heading': 90.0,
      'occupancy': 2,
      'updated_at': updatedAt,
    };

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late _FakeTransport transport;
  late WsClient ws;
  late WsFeederPositionStream feeders;

  setUp(() async {
    transport = _FakeTransport();
    ws = WsClient(url: Uri.parse('ws://gateway/ws/c1?token=t'), connect: (_) => transport);
    feeders = WsFeederPositionStream(ws);
    ws.connect();
    await _settle();
  });

  tearDown(() async {
    await feeders.dispose();
    await ws.dispose();
  });

  test('subscribes to the feeder topic while listened, unsubscribes on cancel', () async {
    final subscription = feeders.subscribe('K1-01').listen((_) {});
    await _settle();
    expect(transport.sent, contains(equals({'type': 'subscribe', 'payload': {'topic': 'feeder:K1-01'}})));

    await subscription.cancel();
    await _settle();
    expect(transport.sent, contains(equals({'type': 'unsubscribe', 'payload': {'topic': 'feeder:K1-01'}})));
  });

  test('delivers only that feeder\'s positions and remembers the last one', () async {
    final received = <FeederPosition>[];
    final subscription = feeders.subscribe('K1-01').listen(received.add);
    await _settle();

    transport
      ..receive('feeder.position', _position('K1-01', '2026-10-15T08:00:00Z'))
      ..receive('feeder.position', _position('K2-01', '2026-10-15T08:00:01Z'))
      ..receive('booking.updated', {'id': 'b1'});
    await _settle();

    expect(received.map((p) => p.feederId), ['K1-01']);
    expect(received.single.heading, 90.0);
    expect(received.single.occupancy, 2);
    expect(feeders.lastKnown('K1-01')?.updatedAt, DateTime.utc(2026, 10, 15, 8));
    expect(feeders.lastKnown('K2-01'), isNotNull); // cached even without a listener
    await subscription.cancel();
  });

  test('drops stale and malformed positions', () async {
    final received = <FeederPosition>[];
    final subscription = feeders.subscribe('K1-01').listen(received.add);
    await _settle();

    transport
      ..receive('feeder.position', _position('K1-01', '2026-10-15T08:00:05Z', lat: -6.91))
      ..receive('feeder.position', _position('K1-01', '2026-10-15T08:00:01Z', lat: -6.99)) // older
      ..receive('feeder.position', {'feeder_id': 'K1-01'}); // malformed
    await _settle();

    expect(received.map((p) => p.lat), [-6.91]);
    expect(feeders.lastKnown('K1-01')?.lat, -6.91);
    await subscription.cancel();
  });
}
