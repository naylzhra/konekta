import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One WebSocket connection per app session to the gateway hub
/// (`/ws/{client_id}?token=...`, DESIGN.md §5.1), shared by booking and
/// live tracking. Every message is an envelope `{"type", "payload"}`.
///
/// Reconnects with capped exponential backoff + jitter until [disconnect]
/// is called, and re-sends topic subscriptions after every reconnect.
/// Consumers must resync state on [WsConnectionState.connected] (booking
/// does `GET /bookings/active`) because events sent while offline are lost.
///
/// The URL carries the session token: never log [url].
class WsClient {
  WsClient({
    required this.url,
    WsTransportFactory? connect,
    Duration Function(int attempt)? backoff,
    this.pingInterval = const Duration(seconds: 25),
  })  : _connect = connect ?? _webSocketTransport,
        _backoff = backoff ?? defaultBackoff;

  /// `ws(s)://<gateway>/ws/<clientId>?token=<token>` from the HTTP base URL.
  static Uri gatewayUrl({required String httpBaseUrl, required String clientId, required String token}) {
    final base = Uri.parse(httpBaseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/$clientId',
      queryParameters: {'token': token},
    );
  }

  /// Random per-app-session id; the server routes by the token's user, not this.
  static String newClientId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static Duration defaultBackoff(int attempt) {
    final cappedMs = min(30000, 500 * pow(2, min(attempt, 6)).toInt());
    return Duration(milliseconds: cappedMs ~/ 2 + Random().nextInt(cappedMs ~/ 2 + 1));
  }

  final Uri url;
  final Duration pingInterval;
  final WsTransportFactory _connect;
  final Duration Function(int attempt) _backoff;

  final _messages = StreamController<WsMessage>.broadcast();
  final _states = StreamController<WsConnectionState>.broadcast();
  final Set<String> _topics = {};

  WsTransport? _transport;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _attempt = 0;
  bool _wanted = false;
  WsConnectionState _state = WsConnectionState.disconnected;

  Stream<WsMessage> get messages => _messages.stream;
  Stream<WsConnectionState> get states => _states.stream;
  WsConnectionState get state => _state;

  void connect() {
    if (_wanted) return;
    _wanted = true;
    _open();
  }

  void disconnect() {
    _wanted = false;
    _reconnectTimer?.cancel();
    _teardown();
    _setState(WsConnectionState.disconnected);
  }

  Future<void> dispose() async {
    disconnect();
    await _messages.close();
    await _states.close();
  }

  /// Remembered across reconnects. Topics look like `feeder:<id>`.
  void subscribe(String topic) {
    if (_topics.add(topic)) _sendEnvelope('subscribe', {'topic': topic});
  }

  void unsubscribe(String topic) {
    if (_topics.remove(topic)) _sendEnvelope('unsubscribe', {'topic': topic});
  }

  void _open() {
    _teardown();
    _setState(_attempt == 0 ? WsConnectionState.connecting : WsConnectionState.reconnecting);
    final WsTransport transport;
    try {
      transport = _connect(url);
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _transport = transport;
    _subscription = transport.stream.listen(
      _onData,
      onError: (Object _) => _onClosed(transport),
      onDone: () => _onClosed(transport),
      cancelOnError: true,
    );
    transport.ready.then((_) {
      if (!identical(_transport, transport)) return;
      _attempt = 0;
      _setState(WsConnectionState.connected);
      for (final topic in _topics) {
        _sendEnvelope('subscribe', {'topic': topic});
      }
      _pingTimer = Timer.periodic(pingInterval, (_) => _sendEnvelope('ping', const {}));
    }, onError: (Object _) => _onClosed(transport));
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final WsMessage message;
    try {
      message = WsMessage.decode(data);
    } on FormatException {
      return; // not an envelope; ignore
    }
    if (!_messages.isClosed) _messages.add(message);
  }

  void _onClosed(WsTransport transport) {
    if (!identical(_transport, transport)) return; // stale socket
    _teardown();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_wanted) return;
    _setState(WsConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff(_attempt), () {
      _attempt++;
      if (_wanted) _open();
    });
  }

  void _teardown() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _transport?.close();
    _transport = null;
  }

  void _sendEnvelope(String type, Map<String, dynamic> payload) {
    // While (re)connecting, topics are sent once the handshake completes.
    if (_state != WsConnectionState.connected) return;
    _transport?.send(jsonEncode({'type': type, 'payload': payload}));
  }

  void _setState(WsConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

class WsMessage {
  const WsMessage(this.type, this.payload);

  factory WsMessage.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['type'] is! String) {
      throw const FormatException('Not a WS envelope');
    }
    final payload = decoded['payload'];
    return WsMessage(decoded['type'] as String, payload is Map<String, dynamic> ? payload : const {});
  }

  final String type;
  final Map<String, dynamic> payload;
}

/// Minimal socket abstraction so the client can be tested without a server.
abstract class WsTransport {
  Stream<dynamic> get stream;

  /// Completes when the handshake succeeded; errors if it failed.
  Future<void> get ready;
  void send(String data);
  Future<void> close();
}

typedef WsTransportFactory = WsTransport Function(Uri url);

WsTransport _webSocketTransport(Uri url) => _ChannelTransport(WebSocketChannel.connect(url));

class _ChannelTransport implements WsTransport {
  _ChannelTransport(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> get ready => _channel.ready;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() async {
    try {
      await _channel.sink.close();
    } catch (_) {
      // already closed
    }
  }
}
