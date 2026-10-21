import 'dart:async';

import '../../../core/websocket/ws_client.dart';
import '../domain/feeder_models.dart';

abstract class FeederPositionStream {
  Stream<FeederPosition> subscribe(String feederId);

  /// Every feeder on [corridorId]'s positions.
  Stream<FeederPosition> subscribeCorridor(String corridorId);
  FeederPosition? lastKnown(String feederId);
}

class WsFeederPositionStream implements FeederPositionStream {
  WsFeederPositionStream(this._ws) {
    _messages = _ws.messages.where((m) => m.type == 'feeder.position').listen(_onPosition);
  }

  final WsClient _ws;
  late final StreamSubscription<WsMessage> _messages;
  final Map<String, StreamController<FeederPosition>> _controllers = {};
  final Map<String, StreamController<FeederPosition>> _corridorControllers = {};
  final Map<String, FeederPosition> _last = {};

  @override
  Stream<FeederPosition> subscribe(String feederId) => _subscribe(_controllers, feederId, _topic(feederId));

  @override
  Stream<FeederPosition> subscribeCorridor(String corridorId) =>
      _subscribe(_corridorControllers, corridorId, 'corridor:$corridorId');

  Stream<FeederPosition> _subscribe(
      Map<String, StreamController<FeederPosition>> controllers, String id, String topic) {
    final controller = controllers.putIfAbsent(
      id,
      () => StreamController<FeederPosition>.broadcast(
        onListen: () => _ws.subscribe(topic),
        onCancel: () {
          _ws.unsubscribe(topic);
          controllers.remove(id)?.close();
        },
      ),
    );
    return controller.stream;
  }

  @override
  FeederPosition? lastKnown(String feederId) => _last[feederId];

  Future<void> dispose() async {
    await _messages.cancel();
    final controllers = [..._controllers.values, ..._corridorControllers.values];
    _controllers.clear();
    _corridorControllers.clear();
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
    // The same report arrives once per subscribed topic; the check above
    // drops the copies, so fan out to both kinds of listener here.
    _controllers[position.feederId]?.add(position);
    final corridorId = position.corridorId;
    if (corridorId != null) _corridorControllers[corridorId]?.add(position);
  }

  static String _topic(String feederId) => 'feeder:$feederId';
}
