import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client stub for live feeder location / ride updates.
///
/// TODO: wire into gateway's `/ws/{client_id}` endpoint (see
/// services/gateway/app/websocket/manager.py) once real-time events
/// (feeder location, virtual stop assignment) are defined.
class WsClient {
  WsClient({required this.url});

  final Uri url;
  WebSocketChannel? _channel;

  void connect() {
    _channel = WebSocketChannel.connect(url);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
