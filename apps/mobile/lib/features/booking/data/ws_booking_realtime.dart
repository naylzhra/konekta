import '../../../core/websocket/ws_client.dart';
import '../domain/booking_models.dart';
import 'booking_repository.dart';

/// Booking events from the shared WS hub (DESIGN.md §5.1). Does not own
/// the connection: whoever created the WsClient connects/disposes it.
class WsBookingRealtime implements BookingRealtime {
  WsBookingRealtime(this._ws);

  final WsClient _ws;

  @override
  Stream<Booking> get bookingUpdates => _payloads('booking.updated', Booking.fromJson);

  @override
  Stream<StopUpdate> get stopUpdates => _payloads('stop.updated', StopUpdate.fromJson);

  @override
  Stream<bool> get connectivity => _ws.states.map((s) => s == WsConnectionState.connected).distinct();

  @override
  bool get isConnected => _ws.state == WsConnectionState.connected;

  // Malformed payloads are dropped; the next resync corrects state.
  Stream<T> _payloads<T>(String type, T Function(Map<String, dynamic>) parse) =>
      _ws.messages.where((m) => m.type == type).expand((m) {
        try {
          return [parse(m.payload)];
        } on Object {
          return <T>[];
        }
      });
}
