/// Mirror of the gateway's authoritative booking state machine
/// (services/gateway/app/bookings/state_machine.py, DESIGN.md §3).
///
/// Used only to decide what the UI may offer (e.g. show "Batalkan" or
/// "Saya sudah naik") and to sanity-check incoming snapshots. The client
/// never moves a booking to a new status itself: status only changes when
/// a server snapshot (REST response or `booking.updated`) is applied.
/// Keep [bookingTransitions] identical to the server's TRANSITIONS table;
/// test/features/booking/booking_state_machine_test.dart pins it.
library;

enum BookingStatus {
  requested('REQUESTED'),
  matching('MATCHING'),
  confirmed('CONFIRMED'),
  feederArriving('FEEDER_ARRIVING'),
  boarded('BOARDED'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  failed('FAILED'),
  noShow('NO_SHOW'),
  expired('EXPIRED');

  const BookingStatus(this.wire);

  final String wire;

  static BookingStatus fromWire(String value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    throw FormatException('Unknown booking status: $value');
  }

  bool get isTerminal => terminalStatuses.contains(this);
  bool get isActive => !isTerminal;
}

enum BookingEvent {
  // gateway
  startMatching,
  matchFound,
  matchFailed,
  feederApproaching,
  expire,
  // passenger
  passengerBoarded,
  cancel,
  // driver, per stop
  driverDepartedPickup,
  driverArrivedDropoff,
}

const Set<BookingStatus> terminalStatuses = {
  BookingStatus.completed,
  BookingStatus.cancelled,
  BookingStatus.failed,
  BookingStatus.noShow,
  BookingStatus.expired,
};

const Map<(BookingStatus, BookingEvent), BookingStatus> bookingTransitions = {
  (BookingStatus.requested, BookingEvent.startMatching): BookingStatus.matching,
  (BookingStatus.matching, BookingEvent.matchFound): BookingStatus.confirmed,
  (BookingStatus.matching, BookingEvent.matchFailed): BookingStatus.failed,
  (BookingStatus.confirmed, BookingEvent.feederApproaching): BookingStatus.feederArriving,
  (BookingStatus.feederArriving, BookingEvent.passengerBoarded): BookingStatus.boarded,
  (BookingStatus.boarded, BookingEvent.driverArrivedDropoff): BookingStatus.completed,
  // cancel: allowed until BOARDED
  (BookingStatus.requested, BookingEvent.cancel): BookingStatus.cancelled,
  (BookingStatus.matching, BookingEvent.cancel): BookingStatus.cancelled,
  (BookingStatus.confirmed, BookingEvent.cancel): BookingStatus.cancelled,
  (BookingStatus.feederArriving, BookingEvent.cancel): BookingStatus.cancelled,
  // driver left the pickup stop without the passenger on board
  (BookingStatus.confirmed, BookingEvent.driverDepartedPickup): BookingStatus.noShow,
  (BookingStatus.feederArriving, BookingEvent.driverDepartedPickup): BookingStatus.noShow,
  // timeout
  (BookingStatus.requested, BookingEvent.expire): BookingStatus.expired,
  (BookingStatus.matching, BookingEvent.expire): BookingStatus.expired,
  (BookingStatus.confirmed, BookingEvent.expire): BookingStatus.expired,
};

bool canApply(BookingStatus status, BookingEvent event) =>
    bookingTransitions.containsKey((status, event));

/// Status the server would move to, or null if the transition is invalid.
BookingStatus? nextStatus(BookingStatus status, BookingEvent event) =>
    bookingTransitions[(status, event)];

