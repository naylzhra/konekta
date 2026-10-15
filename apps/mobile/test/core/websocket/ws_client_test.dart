import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/websocket/ws_client.dart';

class _FakeTransport implements WsTransport {
  _FakeTransport({bool handshakeFails = false}) {
    if (handshakeFails) {
      _ready.completeError(StateError('handshake failed'));
      _incoming.addError(StateError('handshake failed'));
    } else {
      _ready.complete();
    }
  }

  final _incoming = StreamController<dynamic>();
  final _ready = Completer<void>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  void receive(Object data) => _incoming.add(data);
  void drop() => _incoming.close();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  Future<void> get ready => _ready.future;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);

  @override
  Future<void> close() async => closed = true;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late List<_FakeTransport> transports;
  late List<bool> failNext;
  late WsClient client;

  setUp(() {
    transports = [];
    failNext = [];
    client = WsClient(
      url: Uri.parse('ws://gateway/ws/c1?token=t'),
      backoff: (_) => const Duration(milliseconds: 1),
      connect: (_) {
        final transport = _FakeTransport(handshakeFails: failNext.isNotEmpty && failNext.removeAt(0));
        transports.add(transport);
        return transport;
      },
    );
  });

  tearDown(() => client.dispose());

  test('gatewayUrl derives ws/wss from the HTTP base', () {
    final url = WsClient.gatewayUrl(httpBaseUrl: 'https://api.example.com', clientId: 'c1', token: 'a b');
    expect(url.scheme, 'wss');
    expect(url.path, '/ws/c1');
    expect(url.queryParameters['token'], 'a b');
    expect(WsClient.gatewayUrl(httpBaseUrl: 'http://10.0.2.2:8000', clientId: 'c', token: 't').toString(),
        'ws://10.0.2.2:8000/ws/c?token=t');
  });

  test('connects, decodes envelopes and ignores non-envelopes', () async {
    final messages = <WsMessage>[];
    client.messages.listen(messages.add);
    client.connect();
    await _settle();
    expect(client.state, WsConnectionState.connected);

    transports.single
      ..receive('{"type":"booking.updated","payload":{"id":"b1"}}')
      ..receive('not json')
      ..receive('{"payload":{}}')
      ..receive('{"type":"pong","payload":{}}');
    await _settle();

    expect(messages.map((m) => m.type), ['booking.updated', 'pong']);
    expect(messages.first.payload, {'id': 'b1'});
  });

  test('reconnects after a drop and re-sends subscriptions', () async {
    final states = <WsConnectionState>[];
    client.states.listen(states.add);
    client.subscribe('feeder:f1');
    client.connect();
    await _settle();
    expect(transports.single.sent, [
      {'type': 'subscribe', 'payload': {'topic': 'feeder:f1'}},
    ]);

    transports.single.drop();
    await _settle();

    expect(transports, hasLength(2));
    expect(transports.first.closed, isTrue);
    expect(transports.last.sent, [
      {'type': 'subscribe', 'payload': {'topic': 'feeder:f1'}},
    ]);
    expect(states, [
      WsConnectionState.connecting,
      WsConnectionState.connected,
      WsConnectionState.reconnecting,
      WsConnectionState.connected,
    ]);
  });

  test('keeps retrying when handshakes fail', () async {
    failNext = [true, true];
    client.connect();
    await _settle();
    expect(transports, hasLength(3));
    expect(client.state, WsConnectionState.connected);
  });

  test('unsubscribed topics are not re-sent', () async {
    client.connect();
    await _settle();
    client.subscribe('feeder:f1');
    client.unsubscribe('feeder:f1');
    transports.single.drop();
    await _settle();
    expect(transports.last.sent, isEmpty);
  });

  test('disconnect stops reconnecting', () async {
    client.connect();
    await _settle();
    client.disconnect();
    transports.single.drop();
    await _settle();
    expect(transports, hasLength(1));
    expect(client.state, WsConnectionState.disconnected);
  });
}
