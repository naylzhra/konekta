# Pure booking state machine (DESIGN.md §3). The single authoritative place
# for booking status transitions; the Flutter app mirrors TRANSITIONS for
# rendering only. No I/O here -- the service layer persists the result and
# bumps `version`.
from enum import StrEnum


class BookingStatus(StrEnum):
    REQUESTED = "REQUESTED"
    MATCHING = "MATCHING"
    CONFIRMED = "CONFIRMED"
    FEEDER_ARRIVING = "FEEDER_ARRIVING"
    BOARDED = "BOARDED"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"
    FAILED = "FAILED"
    NO_SHOW = "NO_SHOW"
    EXPIRED = "EXPIRED"


class BookingEvent(StrEnum):
    # gateway
    START_MATCHING = "start_matching"
    MATCH_FOUND = "match_found"
    MATCH_FAILED = "match_failed"
    # gateway (feeder within radius) or driver `arrived` at the pickup stop
    FEEDER_APPROACHING = "feeder_approaching"
    EXPIRE = "expire"
    # passenger
    PASSENGER_BOARDED = "passenger_boarded"
    CANCEL = "cancel"
    # driver, per stop -- never per passenger
    DRIVER_DEPARTED_PICKUP = "driver_departed_pickup"
    DRIVER_ARRIVED_DROPOFF = "driver_arrived_dropoff"


TERMINAL_STATUSES: frozenset[BookingStatus] = frozenset(
    {
        BookingStatus.COMPLETED,
        BookingStatus.CANCELLED,
        BookingStatus.FAILED,
        BookingStatus.NO_SHOW,
        BookingStatus.EXPIRED,
    }
)

# Must match the partial unique index in infra/db/migrations/004_bookings.sql.
ACTIVE_STATUSES: frozenset[BookingStatus] = frozenset(BookingStatus) - TERMINAL_STATUSES

_S = BookingStatus
_E = BookingEvent

TRANSITIONS: dict[tuple[BookingStatus, BookingEvent], BookingStatus] = {
    (_S.REQUESTED, _E.START_MATCHING): _S.MATCHING,
    (_S.MATCHING, _E.MATCH_FOUND): _S.CONFIRMED,
    (_S.MATCHING, _E.MATCH_FAILED): _S.FAILED,
    (_S.CONFIRMED, _E.FEEDER_APPROACHING): _S.FEEDER_ARRIVING,
    (_S.FEEDER_ARRIVING, _E.PASSENGER_BOARDED): _S.BOARDED,
    (_S.BOARDED, _E.DRIVER_ARRIVED_DROPOFF): _S.COMPLETED,
    # cancel: allowed until BOARDED
    (_S.REQUESTED, _E.CANCEL): _S.CANCELLED,
    (_S.MATCHING, _E.CANCEL): _S.CANCELLED,
    (_S.CONFIRMED, _E.CANCEL): _S.CANCELLED,
    (_S.FEEDER_ARRIVING, _E.CANCEL): _S.CANCELLED,
    # driver left the pickup stop without the passenger on board
    (_S.CONFIRMED, _E.DRIVER_DEPARTED_PICKUP): _S.NO_SHOW,
    (_S.FEEDER_ARRIVING, _E.DRIVER_DEPARTED_PICKUP): _S.NO_SHOW,
    # timeout
    (_S.REQUESTED, _E.EXPIRE): _S.EXPIRED,
    (_S.MATCHING, _E.EXPIRE): _S.EXPIRED,
    (_S.CONFIRMED, _E.EXPIRE): _S.EXPIRED,
}


class InvalidTransition(Exception):
    """Raised for any (status, event) pair not in TRANSITIONS."""

    code = "invalid_transition"

    def __init__(self, status: BookingStatus, event: BookingEvent) -> None:
        self.status = status
        self.event = event
        super().__init__(f"Cannot apply {event.value} to a booking in {status.value}")


def is_terminal(status: BookingStatus) -> bool:
    return status in TERMINAL_STATUSES


def can_apply(status: BookingStatus, event: BookingEvent) -> bool:
    return (status, event) in TRANSITIONS


def next_status(status: BookingStatus, event: BookingEvent) -> BookingStatus:
    try:
        return TRANSITIONS[(status, event)]
    except KeyError:
        raise InvalidTransition(status, event) from None
