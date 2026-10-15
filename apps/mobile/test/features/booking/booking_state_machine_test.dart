import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/features/booking/domain/booking_state_machine.dart';

// Copy of services/gateway/app/bookings/state_machine.py TRANSITIONS, as
// wire strings. If this test fails, the client mirror drifted from the server.
const _serverTable = {
  ('REQUESTED', 'start_matching'): 'MATCHING',
  ('MATCHING', 'match_found'): 'CONFIRMED',
  ('MATCHING', 'match_failed'): 'FAILED',
  ('CONFIRMED', 'feeder_approaching'): 'FEEDER_ARRIVING',
  ('FEEDER_ARRIVING', 'passenger_boarded'): 'BOARDED',
  ('BOARDED', 'driver_arrived_dropoff'): 'COMPLETED',
  ('REQUESTED', 'cancel'): 'CANCELLED',
  ('MATCHING', 'cancel'): 'CANCELLED',
  ('CONFIRMED', 'cancel'): 'CANCELLED',
  ('FEEDER_ARRIVING', 'cancel'): 'CANCELLED',
  ('CONFIRMED', 'driver_departed_pickup'): 'NO_SHOW',
  ('FEEDER_ARRIVING', 'driver_departed_pickup'): 'NO_SHOW',
  ('REQUESTED', 'expire'): 'EXPIRED',
  ('MATCHING', 'expire'): 'EXPIRED',
  ('CONFIRMED', 'expire'): 'EXPIRED',
};

const _eventWire = {
  BookingEvent.startMatching: 'start_matching',
  BookingEvent.matchFound: 'match_found',
  BookingEvent.matchFailed: 'match_failed',
  BookingEvent.feederApproaching: 'feeder_approaching',
  BookingEvent.expire: 'expire',
  BookingEvent.passengerBoarded: 'passenger_boarded',
  BookingEvent.cancel: 'cancel',
  BookingEvent.driverDepartedPickup: 'driver_departed_pickup',
  BookingEvent.driverArrivedDropoff: 'driver_arrived_dropoff',
};

void main() {
  test('every event has a server wire name', () {
    expect(_eventWire.keys.toSet(), BookingEvent.values.toSet());
  });

  for (final status in BookingStatus.values) {
    for (final event in BookingEvent.values) {
      final expected = _serverTable[(status.wire, _eventWire[event]!)];
      test('${status.wire} + ${_eventWire[event]} -> ${expected ?? 'invalid'}', () {
        expect(canApply(status, event), expected != null);
        expect(nextStatus(status, event)?.wire, expected);
      });
    }
  }

  test('table has no extra entries', () {
    expect(bookingTransitions.length, _serverTable.length);
  });

  test('terminal statuses match the server and have no outgoing transitions', () {
    expect(
      terminalStatuses.map((s) => s.wire).toSet(),
      {'COMPLETED', 'CANCELLED', 'FAILED', 'NO_SHOW', 'EXPIRED'},
    );
    for (final status in terminalStatuses) {
      for (final event in BookingEvent.values) {
        expect(canApply(status, event), isFalse, reason: '${status.wire} is terminal');
      }
    }
  });

  test('wire round trip and unknown status', () {
    for (final status in BookingStatus.values) {
      expect(BookingStatus.fromWire(status.wire), status);
    }
    expect(() => BookingStatus.fromWire('PAID'), throwsFormatException);
  });
}
