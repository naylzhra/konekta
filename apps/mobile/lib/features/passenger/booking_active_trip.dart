import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../booking/domain/booking_state_machine.dart';
import '../booking/state/booking_controller.dart';
import '../live_tracking/state/passenger_map_controller.dart';

/// Booking's active booking as the [ActiveTrip] the Map tab follows.
class BookingActiveTrip extends ChangeNotifier implements ValueListenable<ActiveTrip?> {
  BookingActiveTrip(this._booking) {
    _booking.addListener(_update);
    _update();
  }

  final BookingController _booking;
  ActiveTrip? _value;

  @override
  ActiveTrip? get value => _value;

  void _update() {
    final booking = _booking.current;
    ActiveTrip? next;
    if (booking != null && booking.isActive) {
      // A virtual stop can move after confirmation.
      final pickup = _booking.pickupStopUpdate?.location ?? booking.pickupStop?.location;
      next = ActiveTrip(
        feederId: booking.feederId,
        corridorId: booking.corridorId,
        pickup: pickup == null ? null : LatLng(pickup.lat, pickup.lng),
        pickupName: booking.pickupStop?.name,
        onBoard: booking.status == BookingStatus.boarded,
      );
    }
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _booking.removeListener(_update);
    super.dispose();
  }
}
