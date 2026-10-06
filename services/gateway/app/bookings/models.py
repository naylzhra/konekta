# Pydantic models for every booking request, response and WS payload
# (DESIGN.md §2, §5.1, §6). Money is integer rupiah (`*_idr`).
from datetime import datetime
from enum import StrEnum
from typing import Generic, Literal, Optional, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.bookings.state_machine import BookingStatus


class GeoPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class StopType(StrEnum):
    STATIC = "static"
    VIRTUAL = "virtual"


class Stop(BaseModel):
    id: UUID
    type: StopType
    name: str
    location: GeoPoint
    corridor_id: Optional[str] = None
    valid_until: Optional[datetime] = None


class StopSnapshot(BaseModel):
    """Stop as it was when the booking was confirmed; never rewritten."""

    id: Optional[UUID] = None  # null once the stop row itself is deleted
    type: StopType
    name: str
    location: GeoPoint


class LegMode(StrEnum):
    WALK = "walk"
    FEEDER = "feeder"


class TripLeg(BaseModel):
    mode: LegMode
    distance_m: float = Field(ge=0)
    duration_s: float = Field(ge=0)


# --- trip plans ------------------------------------------------------------


class TripPlanRequest(BaseModel):
    origin: GeoPoint
    destination: GeoPoint
    seats: int = Field(default=1, ge=1, le=4)


class TripPlan(BaseModel):
    id: UUID
    origin: GeoPoint
    destination: GeoPoint
    legs: list[TripLeg]
    fare_estimate_idr: int = Field(ge=0)
    eta_minutes: int = Field(ge=0)
    pickup_stop: Optional[Stop] = None
    dropoff_stop: Optional[Stop] = None
    corridor_id: Optional[str] = None
    expires_at: datetime


class TripPlansResponse(BaseModel):
    plans: list[TripPlan]


# --- bookings --------------------------------------------------------------


class CreateBookingRequest(BaseModel):
    trip_plan_id: UUID
    seats: int = Field(default=1, ge=1, le=4)


class CancelBookingRequest(BaseModel):
    reason: Optional[str] = Field(default=None, max_length=200)


class Booking(BaseModel):
    id: UUID
    status: BookingStatus
    trip_plan_id: Optional[UUID] = None
    seats: int
    pickup_stop: Optional[StopSnapshot] = None
    dropoff_stop: Optional[StopSnapshot] = None
    feeder_id: Optional[str] = None
    fare_estimate_idr: int
    cancellation_fee_idr: int = 0
    eta_to_pickup_s: Optional[int] = None
    cancel_reason: Optional[str] = None
    version: int = Field(ge=1)
    created_at: datetime
    updated_at: datetime


class BookingPage(BaseModel):
    items: list[Booking]
    next_cursor: Optional[str] = None


# --- consent ---------------------------------------------------------------


class ConsentPurpose(StrEnum):
    TRIP_LOCATION = "trip_location"


class ConsentRequest(BaseModel):
    purpose: ConsentPurpose
    policy_version: str = Field(min_length=1, max_length=32)
    granted: bool


class Consent(BaseModel):
    purpose: ConsentPurpose
    policy_version: str
    granted: bool
    created_at: datetime


class ConsentList(BaseModel):
    items: list[Consent]


# --- driver stop events (DESIGN.md §5.6) -----------------------------------


class DriverStopEventRequest(BaseModel):
    feeder_id: str = Field(min_length=1, max_length=64)


class DriverStopEventResult(BaseModel):
    stop_id: UUID
    updated_booking_ids: list[UUID]


# --- errors ----------------------------------------------------------------


class ErrorCode(StrEnum):
    INVALID_TRANSITION = "invalid_transition"
    ACTIVE_BOOKING_EXISTS = "active_booking_exists"
    IDEMPOTENCY_KEY_REUSED = "idempotency_key_reused"
    IDEMPOTENCY_KEY_REQUIRED = "idempotency_key_required"
    PLAN_EXPIRED = "plan_expired"
    NOT_FOUND = "not_found"
    CONSENT_REQUIRED = "consent_required"
    NO_ROUTE = "no_route"


class ErrorDetail(BaseModel):
    code: ErrorCode
    message: str


# --- WebSocket envelope (DESIGN.md §5.1) -----------------------------------

PayloadT = TypeVar("PayloadT", bound=BaseModel)


class WsEnvelope(BaseModel, Generic[PayloadT]):
    model_config = ConfigDict(extra="forbid")

    type: str
    payload: PayloadT


class StopUpdatedPayload(BaseModel):
    stop_id: UUID
    location: GeoPoint
    valid_until: Optional[datetime] = None


class BookingUpdatedEvent(WsEnvelope[Booking]):
    type: Literal["booking.updated"] = "booking.updated"


class StopUpdatedEvent(WsEnvelope[StopUpdatedPayload]):
    type: Literal["stop.updated"] = "stop.updated"
