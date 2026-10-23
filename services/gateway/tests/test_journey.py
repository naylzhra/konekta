"""Journey stage selection and geometry stay tied to an owned booking."""
import asyncio
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

from app.bookings.clients import RouteResult
from app.bookings.journey import passenger_journey
from app.bookings.models import Booking, GeoPoint, Stop, StopSnapshot, StopType, TripPlan
from app.bookings.state_machine import BookingStatus


def test_journey_uses_walking_and_vehicle_routes_in_order() -> None:
    user_id, booking_id, plan_id = uuid4(), uuid4(), uuid4()
    origin = GeoPoint(lat=-6.930, lng=107.610)
    pickup = GeoPoint(lat=-6.929, lng=107.611)
    dropoff = GeoPoint(lat=-6.900, lng=107.620)
    destination = GeoPoint(lat=-6.899, lng=107.621)
    now = datetime.now(timezone.utc)
    booking = Booking(
        id=booking_id, status=BookingStatus.CONFIRMED, trip_plan_id=plan_id,
        seats=1, fare_estimate_idr=5000, version=1, created_at=now, updated_at=now,
        pickup_stop=StopSnapshot(id=uuid4(), type=StopType.STATIC, name="Halte A", location=pickup),
        dropoff_stop=StopSnapshot(id=uuid4(), type=StopType.STATIC, name="Halte B", location=dropoff),
    )
    plan = TripPlan(
        id=plan_id, origin=origin, destination=destination, legs=[],
        fare_estimate_idr=5000, eta_minutes=10, expires_at=now,
        pickup_stop=Stop(id=booking.pickup_stop.id, type=StopType.STATIC,
                         name="Halte A", location=pickup),
        dropoff_stop=Stop(id=booking.dropoff_stop.id, type=StopType.STATIC,
                          name="Halte B", location=dropoff),
    )

    class Repo:
        async def get_active_stop(self, stop_id):
            return None

        async def get_booking(self, requested_id, requested_user):
            return SimpleNamespace(booking=booking) if (requested_id, requested_user) == (booking_id, user_id) else None

        async def get_trip_plan(self, requested_id, requested_user):
            return SimpleNamespace(plan=plan) if (requested_id, requested_user) == (plan_id, user_id) else None

    class Router:
        def __init__(self):
            self.profiles = []

        async def route(self, points, profile="driving", *, geometry=False, steps=False):
            self.profiles.append(profile)
            assert geometry
            return RouteResult(distance_m=400, duration_s=300, points=points)

    router = Router()
    first = asyncio.run(passenger_journey(Repo(), router, booking_id, user_id, origin))
    assert first is not None
    assert first.active_stage == 0
    assert [stage.status for stage in first.stages] == ["active", "upcoming", "upcoming"]
    assert router.profiles == ["walking", "driving", "walking"]
    assert first.stages[0].points == [origin, pickup]

    booking.status = BookingStatus.BOARDED
    current = GeoPoint(lat=-6.915, lng=107.615)
    second = asyncio.run(passenger_journey(Repo(), Router(), booking_id, user_id, current))
    assert second.active_stage == 1
    assert second.stages[1].points[0] == current
    assert asyncio.run(passenger_journey(Repo(), Router(), booking_id, uuid4())) is None
