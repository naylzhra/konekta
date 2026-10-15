from datetime import datetime, timezone
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.bookings.models import (
    Booking,
    BookingUpdatedEvent,
    CancelBookingRequest,
    CreateBookingRequest,
    GeoPoint,
    StopSnapshot,
    StopType,
    TripPlanRequest,
)
from app.bookings.state_machine import BookingStatus


def _booking(**overrides) -> Booking:
    now = datetime(2026, 10, 6, 8, 0, tzinfo=timezone.utc)
    fields = {
        "id": uuid4(),
        "status": BookingStatus.CONFIRMED,
        "trip_plan_id": uuid4(),
        "seats": 1,
        "pickup_stop": StopSnapshot(
            id=uuid4(), type=StopType.VIRTUAL, name="Titik jemput", location=GeoPoint(lat=-6.9, lng=107.6)
        ),
        "fare_estimate_idr": 5000,
        "version": 3,
        "created_at": now,
        "updated_at": now,
    }
    fields.update(overrides)
    return Booking(**fields)


@pytest.mark.parametrize(("lat", "lng"), [(91, 0), (-91, 0), (0, 181), (0, -181)])
def test_geopoint_rejects_out_of_range(lat: float, lng: float) -> None:
    with pytest.raises(ValidationError):
        GeoPoint(lat=lat, lng=lng)


@pytest.mark.parametrize("seats", [0, 5])
def test_seats_bounded(seats: int) -> None:
    with pytest.raises(ValidationError):
        CreateBookingRequest(trip_plan_id=uuid4(), seats=seats)
    with pytest.raises(ValidationError):
        TripPlanRequest(origin=GeoPoint(lat=0, lng=0), destination=GeoPoint(lat=0, lng=0), seats=seats)


def test_cancel_reason_length_limited() -> None:
    CancelBookingRequest(reason=None)
    with pytest.raises(ValidationError):
        CancelBookingRequest(reason="x" * 201)


def test_booking_json_round_trip() -> None:
    booking = _booking()
    assert Booking.model_validate_json(booking.model_dump_json()) == booking


def test_booking_updated_envelope_shape() -> None:
    booking = _booking(status=BookingStatus.FEEDER_ARRIVING, version=4)
    event = BookingUpdatedEvent(payload=booking).model_dump(mode="json")
    assert event["type"] == "booking.updated"
    assert event["payload"]["status"] == "FEEDER_ARRIVING"
    assert event["payload"]["version"] == 4
    assert event["payload"]["pickup_stop"]["type"] == "virtual"
