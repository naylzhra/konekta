"""Passenger itinerary geometry. Never expose candidate or pooling state."""
from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.bookings.clients import OsrmRoutingClient, RouteStep, RoutingError
from app.bookings.models import GeoPoint, LegMode
from app.bookings.repository import BookingRepository
from app.bookings.state_machine import BookingStatus


class JourneyStage(BaseModel):
    mode: Literal["walk", "feeder", "motorcycle", "car"]
    status: Literal["completed", "active", "upcoming"]
    destination_name: str
    destination: GeoPoint
    distance_m: float
    duration_s: float
    points: list[GeoPoint]
    # Turn-by-turn maneuvers, only for the active stage.
    steps: list[RouteStep] = []


class JourneyResponse(BaseModel):
    booking_id: UUID
    active_stage: int
    stages: list[JourneyStage]


class JourneyUnavailable(Exception):
    pass


async def passenger_journey(
    repo: BookingRepository,
    routing: OsrmRoutingClient,
    booking_id: UUID,
    user_id: UUID,
    current_location: GeoPoint | None = None,
) -> JourneyResponse | None:
    booking_record = await repo.get_booking(booking_id, user_id)
    if booking_record is None:
        return None
    booking = booking_record.booking
    if booking.status in {
        BookingStatus.CANCELLED, BookingStatus.FAILED,
        BookingStatus.NO_SHOW, BookingStatus.EXPIRED,
    }:
        raise JourneyUnavailable("This trip has ended")
    plan_record = await repo.get_trip_plan(booking.trip_plan_id, user_id)
    if plan_record is None:
        raise JourneyUnavailable("Trip plan is unavailable")
    plan = plan_record.plan
    pickup = booking.pickup_stop or plan.pickup_stop
    dropoff = booking.dropoff_stop or plan.dropoff_stop
    if pickup is None or dropoff is None:
        raise JourneyUnavailable("Pickup or drop-off stop is unavailable")
    if pickup.id is not None:
        pickup = await repo.get_active_stop(pickup.id) or pickup
    if dropoff.id is not None:
        dropoff = await repo.get_active_stop(dropoff.id) or dropoff

    active = 2 if booking.status is BookingStatus.COMPLETED else (
        1 if booking.status is BookingStatus.BOARDED else 0
    )
    vehicle_mode = next((leg.mode for leg in plan.legs if leg.mode is not LegMode.WALK), LegMode.FEEDER)
    vehicle_profile = "motorcycle" if vehicle_mode is LegMode.MOTORCYCLE else "driving"
    legs = [
        ("walk", plan.origin, pickup.location, pickup.name, "walking"),
        (vehicle_mode.value, pickup.location, dropoff.location, dropoff.name, vehicle_profile),
        ("walk", dropoff.location, plan.destination, "Tujuan akhir", "walking"),
    ]
    stages = []
    for index, (mode, origin, destination, name, profile) in enumerate(legs):
        start = current_location if index == active and current_location is not None else origin
        steps: list[RouteStep] = []
        if start == destination:
            distance_m, duration_s, points = 0.0, 0.0, [destination]
        else:
            try:
                route = await routing.route([start, destination], profile=profile, geometry=True,
                                            steps=index == active)
            except RoutingError as exc:
                raise JourneyUnavailable("Route is unavailable") from exc
            distance_m, duration_s = route.distance_m, route.duration_s
            points = route.points or [start, destination]
            steps = route.steps
        stages.append(JourneyStage(
            mode=mode,
            status="completed" if index < active else "active" if index == active else "upcoming",
            destination_name=name,
            destination=destination,
            distance_m=distance_m,
            duration_s=duration_s,
            points=points,
            steps=steps,
        ))
    return JourneyResponse(booking_id=booking_id, active_stage=active, stages=stages)
