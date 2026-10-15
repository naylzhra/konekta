import 'dart:async';

import '../../../core/websocket/ws_client.dart';
import '../domain/feeder_models.dart';

abstract class FeederPositionStream {
  Stream<FeederPosition> subscribe(String feederId);
  FeederPosition? lastKnown(String feederId);
}

class WsFeederPositionStream implements FeederPositionStream {
  WsFeederPositionStream(this._ws) {
    _messages = _ws.messages.where((m) => m.type == 'feeder.position').listen(_onPosition);
  }

  final WsClient _ws;
  late final StreamSubscription<WsMessage> _messages;
  final Map<String, StreamController<FeederPosition>> _controllers = {};
  final Map<String, FeederPosition> _last = {};

  @override
  Stream<FeederPosition> subscribe(String feederId) {
    final controller = _controllers.putIfAbsent(
      feederId,
      () => StreamController<FeederPosition>.broadcast(
        onListen: () => _ws.subscribe(_topic(feederId)),
        onCancel: () {
          _ws.unsubscribe(_topic(feederId));
          _controllers.remove(feederId)?.close();
        },
      ),
    );
    return controller.stream;
  }

  @override
  FeederPosition? lastKnown(String feederId) => _last[feederId];

  Future<void> dispose() async {
    await _messages.cancel();
    final controllers = _controllers.values.toList();
    _controllers.clear();
    for (final controller in controllers) {
      await controller.close();
    }
  }

  void _onPosition(WsMessage message) {
    final FeederPosition position;
    try {
      position = FeederPosition.fromJson(message.payload);
    } on Object {
      return;
    }
    final previous = _last[position.feederId];
    if (previous != null && !position.updatedAt.isAfter(previous.updatedAt)) return;
    _last[position.feederId] = position;
    _controllers[position.feederId]?.add(position);
  }

  static String _topic(String feederId) => 'feeder:$feederId';
}
